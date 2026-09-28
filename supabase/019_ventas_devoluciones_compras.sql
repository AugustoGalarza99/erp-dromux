-- Dromux ERP · venta con cobro inicial, devoluciones y compras por proveedor.
-- Ejecutar después de 018. Conserva intactos los comprobantes ya emitidos.

create table public.sale_checkouts (
  company_id uuid not null,
  request_id uuid not null,
  sale_id uuid not null,
  payment_request_id uuid,
  payment_mode text not null check(payment_mode in ('pending','partial','paid')),
  amount numeric(18,2),
  method text,
  account_id uuid,
  actor_id uuid not null references auth.users(id),
  primary key(company_id,request_id),
  unique(company_id,sale_id),
  foreign key(company_id,sale_id) references public.sales(company_id,id),
  foreign key(company_id,account_id) references public.treasury_accounts(company_id,id)
);
revoke all on public.sale_checkouts from public,anon,authenticated;

create function public.post_sale_with_payment(
  p_company uuid,p_customer uuid,p_note text,p_lines jsonb,p_request_id uuid,
  p_payment_request_id uuid,p_payment_mode text,p_amount numeric,
  p_method text,p_account uuid
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_sale uuid; v_total numeric; v_previous public.sale_checkouts%rowtype;
begin
  if p_payment_mode not in ('pending','partial','paid') or p_payment_mode is null then
    raise exception 'Elegí cómo quedará el cobro de la venta'; end if;
  if p_payment_mode='pending' then
    if p_amount is not null or p_method is not null or p_account is not null
      or p_payment_request_id is not null then
      raise exception 'La venta pendiente no debe incluir datos de cobro'; end if;
  else
    if auth.uid() is null or not private.has_permission(p_company,'finance','insert')
      or not private.has_permission(p_company,'sales','read') then
      raise exception 'Necesitás permiso para registrar cobros' using errcode='42501'; end if;
    if p_payment_request_id is null or p_amount is null or p_amount<=0
      or p_amount<>round(p_amount,2) or p_account is null
      or p_method not in ('cash','transfer','card','check','other') then
      raise exception 'Indicá monto, medio de pago y cuenta'; end if;
    perform 1 from public.treasury_accounts a
      where a.company_id=p_company and a.id=p_account and a.active
        and (p_method<>'cash' or a.kind='cash');
    if not found then raise exception 'Elegí una cuenta activa compatible con el medio de pago'; end if;
  end if;
  -- La función original comprueba idempotencia, precios y stock en la misma transacción.
  v_sale:=public.post_sale(p_company,p_customer,p_note,p_lines,p_request_id);
  select * into v_previous from public.sale_checkouts
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.sale_id<>v_sale
      or v_previous.payment_request_id is distinct from p_payment_request_id
      or v_previous.payment_mode<>p_payment_mode
      or v_previous.amount is distinct from p_amount
      or v_previous.method is distinct from p_method
      or v_previous.account_id is distinct from p_account then
      raise exception 'Esta solicitud ya se usó con otra forma de cobro'; end if;
    return v_sale;
  end if;
  select total into v_total from public.sales where company_id=p_company and id=v_sale;
  if p_payment_mode<>'pending' then
    if p_amount>v_total or (p_payment_mode='paid' and p_amount<>v_total)
      or (p_payment_mode='partial' and p_amount>=v_total) then
      raise exception 'El cobro no coincide con el total de la venta'; end if;
  end if;
  insert into public.sale_checkouts(company_id,request_id,sale_id,payment_request_id,
    payment_mode,amount,method,account_id,actor_id)
  values(p_company,p_request_id,v_sale,p_payment_request_id,p_payment_mode,
    p_amount,p_method,p_account,auth.uid());
  if p_payment_mode<>'pending' then
    perform public.post_sale_payment_to_account(p_company,v_sale,p_amount,p_method,
      (now() at time zone 'America/Argentina/Buenos_Aires')::date,
      '','Cobro al registrar la venta',p_payment_request_id,p_account);
  end if;
  return v_sale;
end;
$$;
revoke execute on function public.post_sale_with_payment(uuid,uuid,text,jsonb,uuid,uuid,text,numeric,text,uuid) from public,anon;
grant execute on function public.post_sale_with_payment(uuid,uuid,text,jsonb,uuid,uuid,text,numeric,text,uuid) to authenticated;

create table public.sale_adjustments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  sale_id uuid not null,
  request_id uuid not null,
  kind text not null check(kind in ('cancel','return')),
  reason text not null check(length(btrim(reason)) between 5 and 300),
  credit_total numeric(18,2) not null check(credit_total>=0),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique(company_id,id),
  unique(company_id,request_id),
  foreign key(company_id,sale_id) references public.sales(company_id,id)
);
create index sale_adjustments_sale on public.sale_adjustments(company_id,sale_id);
create unique index sale_one_cancellation on public.sale_adjustments(company_id,sale_id)
  where kind='cancel';
