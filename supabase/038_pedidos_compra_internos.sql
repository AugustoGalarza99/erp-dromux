-- Dromux ERP · 038 · Pedidos de compra internos (solicitudes de un operario para Compras).
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización para el entorno destino y después de
-- una revisión crítica de privilegios (ver supabase/verificaciones/038_comprobaciones.sql).
-- Orden: respaldo -> esta migración -> comprobaciones -> publicar frontend -> asignar el permiso a los roles.
--
-- Modelo de permisos (recurso nuevo `purchase_requests`):
--   purchase_requests:read    ver sus propios pedidos
--   purchase_requests:insert  crear pedidos
--   purchase_requests:update  cancelar sus propios pedidos pendientes (solo los propios)
--   Quien tiene purchases:read ve TODOS los pedidos; purchases:update los rechaza (con motivo);
--   purchases:insert los convierte en orden de compra (una sola transacción: convert_purchase_request).
-- Revisión crítica (subagente solo lectura, 23/11/2026): sin P0; se corrigieron conversión atómica,
-- cancelación solo propia con permiso previo al bloqueo, clave foránea compuesta a la orden, rango de
-- fecha y nombre visible sin dominio de correo. Pendiente: pruebas con dos empresas y tres roles.
--
-- Qué hace:
--   1) agrega `purchase_requests` a la lista blanca de recursos de create_company_role,
--      update_company_role y create_company, cambiando solo ese literal sobre la definición vigente
--      (no reescribe cuerpos: H-002) y aborta sin cambios si no encuentra exactamente 1 aparición;
--   2) da al rol `admin` de cada empresa existente los permisos del recurso nuevo;
--   3) crea tablas (RLS activada, sin escritura directa), disparadores de integridad y 5 funciones.
-- No toca stock, dinero ni órdenes de compra existentes.

begin;

-- 1) Lista blanca de recursos --------------------------------------------------------------------
do $$
declare
  r record;
  v_def text;
  v_count integer;
begin
  for r in select * from (values
    ('public.create_company_role(uuid,text,text,jsonb)', '''items'', ''stock'')', '''items'', ''stock'', ''purchase_requests'')'),
    ('public.update_company_role(uuid,uuid,text,jsonb)', '''items'', ''stock'')', '''items'', ''stock'', ''purchase_requests'')'),
    ('public.create_company(text)', '(''stock'')) as r(resource)', '(''stock''),(''purchase_requests'')) as r(resource)')
  ) as t(signature, old_text, new_text) loop
    v_def := pg_get_functiondef(r.signature::regprocedure);
    v_count := (length(v_def) - length(replace(v_def, r.old_text, ''))) / length(r.old_text);
    if v_count <> 1 then
      raise exception 'La función % tiene % apariciones de % (se esperaba 1). No se cambió nada.',
        r.signature, v_count, r.old_text;
    end if;
    execute replace(v_def, r.old_text, r.new_text);
  end loop;
end
$$;

-- 2) El administrador de cada empresa existente recibe el recurso nuevo --------------------------
insert into public.role_permissions(company_id, role_id, resource, action)
select r.company_id, r.id, 'purchase_requests', a.action
from public.roles r
cross join (values ('read'), ('insert'), ('update'), ('delete'), ('manage')) as a(action)
where r.code = 'admin'
on conflict do nothing;

-- 3) Tablas --------------------------------------------------------------------------------------
create table public.purchase_request_counters (
  company_id uuid primary key references public.companies(id) on delete cascade,
  next_number bigint not null default 1 check (next_number >= 1)
);

create table public.purchase_requests (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  number bigint not null,
  requested_by uuid not null,
  requester_label text not null check (length(requester_label) between 1 and 200),
  status text not null default 'pending'
    check (status in ('pending', 'ordered', 'rejected', 'cancelled')),
  priority text not null default 'normal' check (priority in ('normal', 'urgent')),
  needed_by date,
  note text not null default '' check (length(note) <= 500),
  resolution_note text not null default '' check (length(resolution_note) <= 500),
  purchase_order_id uuid,
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  unique (company_id, number),
  unique (company_id, id),
  foreign key (company_id, purchase_order_id) references public.purchase_orders(company_id, id),
  check ((status = 'pending') = (resolved_at is null)),
  check (status <> 'ordered' or purchase_order_id is not null)
);
create index purchase_requests_company_status_idx
  on public.purchase_requests (company_id, status, created_at desc);
