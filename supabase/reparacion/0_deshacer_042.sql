-- Deshace 042: vuelve create_quote y erp_quote_detail a su versión de la 041 y quita la columna tax_included.
-- Aborta si ya hay presupuestos con IVA sumado sin discriminar (se perdería esa indicación).
begin;
lock table public.quotes in share row exclusive mode;

do $$
begin
  if exists (select 1 from public.quotes where tax_included) then
    raise exception 'Hay presupuestos con IVA sumado sin discriminar. No se puede deshacer la 042 sin perder esa información.';
  end if;
end
$$;

drop function public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid, boolean);

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

create or replace function public.erp_quote_detail(p_company uuid, p_quote uuid) returns jsonb
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

revoke all on function
  public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid),
  public.erp_quote_detail(uuid, uuid)
  from public, anon;
grant execute on function
  public.create_quote(uuid, uuid, text, text, text, text, text, date, text, boolean, jsonb, uuid),
  public.erp_quote_detail(uuid, uuid)
  to authenticated;

alter table public.quotes drop constraint quotes_tax_mode_check, drop column tax_included;

notify pgrst, 'reload schema';

commit;
