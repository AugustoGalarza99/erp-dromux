-- Dromux ERP · 039 · Listas de precios múltiples, historial, IVA por producto y lista por cliente.
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario para el entorno destino,
-- después de la revisión crítica y con respaldo. Comprobaciones: supabase/verificaciones/039_comprobaciones.sql.
-- Deshacer: supabase/reparacion/0_deshacer_039.sql (aborta si ya hay listas con precios cargados).
--
-- Decisiones (propietario, 24/11/2026):
--   * IVA: TODO se guarda SIN IVA (neto). Cada producto puede tener su alícuota (item_sale_settings.tax_percent);
--     si no la tiene se usa la de la empresa (price_settings.default_tax_percent, 21 por defecto).
--     El precio con IVA siempre se calcula al leer; nunca se guarda.
--
-- Modelo de privacidad de costos (D-004):
--   * price_list_items (precio neto final) es lo único que ven quienes tienen sales:read.
--   * price_list_item_pricing (método, margen/recargo, costo al fijar el precio), price_list_item_history,
--     price_settings (margen mínimo, comisión, estructura) y price_change_requests NO tienen permisos de
--     tabla: solo se alcanzan por funciones de administrador con finance:read. Un vendedor no puede deducir
--     el costo ni el margen.
--   * Escritura solo por funciones SECURITY DEFINER (search_path vacío); administrador + sales:update.
--     Calcular precio desde costo (margen/recargo, recalcular) exige además finance:read.
--
-- Fuera de esta migración (se hará aparte, con su propia revisión crítica, porque toca dinero):
--   * post_sale_with_payment NO se modifica: la venta sigue usando items.sale_unit_price. erp_resolve_sale_price
--     solo CONSULTA qué precio le correspondería a un cliente. Conectar la venta a la lista, descuentos,
--     presupuestos y ofertas por cantidad quedan para 040.
--
-- No toca stock, ventas, cobros ni datos existentes. Todo es aditivo.

begin;

-- 1) Tablas --------------------------------------------------------------------------------------------
create table public.price_settings (
  company_id uuid primary key references public.companies(id),
  default_tax_percent numeric(5,2) not null default 21 check (default_tax_percent between 0 and 100),
  min_margin_percent numeric(5,2) not null default 0 check (min_margin_percent >= 0 and min_margin_percent < 100),
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  structure_percent numeric(5,2) not null default 0 check (structure_percent between 0 and 100),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);

create table public.price_lists (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null check (length(btrim(name)) between 1 and 80),
  currency text not null default 'ARS' check (currency in ('ARS', 'USD')),
  -- Lista derivada: precio = precio de la lista base × (1 − descuento/100). Descuento negativo = recargo.
  base_list_id uuid,
  base_discount_percent numeric(6,3) not null default 0
    check (base_discount_percent > -1000 and base_discount_percent < 100),
  -- Paso de redondeo del precio derivado y de los precios calculados (0 = solo 2 decimales).
  rounding_step numeric(12,2) not null default 0 check (rounding_step >= 0),
  valid_from date,
  valid_to date,
  is_default boolean not null default false,
  archived boolean not null default false,
  note text not null default '' check (length(note) <= 300),
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid,
  unique (company_id, id),
  foreign key (company_id, base_list_id) references public.price_lists(company_id, id),
  check (base_list_id is null or base_list_id <> id),
  check (valid_to is null or valid_from is null or valid_to >= valid_from),
  check (base_list_id is not null or base_discount_percent = 0)
);
create unique index price_lists_one_default on public.price_lists(company_id) where is_default and not archived;
create unique index price_lists_name_unique on public.price_lists(company_id, lower(btrim(name))) where not archived;

create table public.price_list_items (
  company_id uuid not null,
  price_list_id uuid not null,
  item_id uuid not null,
  net_price numeric(18,2) not null check (net_price >= 0 and net_price < 10000000000000000),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid,
  primary key (company_id, price_list_id, item_id),
  foreign key (company_id, price_list_id) references public.price_lists(company_id, id),
  foreign key (company_id, item_id) references public.items(company_id, id)
);
create index price_list_items_item_idx on public.price_list_items(company_id, item_id);

-- Solo administrador con finance:read, por función. Invariante: cada fila de price_list_items tiene una aquí.
create table public.price_list_item_pricing (
  company_id uuid not null,
  price_list_id uuid not null,
  item_id uuid not null,
  method text not null check (method in ('margin', 'markup', 'fixed')),
  method_value numeric(18,4) not null check (method_value >= 0),
  cost_snapshot numeric(18,2),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (company_id, price_list_id, item_id),
  foreign key (company_id, price_list_id, item_id)
    references public.price_list_items(company_id, price_list_id, item_id)
);

create table public.price_list_item_history (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  price_list_id uuid not null,
  item_id uuid not null,
  old_net_price numeric(18,2),
  new_net_price numeric(18,2),
  method text,
  method_value numeric(18,4),
  cost_snapshot numeric(18,2),
  source text not null check (source in ('manual', 'bulk', 'recalc', 'import', 'remove')),
  reason text not null default '' check (length(reason) <= 200),
  changed_by uuid not null,
  changed_at timestamptz not null default clock_timestamp(),
  foreign key (company_id, price_list_id) references public.price_lists(company_id, id),
  foreign key (company_id, item_id) references public.items(company_id, id)
);
create index price_list_item_history_idx
  on public.price_list_item_history(company_id, price_list_id, item_id, changed_at desc);

create index price_list_item_history_list_idx
  on public.price_list_item_history(company_id, price_list_id, changed_at desc);

-- Idempotencia de operaciones masivas (edición porcentual, recálculo, importación).
create table public.price_change_requests (
  company_id uuid not null references public.companies(id),
  request_id uuid not null,
  price_list_id uuid not null,
  kind text not null check (kind in ('percent', 'recalc', 'import')),
  result jsonb not null,
  created_by uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (company_id, request_id)
);

