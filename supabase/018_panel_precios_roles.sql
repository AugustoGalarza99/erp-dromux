-- ERP Dromux · panel operativo, listas de precios y edición de roles.
-- Aplicar después de las migraciones anteriores; no modifica ventas históricas.

-- Vuelve a habilitar el cambio de rol para quien tenga Usuarios → Editar.
-- Las reglas del administrador y del último administrador activo siguen vigentes.
create or replace function public.set_company_member(
  p_company uuid, p_user uuid, p_role uuid, p_active boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare v_old_code text; v_new_code text; v_old_active boolean;
begin
  if auth.uid() is null or not private.has_permission(p_company,'users','update') then
    raise exception 'Sin permiso para editar usuarios' using errcode='42501';
  end if;
  if p_active is null then raise exception 'Estado inválido'; end if;
  select r.code into v_new_code from public.roles r
    where r.id=p_role and r.company_id=p_company;
  if v_new_code is null then raise exception 'El rol no pertenece a esta empresa'; end if;
  perform 1 from public.companies where id=p_company for update;
  select r.code,cu.active into v_old_code,v_old_active
    from public.company_users cu join public.roles r
      on r.id=cu.role_id and r.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=p_user for update of cu;
  if v_old_code is null then raise exception 'El usuario no pertenece a esta empresa'; end if;
  if (v_old_code='admin' or v_new_code='admin')
    and private.get_user_role(p_company)<>'admin' then
    raise exception 'Solo un administrador puede asignar el rol administrador';
  end if;
  if p_user=auth.uid() and not p_active then
    raise exception 'No podés suspender tu propia cuenta'; end if;
  if v_old_code='admin' and v_old_active and
    (v_new_code<>'admin' or not p_active) and
    (select count(*) from public.company_users cu join public.roles r
      on r.id=cu.role_id and r.company_id=cu.company_id
      where cu.company_id=p_company and cu.active and r.code='admin')<=1 then
    raise exception 'Debe permanecer al menos un administrador activo';
  end if;
  update public.company_users set role_id=p_role,active=p_active
    where company_id=p_company and user_id=p_user;
end;
$$;
revoke execute on function public.set_company_member(uuid,uuid,uuid,boolean)
  from public,anon;
grant execute on function public.set_company_member(uuid,uuid,uuid,boolean)
  to authenticated;

-- Lista de venta: información visible para un rol con Ventas → Ver.
create or replace function public.erp_public_price_list(p_company uuid,p_search text default '')
returns table(id uuid,code text,name text,unit_symbol text,price numeric)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company,'sales','read') then
    raise exception 'Sin permiso para consultar precios' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query select i.id,i.code,i.name,u.symbol,i.sale_unit_price
    from public.items i join public.units u
      on u.company_id=i.company_id and u.id=i.unit_id
    where i.company_id=p_company and i.active and i.item_type='finished_product'
      and (p_search='' or i.code ilike '%'||p_search||'%'
        or i.name ilike '%'||p_search||'%')
    order by i.name,i.id limit 300;
end;
$$;

-- Administrador: precios de venta de la misma ficha de productos.
-- Reutiliza la función de costos de la migración 016 sin exponerla al vendedor.
create or replace function public.erp_admin_product_costs(p_company uuid,p_search text default '')
returns table(item_id uuid,code text,name text,item_type text,unit_symbol text,
  cost numeric,price numeric,margin numeric,margin_percent numeric,status text)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'admin'
    or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'items','read') then
    raise exception 'Solo un administrador puede consultar costos y márgenes'
      using errcode='42501'; end if;
  return query select * from public.erp_product_costs(p_company,p_search);
end;
$$;

