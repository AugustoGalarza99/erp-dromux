-- Dromux ERP · 041 · Presupuestos para clientes (con numeración, vigencia y PDF sin costos) y datos de la empresa.
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario, respaldo y después de la
-- revisión crítica. Requiere 039 y 040 aplicadas. Comprobaciones: supabase/verificaciones/041_comprobaciones.sql.
-- Deshacer: supabase/reparacion/0_deshacer_041.sql (aborta si ya hay presupuestos).
--
-- Un presupuesto NO mueve stock ni dinero: es un documento con precios congelados.
--   * El precio de cada línea lo calcula el servidor con la misma regla que la venta (lista del cliente →
--     lista predeterminada → precio del producto) y los mismos topes de descuento (040).
--   * Guarda copia de los datos del cliente y de cada producto (cambios posteriores no alteran el documento).
--   * No tiene costos ni márgenes en ninguna tabla ni función: lo ve cualquiera con sales:read.
--   * Numeración propia por empresa, idempotente por request_id. No se edita: para corregir, se crea otro.
--     Solo cambia el estado (abierto, aceptado, rechazado, cancelado); "vencido" se calcula por fecha.
--   * Conversión automática a venta: fuera de esta migración (la venta sigue pasando por post_sale).
-- company_profile guarda razón social, CUIT, domicilio, contacto y logo para el membrete de los documentos.
-- El logo se copia desde production_document_settings si ya estaba cargado.

begin;

-- 1) Datos de la empresa para documentos -------------------------------------------------------------------
create table public.company_profile (
  company_id uuid primary key references public.companies(id),
  legal_name text not null default '' check (length(legal_name) <= 160),
  tax_id text not null default '' check (length(tax_id) <= 30),
  tax_condition text not null default '' check (length(tax_condition) <= 60),
  address text not null default '' check (length(address) <= 240),
  phone text not null default '' check (length(phone) <= 40),
  email text not null default '' check (length(email) <= 160),
  website text not null default '' check (length(website) <= 160),
  logo_data text not null default '' check (length(logo_data) <= 3000000),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);

insert into public.company_profile(company_id, logo_data)
select s.company_id, s.logo_data from public.production_document_settings s
where s.logo_data <> '' and length(s.logo_data) <= 3000000
on conflict do nothing;

-- 2) Presupuestos ---------------------------------------------------------------------------------------------
create table public.quote_counters (
  company_id uuid primary key references public.companies(id),
  next_number bigint not null default 1 check (next_number >= 1)
);

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  number bigint not null,
  request_id uuid not null,
  request_payload jsonb not null,
  customer_id uuid,
  customer_name text not null check (length(btrim(customer_name)) between 1 and 160),
  customer_tax_id text not null default '' check (length(customer_tax_id) <= 30),
  customer_email text not null default '' check (length(customer_email) <= 160),
  customer_phone text not null default '' check (length(customer_phone) <= 40),
  customer_address text not null default '' check (length(customer_address) <= 240),
  status text not null default 'open' check (status in ('open', 'accepted', 'rejected', 'cancelled')),
  valid_until date not null,
  note text not null default '' check (length(note) <= 1000),
  show_tax boolean not null default true,
  net_total numeric(18,2) not null check (net_total >= 0 and net_total < 10000000000000000),
  tax_total numeric(18,2) not null check (tax_total >= 0),
  gross_total numeric(18,2) not null check (gross_total >= 0),
  check (gross_total = net_total + tax_total),
  tax_breakdown jsonb not null default '[]'::jsonb,
  created_by uuid not null,
  created_by_label text not null default '',
  created_at timestamptz not null default clock_timestamp(),
  status_changed_at timestamptz,
  status_changed_by uuid,
  unique (company_id, number),
  unique (company_id, request_id),
  unique (company_id, id),
  foreign key (company_id, customer_id) references public.customers(company_id, id)
);
create index quotes_company_created_idx on public.quotes(company_id, created_at desc);
create index quotes_company_status_idx on public.quotes(company_id, status, valid_until);

create table public.quote_status_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  quote_id uuid not null,
  from_status text,
  to_status text not null,
  changed_by uuid not null,
  changed_at timestamptz not null default clock_timestamp(),
  foreign key (company_id, quote_id) references public.quotes(company_id, id)
);
create index quote_status_events_idx on public.quote_status_events(company_id, quote_id, changed_at);

