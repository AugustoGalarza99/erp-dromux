-- Dromux ERP · 043 · Producción: cierre con ajustes de insumos y envases, estadística de producción e índices.
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización del propietario para el entorno destino,
-- después de un respaldo y en este orden: respaldo -> esta migración -> supabase/verificaciones/043_comprobaciones.sql
-- -> publicar el frontend. Deshacer: supabase/reparacion/0_deshacer_043.sql (solo quita lo creado acá).
--
-- Qué hace (todo ADITIVO; no cambia ninguna función existente ni ningún dato):
--  1) Índices de cobertura para las consultas de producción y stock que hoy no tienen índice propio (H-003).
--  2) production_output_summary: producción terminada por día/semana/mes y por unidad, en un rango libre.
--  3) production_output_by_product: lo mismo por producto, paginado en servidor y con búsqueda.
--  4) finish_production_job_adjusted: terminar la orden y, en la misma transacción, registrar los ajustes de
--     insumos (entrega adicional que descuenta stock / devolución que suma stock) y el recuento de envases.
--     Reutiliza issue_production_material, return_production_material y finish_production_job SIN modificarlas:
--     conserva sus permisos, validaciones, idempotencia por request_id y bloqueos.
--
-- No expone costos: ninguna de estas funciones lee ni devuelve columnas de costo (D-004).

begin;

-- ---------------------------------------------------------------------------------------------
-- 1) Índices. Las tablas de producción son chicas hoy; en una base grande conviene crearlos fuera de
--    horario pico (CREATE INDEX bloquea escrituras mientras se construye). Todos con IF NOT EXISTS.
-- ---------------------------------------------------------------------------------------------
-- Estadística: órdenes terminadas por fecha de finalización (índice parcial: solo las terminadas).
create index if not exists production_jobs_done_idx
  on public.production_jobs (company_id, completed_at desc)
  where status = 'completed';
-- "¿Hay órdenes abiertas de este producto?" (guardas de archivado/borrado y planificación).
create index if not exists production_jobs_product_idx
  on public.production_jobs (company_id, product_id, status);
-- Al terminar una orden se suman las devoluciones de cada salida (r.issue_id = e.id).
create index if not exists production_job_events_issue_idx
  on public.production_job_events (company_id, issue_id)
  where issue_id is not null;
-- Consumo histórico de un insumo.
create index if not exists production_job_events_component_idx
  on public.production_job_events (company_id, component_id, created_at desc);
-- Cada entrega de insumo busca la última fabricación del componente para valorizar.
create index if not exists production_runs_product_idx
  on public.production_runs (company_id, product_id, created_at desc);
create index if not exists production_run_lines_component_idx
  on public.production_run_lines (company_id, component_id);
-- "¿En qué fórmulas se usa este insumo?" y guardas antes de archivar un ítem.
create index if not exists production_formula_lines_component_idx
  on public.production_formula_lines (company_id, component_id);
-- Lotes por vencer.
create index if not exists stock_lots_expiry_idx
  on public.stock_lots (company_id, expires_on)
  where expires_on is not null;

