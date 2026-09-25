-- ERP Dromux · costo de referencia y varias cotizaciones por materia prima.
-- Ejecutar una vez después de 008.

alter table public.items
  add column reference_unit_cost numeric(18, 2)
  check (reference_unit_cost is null or reference_unit_cost >= 0);

create table public.supplier_items (
  company_id uuid not null,
  supplier_id uuid not null,
  item_id uuid not null,
  unit_price numeric(18, 2) not null check (unit_price >= 0),
  supplier_sku text not null default '' check (length(supplier_sku) <= 80),
  updated_at timestamptz not null default now(),
  primary key (company_id, supplier_id, item_id),
  constraint supplier_items_supplier_fk foreign key (company_id, supplier_id)
    references public.suppliers(company_id, id),
  constraint supplier_items_item_fk foreign key (company_id, item_id)
    references public.items(company_id, id)
);

create index supplier_items_item_price_idx
  on public.supplier_items(company_id, item_id, unit_price, supplier_id);

create function private.check_supplier_item()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.items i
    where i.company_id = new.company_id and i.id = new.item_id
      and i.item_type = 'raw_material' and i.active
  ) then
    raise exception 'Solo podés asociar materias primas activas';
  end if;
  if not exists (
    select 1 from public.suppliers s
    where s.company_id = new.company_id and s.id = new.supplier_id and s.active
  ) then
    raise exception 'Elegí un proveedor activo';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create trigger supplier_items_check
before insert or update on public.supplier_items for each row
execute function private.check_supplier_item();

create function private.prevent_supplier_price_unit_mismatch()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.unit_id is distinct from old.unit_id
      or new.item_type is distinct from old.item_type)
    and exists (
      select 1 from public.supplier_items si
      where si.company_id = old.company_id and si.item_id = old.id
    ) then
    raise exception 'Quitá los precios de proveedores antes de cambiar la unidad o el tipo';
  end if;
  return new;
end;
$$;

create trigger items_protect_supplier_prices
before update of unit_id, item_type on public.items for each row
execute function private.prevent_supplier_price_unit_mismatch();

revoke execute on function private.check_supplier_item(),
  private.prevent_supplier_price_unit_mismatch()
  from public, anon, authenticated;

alter table public.supplier_items enable row level security;
create policy supplier_items_read on public.supplier_items
  for select to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'read')));
create policy supplier_items_insert on public.supplier_items
  for insert to authenticated
  with check ((select private.has_permission(company_id, 'purchases', 'update')));
create policy supplier_items_update on public.supplier_items
  for update to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'update')))
  with check ((select private.has_permission(company_id, 'purchases', 'update')));
create policy supplier_items_delete on public.supplier_items
  for delete to authenticated
  using ((select private.has_permission(company_id, 'purchases', 'update')));

revoke all on public.supplier_items from anon, authenticated;
grant select on public.supplier_items to authenticated;
grant insert (company_id, supplier_id, item_id, unit_price, supplier_sku)
  on public.supplier_items to authenticated;
grant update (unit_price, supplier_sku)
  on public.supplier_items to authenticated;
grant delete on public.supplier_items to authenticated;

grant update (reference_unit_cost) on public.items to authenticated;
grant insert (reference_unit_cost) on public.items to authenticated;

-- Completa el nombre descriptivo de las líneas antiguas y lo congela para
-- las órdenes nuevas, incluso si después cambia la ficha del ítem.
alter table public.purchase_order_lines add column item_name text;
update public.purchase_order_lines line
set item_name = i.name
from public.items i
where i.company_id = line.company_id and i.id = line.item_id;

create function private.snapshot_purchase_item_name()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_name text;
begin
  select i.name into v_name from public.items i
  where i.company_id = new.company_id and i.id = new.item_id;
  if v_name is null then raise exception 'Ítem inexistente'; end if;
  new.item_name := v_name;
  return new;
end;
$$;
create trigger purchase_lines_snapshot_name
before insert on public.purchase_order_lines for each row
execute function private.snapshot_purchase_item_name();
revoke execute on function private.snapshot_purchase_item_name()
  from public, anon, authenticated;

-- Las órdenes conservan su precio unitario original. Se añade solo una consulta
-- de cotizaciones; no se alteran compras anteriores ni movimientos de stock.
create function public.purchase_supplier_quotes(
  p_company uuid,
  p_supplier uuid default null,
  p_item uuid default null
) returns table (
  supplier_id uuid, supplier_name text, supplier_active boolean,
  item_id uuid, item_code text, item_name text, unit_symbol text,
  reference_unit_cost numeric, unit_price numeric,
  supplier_sku text, updated_at timestamptz
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para ver cotizaciones' using errcode = '42501';
  end if;
  return query
    select s.id, s.name, s.active, i.id, i.code, i.name, u.symbol,
      i.reference_unit_cost, si.unit_price, si.supplier_sku, si.updated_at
    from public.supplier_items si
    join public.suppliers s
      on s.company_id = si.company_id and s.id = si.supplier_id
    join public.items i
      on i.company_id = si.company_id and i.id = si.item_id
    join public.units u
      on u.company_id = i.company_id and u.id = i.unit_id
    where si.company_id = p_company
      and (p_supplier is null or si.supplier_id = p_supplier)
      and (p_item is null or si.item_id = p_item)
    order by i.name, si.unit_price, s.name
    limit 500;
end;
$$;

revoke execute on function public.purchase_supplier_quotes(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.purchase_supplier_quotes(uuid, uuid, uuid)
  to authenticated;

-- El buscador de órdenes devuelve la cotización del proveedor seleccionado.
create function public.purchase_material_options(
  p_company uuid, p_search text default '', p_supplier uuid default null
) returns table (
  id uuid, code text, name text, unit_symbol text,
  item_type text, reference_unit_cost numeric, supplier_unit_price numeric
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.item_type,
      i.reference_unit_cost, si.unit_price
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    left join public.supplier_items si on si.company_id = i.company_id
      and si.item_id = i.id and si.supplier_id = p_supplier
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%'
        or i.barcode ilike '%' || p_search || '%')
    order by i.name, i.id
    limit 30;
end;
$$;

revoke execute on function public.purchase_material_options(uuid, text, uuid)
  from public, anon;
grant execute on function public.purchase_material_options(uuid, text, uuid)
  to authenticated;