create table public.quote_lines (
  company_id uuid not null,
  quote_id uuid not null,
  line_no smallint not null check (line_no between 1 and 200),
  item_id uuid not null,
  item_code text not null,
  item_name text not null,
  unit_symbol text not null,
  quantity numeric(18,6) not null check (quantity > 0),
  price_list_id uuid,
  list_unit_price numeric(18,2) not null check (list_unit_price >= 0),
  discount_percent numeric(5,2) not null default 0 check (discount_percent >= 0 and discount_percent < 100),
  discount_reason text check (discount_reason is null or length(discount_reason) <= 200),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  tax_percent numeric(5,2) not null check (tax_percent between 0 and 100),
  primary key (company_id, quote_id, line_no),
  unique (company_id, quote_id, item_id),
  foreign key (company_id, quote_id) references public.quotes(company_id, id),
  foreign key (company_id, item_id) references public.items(company_id, id),
  foreign key (company_id, price_list_id) references public.price_lists(company_id, id)
);

-- 3) Integridad: las líneas no cambian; del presupuesto solo cambia el estado --------------------------------
create function private.quote_lines_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Las líneas de un presupuesto no se modifican ni se borran';
end;
$$;
create trigger quote_lines_immutable before update or delete on public.quote_lines
  for each row execute function private.quote_lines_immutable();
create trigger quote_status_events_immutable before update or delete on public.quote_status_events
  for each row execute function private.quote_lines_immutable();

create function private.quotes_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Un presupuesto no se borra: cancelalo';
  end if;
  if (to_jsonb(new) - 'status' - 'status_changed_at' - 'status_changed_by')
     is distinct from (to_jsonb(old) - 'status' - 'status_changed_at' - 'status_changed_by') then
    raise exception 'Un presupuesto no se edita: creá uno nuevo';
  end if;
  return new;
end;
$$;
create trigger quotes_guard before update or delete on public.quotes
  for each row execute function private.quotes_guard();

-- 4) RLS y permisos ---------------------------------------------------------------------------------------------
alter table public.company_profile enable row level security;
alter table public.quote_counters enable row level security;
alter table public.quotes enable row level security;
alter table public.quote_lines enable row level security;
alter table public.quote_status_events enable row level security;

revoke all on table public.company_profile, public.quote_counters, public.quotes, public.quote_lines,
  public.quote_status_events from public, anon, authenticated;
-- Lectura por columna (sin request_payload). Sin escritura directa: solo funciones.
grant select (id, company_id, number, customer_id, customer_name, customer_tax_id, customer_email,
  customer_phone, customer_address, status, valid_until, note, show_tax, net_total, tax_total, gross_total,
  tax_breakdown, created_by_label, created_at, status_changed_at)
  on public.quotes to authenticated;
grant select on public.quote_lines, public.quote_status_events to authenticated;

create policy quotes_read on public.quotes for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
create policy quote_lines_read on public.quote_lines for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
create policy quote_status_events_read on public.quote_status_events for select to authenticated
  using ((select private.has_permission(company_id, 'sales', 'read')));
-- company_profile: sin permisos de tabla; se lee con erp_company_profile y se escribe con save_company_profile.

