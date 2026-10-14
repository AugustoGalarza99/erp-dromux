-- Ejecutar una vez después de 031. Compras recibidas, cuenta corriente y OP.
begin;

create table public.supplier_payment_orders (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  number bigint not null check(number>0),
  supplier_id uuid not null,
  account_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  amount numeric(18,2) not null check(amount>0),
  paid_on date not null,
  note text not null check(length(btrim(note)) between 3 and 240),
  reference text not null default '' check(length(reference)<=120),
  status text not null default 'draft' check(status in ('draft','paid','cancelled')),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  confirmed_at timestamptz,
  check((status='paid')=(confirmed_at is not null)),
  unique(company_id,id), unique(company_id,request_id), unique(company_id,number),
  foreign key(company_id,supplier_id) references public.suppliers(company_id,id),
  foreign key(company_id,account_id) references public.treasury_accounts(company_id,id)
);
create table private.supplier_payment_numbers (
  company_id uuid primary key references public.companies(id) on delete cascade,
  next_number bigint not null check(next_number>0)
);
revoke all on private.supplier_payment_numbers from public,anon,authenticated;
create table public.supplier_payment_order_lines (
  company_id uuid not null, payment_order_id uuid not null, order_id uuid not null,
  amount numeric(18,2) not null check(amount>0),
  treasury_request_id uuid not null default gen_random_uuid(), treasury_entry_id uuid,
  primary key(company_id,payment_order_id,order_id),
  foreign key(company_id,payment_order_id) references public.supplier_payment_orders(company_id,id) on delete cascade,
  foreign key(company_id,order_id) references public.purchase_orders(company_id,id),
  foreign key(company_id,treasury_entry_id) references public.treasury_entries(company_id,id)
);
alter table public.supplier_payment_orders enable row level security;
alter table public.supplier_payment_order_lines enable row level security;
create policy payment_orders_read on public.supplier_payment_orders for select to authenticated
  using(private.has_permission(company_id,'finance','read') and private.has_permission(company_id,'purchases','read'));
create policy payment_order_lines_read on public.supplier_payment_order_lines for select to authenticated
  using(private.has_permission(company_id,'finance','read') and private.has_permission(company_id,'purchases','read'));
revoke all on public.supplier_payment_orders,public.supplier_payment_order_lines from public,anon,authenticated;
grant select on public.supplier_payment_orders,public.supplier_payment_order_lines to authenticated;
create index supplier_payment_orders_recent on public.supplier_payment_orders(company_id,created_at desc,id);
create index purchase_receipts_statistics on public.purchase_receipts(company_id,created_at);
create index treasury_supplier_order on public.treasury_entries(company_id,purchase_order_id,occurred_on);