-- IVA por producto y contenido (para precio por unidad de contenido: por kilo, por litro, por metro…).
create table public.item_sale_settings (
  company_id uuid not null,
  item_id uuid not null,
  tax_percent numeric(5,2) check (tax_percent is null or tax_percent between 0 and 100),
  content_quantity numeric(18,6) check (content_quantity is null or content_quantity > 0),
  content_unit_id uuid,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid,
  primary key (company_id, item_id),
  foreign key (company_id, item_id) references public.items(company_id, id),
  foreign key (company_id, content_unit_id) references public.units(company_id, id),
  check ((content_quantity is null) = (content_unit_id is null))
);

create table public.customer_price_lists (
  company_id uuid not null,
  customer_id uuid not null,
  price_list_id uuid not null,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid,
  primary key (company_id, customer_id),
  foreign key (company_id, customer_id) references public.customers(company_id, id),
  foreign key (company_id, price_list_id) references public.price_lists(company_id, id)
);

-- 2) Disparadores de integridad -------------------------------------------------------------------------
create function private.price_lists_guard() returns trigger
language plpgsql set search_path = '' as $$
declare v_base public.price_lists%rowtype;
begin
  if new.base_list_id is not null then
    select * into v_base from public.price_lists
    where company_id = new.company_id and id = new.base_list_id;
    if v_base.base_list_id is not null then
      raise exception 'La lista base no puede ser a su vez una lista derivada';
    end if;
    if v_base.currency <> new.currency then
      raise exception 'La lista derivada debe tener la misma moneda que su lista base';
    end if;
    if tg_op = 'UPDATE' and exists (
      select 1 from public.price_lists d where d.company_id = new.company_id and d.base_list_id = new.id) then
      raise exception 'Esta lista es base de otras listas y no puede volverse derivada';
    end if;
  end if;
  if tg_op = 'UPDATE' and new.currency <> old.currency and (
    exists (select 1 from public.price_list_items i where i.company_id = new.company_id and i.price_list_id = new.id)
    or exists (select 1 from public.price_lists d where d.company_id = new.company_id and d.base_list_id = new.id)) then
    raise exception 'No se puede cambiar la moneda de una lista con precios o con listas derivadas';
  end if;
  return new;
end;
$$;
create trigger price_lists_guard before insert or update on public.price_lists
  for each row execute function private.price_lists_guard();

create function private.price_history_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'El historial de precios no se modifica ni se borra';
end;
$$;
create trigger price_history_immutable before update or delete on public.price_list_item_history
  for each row execute function private.price_history_immutable();

-- 3) RLS y permisos de tabla -----------------------------------------------------------------------------
alter table public.price_settings enable row level security;
alter table public.price_lists enable row level security;
alter table public.price_list_items enable row level security;
alter table public.price_list_item_pricing enable row level security;
alter table public.price_list_item_history enable row level security;
alter table public.price_change_requests enable row level security;
alter table public.item_sale_settings enable row level security;
alter table public.customer_price_lists enable row level security;

revoke all on table public.price_settings, public.price_lists, public.price_list_items,
  public.price_list_item_pricing, public.price_list_item_history, public.price_change_requests,
  public.item_sale_settings, public.customer_price_lists from public, anon, authenticated;

-- Lectura de lo no sensible (sin costos ni márgenes) para quien puede ver ventas.
grant select on table public.price_lists, public.price_list_items, public.item_sale_settings,
  public.customer_price_lists to authenticated;

create policy price_lists_read on public.price_lists for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
create policy price_list_items_read on public.price_list_items for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
create policy item_sale_settings_read on public.item_sale_settings for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
create policy customer_price_lists_read on public.customer_price_lists for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));

-- 4) Ayudantes privados ----------------------------------------------------------------------------------
create function private.price_require_admin(p_company uuid, p_cost boolean default false) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin'
     or not private.has_permission(p_company, 'sales', 'update')
     or (p_cost and not private.has_permission(p_company, 'finance', 'read')) then
    raise exception 'Solo un administrador con permiso puede gestionar listas de precios' using errcode = '42501';
  end if;
end;
$$;