-- 5) Datos de la empresa ----------------------------------------------------------------------------------------
create function public.save_company_profile(
  p_company uuid, p_legal_name text, p_tax_id text, p_tax_condition text, p_address text, p_phone text,
  p_email text, p_website text, p_logo text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_head bytea;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin'
     or not private.has_permission(p_company, 'sales', 'update') then
    raise exception 'Solo un administrador puede editar los datos de la empresa' using errcode = '42501';
  end if;
  if length(coalesce(p_legal_name, '')) > 160 or length(coalesce(p_tax_id, '')) > 30
     or length(coalesce(p_tax_condition, '')) > 60 or length(coalesce(p_address, '')) > 240
     or length(coalesce(p_phone, '')) > 40 or length(coalesce(p_email, '')) > 160
     or length(coalesce(p_website, '')) > 160 then
    raise exception 'Algún dato de la empresa es demasiado largo';
  end if;
  -- p_logo nulo = conservar el logo actual; '' = quitarlo.
  if coalesce(p_logo, '') <> '' then
    if p_logo !~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/]+={0,2}$' or length(p_logo) > 3000000 then
      raise exception 'El logo debe ser una imagen PNG, JPG o WebP de hasta 2 MB';
    end if;
    v_head := decode(substr(split_part(p_logo, ',', 2), 1, 16), 'base64');
    if not ((p_logo like 'data:image/png;%' and substring(v_head from 1 for 4) = '\x89504e47'::bytea)
         or (p_logo like 'data:image/jpeg;%' and substring(v_head from 1 for 3) = '\xffd8ff'::bytea)
         or (p_logo like 'data:image/webp;%' and substring(v_head from 1 for 4) = 'RIFF'::bytea
             and substring(v_head from 9 for 4) = 'WEBP'::bytea)) then
      raise exception 'El archivo del logo no es una imagen válida';
    end if;
  end if;
  insert into public.company_profile(company_id, legal_name, tax_id, tax_condition, address, phone, email,
    website, logo_data, updated_by)
  values (p_company, btrim(coalesce(p_legal_name, '')), btrim(coalesce(p_tax_id, '')),
    btrim(coalesce(p_tax_condition, '')), btrim(coalesce(p_address, '')), btrim(coalesce(p_phone, '')),
    btrim(coalesce(p_email, '')), btrim(coalesce(p_website, '')), coalesce(p_logo, ''), auth.uid())
  on conflict (company_id) do update set legal_name = excluded.legal_name, tax_id = excluded.tax_id,
    tax_condition = excluded.tax_condition, address = excluded.address, phone = excluded.phone,
    email = excluded.email, website = excluded.website,
    logo_data = case when p_logo is null then public.company_profile.logo_data else excluded.logo_data end,
    updated_at = clock_timestamp(), updated_by = auth.uid();
end;
$$;

