-- Dromux ERP · proveedores y compras, actualización 030.
-- Requiere 029 y las migraciones anteriores. Ejecutar una vez, completo.
begin;

alter table public.suppliers add column supplies_description text not null default ''
  check(length(supplies_description)<=200);
grant insert(supplies_description), update(supplies_description) on public.suppliers to authenticated;

-- La cotización es un historial: un valor anterior puede volver a ser vigente.
-- Se retira sólo la unicidad de valor/fecha; la identidad y la inmutabilidad siguen vigentes.
do $$ declare v_constraint record; begin
  for v_constraint in
    select con.conname from pg_catalog.pg_constraint con
    where con.conrelid='public.exchange_rates'::regclass and con.contype='u'
      and (select array_agg(att.attname::text order by key.ord)
        from unnest(con.conkey) with ordinality as key(attnum,ord)
        join pg_catalog.pg_attribute att on att.attrelid=con.conrelid
          and att.attnum=key.attnum)
        =array['company_id','type_id','effective_on','ars_per_usd']::text[]
  loop
    execute format('alter table public.exchange_rates drop constraint %I',v_constraint.conname);
  end loop;
end $$;

create or replace function public.add_exchange_rate(
  p_company uuid,p_type uuid,p_rate numeric,p_date date
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_latest public.exchange_rates%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para actualizar el tipo de cambio' using errcode='42501';
  end if;
  if p_rate is null or p_rate<=0 or p_rate>=1000000000000
    or p_rate<>round(p_rate,6) or p_date is null
    or p_date>(now() at time zone 'America/Argentina/Buenos_Aires')::date then
    raise exception 'Indicá una cotización válida y una fecha no futura';
  end if;
  perform 1 from public.companies c where c.id=p_company and c.active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('exchange-rate:'||p_company::text||':'||p_type::text,0));
  perform 1 from public.exchange_rate_types t where t.company_id=p_company
    and t.id=p_type and t.active for share;
  if not found then raise exception 'Elegí un tipo de dólar activo'; end if;
  select * into v_latest from public.exchange_rates r
    where r.company_id=p_company and r.type_id=p_type and r.effective_on=p_date
    order by r.created_at desc,r.id desc limit 1;
  if found and v_latest.ars_per_usd=p_rate then return v_latest.id; end if;
  insert into public.exchange_rates(company_id,type_id,ars_per_usd,effective_on,actor_id)
    values(p_company,p_type,p_rate,p_date,auth.uid()) returning id into v_id;
  return v_id;
end; $$;

-- Todos los tipos de ítem pueden tener proveedor: también insumos y piezas compradas.
create or replace function private.check_supplier_item()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' or new.unit_price is distinct from old.unit_price
    or new.supplier_sku is distinct from old.supplier_sku
    or new.currency_code is distinct from old.currency_code
    or new.exchange_rate_type_id is distinct from old.exchange_rate_type_id
    or new.adjustment_percent is distinct from old.adjustment_percent
    or (new.preferred and new.preferred is distinct from old.preferred) then
    if not exists(select 1 from public.items i where i.company_id=new.company_id
      and i.id=new.item_id and i.active) then
      raise exception 'Elegí un ítem activo'; end if;
    if not exists(select 1 from public.suppliers s where s.company_id=new.company_id
      and s.id=new.supplier_id and s.active) then
      raise exception 'Elegí un proveedor activo'; end if;
    if new.currency_code='USD' and not exists(select 1 from public.exchange_rate_types t
      where t.company_id=new.company_id and t.id=new.exchange_rate_type_id and t.active) then
      raise exception 'Elegí un tipo de dólar activo'; end if;
  end if;
  new.updated_at:=clock_timestamp();
  return new;
end; $$;