create function public.create_supplier_payment_order(p_company uuid,p_supplier uuid,p_account uuid,
  p_on date,p_note text,p_reference text,p_lines jsonb,p_request uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_row jsonb; v_amount numeric; v_total numeric:=0; v_old public.supplier_payment_orders%rowtype;
  v_payload jsonb; v_order uuid; v_remaining numeric; v_number bigint;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert')
    or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Necesitás crear Finanzas y leer Compras' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_request is null or p_on is null or p_on>(now() at time zone 'America/Argentina/Buenos_Aires')::date
    or length(btrim(coalesce(p_note,''))) not between 3 and 240
    or length(coalesce(p_reference,''))>120 or p_lines is null or jsonb_typeof(p_lines)<>'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then raise exception 'Revisá fecha, detalle y órdenes a pagar'; end if;
  v_payload:=jsonb_build_object('supplier',p_supplier,'account',p_account,'on',p_on,
    'note',btrim(p_note),'reference',coalesce(p_reference,''),'lines',p_lines);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_old from public.supplier_payment_orders where company_id=p_company and request_id=p_request;
  if found then
    if v_old.request_payload<>v_payload or v_old.actor_id<>auth.uid() then raise exception 'Solicitud usada con otros datos'; end if;
    return v_old.id;
  end if;
  perform 1 from public.suppliers where company_id=p_company and id=p_supplier and active;
  if not found then raise exception 'Elegí un proveedor activo'; end if;
  perform 1 from public.treasury_accounts where company_id=p_company and id=p_account and active;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  for v_row in select value from jsonb_array_elements(p_lines) loop
    v_order:=(v_row->>'order_id')::uuid; v_amount:=(v_row->>'amount')::numeric;
    if v_amount is null or v_amount<=0 or v_amount>=1000000000000 or v_amount<>round(v_amount,2) then
      raise exception 'Importe inválido, hasta dos decimales'; end if;
    perform 1 from public.purchase_orders where company_id=p_company and id=v_order
      and supplier_id=p_supplier and status in ('open','partial','received');
    if not found then raise exception 'Todas las órdenes deben ser del proveedor y estar vigentes'; end if;
    select round(sum(l.quantity*l.unit_price),2)-coalesce((select sum(t.amount)
      from public.treasury_entries t where t.company_id=p_company and t.purchase_order_id=v_order),0)
      into v_remaining from public.purchase_order_lines l where l.company_id=p_company and l.order_id=v_order;
    if v_amount>v_remaining then raise exception 'El importe supera el saldo pendiente de la orden'; end if;
    v_total:=v_total+v_amount;
  end loop;
  insert into private.supplier_payment_numbers(company_id,next_number) values(p_company,2)
    on conflict(company_id) do update set next_number=private.supplier_payment_numbers.next_number+1
    returning next_number-1 into v_number;
  insert into public.supplier_payment_orders(company_id,number,supplier_id,account_id,request_id,request_payload,
    amount,paid_on,note,reference,actor_id)
  values(p_company,v_number,p_supplier,p_account,p_request,v_payload,v_total,p_on,btrim(p_note),coalesce(p_reference,''),auth.uid()) returning id into v_id;
  insert into public.supplier_payment_order_lines(company_id,payment_order_id,order_id,amount)
    select p_company,v_id,(x->>'order_id')::uuid,(x->>'amount')::numeric from jsonb_array_elements(p_lines) x;
  return v_id;
end; $$;

create function public.confirm_supplier_payment_order(p_company uuid,p_payment uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_payment public.supplier_payment_orders%rowtype; v_line record; v_entry uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert')
    or not private.has_permission(p_company,'purchases','read') then raise exception 'Sin permiso para pagar' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_payment from public.supplier_payment_orders where company_id=p_company and id=p_payment for update;
  if not found then raise exception 'Orden de pago inexistente'; end if;
  if v_payment.status='paid' then return v_payment.id; end if;
  if v_payment.status<>'draft' then raise exception 'La orden está anulada'; end if;
  for v_line in select * from public.supplier_payment_order_lines
    where company_id=p_company and payment_order_id=p_payment order by order_id loop
    v_entry:=public.post_treasury_entry(p_company,v_payment.account_id,'supplier_payment',
      v_line.amount,v_line.order_id,v_payment.note,v_payment.paid_on,v_line.treasury_request_id,null);
    update public.supplier_payment_order_lines set treasury_entry_id=v_entry
      where company_id=p_company and payment_order_id=p_payment and order_id=v_line.order_id;
  end loop;
  update public.supplier_payment_orders set status='paid',confirmed_at=clock_timestamp()
    where company_id=p_company and id=p_payment;
  return p_payment;
end; $$;

create function public.cancel_supplier_payment_order(p_company uuid,p_payment uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','update') then
    raise exception 'Sin permiso para anular' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  update public.supplier_payment_orders set status='cancelled'
    where company_id=p_company and id=p_payment and status='draft';
  if not found then raise exception 'Solo se pueden anular borradores sin pagos'; end if;
end; $$;

-- Consulta de compras recibidas: nunca sumar cantidades de unidades incompatibles.
create function public.supplier_purchase_statistics(p_company uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a compras' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Rango de fechas inválido'; end if;
  with received as (
    select o.supplier_id,o.supplier_name,l.item_id,pl.item_code,pl.item_name,pl.unit_symbol,
      l.quantity,l.quantity*l.unit_price amount,r.id receipt_id
    from public.purchase_receipts r join public.purchase_receipt_lines l on l.company_id=r.company_id and l.receipt_id=r.id
    join public.purchase_orders o on o.company_id=r.company_id and o.id=r.order_id
    join public.purchase_order_lines pl on pl.company_id=l.company_id and pl.order_id=l.order_id and pl.line_no=l.line_no
    where r.company_id=p_company and r.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and r.created_at < ((p_to+1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
  ) select jsonb_build_object('total',coalesce((select sum(amount) from received),0),
    'receipts',(select count(distinct receipt_id) from received),
    'suppliers',coalesce((select jsonb_agg(x) from (
      select supplier_id,max(supplier_name) name,sum(amount) amount,count(distinct receipt_id) receipts
      from received group by supplier_id order by sum(amount) desc,supplier_id limit 10) x),'[]'::jsonb),
    'products_frequency',coalesce((select jsonb_agg(x) from (
      select item_id,max(item_code) code,max(item_name) name,unit_symbol,sum(quantity) quantity,sum(amount) amount,
        count(distinct receipt_id) frequency
      from received group by item_id,unit_symbol order by count(distinct receipt_id) desc,sum(amount) desc,item_id limit 10) x),'[]'::jsonb),
    'products',coalesce((select jsonb_agg(x) from (
      select item_id,max(item_code) code,max(item_name) name,unit_symbol,sum(quantity) quantity,sum(amount) amount
      from received group by item_id,unit_symbol order by sum(amount) desc,item_id limit 10) x),'[]'::jsonb)) into v_result;
  return v_result;
end; $$;

create function public.supplier_account(p_company uuid,p_supplier uuid,p_from date,p_to date,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read')
    or not private.has_permission(p_company,'finance','read') then
    raise exception 'Necesitás leer Compras y Finanzas' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_from>p_to or p_page is null or p_page<0 or p_page>100000 then
    raise exception 'Rango o página inválidos'; end if;
  return (with ledger as (
    select r.id,r.created_at,(r.created_at at time zone 'America/Argentina/Buenos_Aires')::date ledger_date,
      'Recepción · OC '||o.number::text title,round(sum(l.quantity*l.unit_price),2) debit,0::numeric credit
    from public.purchase_receipts r join public.purchase_receipt_lines l on l.company_id=r.company_id and l.receipt_id=r.id
    join public.purchase_orders o on o.company_id=r.company_id and o.id=r.order_id
    where r.company_id=p_company and o.supplier_id=p_supplier group by r.id,o.number
    union all
    select t.id,t.created_at,t.occurred_on,'Pago · OC '||o.number::text||' · '||t.note,0,t.amount
    from public.treasury_entries t join public.purchase_orders o on o.company_id=t.company_id and o.id=t.purchase_order_id
    where t.company_id=p_company and o.supplier_id=p_supplier and t.kind='supplier_payment'
  ), running as (
    select *,sum(debit-credit) over(order by ledger_date,created_at,id rows unbounded preceding) balance from ledger
  ) select jsonb_build_object(
    'opening',coalesce((select sum(debit-credit) from ledger where ledger_date<p_from),0),
    'debit',coalesce((select sum(debit) from ledger where ledger_date between p_from and p_to),0),
    'credit',coalesce((select sum(credit) from ledger where ledger_date between p_from and p_to),0),
    'balance',coalesce((select sum(debit-credit) from ledger where ledger_date<=p_to),0),
    'total_count',(select count(*) from ledger where ledger_date between p_from and p_to),
    'rows',coalesce((select jsonb_agg(x order by x.ledger_date,x.created_at,x.id) from (
      select * from running where ledger_date between p_from and p_to order by ledger_date,created_at,id
        limit 25 offset p_page*25) x),'[]'::jsonb)));
end; $$;

create function public.supplier_payable_orders(p_company uuid,p_supplier uuid,p_page integer default 0)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read')
    or not private.has_permission(p_company,'finance','read') then raise exception 'Sin acceso a cuentas' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 then raise exception 'Página inválida'; end if;
  return (with orders as (
    select o.id,o.number,o.status,round(sum(l.quantity*l.unit_price),2) total,
      round(sum(l.received_quantity*l.unit_price),2) received,
      coalesce((select sum(t.amount) from public.treasury_entries t
        where t.company_id=o.company_id and t.purchase_order_id=o.id and t.kind='supplier_payment'),0) paid
    from public.purchase_orders o join public.purchase_order_lines l on l.company_id=o.company_id and l.order_id=o.id
    where o.company_id=p_company and o.supplier_id=p_supplier and o.status in ('open','partial','received')
    group by o.id
  ), pending as (select *,total-paid remaining from orders where total>paid)
  select jsonb_build_object('count',(select count(*) from pending),'rows',coalesce((select jsonb_agg(x) from (
    select * from pending order by number limit 25 offset p_page*25) x),'[]'::jsonb)));
end; $$;

revoke all on function public.create_supplier_payment_order(uuid,uuid,uuid,date,text,text,jsonb,uuid),
  public.confirm_supplier_payment_order(uuid,uuid),public.cancel_supplier_payment_order(uuid,uuid),
  public.supplier_purchase_statistics(uuid,date,date),public.supplier_account(uuid,uuid,date,date,integer),
  public.supplier_payable_orders(uuid,uuid,integer) from public,anon;
grant execute on function public.create_supplier_payment_order(uuid,uuid,uuid,date,text,text,jsonb,uuid),
  public.confirm_supplier_payment_order(uuid,uuid),public.cancel_supplier_payment_order(uuid,uuid),
  public.supplier_purchase_statistics(uuid,date,date),public.supplier_account(uuid,uuid,date,date,integer),
  public.supplier_payable_orders(uuid,uuid,integer) to authenticated;

-- Los pagos previos y nuevos usan el mismo registro inmutable de Tesorería.
-- La función siguiente amplía los estados admitidos por la versión 016.
create or replace function public.post_treasury_entry(p_company uuid,p_account uuid,p_kind text,
  p_amount numeric,p_order uuid,p_note text,p_on date,p_request uuid,p_target uuid default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.treasury_entries%rowtype; v_id uuid; v_total numeric; v_paid numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_request is null or p_amount is null or p_amount<=0 or p_amount<>round(p_amount,2)
    or p_kind not in ('income','expense','supplier_payment','transfer_out')
    or p_note is null or length(btrim(p_note)) not between 3 and 240
    or p_on is null or p_on>(now() at time zone 'America/Argentina/Buenos_Aires')::date
    or (p_kind='supplier_payment') is distinct from (p_order is not null)
    or (p_kind='transfer_out') is distinct from (p_target is not null)
    or p_account=p_target then raise exception 'Revisá los datos del movimiento'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('treasury:'||p_company::text,0));
  select * into v_old from public.treasury_entries
    where company_id=p_company and request_id=p_request and kind=p_kind;
  if found then
    if v_old.account_id<>p_account or v_old.amount<>p_amount
      or v_old.purchase_order_id is distinct from p_order or v_old.note<>btrim(p_note)
      or v_old.occurred_on<>p_on or v_old.actor_id<>auth.uid()
      or (p_kind='transfer_out' and not exists (
        select 1 from public.treasury_entries t where t.company_id=p_company
        and t.request_id=p_request and t.kind='transfer_in' and t.account_id=p_target))
      then raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_old.id;
  end if;
  perform 1 from public.treasury_accounts where company_id=p_company and id=p_account and active;
  if not found then raise exception 'Cuenta de origen inexistente o inactiva'; end if;
  if p_target is not null then
    perform 1 from public.treasury_accounts where company_id=p_company and id=p_target and active;
    if not found then raise exception 'Cuenta de destino inexistente o inactiva'; end if;
  end if;
  if p_order is not null then
    select coalesce(sum(l.quantity*l.unit_price),0) into v_total
      from public.purchase_orders o join public.purchase_order_lines l
      on l.company_id=o.company_id and l.order_id=o.id
      where o.company_id=p_company and o.id=p_order and o.status in ('open','partial','received');
    if v_total=0 then raise exception 'Seleccioná una orden de compra abierta'; end if;
    select coalesce(sum(amount),0) into v_paid from public.treasury_entries
      where company_id=p_company and purchase_order_id=p_order;
    if p_amount>round(v_total,2)-v_paid then
      raise exception 'El pago supera el saldo de la orden'; end if;
  end if;
  insert into public.treasury_entries(company_id,account_id,request_id,kind,
    amount,purchase_order_id,note,occurred_on,actor_id)
  values(p_company,p_account,p_request,p_kind,p_amount,p_order,btrim(p_note),p_on,auth.uid())
  returning id into v_id;
  if p_target is not null then
    insert into public.treasury_entries(company_id,account_id,request_id,kind,
      amount,note,occurred_on,actor_id)
    values(p_company,p_target,p_request,'transfer_in',p_amount,btrim(p_note),p_on,auth.uid());
  end if;
  return v_id;
end;
$$;


commit;