create function public.erp_company_profile(p_company uuid)
returns table(legal_name text, tax_id text, tax_condition text, address text, phone text, email text,
  website text, logo_data text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not (private.has_permission(p_company, 'sales', 'read')
     or private.has_permission(p_company, 'production', 'read')) then
    raise exception 'Sin acceso a los datos de la empresa' using errcode = '42501';
  end if;
  return query
  select coalesce(nullif(p.legal_name, ''), c.name), coalesce(p.tax_id, ''), coalesce(p.tax_condition, ''),
    coalesce(p.address, ''), coalesce(p.phone, ''), coalesce(p.email, ''), coalesce(p.website, ''),
    coalesce(p.logo_data, '')
  from public.companies c left join public.company_profile p on p.company_id = c.id
  where c.id = p_company;
end;
$$;

-- 6) Crear un presupuesto -----------------------------------------------------------------------------------------
-- p_lines: [{"item_id", "quantity", "discount_percent"?, "discount_reason"?}] (hasta 200). El precio lo calcula
-- el servidor. p_customer opcional: sin cliente se presupuesta a un interesado (p_name obligatorio).
create function public.create_quote(
  p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text,
  p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_payload jsonb; v_existing public.quotes%rowtype; v_customer public.customers%rowtype;
  v_name text; v_tax_id text; v_email text; v_phone text; v_address text;
  v_line jsonb; v_item public.items%rowtype; v_res record; v_unit_symbol text;
  v_qty numeric; v_disc numeric; v_reason text; v_cap numeric; v_unit numeric; v_total numeric;
  v_lines jsonb := '[]'::jsonb; v_seen uuid[] := '{}'; v_n smallint := 0;
  v_net numeric := 0; v_tax numeric := 0; v_breakdown jsonb; v_id uuid := gen_random_uuid(); v_number bigint;
  v_label text; v_item_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'insert')
     or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Necesitás permiso para crear presupuestos' using errcode = '42501';
  end if;
  if p_request_id is null or p_lines is null or jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Revisá los productos del presupuesto (entre 1 y 200)';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('quote:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('customer', p_customer, 'name', btrim(coalesce(p_name, '')),
    'tax_id', btrim(coalesce(p_tax_id, '')), 'email', btrim(coalesce(p_email, '')),
    'phone', btrim(coalesce(p_phone, '')), 'address', btrim(coalesce(p_address, '')),
    'valid_until', p_valid_until, 'note', btrim(coalesce(p_note, '')),
    'show_tax', coalesce(p_show_tax, true), 'lines', p_lines);
  select * into v_existing from public.quotes where company_id = p_company and request_id = p_request_id;
  if found then
    if v_existing.created_by <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_existing.id;
  end if;
  -- Estas validaciones van DESPUÉS de la idempotencia: un reintento tardío devuelve el presupuesto ya creado.
  if p_valid_until is null or p_valid_until < v_today or p_valid_until > v_today + 365 then
    raise exception 'La vigencia debe estar entre hoy y un año';
  end if;
  if length(coalesce(p_note, '')) > 1000 then raise exception 'Las condiciones son demasiado largas'; end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  if p_customer is not null then
    select * into v_customer from public.customers
    where company_id = p_company and id = p_customer and active for share;
    if not found then raise exception 'Elegí un cliente activo'; end if;
    v_name := v_customer.name; v_tax_id := v_customer.tax_id; v_email := v_customer.email;
    v_phone := v_customer.phone; v_address := v_customer.address;
  else
    v_name := btrim(coalesce(p_name, '')); v_tax_id := btrim(coalesce(p_tax_id, ''));
    v_email := btrim(coalesce(p_email, '')); v_phone := btrim(coalesce(p_phone, ''));
    v_address := btrim(coalesce(p_address, ''));
    if length(v_name) not between 2 and 160 or length(v_tax_id) > 30 or length(v_email) > 160
       or length(v_phone) > 40 or length(v_address) > 240 then
      raise exception 'Indicá el nombre del interesado (hasta 160 caracteres) y revisá sus datos';
    end if;
  end if;

  select coalesce(s.max_discount_percent, 0) into v_cap from (select 1) x
  left join public.price_settings s on s.company_id = p_company;

  -- Se conserva el orden en que se cargaron las líneas (es el orden que ve el cliente en el PDF).
  for v_line in select t.value from jsonb_array_elements(p_lines) with ordinality as t(value, ord) order by t.ord loop
    v_n := v_n + 1;
    begin
      v_qty := (v_line ->> 'quantity')::numeric;
    exception when others then v_qty := null;
    end;
    if v_qty is null or v_qty <= 0 or v_qty >= 1000000000000 or v_qty <> round(v_qty, 6) then
      raise exception 'La cantidad de la línea % es inválida', v_n;
    end if;
    begin
      v_item_id := (v_line ->> 'item_id')::uuid;
    exception when others then v_item_id := null;
    end;
    select * into v_item from public.items
    where company_id = p_company and id = v_item_id and active and item_type = 'finished_product';
    if v_item_id is null or not found then raise exception 'La línea % tiene un producto inactivo o que no es terminado', v_n; end if;
    if v_item.id = any (v_seen) then raise exception 'Cada producto puede figurar una sola vez'; end if;
    v_seen := v_seen || v_item.id;
    select * into v_res from private.sale_resolve_price(p_company, p_customer, v_item.id);
    if v_res.price is null or v_res.price <= 0 then raise exception 'Definí el precio de venta de %', v_item.name; end if;

    begin
      v_disc := coalesce(nullif(btrim(v_line ->> 'discount_percent'), '')::numeric, 0);
    exception when others then v_disc := -1;
    end;
    v_reason := nullif(btrim(v_line ->> 'discount_reason'), '');
    if v_disc = 0 then v_reason := null; end if;
    if v_disc < 0 or v_disc >= 100 or v_disc <> round(v_disc, 2) then
      raise exception 'El descuento de % es inválido', v_item.name;
    end if;
    if length(coalesce(v_reason, '')) > 200 then raise exception 'El motivo del descuento es demasiado largo'; end if;
    if v_disc > v_cap then
      if private.get_user_role(p_company) is distinct from 'admin' then
        raise exception 'El descuento de % supera el máximo permitido (% %%)', v_item.name, v_cap;
      end if;
      if length(regexp_replace(coalesce(v_reason, ''), '[^[:alnum:]]', '', 'g')) < 3 then
        raise exception 'Indicá el motivo del descuento de %', v_item.name;
      end if;
    end if;
    v_unit := round(v_res.price * (1 - v_disc / 100), 2);
    if v_disc > 0 and v_unit <= 0 then raise exception 'El descuento de % deja el precio en cero', v_item.name; end if;
    v_total := round(v_qty * v_unit, 2);
    v_net := v_net + v_total;
    if v_net >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;
    select symbol into v_unit_symbol from public.units where company_id = p_company and id = v_item.unit_id;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'item_id', v_item.id, 'item_code', v_item.code, 'item_name', v_item.name, 'unit_symbol', v_unit_symbol,
      'quantity', v_qty, 'price_list_id', v_res.list_id, 'list_unit_price', v_res.price,
      'discount_percent', v_disc, 'discount_reason', v_reason, 'unit_price', v_unit,
      'line_total', v_total, 'tax_percent', v_res.tax_percent));
  end loop;

  -- IVA discriminado por alícuota: sobre la base de cada alícuota (no línea por línea).
  select coalesce(jsonb_agg(jsonb_build_object('rate', g.rate, 'base', g.base, 'tax', round(g.base * g.rate / 100, 2))
    order by g.rate), '[]'::jsonb)
  into v_breakdown
  from (select (e ->> 'tax_percent')::numeric as rate, sum((e ->> 'line_total')::numeric) as base
        from jsonb_array_elements(v_lines) e group by 1) g;
  select coalesce(sum((b ->> 'tax')::numeric), 0) into v_tax from jsonb_array_elements(v_breakdown) b;
  if v_net + v_tax >= 10000000000000000 then raise exception 'El total supera el máximo permitido'; end if;

  insert into public.quote_counters(company_id) values (p_company) on conflict do nothing;
  update public.quote_counters set next_number = next_number + 1
  where company_id = p_company returning next_number - 1 into v_number;
  select coalesce(nullif(btrim(p.name), ''), 'Usuario') into v_label
  from (select 1) x left join public.profiles p on p.id = auth.uid();

  insert into public.quotes(id, company_id, number, request_id, request_payload, customer_id, customer_name,
    customer_tax_id, customer_email, customer_phone, customer_address, valid_until, note, show_tax,
    net_total, tax_total, gross_total, tax_breakdown, created_by, created_by_label)
  values (v_id, p_company, v_number, p_request_id, v_payload, p_customer, v_name, v_tax_id, v_email, v_phone,
    v_address, p_valid_until, btrim(coalesce(p_note, '')), coalesce(p_show_tax, true), v_net, v_tax,
    v_net + v_tax, v_breakdown, auth.uid(), coalesce(v_label, 'Usuario'));

  v_n := 0;
  for v_line in select value from jsonb_array_elements(v_lines) loop
    v_n := v_n + 1;
    insert into public.quote_lines(company_id, quote_id, line_no, item_id, item_code, item_name, unit_symbol,
      quantity, price_list_id, list_unit_price, discount_percent, discount_reason, unit_price, line_total,
      tax_percent)
    values (p_company, v_id, v_n, (v_line ->> 'item_id')::uuid, v_line ->> 'item_code', v_line ->> 'item_name',
      v_line ->> 'unit_symbol', (v_line ->> 'quantity')::numeric, (v_line ->> 'price_list_id')::uuid,
      (v_line ->> 'list_unit_price')::numeric, (v_line ->> 'discount_percent')::numeric,
      v_line ->> 'discount_reason', (v_line ->> 'unit_price')::numeric, (v_line ->> 'line_total')::numeric,
      (v_line ->> 'tax_percent')::numeric);
  end loop;
  return v_id;