create table public.sale_adjustment_lines (
  company_id uuid not null,
  adjustment_id uuid not null,
  sale_id uuid not null,
  sale_line_no smallint not null,
  quantity numeric(18,6) not null check(quantity>0),
  credit_amount numeric(18,2) not null check(credit_amount>=0),
  restocked boolean not null,
  stock_operation_id uuid,
  primary key(company_id,adjustment_id,sale_line_no),
  foreign key(company_id,adjustment_id) references public.sale_adjustments(company_id,id),
  foreign key(company_id,sale_id,sale_line_no) references public.sale_lines(company_id,sale_id,line_no),
  foreign key(company_id,stock_operation_id) references public.stock_operations(company_id,id),
  check(restocked=(stock_operation_id is not null))
);
alter table public.sale_adjustments enable row level security;
alter table public.sale_adjustment_lines enable row level security;
create policy sale_adjustments_read on public.sale_adjustments for select to authenticated
  using((select private.has_permission(company_id,'sales','read')));
create policy sale_adjustment_lines_read on public.sale_adjustment_lines for select to authenticated
  using((select private.has_permission(company_id,'sales','read')));
revoke all on public.sale_adjustments,public.sale_adjustment_lines from public,anon,authenticated;
grant select on public.sale_adjustments,public.sale_adjustment_lines to authenticated;
create trigger sale_adjustments_immutable before delete on public.sale_adjustments
  for each row execute function private.reject_stock_history_mutation();
create trigger sale_adjustment_lines_immutable before update or delete on public.sale_adjustment_lines
  for each row execute function private.reject_stock_history_mutation();