create index purchase_requests_requester_idx
  on public.purchase_requests (company_id, requested_by, created_at desc);

create table public.purchase_request_lines (
  company_id uuid not null,
  request_id uuid not null,
  line_no smallint not null check (line_no between 1 and 200),
  item_id uuid,
  item_code text,
  item_name text not null check (length(btrim(item_name)) between 2 and 160),
  unit_symbol text not null default '' check (length(unit_symbol) <= 20),
  quantity numeric not null check (quantity > 0 and quantity < 1000000000000),
  note text not null default '' check (length(note) <= 200),
  primary key (request_id, line_no),
  foreign key (company_id, request_id) references public.purchase_requests(company_id, id),
  foreign key (company_id, item_id) references public.items(company_id, id),
  check (item_id is not null or item_code is null)
);

create table public.purchase_request_submissions (
  company_id uuid not null references public.companies(id),
  request_key uuid not null,
  request_id uuid not null references public.purchase_requests(id),
  request_payload jsonb not null,
  actor_id uuid not null,
  primary key (company_id, request_key)
);

alter table public.purchase_request_counters enable row level security;
alter table public.purchase_requests enable row level security;
alter table public.purchase_request_lines enable row level security;
alter table public.purchase_request_submissions enable row level security;

revoke all on table public.purchase_request_counters, public.purchase_requests,
  public.purchase_request_lines, public.purchase_request_submissions
  from public, anon, authenticated;
grant select on table public.purchase_requests, public.purchase_request_lines to authenticated;

create policy purchase_requests_read on public.purchase_requests
  for select to authenticated
  using (
    (select private.has_permission(company_id, 'purchases', 'read'))
    or (requested_by = (select auth.uid())
        and (select private.has_permission(company_id, 'purchase_requests', 'read')))
  );

create policy purchase_request_lines_read on public.purchase_request_lines
  for select to authenticated
  using (
    exists (
      select 1 from public.purchase_requests r
      where r.company_id = purchase_request_lines.company_id
        and r.id = purchase_request_lines.request_id
    )
  );

-- Disparadores de integridad ------------------------------------------------------------------------
create function private.purchase_request_lines_immutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Las líneas de un pedido de compra no se modifican ni se borran';
end;
$$;

create trigger purchase_request_lines_immutable
  before update or delete on public.purchase_request_lines
  for each row execute function private.purchase_request_lines_immutable();

create function private.purchase_requests_guard()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los pedidos de compra no se borran: se cancelan o se rechazan';
  end if;
  if old.status <> 'pending' then
    raise exception 'El pedido ya fue resuelto y no admite cambios';
  end if;
  if new.company_id <> old.company_id or new.number <> old.number
     or new.requested_by <> old.requested_by or new.created_at <> old.created_at
     or new.requester_label <> old.requester_label or new.priority <> old.priority
     or new.needed_by is distinct from old.needed_by or new.note <> old.note then
    raise exception 'Solo se puede cambiar el estado de un pedido';
  end if;
  return new;
end;
$$;

create trigger purchase_requests_guard
  before update or delete on public.purchase_requests
  for each row execute function private.purchase_requests_guard();

revoke all on function private.purchase_request_lines_immutable(), private.purchase_requests_guard()
  from public, anon, authenticated;

-- 4) Funciones -----------------------------------------------------------------------------------
-- Opciones de ítems para el pedido: sin costos ni precios (el operario no los ve).
create function public.purchase_request_item_options(p_company uuid, p_search text default '')
returns table (id uuid, code text, name text, unit_symbol text, item_type text)
language plpgsql stable security definer set search_path = '' as $$
declare v_term text := lower(btrim(coalesce(p_search, '')));
begin
  if auth.uid() is null
     or not (private.has_permission(p_company, 'purchase_requests', 'insert')
             or private.has_permission(p_company, 'purchases', 'insert')) then
    raise exception 'Sin permiso para armar pedidos de compra' using errcode = '42501';
  end if;
  if length(v_term) > 100 then raise exception 'Búsqueda demasiado larga'; end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.item_type
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where i.company_id = p_company and i.active and not i.archived
      and i.item_type in ('raw_material', 'consumable', 'semi_finished')
      and (v_term = '' or position(v_term in lower(i.code || ' ' || i.name)) > 0)
    order by i.name, i.id
    limit 20;