end;
$$;

-- 7) Estado -----------------------------------------------------------------------------------------------------------
-- Desde "abierto" a aceptado, rechazado o cancelado; solo el administrador puede reabrir.
create function public.set_quote_status(p_company uuid, p_quote uuid, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row public.quotes%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'update') then
    raise exception 'Sin permiso para cambiar presupuestos' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('open', 'accepted', 'rejected', 'cancelled') then
    raise exception 'Estado inválido';
  end if;
  select * into v_row from public.quotes where company_id = p_company and id = p_quote for update;
  if not found then raise exception 'Presupuesto inexistente'; end if;
  if v_row.status = p_status then return; end if;
  if p_status = 'accepted' and v_row.valid_until < (now() at time zone 'America/Argentina/Buenos_Aires')::date
     and private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'El presupuesto está vencido: solo un administrador puede aceptarlo';
  end if;
  if v_row.status <> 'open' and (p_status <> 'open'
     or private.get_user_role(p_company) is distinct from 'admin') then
    raise exception 'Ese presupuesto ya está resuelto; solo un administrador puede reabrirlo';
  end if;
  update public.quotes set status = p_status, status_changed_at = clock_timestamp(), status_changed_by = auth.uid()
  where company_id = p_company and id = p_quote;
  insert into public.quote_status_events(company_id, quote_id, from_status, to_status, changed_by)
  values (p_company, p_quote, v_row.status, p_status, auth.uid());
end;
$$;