create function public.adjust_sale(p_company uuid,p_sale uuid,p_kind text,
  p_reason text,p_lines jsonb,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.sale_adjustments%rowtype; v_sale public.sales%rowtype;
  v_row public.sale_lines%rowtype; v_entry jsonb; v_adjustment uuid;
  v_quantity numeric; v_remaining numeric; v_credit numeric:=0;
  v_line_credit numeric; v_restock boolean; v_operation uuid; v_expiry date;
  v_expected integer; v_count integer:=0;
begin
  if auth.uid() is null or not private.has_permission(p_company,'sales','update')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos para modificar ventas y registrar stock' using errcode='42501'; end if;
  if p_kind not in ('cancel','return') or p_kind is null or p_sale is null
    or p_request_id is null or length(btrim(coalesce(p_reason,''))) not between 5 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Indicá el motivo y los productos a devolver'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.sale_adjustments
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.actor_id<>auth.uid() or v_existing.sale_id<>p_sale
      or v_existing.kind<>p_kind or v_existing.reason<>btrim(p_reason)
      or (select jsonb_agg(jsonb_build_object('line_no',l.sale_line_no,
        'quantity',l.quantity,'restock',l.restocked) order by l.sale_line_no)
          from public.sale_adjustment_lines l
          where l.company_id=p_company and l.adjustment_id=v_existing.id)
        is distinct from (
          select jsonb_agg(jsonb_build_object('line_no',(x.value->>'line_no')::smallint,
            'quantity',(x.value->>'quantity')::numeric,
            'restock',(x.value->>'restock')::boolean) order by (x.value->>'line_no')::smallint)
          from jsonb_array_elements(p_lines) x(value)) then
      raise exception 'Esta solicitud ya se utilizó con otros datos'; end if;
    return v_existing.id;
  end if;
  select * into v_sale from public.sales where company_id=p_company and id=p_sale;
  if not found then raise exception 'Venta inexistente'; end if;
  if exists(select 1 from public.sale_adjustments
    where company_id=p_company and sale_id=p_sale and kind='cancel') then
    raise exception 'Esta venta ya está anulada'; end if;
  select count(*) into v_expected from public.sale_lines l
    where l.company_id=p_company and l.sale_id=p_sale
      and l.quantity>coalesce((select sum(al.quantity)
        from public.sale_adjustment_lines al
        where al.company_id=l.company_id and al.sale_id=l.sale_id
          and al.sale_line_no=l.line_no),0);
  if p_kind='cancel' and jsonb_array_length(p_lines)<>v_expected then
    raise exception 'Para anular, devolvé todas las cantidades pendientes'; end if;
  insert into public.sale_adjustments(company_id,sale_id,request_id,kind,reason,
    credit_total,actor_id)
  values(p_company,p_sale,p_request_id,p_kind,btrim(p_reason),0,auth.uid())
  returning id into v_adjustment;
  for v_entry in select value from jsonb_array_elements(p_lines) x(value) loop
    if jsonb_typeof(v_entry)<>'object' or coalesce(v_entry->>'line_no','') !~ '^[0-9]{1,2}$'
      or coalesce(v_entry->>'quantity','') !~ '^[0-9]+(\.[0-9]{1,6})?$'
      or jsonb_typeof(v_entry->'restock')<>'boolean' then
      raise exception 'Revisá los productos y las cantidades devueltas'; end if;
    select * into v_row from public.sale_lines
      where company_id=p_company and sale_id=p_sale
        and line_no=(v_entry->>'line_no')::smallint;
    if not found then raise exception 'Producto inexistente en la venta'; end if;
    v_quantity:=(v_entry->>'quantity')::numeric;
    v_restock:=(v_entry->>'restock')::boolean;
    select v_row.quantity-coalesce(sum(al.quantity),0) into v_remaining
      from public.sale_adjustment_lines al
      where al.company_id=p_company and al.sale_id=p_sale
        and al.sale_line_no=v_row.line_no;
    if v_quantity<=0 or v_quantity>v_remaining then
      raise exception 'La devolución supera la cantidad pendiente de %',v_row.item_name; end if;
    if p_kind='cancel' and v_quantity<>v_remaining then
      raise exception 'La anulación debe incluir toda la cantidad pendiente'; end if;
    v_line_credit:=case when v_quantity=v_remaining then
      v_row.line_total-coalesce((select sum(al.credit_amount)
        from public.sale_adjustment_lines al where al.company_id=p_company
          and al.sale_id=p_sale and al.sale_line_no=v_row.line_no),0)
      else round(v_quantity*v_row.unit_price,2) end;
    v_operation:=null;
    if v_restock then
      if v_row.lot_code is not null then
        select expires_on into v_expiry from public.stock_lots
        where company_id=p_company and item_id=v_row.item_id
          and lower(code)=lower(v_row.lot_code);
      else v_expiry:=null; end if;
      v_operation:=public.post_stock_operation(p_company,v_row.item_id,
        v_row.warehouse_id,null,'receipt',v_quantity,
        'Devolución venta '||v_sale.number::text,gen_random_uuid(),v_row.lot_code,v_expiry);
    end if;
    insert into public.sale_adjustment_lines(company_id,adjustment_id,sale_id,
      sale_line_no,quantity,credit_amount,restocked,stock_operation_id)
    values(p_company,v_adjustment,p_sale,v_row.line_no,v_quantity,v_line_credit,
      v_restock,v_operation);
    v_credit:=v_credit+v_line_credit;
    v_count:=v_count+1;
  end loop;
  if p_kind='cancel' and v_count<>v_expected then
    raise exception 'Faltan productos por anular'; end if;
  update public.sale_adjustments set credit_total=v_credit
    where company_id=p_company and id=v_adjustment;
  return v_adjustment;
end;
$$;
-- La función finaliza el total del encabezado antes de confirmar la transacción.
revoke execute on function public.adjust_sale(uuid,uuid,text,text,jsonb,uuid) from public,anon;
grant execute on function public.adjust_sale(uuid,uuid,text,text,jsonb,uuid) to authenticated;

-- Saldos devueltos: cobros anteriores quedan en el historial; un pago que
-- excede el neto de la venta pasa a ser un crédito del cliente hasta reintegrarlo.
create table public.sale_refunds (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  sale_id uuid not null,
  request_id uuid not null,
  account_id uuid not null,
  treasury_entry_id uuid not null,
  amount numeric(18,2) not null check(amount>0),
  reason text not null check(length(btrim(reason)) between 5 and 240),
  actor_id uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique(company_id,request_id),
  unique(company_id,treasury_entry_id),
  foreign key(company_id,sale_id) references public.sales(company_id,id),
  foreign key(company_id,account_id) references public.treasury_accounts(company_id,id),
  foreign key(company_id,treasury_entry_id) references public.treasury_entries(company_id,id)
);
alter table public.sale_refunds enable row level security;
create policy sale_refunds_read on public.sale_refunds for select to authenticated
  using((select private.has_permission(company_id,'finance','read')));
revoke all on public.sale_refunds from public,anon,authenticated;
grant select on public.sale_refunds to authenticated;
create trigger sale_refunds_immutable before update or delete on public.sale_refunds
  for each row execute function private.reject_stock_history_mutation();

create function public.sale_credit_balance(p_company uuid,p_sale uuid)
returns table(net_total numeric,paid numeric,refunded numeric,credit_due numeric)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'sales','read') then
    raise exception 'Sin permiso para consultar saldos' using errcode='42501'; end if;
  return query select greatest(0,s.total-coalesce((select sum(a.credit_total)
      from public.sale_adjustments a where a.company_id=p_company and a.sale_id=p_sale),0)),
    coalesce((select sum(p.amount) from public.sale_payments p
      where p.company_id=p_company and p.sale_id=p_sale and not exists(
        select 1 from public.sale_payment_reversals r
        where r.company_id=p.company_id and r.payment_id=p.id)),0),
    coalesce((select sum(f.amount) from public.sale_refunds f
      where f.company_id=p_company and f.sale_id=p_sale),0),
    greatest(0,
      coalesce((select sum(p.amount) from public.sale_payments p
        where p.company_id=p_company and p.sale_id=p_sale and not exists(
          select 1 from public.sale_payment_reversals r
          where r.company_id=p.company_id and r.payment_id=p.id)),0)
      - greatest(0,s.total-coalesce((select sum(a.credit_total)
        from public.sale_adjustments a where a.company_id=p_company and a.sale_id=p_sale),0))
      - coalesce((select sum(f.amount) from public.sale_refunds f
        where f.company_id=p_company and f.sale_id=p_sale),0))
  from public.sales s where s.company_id=p_company and s.id=p_sale;