end;
$$;

create function public.create_purchase_request(
  p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_existing public.purchase_request_submissions%rowtype;
  v_payload jsonb;
  v_number bigint;
  v_request uuid;
  v_label text;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_code text;
  v_name text;
  v_unit text;
  v_note text;
  v_index smallint := 0;
  v_seen uuid[] := '{}';
begin
  if auth.uid() is null
     or not (private.has_permission(p_company, 'purchase_requests', 'insert')
             or private.has_permission(p_company, 'purchases', 'insert')) then
    raise exception 'Sin permiso para crear pedidos de compra' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  if p_priority is null or p_priority not in ('normal', 'urgent')
     or (p_needed_by is not null
         and (p_needed_by < current_date - 1 or p_needed_by > current_date + 730))
     or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 200 then
    raise exception 'Datos del pedido inválidos';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('purchase-request:' || p_company::text || ':' || p_request_id::text, 0));
  v_payload := jsonb_build_object('note', btrim(coalesce(p_note, '')),
    'needed_by', p_needed_by, 'priority', p_priority, 'lines', p_lines);
  select * into v_existing from public.purchase_request_submissions
  where company_id = p_company and request_key = p_request_id;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otro pedido';
    end if;
    return v_existing.request_id;
  end if;

  perform 1 from public.companies c where c.id = p_company and c.active for share;
  if not found then raise exception 'Empresa inactiva'; end if;

  -- Nombre visible: el cargado en el perfil o, si falta, la parte local del correo (sin el dominio).
  select coalesce(nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
                  nullif(split_part(coalesce(u.email, ''), '@', 1), ''), 'Usuario')
  into v_label from auth.users u where u.id = auth.uid();

  insert into public.purchase_request_counters(company_id) values (p_company)
  on conflict (company_id) do nothing;
  update public.purchase_request_counters c
  set next_number = c.next_number + 1
  where c.company_id = p_company
  returning c.next_number - 1 into v_number;

  insert into public.purchase_requests(
    company_id, number, requested_by, requester_label, priority, needed_by, note
  ) values (
    p_company, v_number, auth.uid(), left(coalesce(v_label, 'Usuario'), 200),
    p_priority, p_needed_by, btrim(coalesce(p_note, ''))
  ) returning id into v_request;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line ->> 'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$' then
      raise exception 'Línea de pedido inválida';
    end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000 then
      raise exception 'Cantidad fuera de rango';
    end if;
    v_note := btrim(coalesce(v_line ->> 'note', ''));
    if length(v_note) > 200 then raise exception 'La nota de una línea es demasiado larga'; end if;

    v_index := v_index + 1;
    if coalesce(v_line ->> 'item_id', '') <> '' then
      if (v_line ->> 'item_id') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
        raise exception 'Línea de pedido inválida';
      end if;
      v_item := (v_line ->> 'item_id')::uuid;
      if v_item = any (v_seen) then raise exception 'Un ítem no puede repetirse en el pedido'; end if;
      v_seen := v_seen || v_item;
      select i.code, i.name, u.symbol into v_code, v_name, v_unit
      from public.items i
      join public.units u on u.company_id = i.company_id and u.id = i.unit_id
      where i.company_id = p_company and i.id = v_item and i.active and not i.archived
      for share of i;
      if not found then raise exception 'El pedido contiene un ítem inexistente o inactivo'; end if;
      insert into public.purchase_request_lines(
        company_id, request_id, line_no, item_id, item_code, item_name, unit_symbol, quantity, note
      ) values (p_company, v_request, v_index, v_item, v_code, v_name, v_unit, v_quantity, v_note);
    else
      v_name := btrim(coalesce(v_line ->> 'free_text', ''));
      v_unit := btrim(coalesce(v_line ->> 'unit', ''));
      if length(v_name) not between 2 and 160 or length(v_unit) > 20 then
        raise exception 'Escribí qué necesitás (2 a 160 caracteres) y una unidad de hasta 20';
      end if;
      insert into public.purchase_request_lines(
        company_id, request_id, line_no, item_id, item_code, item_name, unit_symbol, quantity, note
      ) values (p_company, v_request, v_index, null, null, v_name, v_unit, v_quantity, v_note);
    end if;
  end loop;

  insert into public.purchase_request_submissions(company_id, request_key, request_id, request_payload, actor_id)
  values (p_company, p_request_id, v_request, v_payload, auth.uid());
  return v_request;