-- ---------------------------------------------------------------------------------------------
-- 2) Producción por período.
-- ---------------------------------------------------------------------------------------------
create or replace function public.production_output_summary(
  p_company uuid,
  p_from date,
  p_to date,
  p_bucket text default 'month',
  p_product uuid default null,
  p_tz text default 'America/Argentina/Buenos_Aires'
) returns table (
  bucket_start date,
  unit_symbol text,
  orders bigint,
  planned_quantity numeric,
  expected_quantity numeric,
  actual_quantity numeric
)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or not private.has_permission(p_company, 'production', 'read') then
    raise exception 'Sin permiso para ver la producción' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 3660 then
    raise exception 'Elegí un rango de fechas válido (hasta 10 años)';
  end if;
  if p_bucket not in ('day', 'week', 'month') then
    raise exception 'Agrupá por día, semana o mes';
  end if;
  if p_bucket = 'day' and p_to - p_from > 366 then
    raise exception 'Para agrupar por día elegí un rango de hasta un año';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then
    raise exception 'Zona horaria inválida';
  end if;
  return query
    select date_trunc(p_bucket, j.completed_at at time zone p_tz)::date,
      u.symbol,
      count(*),
      sum(j.planned_quantity),
      sum(j.expected_output),
      sum(j.actual_quantity)
    from public.production_jobs j
    join public.items i on i.company_id = j.company_id and i.id = j.product_id
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where j.company_id = p_company
      and j.status = 'completed'
      and j.completed_at >= (p_from::timestamp at time zone p_tz)
      and j.completed_at < ((p_to + 1)::timestamp at time zone p_tz)
      and (p_product is null or j.product_id = p_product)
    group by 1, 2
    order by 1, 2;
end;
$$;

create or replace function public.production_output_by_product(
  p_company uuid,
  p_from date,
  p_to date,
  p_search text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_tz text default 'America/Argentina/Buenos_Aires'
) returns table (
  product_id uuid,
  product_code text,
  product_name text,
  unit_symbol text,
  orders bigint,
  planned_quantity numeric,
  expected_quantity numeric,
  actual_quantity numeric,
  total_count bigint
)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_search text := lower(btrim(coalesce(p_search, '')));
begin
  if auth.uid() is null or not private.has_permission(p_company, 'production', 'read') then
    raise exception 'Sin permiso para ver la producción' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_from > p_to or p_to - p_from > 3660 then
    raise exception 'Elegí un rango de fechas válido (hasta 10 años)';
  end if;
  if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset < 0 then
    raise exception 'Paginación inválida';
  end if;
  if length(v_search) > 80 then
    raise exception 'La búsqueda es demasiado larga';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_tz) then
    raise exception 'Zona horaria inválida';
  end if;
  return query
    select g.product_id, g.code, g.name, g.symbol, g.orders, g.planned, g.expected, g.actual,
      count(*) over ()
    from (
      select j.product_id, i.code, i.name, u.symbol,
        count(*) as orders,
        sum(j.planned_quantity) as planned,
        sum(j.expected_output) as expected,
        sum(j.actual_quantity) as actual
      from public.production_jobs j
      join public.items i on i.company_id = j.company_id and i.id = j.product_id
      join public.units u on u.company_id = i.company_id and u.id = i.unit_id
      where j.company_id = p_company
        and j.status = 'completed'
        and j.completed_at >= (p_from::timestamp at time zone p_tz)
        and j.completed_at < ((p_to + 1)::timestamp at time zone p_tz)
        and (v_search = ''
          or position(v_search in lower(i.name)) > 0
          or position(v_search in lower(i.code)) > 0)
      group by j.product_id, i.code, i.name, u.symbol
    ) g
    order by g.actual desc, g.name, g.product_id
    limit p_limit offset p_offset;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- 3) Terminar la orden con ajustes de insumos y recuento de envases (una sola transacción).