end;
$$;
revoke execute on function public.sale_credit_balance(uuid,uuid) from public,anon;
grant execute on function public.sale_credit_balance(uuid,uuid) to authenticated;

create function public.refund_sale_credit(p_company uuid,p_sale uuid,p_account uuid,
  p_amount numeric,p_reason text,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.sale_refunds%rowtype; v_available numeric;
  v_entry uuid; v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert')
    or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'sales','update') then
    raise exception 'Sin permiso para registrar devoluciones de dinero' using errcode='42501'; end if;
  if p_sale is null or p_account is null or p_request_id is null or p_amount is null
    or p_amount<=0 or p_amount<>round(p_amount,2)
    or length(btrim(coalesce(p_reason,''))) not between 5 and 240 then
    raise exception 'Indicá cuenta, importe y motivo del reintegro'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.sale_refunds
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.actor_id<>auth.uid() or v_existing.sale_id<>p_sale
      or v_existing.account_id<>p_account or v_existing.amount<>p_amount
      or v_existing.reason<>btrim(p_reason) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_existing.id;
  end if;
  select b.credit_due into v_available from public.sale_credit_balance(p_company,p_sale) b;
  if v_available is null or p_amount>v_available then
    raise exception 'El reintegro supera el crédito disponible'; end if;
  v_entry:=public.post_treasury_entry(p_company,p_account,'expense',p_amount,
    null,'Reintegro venta '||p_sale::text,
    (now() at time zone 'America/Argentina/Buenos_Aires')::date,p_request_id,null);
  insert into public.sale_refunds(company_id,sale_id,request_id,account_id,
    treasury_entry_id,amount,reason,actor_id)
  values(p_company,p_sale,p_request_id,p_account,v_entry,p_amount,btrim(p_reason),auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;
revoke execute on function public.refund_sale_credit(uuid,uuid,uuid,numeric,text,uuid) from public,anon;
grant execute on function public.refund_sale_credit(uuid,uuid,uuid,numeric,text,uuid) to authenticated;

-- Evita cobros posteriores por encima del valor neto y la reversión de cobros
-- que ya fueron reintegrados al cliente.
create function private.guard_sale_payment_net()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_net numeric; v_paid numeric;
begin
  select greatest(0,s.total-coalesce(sum(a.credit_total),0)) into v_net
  from public.sales s left join public.sale_adjustments a
    on a.company_id=s.company_id and a.sale_id=s.id
  where s.company_id=new.company_id and s.id=new.sale_id
  group by s.total;
  select coalesce(sum(p.amount),0) into v_paid from public.sale_payments p
    where p.company_id=new.company_id and p.sale_id=new.sale_id
      and not exists(select 1 from public.sale_payment_reversals r
        where r.company_id=p.company_id and r.payment_id=p.id);
  if v_net is null or v_paid+new.amount>v_net then
    raise exception 'El cobro supera el saldo neto después de las devoluciones'; end if;
  return new;
end;
$$;
create trigger guard_sale_payment_net before insert on public.sale_payments
  for each row execute function private.guard_sale_payment_net();
revoke execute on function private.guard_sale_payment_net() from public,anon,authenticated;

create function private.guard_reversal_after_refund()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_net numeric; v_paid numeric; v_refunded numeric; v_payment public.sale_payments%rowtype;
begin
  select * into v_payment from public.sale_payments
    where company_id=new.company_id and id=new.payment_id;
  select greatest(0,s.total-coalesce(sum(a.credit_total),0)) into v_net
    from public.sales s left join public.sale_adjustments a
      on a.company_id=s.company_id and a.sale_id=s.id
    where s.company_id=new.company_id and s.id=v_payment.sale_id
    group by s.total;
  select coalesce(sum(p.amount),0) into v_paid from public.sale_payments p
    where p.company_id=new.company_id and p.sale_id=v_payment.sale_id
      and p.id<>new.payment_id and not exists(
        select 1 from public.sale_payment_reversals r
        where r.company_id=p.company_id and r.payment_id=p.id);
  select coalesce(sum(f.amount),0) into v_refunded from public.sale_refunds f
    where f.company_id=new.company_id and f.sale_id=v_payment.sale_id;
  if v_refunded>greatest(0,v_paid-v_net) then
    raise exception 'El cobro ya tiene un reintegro: no puede anularse sin regularizarlo'; end if;
  return new;
end;
$$;
create trigger guard_reversal_after_refund before insert on public.sale_payment_reversals
  for each row execute function private.guard_reversal_after_refund();
revoke execute on function private.guard_reversal_after_refund() from public,anon,authenticated;

create or replace function public.sale_receivables(p_company uuid,p_page integer default 0,
  p_search text default '')
returns table(sale_id uuid,sale_number bigint,customer_name text,total numeric,
  paid numeric,outstanding numeric,created_at timestamptz,total_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'sales','read') then
    raise exception 'Necesitás permisos de Finanzas y Ventas' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000
    or length(coalesce(p_search,''))>100 then
    raise exception 'Página o búsqueda inválida'; end if;
  return query with amounts as (
    select p.sale_id,sum(p.amount) paid_amount from public.sale_payments p
    where p.company_id=p_company and not exists(
      select 1 from public.sale_payment_reversals r
      where r.company_id=p.company_id and r.payment_id=p.id)
    group by p.sale_id
  ), credits as (
    select a.sale_id,sum(a.credit_total) credit_amount
    from public.sale_adjustments a where a.company_id=p_company group by a.sale_id
  ), filtered as (
    select s.id,s.number,s.customer_name,
      greatest(0,s.total-coalesce(c.credit_amount,0)) net,
      coalesce(a.paid_amount,0) paid_amount,s.created_at
    from public.sales s
    left join amounts a on a.sale_id=s.id
    left join credits c on c.sale_id=s.id
    where s.company_id=p_company and (btrim(coalesce(p_search,''))=''
      or s.customer_name ilike '%'||btrim(p_search)||'%'
      or s.number::text ilike '%'||btrim(p_search)||'%')
  )
  select f.id,f.number,f.customer_name,f.net,f.paid_amount,
    greatest(0,f.net-f.paid_amount),f.created_at,count(*) over()
  from filtered f order by f.created_at desc,f.id desc
  limit 25 offset p_page*25;
end;
$$;

create or replace function public.erp_sales_profit_summary(p_company uuid)
returns table(sales_total numeric,covered_revenue numeric,covered_cost numeric,
  estimated_profit numeric,missing_lines bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'sales','read') then
    raise exception 'Necesitás acceso a finanzas y ventas' using errcode='42501'; end if;
  return query with net_lines as (
    select l.line_total-coalesce(a.credit,0) revenue,
      l.quantity-coalesce(a.quantity,0) quantity,
      l.estimated_unit_cost cost
    from public.sale_lines l
    left join lateral (
      select sum(al.quantity) filter(where al.restocked) quantity,
        sum(al.credit_amount) credit
      from public.sale_adjustment_lines al
      where al.company_id=l.company_id and al.sale_id=l.sale_id
        and al.sale_line_no=l.line_no
    ) a on true where l.company_id=p_company
  ) select coalesce(sum(n.revenue),0),
    coalesce(sum(n.revenue) filter(where n.cost is not null),0),
    coalesce(sum(n.quantity*n.cost),0),
    coalesce(sum(n.revenue-n.quantity*n.cost) filter(where n.cost is not null),0),
    count(*) filter(where n.cost is null and n.quantity>0)
  from net_lines n;
end;
$$;

create or replace function public.erp_operational_dashboard(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb:='{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al inicio' using errcode='42501'; end if;
  if private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object(
      'sales_30d',(select count(*) from public.sales s
        where s.company_id=p_company and s.created_at>=now()-interval '30 days'
          and s.total>coalesce((select sum(a.credit_total) from public.sale_adjustments a
            where a.company_id=s.company_id and a.sale_id=s.id),0)),
      'revenue_30d',(select coalesce(sum(s.total-coalesce(a.credit,0)),0)
        from public.sales s left join lateral (
          select sum(sa.credit_total) credit from public.sale_adjustments sa
          where sa.company_id=s.company_id and sa.sale_id=s.id
        ) a on true
        where s.company_id=p_company and s.created_at>=now()-interval '30 days')
    );
  end if;
  if private.has_permission(p_company,'finance','read')
    and private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object(
      'receivables',(select coalesce(sum(greatest(0,s.total-coalesce(a.credit,0)
        -coalesce(p.paid,0))),0)
        from public.sales s
        left join lateral (select sum(sa.credit_total) credit
          from public.sale_adjustments sa
          where sa.company_id=s.company_id and sa.sale_id=s.id) a on true
        left join lateral (select sum(sp.amount) paid from public.sale_payments sp
          where sp.company_id=s.company_id and sp.sale_id=s.id
          and not exists(select 1 from public.sale_payment_reversals r
            where r.company_id=sp.company_id and r.payment_id=sp.id)) p on true
        where s.company_id=p_company)
    );
    if private.get_user_role(p_company)='admin' then
      v_result:=v_result||jsonb_build_object(
        'profit_30d',(select coalesce(sum(
          (l.line_total-coalesce(a.credit,0))
          -(l.quantity-coalesce(a.quantity,0))*l.estimated_unit_cost),0)
          from public.sale_lines l
          join public.sales s on s.company_id=l.company_id and s.id=l.sale_id
          left join lateral (select sum(al.credit_amount) credit,
            sum(al.quantity) filter(where al.restocked) quantity
            from public.sale_adjustment_lines al where al.company_id=l.company_id
              and al.sale_id=l.sale_id and al.sale_line_no=l.line_no) a on true
          where s.company_id=p_company and s.created_at>=now()-interval '30 days'
            and l.estimated_unit_cost is not null)
      );
    end if;
  end if;
  if private.has_permission(p_company,'purchases','read') then
    v_result:=v_result||jsonb_build_object(
      'open_orders',(select count(*) from public.purchase_orders o
        where o.company_id=p_company and o.status in ('open','partial')));
  end if;
  if private.has_permission(p_company,'production','read') then
    v_result:=v_result||jsonb_build_object(
      'planned_runs',(select count(*) from public.production_plans p
        where p.company_id=p_company and p.status='planned'));
  end if;
  if private.has_permission(p_company,'items','read')
    and private.has_permission(p_company,'stock','read') then
    v_result:=v_result||jsonb_build_object(
      'low_stock',(select count(*) from public.items i
        where i.company_id=p_company and i.active and i.minimum_stock>0
          and i.minimum_stock>(select coalesce(sum(b.quantity),0)
            from public.stock_balances b where b.company_id=i.company_id
              and b.item_id=i.id)));
  end if;
  return v_result;
end;
$$;

-- Al elegir proveedor, sólo se ofrecen sus materiales activos con cotización.
create or replace function public.purchase_material_options(
  p_company uuid,p_search text default '',p_supplier uuid default null
) returns table(id uuid,code text,name text,unit_symbol text,item_type text,
  reference_unit_cost numeric,supplier_unit_price numeric)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query select i.id,i.code,i.name,u.symbol,i.item_type,i.reference_unit_cost,
    case when si.currency_code='USD' then
      round(si.unit_price*private.current_fx_rate(p_company,si.exchange_rate_type_id)
        *(1+si.adjustment_percent/100),2)
    else round(si.unit_price*(1+si.adjustment_percent/100),2) end
  from public.items i
  join public.units u on u.company_id=i.company_id and u.id=i.unit_id
  left join public.supplier_items si on si.company_id=i.company_id
    and si.item_id=i.id and si.supplier_id=p_supplier
  where i.company_id=p_company and i.active
    and (p_supplier is null or si.item_id is not null)
    and (coalesce(p_search,'')='' or i.name ilike '%'||p_search||'%'
      or i.code ilike '%'||p_search||'%' or i.barcode ilike '%'||p_search||'%')
  order by i.name,i.id limit 50;
end;
$$;

create function private.guard_purchase_supplier_item()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_supplier uuid; v_currency text; v_exchange_type uuid;
begin
  select o.supplier_id into v_supplier from public.purchase_orders o
    where o.company_id=new.company_id and o.id=new.order_id;
  select si.currency_code,si.exchange_rate_type_id into v_currency,v_exchange_type
    from public.supplier_items si
    join public.items i on i.company_id=si.company_id and i.id=si.item_id
    where si.company_id=new.company_id and si.supplier_id=v_supplier
      and si.item_id=new.item_id and i.active;
  if not found then
    raise exception 'El proveedor no tiene asociado este ítem. Cargá primero su cotización'; end if;
  if v_currency='USD' and private.current_fx_rate(new.company_id,v_exchange_type) is null then
    raise exception 'La cotización en dólares necesita un tipo de cambio vigente'; end if;
  return new;
end;
$$;
create trigger guard_purchase_supplier_item before insert on public.purchase_order_lines
  for each row execute function private.guard_purchase_supplier_item();
revoke execute on function private.guard_purchase_supplier_item() from public,anon,authenticated;

-- Reintentos de una orden no deben duplicar el comprobante si falla la red.
create table public.purchase_order_requests (
  company_id uuid not null,
  request_id uuid not null,
  order_id uuid not null,
  request_payload jsonb not null,
  actor_id uuid not null references auth.users(id),
  primary key(company_id,request_id),
  unique(company_id,order_id),
  foreign key(company_id,order_id) references public.purchase_orders(company_id,id)
);
revoke all on public.purchase_order_requests from public,anon,authenticated;

create function public.create_purchase_order_once(p_company uuid,p_supplier uuid,
  p_note text,p_lines jsonb,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_existing public.purchase_order_requests%rowtype;
  v_payload jsonb; v_order uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','insert') then
    raise exception 'Sin permiso para crear órdenes' using errcode='42501'; end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('purchase-order:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('supplier',p_supplier,
    'note',btrim(coalesce(p_note,'')),'lines',p_lines);
  select * into v_existing from public.purchase_order_requests
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.actor_id<>auth.uid() or v_existing.request_payload<>v_payload then
      raise exception 'Esta solicitud ya se usó con otra orden'; end if;
    return v_existing.order_id;
  end if;
  v_order:=public.create_purchase_order(p_company,p_supplier,p_note,p_lines);
  insert into public.purchase_order_requests(company_id,request_id,order_id,
    request_payload,actor_id)
  values(p_company,p_request_id,v_order,v_payload,auth.uid());
  return v_order;
end;
$$;
revoke execute on function public.create_purchase_order_once(uuid,uuid,text,jsonb,uuid)
  from public,anon;
grant execute on function public.create_purchase_order_once(uuid,uuid,text,jsonb,uuid)
  to authenticated;

-- El cliente actualizado usa siempre la operación idempotente.
revoke execute on function public.create_purchase_order(uuid,uuid,text,jsonb)
  from authenticated;

-- Un único pedido de red encuentra los proveedores comunes a todos los ítems.
create function public.purchase_suppliers_for_items(p_company uuid,p_items uuid[])
returns table(id uuid,name text)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin permiso para consultar proveedores' using errcode='42501'; end if;
  if p_items is null or coalesce(array_length(p_items,1),0) not between 1 and 40
    or (select count(distinct x) from unnest(p_items) x)<>array_length(p_items,1)
    or array_position(p_items,null) is not null then
    raise exception 'Seleccioná entre uno y cuarenta ítems distintos'; end if;
  return query select s.id,s.name from public.suppliers s
    join public.supplier_items si on si.company_id=s.company_id
      and si.supplier_id=s.id and si.item_id=any(p_items)
    join public.items i on i.company_id=si.company_id and i.id=si.item_id and i.active
    where s.company_id=p_company and s.active
    group by s.id,s.name having count(distinct si.item_id)=array_length(p_items,1)
    order by s.name limit 100;
end;
$$;
revoke execute on function public.purchase_suppliers_for_items(uuid,uuid[]) from public,anon;
grant execute on function public.purchase_suppliers_for_items(uuid,uuid[]) to authenticated;