create function private.price_require_cost_view(p_company uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin'
     or not private.has_permission(p_company, 'finance', 'read')
     or not private.has_permission(p_company, 'items', 'read')
     or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Solo un administrador puede consultar costos y márgenes' using errcode = '42501';
  end if;
end;
$$;

create function private.price_round(p numeric, p_step numeric) returns numeric
language sql immutable set search_path = '' as $$
  select case when p is null then null
    when coalesce(p_step, 0) > 0 then round(round(p / p_step) * p_step, 2)
    else round(p, 2) end;
$$;

create function private.price_compute(p_method text, p_value numeric, p_cost numeric, p_step numeric)
returns numeric language plpgsql immutable set search_path = '' as $$
declare v numeric;
begin
  if p_value is null or p_value < 0 then raise exception 'Indicá un valor válido'; end if;
  if p_method = 'fixed' then
    v := p_value;
  elsif p_method = 'margin' then
    if p_cost is null then raise exception 'El producto no tiene costo para calcular el precio'; end if;
    if p_value >= 100 then raise exception 'El margen debe ser menor a 100 %%'; end if;
    v := p_cost / (1 - p_value / 100);
  elsif p_method = 'markup' then
    if p_cost is null then raise exception 'El producto no tiene costo para calcular el precio'; end if;
    if p_value > 10000 then raise exception 'El recargo es demasiado alto'; end if;
    v := p_cost * (1 + p_value / 100);
  else
    raise exception 'Método de precio inválido';
  end if;
  if v >= 10000000000000000 then raise exception 'Precio fuera de rango'; end if;
  return private.price_round(v, p_step);
end;
$$;

-- Costo vigente por producto, con la misma regla que Costos (erp_product_costs): costo de la fórmula si la
-- tiene, si no el costo de referencia. A diferencia de erp_product_costs NO tiene tope de 100 productos y
-- calcula solo los ids pedidos. Solo se llama desde funciones de administrador (que ya verificaron permisos).
create function private.price_costs(p_company uuid, p_items uuid[])
returns table(item_id uuid, cost numeric)
language plpgsql stable security definer set search_path = '' as $$
declare r record; v numeric;
begin
  if p_items is null then return; end if;
  for r in
    select i.id, i.reference_unit_cost, f.product_id as has_formula
    from public.items i
    left join public.production_formulas f on f.company_id = i.company_id and f.product_id = i.id
    where i.company_id = p_company and i.id = any (p_items)
  loop
    v := null;
    if r.has_formula is not null then
      begin
        v := private.production_unit_cost(p_company, r.id);
      exception when raise_exception then v := null;
      end;
    else
      v := r.reference_unit_cost;
    end if;
    item_id := r.id; cost := v;
    return next;
  end loop;
end;
$$;

create function private.price_item_cost(p_company uuid, p_item uuid) returns numeric
language sql stable security definer set search_path = '' as $$
  select c.cost from private.price_costs(p_company, array[p_item]) c limit 1;
$$;

-- Precio efectivo de cada producto terminado activo en una lista (propio o derivado de la base) y sus datos
-- de método. Contiene método/margen: SOLO para funciones que ya exigieron permisos.
create function private.price_effective(p_company uuid, p_list uuid, p_term text)
returns table(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text,
  method text, method_value numeric, cost_snapshot numeric)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_list public.price_lists%rowtype;
begin
  select * into v_list from public.price_lists where company_id = p_company and id = p_list;
  if not found then raise exception 'Lista inexistente'; end if;
  return query
  select i.id, i.code, i.name, u.symbol,
    coalesce(own.net_price, private.price_round(b.net_price * (1 - v_list.base_discount_percent / 100), v_list.rounding_step)),
    case when own.net_price is not null then 'own' when b.net_price is not null then 'derived' else 'none' end,
    pp.method, pp.method_value, pp.cost_snapshot
  from public.items i
  join public.units u on u.company_id = i.company_id and u.id = i.unit_id
  left join public.price_list_items own
    on own.company_id = i.company_id and own.price_list_id = p_list and own.item_id = i.id
  left join public.price_list_item_pricing pp
    on pp.company_id = i.company_id and pp.price_list_id = p_list and pp.item_id = i.id
  left join public.price_list_items b
    on b.company_id = i.company_id and b.price_list_id = v_list.base_list_id and b.item_id = i.id
  where i.company_id = p_company and i.item_type = 'finished_product' and i.active
    and (coalesce(p_term, '') = '' or position(p_term in lower(i.name)) > 0 or position(p_term in lower(i.code)) > 0);
end;
$$;

revoke all on function private.price_lists_guard(), private.price_history_immutable(),
  private.price_require_admin(uuid, boolean), private.price_require_cost_view(uuid),
  private.price_round(numeric, numeric), private.price_compute(text, numeric, numeric, numeric),
  private.price_item_cost(uuid, uuid), private.price_costs(uuid, uuid[]),
  private.price_effective(uuid, uuid, text) from public, anon, authenticated;

-- 5) Escritura: configuración y listas --------------------------------------------------------------------
create function public.save_price_settings(
  p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.price_require_admin(p_company, true);
  if p_default_tax is null or p_default_tax not between 0 and 100
     or p_min_margin is null or p_min_margin < 0 or p_min_margin >= 100
     or p_commission is null or p_commission not between 0 and 100
     or p_structure is null or p_structure not between 0 and 100 then
    raise exception 'Revisá los porcentajes (IVA 0–100, margen mínimo menor a 100)';
  end if;
  insert into public.price_settings(company_id, default_tax_percent, min_margin_percent,
    commission_percent, structure_percent, updated_by)
  values (p_company, p_default_tax, p_min_margin, p_commission, p_structure, auth.uid())
  on conflict (company_id) do update set default_tax_percent = excluded.default_tax_percent,
    min_margin_percent = excluded.min_margin_percent, commission_percent = excluded.commission_percent,
    structure_percent = excluded.structure_percent, updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;

create function public.erp_price_settings(p_company uuid)
returns table(default_tax_percent numeric, min_margin_percent numeric,
  commission_percent numeric, structure_percent numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.price_require_cost_view(p_company);
  return query select coalesce(s.default_tax_percent, 21::numeric), coalesce(s.min_margin_percent, 0::numeric),
    coalesce(s.commission_percent, 0::numeric), coalesce(s.structure_percent, 0::numeric)
  from (select 1) x left join public.price_settings s on s.company_id = p_company;
end;
$$;

create function public.save_price_list(
  p_company uuid, p_id uuid, p_name text, p_currency text, p_valid_from date, p_valid_to date,
  p_is_default boolean, p_base_list uuid, p_base_discount numeric, p_rounding_step numeric,
  p_note text, p_archived boolean
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_old public.price_lists%rowtype;
begin
  perform private.price_require_admin(p_company);
  perform pg_advisory_xact_lock(hashtextextended('price_lists:' || p_company::text, 0));
  if coalesce(btrim(p_name), '') = '' or length(btrim(p_name)) > 80 then
    raise exception 'Indicá un nombre de hasta 80 caracteres';
  end if;
  if p_currency is null or p_currency not in ('ARS', 'USD') then raise exception 'Moneda inválida'; end if;
  if p_valid_from is not null and p_valid_to is not null and p_valid_to < p_valid_from then
    raise exception 'La vigencia hasta no puede ser anterior a la vigencia desde';
  end if;
  if p_base_list is not null and not exists (
    select 1 from public.price_lists where company_id = p_company and id = p_base_list and not archived) then
    raise exception 'Lista base inexistente o archivada';
  end if;
  if p_base_list is null and coalesce(p_base_discount, 0) <> 0 then
    raise exception 'El descuento sobre base requiere una lista base';
  end if;
  if coalesce(p_archived, false) and coalesce(p_is_default, false) then
    raise exception 'Una lista archivada no puede ser la predeterminada';
  end if;
  if coalesce(p_rounding_step, 0) < 0 then raise exception 'Redondeo inválido'; end if;

  if p_id is null then
    insert into public.price_lists(company_id, name, currency, base_list_id, base_discount_percent,
      rounding_step, valid_from, valid_to, is_default, note, created_by)
    values (p_company, btrim(p_name), p_currency, p_base_list, coalesce(p_base_discount, 0),
      coalesce(p_rounding_step, 0), p_valid_from, p_valid_to, false, coalesce(left(p_note, 300), ''), auth.uid())
    returning id into v_id;
  else
    select * into v_old from public.price_lists where company_id = p_company and id = p_id for update;
    if not found then raise exception 'Lista inexistente'; end if;
    v_id := p_id;
    if p_archived and exists (
      select 1 from public.price_lists d where d.company_id = p_company and d.base_list_id = p_id and not d.archived) then
      raise exception 'Archivá primero las listas derivadas de esta lista';
    end if;
    update public.price_lists set name = btrim(p_name), currency = p_currency, base_list_id = p_base_list,
      base_discount_percent = coalesce(p_base_discount, 0), rounding_step = coalesce(p_rounding_step, 0),
      valid_from = p_valid_from, valid_to = p_valid_to, note = coalesce(left(p_note, 300), ''),
      archived = coalesce(p_archived, false), is_default = case when coalesce(p_archived, false) then false else is_default end
    where company_id = p_company and id = p_id;
  end if;
  if coalesce(p_is_default, false) then
    update public.price_lists set is_default = false where company_id = p_company and is_default and id <> v_id;
    update public.price_lists set is_default = true where company_id = p_company and id = v_id and not archived;
  end if;
  return v_id;
end;
$$;

-- 6) Escritura: precios por producto -----------------------------------------------------------------------
create function private.price_write(
  p_company uuid, p_list uuid, p_item uuid, p_new numeric, p_method text, p_value numeric,
  p_cost numeric, p_keep_cost boolean, p_source text, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_old numeric; v_old_cost numeric;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_list::text || p_item::text, 0));
  select net_price into v_old from public.price_list_items
  where company_id = p_company and price_list_id = p_list and item_id = p_item for update;
  select cost_snapshot into v_old_cost from public.price_list_item_pricing
  where company_id = p_company and price_list_id = p_list and item_id = p_item;
  insert into public.price_list_items(company_id, price_list_id, item_id, net_price, updated_by)
  values (p_company, p_list, p_item, p_new, auth.uid())
  on conflict (company_id, price_list_id, item_id) do update
    set net_price = excluded.net_price, updated_at = clock_timestamp(), updated_by = auth.uid();
  insert into public.price_list_item_pricing(company_id, price_list_id, item_id, method, method_value, cost_snapshot)
  values (p_company, p_list, p_item, p_method, p_value, case when p_keep_cost then v_old_cost else p_cost end)
  on conflict (company_id, price_list_id, item_id) do update
    set method = excluded.method, method_value = excluded.method_value,
        cost_snapshot = case when p_keep_cost then public.price_list_item_pricing.cost_snapshot else excluded.cost_snapshot end,
        updated_at = clock_timestamp();
  insert into public.price_list_item_history(company_id, price_list_id, item_id, old_net_price, new_net_price,
    method, method_value, cost_snapshot, source, reason, changed_by)
  values (p_company, p_list, p_item, v_old, p_new, p_method, p_value,
    case when p_keep_cost then v_old_cost else p_cost end, p_source, left(coalesce(p_reason, ''), 200), auth.uid());
end;
$$;
revoke all on function private.price_write(uuid, uuid, uuid, numeric, text, numeric, numeric, boolean, text, text)
  from public, anon, authenticated;

create function public.set_price_list_item(
  p_company uuid, p_list uuid, p_item uuid, p_method text, p_value numeric, p_reason text
) returns numeric language plpgsql security definer set search_path = '' as $$
declare v_list public.price_lists%rowtype; v_cost numeric; v_price numeric;
begin
  perform private.price_require_admin(p_company, p_method in ('margin', 'markup'));
  select * into v_list from public.price_lists
  where company_id = p_company and id = p_list for share;
  if not found or v_list.archived then raise exception 'Lista inexistente o archivada'; end if;
  if not exists (select 1 from public.items where company_id = p_company and id = p_item
                 and active and item_type = 'finished_product') then
    raise exception 'Producto terminado inexistente o inactivo';
  end if;
  if p_method in ('margin', 'markup') then v_cost := private.price_item_cost(p_company, p_item); end if;
  v_price := private.price_compute(p_method, p_value, v_cost, v_list.rounding_step);
  perform private.price_write(p_company, p_list, p_item, v_price, p_method, p_value, v_cost, false, 'manual', p_reason);
  return v_price;
end;
$$;

create function public.remove_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_old numeric;
begin
  perform private.price_require_admin(p_company);
  perform 1 from public.price_lists where company_id = p_company and id = p_list and not archived for share;
  if not found then raise exception 'Lista inexistente o archivada'; end if;
  select net_price into v_old from public.price_list_items
  where company_id = p_company and price_list_id = p_list and item_id = p_item for update;
  if not found then return; end if;
  delete from public.price_list_item_pricing where company_id = p_company and price_list_id = p_list and item_id = p_item;
  delete from public.price_list_items where company_id = p_company and price_list_id = p_list and item_id = p_item;
  insert into public.price_list_item_history(company_id, price_list_id, item_id, old_net_price, new_net_price,
    source, reason, changed_by)
  values (p_company, p_list, p_item, v_old, null, 'remove', left(coalesce(p_reason, ''), 200), auth.uid());
end;
$$;

-- Edición masiva: p_mode 'percent' (sube/baja el precio neto actual; las filas pasan a precio fijo) o
-- 'recalc' (vuelve a calcular desde el costo vigente las filas con margen o recargo). p_apply=false: vista previa
-- sin escribir. Tope 5000 filas por operación.
create function public.bulk_price_change(
  p_company uuid, p_list uuid, p_mode text, p_percent numeric, p_item_ids uuid[],
  p_apply boolean, p_reason text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_list public.price_lists%rowtype; r record; v_new numeric;
  v_total int := 0; v_changed int := 0; v_skipped int := 0; v_sample jsonb := '[]'::jsonb;
  v_prev jsonb; v_result jsonb; v_method text; v_value numeric;
begin
  if p_mode not in ('percent', 'recalc') then raise exception 'Modo inválido'; end if;
  perform private.price_require_admin(p_company, p_mode = 'recalc');
  if p_mode = 'percent' and (p_percent is null or p_percent <= -100 or p_percent > 1000) then
    raise exception 'Indicá un porcentaje entre -99,99 y 1000';
  end if;
  if p_item_ids is not null and cardinality(p_item_ids) > 5000 then
    raise exception 'Seleccioná hasta 5000 productos por operación';
  end if;
  if p_apply then
    if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
    select * into v_list from public.price_lists where company_id = p_company and id = p_list for update;
  else
    select * into v_list from public.price_lists where company_id = p_company and id = p_list;
  end if;
  if not found or v_list.archived then raise exception 'Lista inexistente o archivada'; end if;
  if p_apply then
    select result into v_prev from public.price_change_requests
    where company_id = p_company and request_id = p_request_id and price_list_id = p_list and kind = p_mode;
    if v_prev is not null then return v_prev; end if;
    if exists (select 1 from public.price_change_requests where company_id = p_company and request_id = p_request_id) then
      raise exception 'Ese identificador ya se usó en otra operación';
    end if;
  end if;

  for r in
    with c as materialized (
      select cc.item_id, cc.cost from private.price_costs(p_company, (
        select array_agg(x.item_id) from public.price_list_items x
        where x.company_id = p_company and x.price_list_id = p_list
          and (p_item_ids is null or x.item_id = any (p_item_ids)))) cc
      where p_mode = 'recalc')
    select pi.item_id, pi.net_price, pp.method, pp.method_value, i.code, i.name, c.cost
    from public.price_list_items pi
    join public.items i on i.company_id = pi.company_id and i.id = pi.item_id and i.active
    left join public.price_list_item_pricing pp
      on pp.company_id = pi.company_id and pp.price_list_id = pi.price_list_id and pp.item_id = pi.item_id
    left join c on c.item_id = pi.item_id
    where pi.company_id = p_company and pi.price_list_id = p_list
      and (p_item_ids is null or pi.item_id = any (p_item_ids))
    order by i.name, pi.item_id
    limit 5001
  loop
    v_total := v_total + 1;
    if v_total > 5000 then raise exception 'La lista supera 5000 filas: seleccioná un subconjunto'; end if;
    if p_mode = 'percent' then
      v_new := private.price_round(r.net_price * (1 + p_percent / 100), v_list.rounding_step);
      v_method := 'fixed'; v_value := v_new;
    else
      if coalesce(r.method, '') not in ('margin', 'markup') or r.cost is null then v_skipped := v_skipped + 1; continue; end if;
      v_new := private.price_compute(r.method, r.method_value, r.cost, v_list.rounding_step);
      v_method := r.method; v_value := r.method_value;
    end if;
    if v_new >= 10000000000000000 then raise exception 'El aumento deja un precio fuera de rango'; end if;
    if v_new = r.net_price then continue; end if;
    v_changed := v_changed + 1;
    if jsonb_array_length(v_sample) < 200 then
      v_sample := v_sample || jsonb_build_object('item_id', r.item_id, 'code', r.code, 'name', r.name,
        'old_price', r.net_price, 'new_price', v_new);
    end if;
    if p_apply then
      perform private.price_write(p_company, p_list, r.item_id, v_new, v_method, v_value, r.cost,
        p_mode = 'percent', case p_mode when 'percent' then 'bulk' else 'recalc' end, p_reason);
    end if;
  end loop;

  v_result := jsonb_build_object('mode', p_mode, 'applied', p_apply, 'total', v_total,
    'changed', v_changed, 'skipped', v_skipped, 'sample', v_sample);
  if p_apply then
    insert into public.price_change_requests(company_id, request_id, price_list_id, kind, result, created_by)
    values (p_company, p_request_id, p_list, p_mode, v_result, auth.uid());
  end if;
  return v_result;
end;
$$;

-- Importación desde planilla: p_rows = [{"code": "...", "price": 123.45}] (precio neto sin IVA). Máximo 500
-- filas por llamada (el cliente divide). Los productos se identifican por código SOLO para emparejar; lo que
-- se guarda es el id del producto. p_apply=false: vista previa.
create function public.import_price_list_items(
  p_company uuid, p_list uuid, p_rows jsonb, p_apply boolean, p_reason text, p_request_id uuid
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_list public.price_lists%rowtype; v_row jsonb; v_code text; v_price numeric; v_item uuid; v_old numeric;
  v_matched int := 0; v_changed int := 0; v_unchanged int := 0;
  v_unmatched jsonb := '[]'::jsonb; v_invalid jsonb := '[]'::jsonb; v_sample jsonb := '[]'::jsonb;
  v_seen text[] := '{}'; v_prev jsonb; v_result jsonb;
begin
  perform private.price_require_admin(p_company);
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0
     or jsonb_array_length(p_rows) > 500 then
    raise exception 'Enviá entre 1 y 500 filas por vez';
  end if;
  if p_apply then
    if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
    select * into v_list from public.price_lists where company_id = p_company and id = p_list for update;
  else
    select * into v_list from public.price_lists where company_id = p_company and id = p_list;
  end if;
  if not found or v_list.archived then raise exception 'Lista inexistente o archivada'; end if;
  if p_apply then
    select result into v_prev from public.price_change_requests
    where company_id = p_company and request_id = p_request_id and price_list_id = p_list and kind = 'import';
    if v_prev is not null then return v_prev; end if;
    if exists (select 1 from public.price_change_requests where company_id = p_company and request_id = p_request_id) then
      raise exception 'Ese identificador ya se usó en otra operación';
    end if;
  end if;

  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_code := btrim(coalesce(v_row ->> 'code', ''));
    begin
      v_price := (v_row ->> 'price')::numeric;
    exception when others then
      v_price := null;
    end;
    if v_code = '' or length(v_code) > 60 or v_price is null or v_price < 0
       or v_price >= 10000000000000000 or v_price <> round(v_price, 2) then
      if jsonb_array_length(v_invalid) < 50 then v_invalid := v_invalid || to_jsonb(left(v_code, 60)); end if;
      continue;
    end if;
    if v_code = any (v_seen) then
      if jsonb_array_length(v_invalid) < 50 then v_invalid := v_invalid || to_jsonb(v_code || ' (repetido)'); end if;
      continue;
    end if;
    v_seen := v_seen || v_code;
    select id into v_item from public.items
    where company_id = p_company and code = v_code and active and item_type = 'finished_product';
    if v_item is null then
      if jsonb_array_length(v_unmatched) < 50 then v_unmatched := v_unmatched || to_jsonb(v_code); end if;
      continue;
    end if;
    v_matched := v_matched + 1;
    select net_price into v_old from public.price_list_items
    where company_id = p_company and price_list_id = p_list and item_id = v_item;
    if v_old is not distinct from private.price_round(v_price, v_list.rounding_step) then
      v_unchanged := v_unchanged + 1; continue;
    end if;
    v_changed := v_changed + 1;
    if jsonb_array_length(v_sample) < 200 then
      v_sample := v_sample || jsonb_build_object('item_id', v_item, 'code', v_code,
        'old_price', v_old, 'new_price', private.price_round(v_price, v_list.rounding_step));
    end if;
    if p_apply then
      perform private.price_write(p_company, p_list, v_item, private.price_round(v_price, v_list.rounding_step),
        'fixed', private.price_round(v_price, v_list.rounding_step), null, true, 'import', p_reason);
    end if;
  end loop;

  v_result := jsonb_build_object('applied', p_apply, 'received', jsonb_array_length(p_rows),
    'matched', v_matched, 'changed', v_changed, 'unchanged', v_unchanged,
    'unmatched', v_unmatched, 'invalid', v_invalid, 'sample', v_sample);
  if p_apply then
    insert into public.price_change_requests(company_id, request_id, price_list_id, kind, result, created_by)
    values (p_company, p_request_id, p_list, 'import', v_result, auth.uid());
  end if;
  return v_result;
end;
$$;

create function public.save_item_sale_settings(
  p_company uuid, p_item uuid, p_tax numeric, p_content numeric, p_content_unit uuid
) returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.price_require_admin(p_company);
  if not exists (select 1 from public.items where company_id = p_company and id = p_item
                 and item_type = 'finished_product') then
    raise exception 'Producto terminado inexistente';
  end if;
  if p_tax is not null and p_tax not between 0 and 100 then raise exception 'IVA inválido'; end if;
  if (p_content is null) <> (p_content_unit is null) or (p_content is not null and p_content <= 0) then
    raise exception 'Indicá contenido y unidad juntos (contenido mayor a 0)';
  end if;
  insert into public.item_sale_settings(company_id, item_id, tax_percent, content_quantity, content_unit_id, updated_by)
  values (p_company, p_item, p_tax, p_content, p_content_unit, auth.uid())
  on conflict (company_id, item_id) do update set tax_percent = excluded.tax_percent,
    content_quantity = excluded.content_quantity, content_unit_id = excluded.content_unit_id,
    updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;

create function public.assign_customer_price_list(p_company uuid, p_customer uuid, p_list uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform private.price_require_admin(p_company);
  if not exists (select 1 from public.customers where company_id = p_company and id = p_customer) then
    raise exception 'Cliente inexistente';
  end if;
  if p_list is null then
    delete from public.customer_price_lists where company_id = p_company and customer_id = p_customer;
    return;
  end if;
  if not exists (select 1 from public.price_lists where company_id = p_company and id = p_list and not archived) then
    raise exception 'Lista inexistente o archivada';
  end if;
  insert into public.customer_price_lists(company_id, customer_id, price_list_id, updated_by)
  values (p_company, p_customer, p_list, auth.uid())
  on conflict (company_id, customer_id) do update set price_list_id = excluded.price_list_id,
    updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;

-- 7) Lectura ----------------------------------------------------------------------------------------------
-- Vista de ventas: precio neto, IVA, precio final y precio por contenido. SIN costos ni márgenes.
-- Precio efectivo: el propio de la lista; si la lista es derivada y no tiene propio, el de la base con descuento.
create function public.erp_price_list_rows(
  p_company uuid, p_list uuid, p_search text default '', p_only_missing boolean default false,
  p_page integer default 0, p_page_size integer default 50
) returns table(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text,
  tax_percent numeric, gross_price numeric, content_quantity numeric, content_unit_symbol text,
  price_per_content numeric, total_count bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_tax numeric; v_size integer; v_term text;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if not exists (select 1 from public.price_lists where company_id = p_company and id = p_list) then
    raise exception 'Lista inexistente';
  end if;
  select coalesce((select s.default_tax_percent from public.price_settings s where s.company_id = p_company), 21)
    into v_tax;
  v_size := least(greatest(coalesce(p_page_size, 50), 1), 200);
  v_term := lower(btrim(coalesce(p_search, '')));
  return query
  select e.item_id, e.code, e.name, e.unit_symbol, e.net_price, e.source, coalesce(s.tax_percent, v_tax),
    round(e.net_price * (1 + coalesce(s.tax_percent, v_tax) / 100), 2), s.content_quantity, cu.symbol,
    case when s.content_quantity is not null and e.net_price is not null
      then round(e.net_price / s.content_quantity, 4) end,
    count(*) over ()
  from private.price_effective(p_company, p_list, v_term) e
  left join public.item_sale_settings s on s.company_id = p_company and s.item_id = e.item_id
  left join public.units cu on cu.company_id = s.company_id and cu.id = s.content_unit_id
  where (not coalesce(p_only_missing, false) or e.net_price is null)
  order by (e.net_price is null) desc, e.name, e.item_id
  limit v_size offset greatest(coalesce(p_page, 0), 0) * v_size;
end;
$$;

-- Vista del administrador: agrega costo, método, margen sobre precio, recargo sobre costo, ganancia unitaria
-- (bruta y después de comisión + estructura) y alertas. p_filter: all | missing | low_margin | cost_changed.
-- El costo se calcula solo para los productos de la página; los filtros low_margin y cost_changed lo calculan
-- para todos los productos con precio y exigen que no sean más de 1000 (acotar con la búsqueda).
create function public.erp_admin_price_list_rows(
  p_company uuid, p_list uuid, p_search text default '', p_filter text default 'all',
  p_page integer default 0, p_page_size integer default 50
) returns table(item_id uuid, code text, name text, unit_symbol text, net_price numeric, source text,
  method text, method_value numeric, cost numeric, margin_percent numeric, markup_percent numeric,
  profit numeric, profit_after_costs numeric, low_margin boolean, cost_changed boolean, total_count bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_size integer; v_term text; v_min numeric; v_over numeric; v_ids uuid[]; v_total bigint;
  v_page integer; v_by_cost boolean;
begin
  perform private.price_require_cost_view(p_company);
  if p_filter is null or p_filter not in ('all', 'missing', 'low_margin', 'cost_changed') then
    raise exception 'Filtro inválido';
  end if;
  if not exists (select 1 from public.price_lists where company_id = p_company and id = p_list) then
    raise exception 'Lista inexistente';
  end if;
  select coalesce(s.min_margin_percent, 0), coalesce(s.commission_percent, 0) + coalesce(s.structure_percent, 0)
    into v_min, v_over
  from (select 1) x left join public.price_settings s on s.company_id = p_company;
  v_size := least(greatest(coalesce(p_page_size, 50), 1), 200);
  v_page := greatest(coalesce(p_page, 0), 0);
  v_term := lower(btrim(coalesce(p_search, '')));
  v_by_cost := p_filter in ('low_margin', 'cost_changed');

  if v_by_cost then
    select coalesce(array_agg(t.item_id), '{}') into v_ids from (
      select e.item_id from private.price_effective(p_company, p_list, v_term) e
      where e.net_price is not null limit 1001) t;
    if cardinality(v_ids) > 1000 then
      raise exception 'Hay más de 1000 productos con precio: buscá por nombre para acotar este filtro';
    end if;
  else
    select count(*) into v_total from private.price_effective(p_company, p_list, v_term) e
    where p_filter = 'all' or e.net_price is null;
    select coalesce(array_agg(t.item_id), '{}') into v_ids from (
      select e.item_id from private.price_effective(p_company, p_list, v_term) e
      where p_filter = 'all' or e.net_price is null
      order by (e.net_price is null) desc, e.name, e.item_id
      limit v_size offset v_page * v_size) t;
  end if;

  return query
  with c as materialized (select cc.item_id, cc.cost from private.price_costs(p_company, v_ids) cc),
  calc as (
    select e.*, c.cost,
      case when e.net_price > 0 and c.cost is not null then round((e.net_price - c.cost) / e.net_price * 100, 2) end as margin_percent,
      case when c.cost > 0 and e.net_price is not null then round((e.net_price - c.cost) / c.cost * 100, 2) end as markup_percent,
      case when e.net_price is not null and c.cost is not null then round(e.net_price - c.cost, 2) end as profit,
      case when e.net_price is not null and c.cost is not null
        then round(e.net_price - c.cost - e.net_price * v_over / 100, 2) end as profit_after_costs
    from private.price_effective(p_company, p_list, v_term) e
    left join c on c.item_id = e.item_id
    where e.item_id = any (v_ids)
  ),
  flagged as (
    select k.*, (k.margin_percent is not null and k.margin_percent < v_min) as low_margin,
      (k.cost_snapshot is not null and k.cost is not null and k.cost_snapshot <> k.cost) as cost_changed
    from calc k
  )
  select f.item_id, f.code, f.name, f.unit_symbol, f.net_price, f.source, f.method, f.method_value, f.cost,
    f.margin_percent, f.markup_percent, f.profit, f.profit_after_costs, f.low_margin, f.cost_changed,
    case when v_by_cost then count(*) over () else v_total end
  from flagged f
  where case p_filter when 'low_margin' then f.low_margin when 'cost_changed' then f.cost_changed else true end
  order by (f.net_price is null) desc, f.name, f.item_id
  limit v_size offset case when v_by_cost then v_page * v_size else 0 end;
end;
$$;

create function public.erp_price_list_history(
  p_company uuid, p_list uuid, p_item uuid, p_page integer default 0
) returns table(changed_at timestamptz, item_id uuid, item_code text, item_name text, old_net_price numeric,
  new_net_price numeric, method text, method_value numeric, cost_snapshot numeric, source text,
  reason text, changed_by_label text, total_count bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  perform private.price_require_cost_view(p_company);
  return query
  select h.changed_at, h.item_id, i.code, i.name, h.old_net_price, h.new_net_price, h.method, h.method_value,
    h.cost_snapshot, h.source, h.reason,
    coalesce(nullif(btrim((select p.name from public.profiles p where p.id = h.changed_by)), ''), 'Usuario'),
    count(*) over ()
  from public.price_list_item_history h
  join public.items i on i.company_id = h.company_id and i.id = h.item_id
  where h.company_id = p_company and h.price_list_id = p_list and (p_item is null or h.item_id = p_item)
  order by h.changed_at desc, h.id
  limit 50 offset greatest(coalesce(p_page, 0), 0) * 50;
end;
$$;

-- Qué precio neto le corresponde a un cliente (solo consulta; la venta todavía no lo usa).
-- Orden: lista del cliente vigente hoy → lista predeterminada vigente → precio actual del producto.
create function public.erp_resolve_sale_price(p_company uuid, p_customer uuid, p_item uuid)
returns table(net_price numeric, currency text, tax_percent numeric, gross_price numeric, price_list_id uuid, source text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_list public.price_lists%rowtype; v_price numeric; v_tax numeric; v_try uuid; v_src text;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  select coalesce(s.tax_percent, (select default_tax_percent from public.price_settings where company_id = p_company), 21)
    into v_tax from (select 1) x
    left join public.item_sale_settings s on s.company_id = p_company and s.item_id = p_item;
  for v_try, v_src in
    select l.price_list_id, 'customer' from public.customer_price_lists l
      where l.company_id = p_company and l.customer_id = p_customer
    union all
    select d.id, 'default' from public.price_lists d where d.company_id = p_company and d.is_default
    order by 2 asc -- 'customer' antes que 'default'
  loop
    select * into v_list from public.price_lists
    where company_id = p_company and id = v_try and not archived
      and (valid_from is null or valid_from <= v_today) and (valid_to is null or valid_to >= v_today);
    if not found then continue; end if;
    select coalesce(own.net_price, private.price_round(b.net_price * (1 - v_list.base_discount_percent / 100), v_list.rounding_step))
      into v_price
    from (select 1) x
    left join public.price_list_items own
      on own.company_id = p_company and own.price_list_id = v_list.id and own.item_id = p_item
    left join public.price_list_items b
      on b.company_id = p_company and b.price_list_id = v_list.base_list_id and b.item_id = p_item;
    if v_price is not null then
      return query select v_price, v_list.currency, v_tax, round(v_price * (1 + v_tax / 100), 2), v_list.id, v_src;
      return;
    end if;
  end loop;
  return query select i.sale_unit_price, 'ARS'::text, v_tax,
    case when i.sale_unit_price is not null then round(i.sale_unit_price * (1 + v_tax / 100), 2) end,
    null::uuid, 'item'::text
  from public.items i where i.company_id = p_company and i.id = p_item;
end;
$$;

revoke all on function
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric),
  public.erp_price_settings(uuid),
  public.save_price_list(uuid, uuid, text, text, date, date, boolean, uuid, numeric, numeric, text, boolean),
  public.set_price_list_item(uuid, uuid, uuid, text, numeric, text),
  public.remove_price_list_item(uuid, uuid, uuid, text),
  public.bulk_price_change(uuid, uuid, text, numeric, uuid[], boolean, text, uuid),
  public.import_price_list_items(uuid, uuid, jsonb, boolean, text, uuid),
  public.save_item_sale_settings(uuid, uuid, numeric, numeric, uuid),
  public.assign_customer_price_list(uuid, uuid, uuid),
  public.erp_price_list_rows(uuid, uuid, text, boolean, integer, integer),
  public.erp_admin_price_list_rows(uuid, uuid, text, text, integer, integer),
  public.erp_price_list_history(uuid, uuid, uuid, integer),
  public.erp_resolve_sale_price(uuid, uuid, uuid)
  from public, anon;
grant execute on function
  public.save_price_settings(uuid, numeric, numeric, numeric, numeric),
  public.erp_price_settings(uuid),
  public.save_price_list(uuid, uuid, text, text, date, date, boolean, uuid, numeric, numeric, text, boolean),
  public.set_price_list_item(uuid, uuid, uuid, text, numeric, text),
  public.remove_price_list_item(uuid, uuid, uuid, text),
  public.bulk_price_change(uuid, uuid, text, numeric, uuid[], boolean, text, uuid),
  public.import_price_list_items(uuid, uuid, jsonb, boolean, text, uuid),
  public.save_item_sale_settings(uuid, uuid, numeric, numeric, uuid),
  public.assign_customer_price_list(uuid, uuid, uuid),
  public.erp_price_list_rows(uuid, uuid, text, boolean, integer, integer),
  public.erp_admin_price_list_rows(uuid, uuid, text, text, integer, integer),
  public.erp_price_list_history(uuid, uuid, uuid, integer),
  public.erp_resolve_sale_price(uuid, uuid, uuid)
  to authenticated;

commit;