-- 8) Lectura ------------------------------------------------------------------------------------------------------------
-- Lista paginada. p_status: all | open | expired | accepted | rejected | cancelled ("vencido" = abierto con fecha pasada).
create function public.erp_quotes_page(
  p_company uuid, p_search text default '', p_status text default 'all', p_page integer default 0,
  p_size integer default 25
) returns table(id uuid, number bigint, customer_name text, customer_tax_id text, status text,
  effective_status text, valid_until date, net_total numeric, gross_total numeric, created_at timestamptz,
  created_by_label text, line_count bigint, total_count bigint)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
  v_term text := lower(btrim(coalesce(p_search, ''))); v_size integer := least(greatest(coalesce(p_size, 25), 1), 100);
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  if p_status is null or p_status not in ('all', 'open', 'expired', 'accepted', 'rejected', 'cancelled') then
    raise exception 'Filtro inválido';
  end if;
  return query
  select q.id, q.number, q.customer_name, q.customer_tax_id, q.status,
    case when q.status = 'open' and q.valid_until < v_today then 'expired' else q.status end,
    q.valid_until, q.net_total, q.gross_total, q.created_at, q.created_by_label,
    (select count(*) from public.quote_lines l where l.company_id = q.company_id and l.quote_id = q.id),
    count(*) over ()
  from public.quotes q
  where q.company_id = p_company
    and (v_term = '' or q.number::text = v_term or position(v_term in lower(q.customer_name)) > 0
         or position(v_term in lower(q.customer_tax_id)) > 0)
    and (p_status = 'all'
         or (p_status = 'expired' and q.status = 'open' and q.valid_until < v_today)
         or (p_status = 'open' and q.status = 'open' and q.valid_until >= v_today)
         or (p_status in ('accepted', 'rejected', 'cancelled') and q.status = p_status))
  order by q.created_at desc, q.id
  limit v_size offset greatest(coalesce(p_page, 0), 0) * v_size;
end;
$$;

-- Detalle completo (para ver e imprimir): presupuesto + líneas.
create function public.erp_quote_detail(p_company uuid, p_quote uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date; v_q public.quotes%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Sin acceso a ventas' using errcode = '42501';
  end if;
  select * into v_q from public.quotes where company_id = p_company and id = p_quote;
  if not found then raise exception 'Presupuesto inexistente'; end if;
  return jsonb_build_object(
    'id', v_q.id, 'number', v_q.number, 'customer_name', v_q.customer_name, 'customer_tax_id', v_q.customer_tax_id,
    'customer_email', v_q.customer_email, 'customer_phone', v_q.customer_phone,
    'customer_address', v_q.customer_address, 'status', v_q.status,
    'effective_status', case when v_q.status = 'open' and v_q.valid_until < v_today then 'expired' else v_q.status end,
    'valid_until', v_q.valid_until, 'note', v_q.note, 'show_tax', v_q.show_tax, 'net_total', v_q.net_total,
    'tax_total', v_q.tax_total, 'gross_total', v_q.gross_total, 'tax_breakdown', v_q.tax_breakdown,
    'created_at', v_q.created_at, 'created_by_label', v_q.created_by_label,
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'line_no', l.line_no, 'item_code', l.item_code, 'item_name', l.item_name, 'unit_symbol', l.unit_symbol,
        'quantity', l.quantity, 'list_unit_price', l.list_unit_price, 'discount_percent', l.discount_percent,
        'unit_price', l.unit_price, 'line_total', l.line_total, 'tax_percent', l.tax_percent) order by l.line_no)
      from public.quote_lines l where l.company_id = v_q.company_id and l.quote_id = v_q.id), '[]'::jsonb));
end;
$$;

revoke all on function private.quote_lines_immutable(), private.quotes_guard() from public, anon, authenticated;
revoke all on function
  public.save_company_profile(uuid, text, text, text, text, text, text, text, text),
  public.erp_company_profile(uuid),
  public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid),
  public.set_quote_status(uuid, uuid, text),
  public.erp_quotes_page(uuid, text, text, integer, integer),
  public.erp_quote_detail(uuid, uuid)
  from public, anon;
grant execute on function
  public.save_company_profile(uuid, text, text, text, text, text, text, text, text),
  public.erp_company_profile(uuid),
  public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid),
  public.set_quote_status(uuid, uuid, text),
  public.erp_quotes_page(uuid, text, text, integer, integer),
  public.erp_quote_detail(uuid, uuid)
  to authenticated;

commit;