--    p_adjustments: [{"kind":"issue","component_id":..,"warehouse_id":..,"lot_code":..,"quantity":..,"note":..},
--                    {"kind":"return","component_id":..,"quantity":..,"note":..}]
--      issue  = se usó MÁS de lo entregado: descuenta stock del depósito/lote indicado.
--      return = se usó MENOS de lo entregado: suma stock en el depósito/lote de origen (se reparte entre las
--               salidas abiertas de ese insumo, de la más reciente a la más antigua).
--    p_packaging: {"<id de envasado de la orden>": cantidad_real_de_envases, ...}
-- ---------------------------------------------------------------------------------------------
create or replace function public.finish_production_job_adjusted(
  p_company uuid,
  p_job uuid,
  p_actual_quantity numeric,
  p_output_lot text,
  p_expires_on date,
  p_variance_note text,
  p_request_id uuid,
  p_adjustments jsonb default '[]'::jsonb,
  p_packaging jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_job public.production_jobs%rowtype;
  v_adj jsonb;
  v_index integer := 0;
  v_part integer;
  v_kind text;
  v_component uuid;
  v_warehouse uuid;
  v_lot text;
  v_quantity numeric;
  v_note text;
  v_left numeric;
  v_take numeric;
  v_event record;
  v_seen uuid[] := '{}';
  v_pack jsonb;
  v_packs jsonb := '[]'::jsonb;
  v_count numeric;
  v_unit text;
  v_total numeric := 0;
  v_complete boolean := true;
  v_options jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'production', 'insert')
    or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode = '42501';
  end if;
  if p_request_id is null
    or p_adjustments is null or jsonb_typeof(p_adjustments) <> 'array'
    or jsonb_array_length(p_adjustments) > 300
    or p_packaging is null or jsonb_typeof(p_packaging) <> 'object' then
    raise exception 'Revisá los ajustes y el recuento de envases';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('finish-job:' || p_company::text || ':' || p_job::text, 0));
  select * into v_job from public.production_jobs where company_id = p_company and id = p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;

  -- Reintento de una orden ya terminada: no se repiten ajustes; la función original valida que sean los mismos datos.
  if v_job.status = 'completed' then
    return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
      p_expires_on, p_variance_note, p_request_id);
  end if;
  if v_job.status <> 'in_progress' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar';
  end if;

  -- Devolver exige además producción:update (lo valida return_production_material): avisar antes de mover nada.
  if exists (select 1 from jsonb_array_elements(p_adjustments) a where a.value->>'kind' = 'return')
    and not private.has_permission(p_company, 'production', 'update') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode = '42501';
  end if;

  -- Ajustes de insumos.
  for v_adj in select value from jsonb_array_elements(p_adjustments) loop
    v_index := v_index + 1;
    if jsonb_typeof(v_adj) <> 'object' then raise exception 'Ajuste inválido en la línea %', v_index; end if;
    v_kind := v_adj->>'kind';
    -- Validar formato antes de convertir: evita errores crudos de conversión.
    if coalesce(v_adj->>'component_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or coalesce(v_adj->>'quantity', '') !~ '^[0-9]{1,12}(\.[0-9]{1,6})?$'
      or (nullif(v_adj->>'warehouse_id', '') is not null
        and v_adj->>'warehouse_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    v_component := (v_adj->>'component_id')::uuid;
    v_quantity := (v_adj->>'quantity')::numeric;
    v_note := left('Ajuste al terminar: ' || coalesce(nullif(btrim(v_adj->>'note'), ''), 'diferencia de consumo'), 300);
    if coalesce(v_kind, '') not in ('issue', 'return') or v_component is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Ajuste inválido en la línea %', v_index;
    end if;
    if v_component = any(v_seen) then
      raise exception 'Hay dos ajustes para el mismo insumo (línea %)', v_index;
    end if;
    v_seen := array_append(v_seen, v_component);

    if v_kind = 'issue' then
      v_warehouse := (v_adj->>'warehouse_id')::uuid;
      v_lot := nullif(btrim(v_adj->>'lot_code'), '');
      if v_warehouse is null then raise exception 'Indicá el depósito del insumo adicional (línea %)', v_index; end if;
      perform public.issue_production_material(p_company, p_job, v_component, v_warehouse, v_lot,
        v_quantity, v_note, md5(p_request_id::text || ':adj:' || v_index::text)::uuid);
    else
      v_left := v_quantity;
      v_part := 0;
      for v_event in
        select e.id,
          e.quantity - coalesce((select sum(r.quantity) from public.production_job_events r
            where r.company_id = e.company_id and r.issue_id = e.id and r.kind = 'return'), 0) as open_quantity
        from public.production_job_events e
        where e.company_id = p_company and e.job_id = p_job
          and e.component_id = v_component and e.kind = 'issue'
        order by e.created_at desc, e.id desc
      loop
        exit when v_left <= 0;
        if v_event.open_quantity > 0 then
          v_take := least(v_event.open_quantity, v_left);
          v_part := v_part + 1;
          perform public.return_production_material(p_company, p_job, v_event.id, v_take, v_note,
            md5(p_request_id::text || ':ret:' || v_index::text || ':' || v_part::text)::uuid);
          v_left := v_left - v_take;
        end if;
      end loop;
      if v_left > 0 then
        raise exception 'La devolución supera lo entregado de ese insumo (línea %)', v_index;
      end if;
    end if;
  end loop;

  -- Recuento de envases (informativo: no mueve stock). El resto sin envasar se calcula si todos los envases
  -- tienen la misma unidad que el producto.
  if exists (select 1 from jsonb_object_keys(p_packaging)) then
    if exists (
      select 1 from jsonb_each(p_packaging) e
      where not exists (select 1 from jsonb_array_elements(coalesce(v_job.work_options->'packaging', '[]')) x
          where x->>'id' = e.key)
        or (jsonb_typeof(e.value) not in ('number', 'null'))
        or (jsonb_typeof(e.value) = 'number'
          and ((e.value#>>'{}')::numeric < 0 or (e.value#>>'{}')::numeric >= 1000000000
            or (e.value#>>'{}')::numeric <> trunc((e.value#>>'{}')::numeric)))
    ) then
      raise exception 'El recuento de envases debe usar los envasados de la orden con cantidades enteras';
    end if;
    select u.symbol into v_unit
      from public.items i
      join public.units u on u.company_id = i.company_id and u.id = i.unit_id
      where i.company_id = p_company and i.id = v_job.product_id;
    for v_pack in select value from jsonb_array_elements(coalesce(v_job.work_options->'packaging', '[]')) loop
      v_count := case when p_packaging ? (v_pack->>'id')
        then nullif(p_packaging->>(v_pack->>'id'), '')::numeric
        else nullif(v_pack->>'actual_count', '')::numeric end;
      v_packs := v_packs || jsonb_build_array(v_pack || jsonb_build_object('actual_count', v_count));
      if v_count is null or (v_pack->>'unit') is distinct from v_unit then
        v_complete := false;
      else
        v_total := v_total + v_count * (v_pack->>'capacity')::numeric;
      end if;
    end loop;
    if v_complete and v_total > p_actual_quantity then
      raise exception 'Los envases contados suman más de lo fabricado: revisá los recuentos';
    end if;
    v_options := coalesce(v_job.work_options, '{}'::jsonb)
      || jsonb_build_object('packaging', v_packs,
        'unpackaged_quantity', case when v_complete and jsonb_array_length(v_packs) > 0
          then to_jsonb(round(p_actual_quantity - v_total, 6)) else 'null'::jsonb end);
    update public.production_jobs
      set work_options = v_options, details_updated_at = clock_timestamp()
      where company_id = p_company and id = p_job;
  end if;

  return public.finish_production_job(p_company, p_job, p_actual_quantity, p_output_lot,
    p_expires_on, p_variance_note, p_request_id);
end;
$$;

-- Permisos: solo usuarios autenticados; anon y public sin acceso. Las comprobaciones de empresa y permiso
-- están dentro de cada función.
revoke all on function
  public.production_output_summary(uuid, date, date, text, uuid, text),
  public.production_output_by_product(uuid, date, date, text, integer, integer, text),
  public.finish_production_job_adjusted(uuid, uuid, numeric, text, date, text, uuid, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function
  public.production_output_summary(uuid, date, date, text, uuid, text),
  public.production_output_by_product(uuid, date, date, text, integer, integer, text),
  public.finish_production_job_adjusted(uuid, uuid, numeric, text, date, text, uuid, jsonb, jsonb)
  to authenticated;

commit;