create function public.supplier_directory(p_company uuid,p_search text default '',p_page integer default 0)
returns table(id uuid,name text,tax_id text,email text,phone text,notes text,
  active boolean,lead_time_days integer,supplies_description text,item_count bigint,total_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a proveedores' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then
    raise exception 'Búsqueda inválida'; end if;
  return query select s.id,s.name,s.tax_id,s.email,s.phone,s.notes,s.active,
    s.lead_time_days::integer,s.supplies_description,
    (select count(*) from public.supplier_items q where q.company_id=s.company_id and q.supplier_id=s.id),
    count(*) over()
    from public.suppliers s where s.company_id=p_company
      and (coalesce(p_search,'')='' or s.name ilike '%'||p_search||'%'
        or s.supplies_description ilike '%'||p_search||'%' or s.tax_id ilike '%'||p_search||'%')
    order by s.active desc,s.name,s.id limit 25 offset p_page*25;
end; $$;

create function public.supplier_quote_catalog(
  p_company uuid,p_supplier uuid default null,p_item uuid default null,
  p_search text default '',p_page integer default 0
) returns table(supplier_id uuid,supplier_name text,supplier_active boolean,
  item_id uuid,item_code text,item_name text,item_type text,item_active boolean,unit_symbol text,
  unit_price numeric,currency_code text,exchange_rate_type_id uuid,exchange_rate_type text,
  exchange_rate numeric,adjustment_percent numeric,unit_cost_ars numeric,
  preferred boolean,supplier_sku text,updated_at timestamptz,is_best_price boolean,total_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a precios de proveedores' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then
    raise exception 'Búsqueda inválida'; end if;
  return query with costs as (
    select q.supplier_id,s.name supplier_name,s.active supplier_active,
      q.item_id,i.code item_code,i.name item_name,i.item_type,i.active item_active,u.symbol unit_symbol,
      q.unit_price,q.currency_code,q.exchange_rate_type_id,t.name exchange_rate_type,
      case when q.currency_code='USD' then private.current_fx_rate(p_company,q.exchange_rate_type_id)
        else 1::numeric end exchange_rate,q.adjustment_percent,q.preferred,q.supplier_sku,q.updated_at
    from public.supplier_items q
    join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id
    join public.items i on i.company_id=q.company_id and i.id=q.item_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    left join public.exchange_rate_types t on t.company_id=q.company_id and t.id=q.exchange_rate_type_id
    where q.company_id=p_company
  ), priced as (
    select c.*,round(c.unit_price*c.exchange_rate*(1+c.adjustment_percent/100),2) unit_cost_ars
    from costs c
  ), ranked as (
    select c.*,min(c.unit_cost_ars) filter(where c.supplier_active and c.item_active)
      over(partition by c.item_id) best_price,
      count(*) filter(where c.supplier_active and c.item_active and c.unit_cost_ars is not null)
      over(partition by c.item_id) comparable_count from priced c
  ) select c.supplier_id,c.supplier_name,c.supplier_active,c.item_id,c.item_code,c.item_name,
    c.item_type,c.item_active,c.unit_symbol,c.unit_price,c.currency_code,c.exchange_rate_type_id,
    c.exchange_rate_type,c.exchange_rate,c.adjustment_percent,c.unit_cost_ars,c.preferred,
    c.supplier_sku,c.updated_at,
    (c.supplier_active and c.item_active and c.comparable_count>1 and c.unit_cost_ars=c.best_price),
    count(*) over()
    from ranked c where (p_supplier is null or c.supplier_id=p_supplier)
      and (p_item is null or c.item_id=p_item)
      and (coalesce(p_search,'')='' or c.item_name ilike '%'||p_search||'%'
        or c.item_code ilike '%'||p_search||'%' or c.supplier_sku ilike '%'||p_search||'%')
    order by c.supplier_active desc,c.item_active desc,
      case when p_supplier is null then c.unit_cost_ars end asc nulls last,
      c.item_name,c.supplier_name,c.item_id,c.supplier_id
    limit 25 offset p_page*25;
end; $$;

-- Guardado atómico; no sobrescribe una edición hecha por otra persona desde la vista previa.
create function public.save_supplier_quote(
  p_company uuid,p_supplier uuid,p_item uuid,p_price numeric,p_sku text,
  p_currency text,p_exchange_type uuid,p_adjustment numeric,
  p_expected_updated_at timestamptz default null,p_create_only boolean default false
) returns void language plpgsql security definer set search_path='' as $$
declare v_existing public.supplier_items%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para modificar precios' using errcode='42501'; end if;
  if p_item is null or p_supplier is null or p_price is null or p_price<0
    or p_price>=10000000000000000 or p_price<>round(p_price,2)
    or length(coalesce(p_sku,''))>80 or p_currency is null or p_currency not in ('ARS','USD')
    or p_adjustment is null or p_adjustment not between -99.99 and 1000
    or p_adjustment<>round(p_adjustment,2)
    or (p_currency='USD' and p_exchange_type is null)
    or (p_currency='ARS' and p_exchange_type is not null) then
    raise exception 'Revisá precio, moneda y tipo de dólar'; end if;
  perform 1 from public.companies c where c.id=p_company and c.active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('supplier-quote:'||p_company::text||':'||p_supplier::text||':'||p_item::text,0));
  select * into v_existing from public.supplier_items q where q.company_id=p_company
    and q.supplier_id=p_supplier and q.item_id=p_item for update;
  if found then
    if p_create_only then raise exception 'Este ítem ya está asociado. Usá Editar precio en su ficha'; end if;
    if p_expected_updated_at is null or v_existing.updated_at<>p_expected_updated_at then
      raise exception 'El precio cambió mientras lo editabas. Cerrá la ventana y volvé a abrirlo'; end if;
    update public.supplier_items set unit_price=p_price,supplier_sku=btrim(coalesce(p_sku,'')),
      currency_code=p_currency,exchange_rate_type_id=p_exchange_type,adjustment_percent=p_adjustment
      where company_id=p_company and supplier_id=p_supplier and item_id=p_item;
  else
    if not p_create_only then raise exception 'La relación ya no existe. Agregá el ítem nuevamente'; end if;
    insert into public.supplier_items(company_id,supplier_id,item_id,unit_price,supplier_sku,
      currency_code,exchange_rate_type_id,adjustment_percent)
      values(p_company,p_supplier,p_item,p_price,btrim(coalesce(p_sku,'')),p_currency,p_exchange_type,p_adjustment);
  end if;
end; $$;

create function public.supplier_adjustment_preview(p_company uuid,p_supplier uuid,p_item uuid,p_percent numeric)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para ajustar precios' using errcode='42501'; end if;
  if p_supplier is null or p_percent is null or p_percent not between -99.99 and 1000
    or p_percent=0 or p_percent<>round(p_percent,2) then
    raise exception 'Elegí proveedor y porcentaje válido'; end if;
  return jsonb_build_object('count',(select count(*) from public.supplier_items q
    join public.items i on i.company_id=q.company_id and i.id=q.item_id and i.active
    join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id and s.active
    where q.company_id=p_company and q.supplier_id=p_supplier and (p_item is null or q.item_id=p_item)),
    'examples',coalesce((select jsonb_agg(x) from (
      select i.name,q.unit_price,q.currency_code,
        round(q.unit_price*(1+p_percent/100),2) next_price
      from public.supplier_items q
      join public.items i on i.company_id=q.company_id and i.id=q.item_id and i.active
      join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id and s.active
      where q.company_id=p_company and q.supplier_id=p_supplier and (p_item is null or q.item_id=p_item)
      order by i.name limit 5) x),'[]'::jsonb));
end; $$;

revoke execute on function public.supplier_directory(uuid,text,integer),
  public.supplier_quote_catalog(uuid,uuid,uuid,text,integer),
  public.save_supplier_quote(uuid,uuid,uuid,numeric,text,text,uuid,numeric,timestamptz,boolean),
  public.supplier_adjustment_preview(uuid,uuid,uuid,numeric) from public,anon;
grant execute on function public.supplier_directory(uuid,text,integer),
  public.supplier_quote_catalog(uuid,uuid,uuid,text,integer),
  public.save_supplier_quote(uuid,uuid,uuid,numeric,text,text,uuid,numeric,timestamptz,boolean),
  public.supplier_adjustment_preview(uuid,uuid,uuid,numeric) to authenticated;

create or replace function public.adjust_supplier_prices(p_company uuid,p_supplier uuid,p_item uuid,
  p_percent numeric,p_request_id uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_previous public.supplier_price_adjustments%rowtype; v_count integer;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para ajustar precios' using errcode='42501'; end if;
  if p_request_id is null or p_percent is null or p_percent not between -99.99 and 1000
    or p_percent<>round(p_percent,2) or p_percent=0 or (p_supplier is null and p_item is null) then
    raise exception 'Elegí proveedor o materia prima y un porcentaje distinto de cero'; end if;
  perform 1 from public.companies c where c.id=p_company and c.active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('adjustment:'||p_company::text,0));
  select * into v_previous from public.supplier_price_adjustments
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.supplier_id is distinct from p_supplier
      or v_previous.item_id is distinct from p_item or v_previous.percent<>p_percent then
      raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_previous.changed_count;
  end if;
  update public.supplier_items si
    set unit_price=round(si.unit_price*(1+p_percent/100),2)
    where si.company_id=p_company
      and exists(select 1 from public.suppliers s where s.company_id=si.company_id
        and s.id=si.supplier_id and s.active)
      and exists(select 1 from public.items i where i.company_id=si.company_id
        and i.id=si.item_id and i.active)
      and (p_supplier is null or si.supplier_id=p_supplier)
      and (p_item is null or si.item_id=p_item);
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'No hay cotizaciones para ese filtro'; end if;
  insert into public.supplier_price_adjustments(company_id,request_id,supplier_id,
    item_id,percent,changed_count,actor_id)
  values(p_company,p_request_id,p_supplier,p_item,p_percent,v_count,auth.uid());
  return v_count;
end;
$$;

-- Resumen vigente por tipo, independiente del límite del historial visible.
create function public.exchange_rate_overview(p_company uuid)
returns table(id uuid,name text,active boolean,current_rate numeric,effective_on date)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a cotizaciones' using errcode='42501'; end if;
  return query select t.id,t.name,t.active,r.ars_per_usd,r.effective_on
    from public.exchange_rate_types t left join lateral (
      select e.ars_per_usd,e.effective_on from public.exchange_rates e
      where e.company_id=t.company_id and e.type_id=t.id
        and e.effective_on<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
      order by e.effective_on desc,e.created_at desc,e.id desc limit 1
    ) r on true where t.company_id=p_company order by t.name;
end; $$;
revoke execute on function public.exchange_rate_overview(uuid) from public,anon;
grant execute on function public.exchange_rate_overview(uuid) to authenticated;

commit;