create or replace function public.erp_admin_sales_profit_summary(p_company uuid)
returns table(sales_total numeric,covered_revenue numeric,covered_cost numeric,
  estimated_profit numeric,missing_lines bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'admin'
    or not private.has_permission(p_company,'finance','read') then
    raise exception 'Solo un administrador puede consultar ganancias'
      using errcode='42501'; end if;
  return query select * from public.erp_sales_profit_summary(p_company);
end;
$$;

create or replace function public.erp_set_finished_product_price(
  p_company uuid,p_item uuid,p_price numeric
) returns void language plpgsql security definer set search_path='' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'admin'
    or not private.has_permission(p_company,'sales','update') then
    raise exception 'Solo un administrador puede editar precios'
      using errcode='42501'; end if;
  if p_price is null or p_price<0 or p_price>=10000000000000000
    or p_price<>round(p_price,2) then
    raise exception 'Indicá un precio válido en pesos con dos decimales'; end if;
  update public.items set sale_unit_price=p_price
    where company_id=p_company and id=p_item and active
      and item_type='finished_product';
  if not found then raise exception 'Producto terminado inexistente o inactivo'; end if;
end;
$$;

-- El precio deja de poder cambiarse mediante UPDATE directo desde el navegador.
-- Los otros campos de ítems conservan sus permisos actuales.
revoke update(sale_unit_price) on public.items from authenticated;
revoke execute on function public.erp_product_costs(uuid,text),
  public.erp_sales_profit_summary(uuid) from authenticated;

revoke execute on function public.erp_public_price_list(uuid,text),
  public.erp_admin_product_costs(uuid,text),
  public.erp_admin_sales_profit_summary(uuid),
  public.erp_set_finished_product_price(uuid,uuid,numeric) from public,anon;
grant execute on function public.erp_public_price_list(uuid,text),
  public.erp_admin_product_costs(uuid,text),
  public.erp_admin_sales_profit_summary(uuid),
  public.erp_set_finished_product_price(uuid,uuid,numeric) to authenticated;

-- Indicadores acotados a los permisos del usuario y a la empresa activa.
create or replace function public.erp_operational_dashboard(p_company uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb:='{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al inicio' using errcode='42501'; end if;

  if private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object(
      'sales_30d',(select count(*) from public.sales s
        where s.company_id=p_company and s.created_at>=now()-interval '30 days'),
      'revenue_30d',(select coalesce(sum(s.total),0) from public.sales s
        where s.company_id=p_company and s.created_at>=now()-interval '30 days')
    );
  end if;

  if private.has_permission(p_company,'finance','read')
    and private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object(
      'receivables',(select coalesce(sum(s.total-coalesce(p.paid,0)),0)
        from public.sales s left join lateral (
          select sum(sp.amount) paid from public.sale_payments sp
          where sp.company_id=s.company_id and sp.sale_id=s.id
            and not exists(select 1 from public.sale_payment_reversals r
              where r.company_id=sp.company_id and r.payment_id=sp.id)
        ) p on true where s.company_id=p_company)
    );
    if private.get_user_role(p_company)='admin' then
      v_result:=v_result||jsonb_build_object(
        'profit_30d',(select coalesce(sum(l.line_total-l.quantity*l.estimated_unit_cost),0)
          from public.sale_lines l join public.sales s
            on s.company_id=l.company_id and s.id=l.sale_id
          where s.company_id=p_company and s.created_at>=now()-interval '30 days'
            and l.estimated_unit_cost is not null)
      );
    end if;
  end if;

  if private.has_permission(p_company,'purchases','read') then
    v_result:=v_result||jsonb_build_object(
      'open_orders',(select count(*) from public.purchase_orders o
        where o.company_id=p_company and o.status in ('open','partial'))
    );
  end if;
  if private.has_permission(p_company,'production','read') then
    v_result:=v_result||jsonb_build_object(
      'planned_runs',(select count(*) from public.production_plans p
        where p.company_id=p_company and p.status='planned')
    );
  end if;
  if private.has_permission(p_company,'items','read')
    and private.has_permission(p_company,'stock','read') then
    v_result:=v_result||jsonb_build_object(
      'low_stock',(select count(*) from public.items i
        where i.company_id=p_company and i.active and i.minimum_stock>0
          and i.minimum_stock>(select coalesce(sum(b.quantity),0)
            from public.stock_balances b where b.company_id=i.company_id
              and b.item_id=i.id))
    );
  end if;

  return v_result;
end;
$$;
revoke execute on function public.erp_operational_dashboard(uuid) from public,anon;
grant execute on function public.erp_operational_dashboard(uuid) to authenticated;