end;
$$;

-- Cancelar es solo para quien hizo el pedido. Compras no cancela pedidos ajenos: los rechaza con motivo.
create function public.cancel_purchase_request(p_company uuid, p_request uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row public.purchase_requests%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'purchase_requests', 'update') then
    raise exception 'Sin permiso para cancelar pedidos' using errcode = '42501';
  end if;
  select * into v_row from public.purchase_requests
  where id = p_request and company_id = p_company and requested_by = auth.uid() for update;
  if not found then raise exception 'Pedido inexistente o no es tuyo'; end if;
  if v_row.status <> 'pending' then raise exception 'El pedido ya fue resuelto'; end if;
  update public.purchase_requests
  set status = 'cancelled', resolved_by = auth.uid(), resolved_at = clock_timestamp()
  where id = p_request;
end;
$$;

create function public.reject_purchase_request(p_company uuid, p_request uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_row public.purchase_requests%rowtype; v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.uid() is null or not private.has_permission(p_company, 'purchases', 'update') then
    raise exception 'Sin permiso para rechazar pedidos' using errcode = '42501';
  end if;
  if length(v_reason) not between 5 and 500 then
    raise exception 'Indicá el motivo (5 a 500 caracteres)';
  end if;
  select * into v_row from public.purchase_requests
  where id = p_request and company_id = p_company for update;
  if not found then raise exception 'Pedido inexistente'; end if;
  if v_row.status <> 'pending' then raise exception 'El pedido ya fue resuelto'; end if;
  update public.purchase_requests
  set status = 'rejected', resolution_note = v_reason,
      resolved_by = auth.uid(), resolved_at = clock_timestamp()
  where id = p_request;
end;
$$;

-- Convierte el pedido en orden de compra en UNA sola transacción: bloquea el pedido, crea la orden
-- (idempotente por p_request_id, con la función existente) y lo marca como ordenado. Evita que dos
-- compradores conviertan el mismo pedido y que quede una orden huérfana si falla el marcado.
create function public.convert_purchase_request(
  p_company uuid, p_request uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_row public.purchase_requests%rowtype; v_order uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'purchases', 'insert') then
    raise exception 'Sin permiso para convertir pedidos en órdenes' using errcode = '42501';
  end if;
  if p_request_id is null then raise exception 'Identificador de solicitud inválido'; end if;
  select * into v_row from public.purchase_requests
  where id = p_request and company_id = p_company for update;
  if not found then raise exception 'Pedido inexistente'; end if;
  if v_row.status = 'ordered' then
    -- Reintento de la misma conversión: solo si esta solicitud ya creó esa orden.
    if v_row.purchase_order_id is not null and exists (
      select 1 from public.purchase_order_requests r
      where r.company_id = p_company and r.request_id = p_request_id
        and r.order_id = v_row.purchase_order_id) then
      return v_row.purchase_order_id;
    end if;
    raise exception 'El pedido ya fue resuelto';
  end if;
  if v_row.status <> 'pending' then raise exception 'El pedido ya fue resuelto'; end if;

  v_order := public.create_purchase_order_once(p_company, p_supplier, p_note, p_lines, p_request_id);
  update public.purchase_requests
  set status = 'ordered', purchase_order_id = v_order,
      resolved_by = auth.uid(), resolved_at = clock_timestamp()
  where id = p_request;
  return v_order;
end;
$$;

revoke all on function
  public.purchase_request_item_options(uuid, text),
  public.create_purchase_request(uuid, text, date, text, jsonb, uuid),
  public.cancel_purchase_request(uuid, uuid),
  public.reject_purchase_request(uuid, uuid, text),
  public.convert_purchase_request(uuid, uuid, uuid, text, jsonb, uuid)
  from public, anon;
grant execute on function
  public.purchase_request_item_options(uuid, text),
  public.create_purchase_request(uuid, text, date, text, jsonb, uuid),
  public.cancel_purchase_request(uuid, uuid),
  public.reject_purchase_request(uuid, uuid, text),
  public.convert_purchase_request(uuid, uuid, uuid, text, jsonb, uuid)
  to authenticated;

commit;
