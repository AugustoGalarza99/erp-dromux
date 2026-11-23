-- Línea base del esquema observado el 2026-11-20 (solo estructura, sin datos), generada desde catálogos en solo lectura.
-- Requiere un proyecto Supabase vacío (esquemas auth/storage/extensions). No incluye el event trigger rls_auto_enable.
-- Orden: tablas, funciones, restricciones, índices, RLS, políticas, triggers, permisos.
set check_function_bodies = off;
create schema if not exists private;
create table private.deleted_production_requests (company_id uuid not null,
  resource text not null,
  request_id uuid not null,
  actor_id uuid not null,
  deleted_at timestamp with time zone default clock_timestamp() not null);
create table private.production_job_numbers (company_id uuid not null,
  next_number bigint not null);
create table private.supplier_payment_numbers (company_id uuid not null,
  next_number bigint not null);
create table private.support_access_log (id bigint generated always as identity not null,
  user_id uuid not null,
  company_id uuid not null,
  reason text not null,
  started_at timestamp with time zone default clock_timestamp() not null,
  expires_at timestamp with time zone not null);
create table private.support_operators (user_id uuid not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table private.support_sessions (user_id uuid not null,
  company_id uuid not null,
  expires_at timestamp with time zone not null);
create table public.companies (id uuid default gen_random_uuid() not null,
  name text not null,
  slug text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  active boolean default true not null);
create table public.company_invitations (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  email text not null,
  role_id uuid not null,
  token_hash text not null,
  created_by uuid not null,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '7 days'::interval) not null,
  used_at timestamp with time zone,
  revoked_at timestamp with time zone);
create table public.company_modules (company_id uuid not null,
  module text not null,
  enabled boolean default false not null);
create table public.company_settings (company_id uuid not null,
  currency_code text default 'ARS'::text not null,
  timezone text default 'America/Argentina/Cordoba'::text not null,
  updated_at timestamp with time zone default now() not null);
create table public.company_users (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  user_id uuid not null,
  role_id uuid not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table public.customers (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  name text not null,
  tax_id text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  address text default ''::text not null,
  notes text default ''::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table public.delivery_note_counters (company_id uuid not null,
  next_number bigint default 1 not null);
create table public.delivery_note_lines (company_id uuid not null,
  note_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  item_code text not null,
  item_name text not null,
  unit_symbol text not null,
  warehouse_id uuid not null,
  warehouse_name text not null,
  lot_code text,
  quantity numeric(18,6) not null,
  stock_operation_id uuid not null,
  production_event_id uuid,
  sale_id uuid,
  sale_line_no smallint);
create table public.delivery_note_reversals (company_id uuid not null,
  note_id uuid not null,
  line_no smallint not null,
  stock_operation_id uuid not null,
  production_event_id uuid,
  sale_id uuid,
  sale_line_no smallint);
create table public.delivery_notes (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  number bigint not null,
  request_id uuid not null,
  request_payload jsonb not null,
  kind text not null,
  job_id uuid,
  sale_id uuid,
  recipient text not null,
  note text not null,
  status text default 'issued'::text not null,
  void_reason text,
  voided_at timestamp with time zone,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  archived boolean default false not null);
create table public.exchange_rate_types (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  name text not null,
  active boolean default true not null,
  archived boolean default false not null,
  archive_previous_active boolean);
create table public.exchange_rates (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  type_id uuid not null,
  ars_per_usd numeric(18,6) not null,
  effective_on date not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.item_categories (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  code text not null,
  name text not null,
  description text default ''::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table public.items (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  code text not null,
  name text not null,
  item_type text not null,
  category_id uuid,
  unit_id uuid not null,
  barcode text,
  description text default ''::text not null,
  minimum_stock numeric(18,6) default 0 not null,
  track_lots boolean default false not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  reference_unit_cost numeric(18,2),
  sale_unit_price numeric(18,2),
  infinite_stock boolean default false not null,
  reference_cost_usd numeric(14,2),
  reference_exchange_rate_type_id uuid,
  yield_enabled boolean default false not null,
  yield_factor numeric(12,6) default 1 not null,
  archived boolean default false not null,
  archive_previous_active boolean);
create table public.operational_alert_reads (company_id uuid not null,
  user_id uuid not null,
  alert_key text not null,
  fingerprint text not null,
  read_at timestamp with time zone default now() not null);
create table public.production_document_settings (company_id uuid not null,
  logo_data text default ''::text not null,
  document_code text default 'OP'::text not null,
  revision text default '01'::text not null,
  observation_labels jsonb default '[]'::jsonb not null,
  updated_at timestamp with time zone default clock_timestamp() not null);
create table public.production_formula_lines (company_id uuid not null,
  product_id uuid not null,
  component_id uuid not null,
  quantity numeric(18,6) not null);
create table public.production_formulas (company_id uuid not null,
  product_id uuid not null,
  batch_quantity numeric(18,6) not null,
  version integer default 1 not null,
  updated_at timestamp with time zone default now() not null,
  archived boolean default false not null);
create table public.production_job_events (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  job_id uuid not null,
  request_id uuid not null,
  kind text not null,
  issue_id uuid,
  component_id uuid not null,
  warehouse_id uuid not null,
  lot_code text,
  quantity numeric(18,6) not null,
  unit_cost numeric(18,2) not null,
  stock_operation_id uuid not null,
  note text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.production_job_reservations (company_id uuid not null,
  job_id uuid not null,
  component_id uuid not null,
  required_quantity numeric(18,6) not null,
  reserved_quantity numeric(18,6) default 0 not null,
  updated_at timestamp with time zone default now() not null);
create table public.production_jobs (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  product_id uuid not null,
  plan_id uuid,
  planned_quantity numeric(18,6) not null,
  actual_quantity numeric(18,6),
  warehouse_id uuid not null,
  due_on date,
  formula_version integer not null,
  formula_snapshot jsonb not null,
  status text default 'queued'::text not null,
  note text not null,
  cancel_reason text,
  variance_note text,
  output_lot text,
  output_expiry date,
  run_id uuid,
  completion_request_id uuid,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  number bigint not null,
  yield_factor numeric(12,6) default 1 not null,
  expected_output numeric(18,6) not null,
  document_snapshot jsonb default '{}'::jsonb not null,
  work_options jsonb default '{}'::jsonb not null,
  work_request_options jsonb default '{}'::jsonb not null,
  details_updated_at timestamp with time zone default clock_timestamp() not null,
  archived boolean default false not null);
create table public.production_one_step_requests (company_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  job_id uuid not null,
  run_id uuid not null,
  actor_id uuid not null);
create table public.production_packaging_types (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  name text not null,
  capacity numeric(18,6) not null,
  unit_id uuid not null,
  active boolean default true not null);
create table public.production_plans (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  request_id uuid not null,
  product_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18,6) not null,
  formula_version integer not null,
  estimated_cost numeric(18,2) not null,
  component_snapshot jsonb not null,
  due_on date,
  note text not null,
  status text default 'planned'::text not null,
  run_id uuid,
  completion_request_id uuid,
  actor_id uuid not null,
  created_at timestamp with time zone default now() not null,
  completed_at timestamp with time zone,
  cancelled_at timestamp with time zone,
  archived boolean default false not null);
create table public.production_reservation_locations (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  job_id uuid not null,
  component_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid,
  lot_code text,
  quantity numeric(18,6) not null);
create table public.production_run_lines (company_id uuid not null,
  run_id uuid not null,
  component_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18,6) not null,
  lot_code text,
  unit_cost numeric(18,2) not null,
  stock_operation_id uuid not null);
create table public.production_runs (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  product_id uuid not null,
  formula_version integer not null,
  quantity numeric(18,6) not null,
  warehouse_id uuid not null,
  output_operation_id uuid not null,
  estimated_cost numeric(18,2) not null,
  request_id uuid not null,
  request_payload jsonb not null,
  note text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  archived boolean default false not null);
create table public.profiles (id uuid not null,
  name text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null);
create table public.purchase_counters (company_id uuid not null,
  next_number bigint default 1 not null);
create table public.purchase_order_lines (company_id uuid not null,
  order_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  item_code text not null,
  unit_symbol text not null,
  quantity numeric(18,6) not null,
  unit_price numeric(18,2) not null,
  item_name text,
  received_quantity numeric(18,6) default 0 not null);
create table public.purchase_order_requests (company_id uuid not null,
  request_id uuid not null,
  order_id uuid not null,
  request_payload jsonb not null,
  actor_id uuid not null);
create table public.purchase_orders (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  number bigint not null,
  supplier_id uuid not null,
  supplier_name text not null,
  status text default 'open'::text not null,
  note text default ''::text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  cancelled_at timestamp with time zone);
create table public.purchase_receipt_lines (company_id uuid not null,
  receipt_id uuid not null,
  order_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  warehouse_code text not null,
  quantity numeric(18,6) not null,
  unit_price numeric(18,2) not null,
  lot_code text,
  expires_on date,
  stock_operation_id uuid not null);
create table public.purchase_receipts (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  order_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  note text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.role_permissions (company_id uuid not null,
  role_id uuid not null,
  resource text not null,
  action text not null);
create table public.roles (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  code text not null,
  name text not null,
  created_at timestamp with time zone default now() not null);
create table public.sale_adjustment_lines (company_id uuid not null,
  adjustment_id uuid not null,
  sale_id uuid not null,
  sale_line_no smallint not null,
  quantity numeric(18,6) not null,
  credit_amount numeric(18,2) not null,
  restocked boolean not null,
  stock_operation_id uuid);
create table public.sale_adjustments (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  sale_id uuid not null,
  request_id uuid not null,
  kind text not null,
  reason text not null,
  credit_total numeric(18,2) not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.sale_checkouts (company_id uuid not null,
  request_id uuid not null,
  sale_id uuid not null,
  payment_request_id uuid,
  payment_mode text not null,
  amount numeric(18,2),
  method text,
  account_id uuid,
  actor_id uuid not null);
create table public.sale_counters (company_id uuid not null,
  next_number bigint default 1 not null);
create table public.sale_lines (company_id uuid not null,
  sale_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  item_code text not null,
  item_name text not null,
  unit_symbol text not null,
  warehouse_id uuid not null,
  warehouse_code text not null,
  lot_code text,
  quantity numeric(18,6) not null,
  unit_price numeric(18,2) not null,
  line_total numeric(18,2) not null,
  estimated_unit_cost numeric(18,2),
  stock_operation_id uuid not null);
create table public.sale_payment_reversals (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  sale_id uuid not null,
  payment_id uuid not null,
  reason text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.sale_payments (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  sale_id uuid not null,
  request_id uuid not null,
  amount numeric(18,2) not null,
  method text not null,
  paid_on date not null,
  reference text default ''::text not null,
  note text default ''::text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.sale_refunds (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  sale_id uuid not null,
  request_id uuid not null,
  account_id uuid not null,
  treasury_entry_id uuid not null,
  amount numeric(18,2) not null,
  reason text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.sales (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  number bigint not null,
  request_id uuid not null,
  request_payload jsonb not null,
  customer_id uuid not null,
  customer_name text not null,
  customer_tax_id text not null,
  note text not null,
  total numeric(18,2) not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.stock_balances (company_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  quantity numeric(18,6) default 0 not null,
  version bigint default 0 not null,
  updated_at timestamp with time zone default now() not null);
create table public.stock_lot_balances (company_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid not null,
  quantity numeric(18,6) default 0 not null);
create table public.stock_lot_openings (company_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  lot_id uuid not null,
  quantity numeric(18,6) not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.stock_lots (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  item_id uuid not null,
  code text not null,
  expires_on date,
  created_at timestamp with time zone default now() not null);
create table public.stock_movements (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  operation_id uuid not null,
  line_no smallint not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  kind text not null,
  delta numeric(18,6) not null,
  balance_after numeric(18,6) not null,
  balance_version bigint not null,
  item_code text not null,
  warehouse_code text not null,
  unit_symbol text not null,
  note text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  lot_id uuid,
  lot_code text,
  lot_expires_on date);
create table public.stock_operations (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  request_id uuid not null,
  item_id uuid not null,
  warehouse_id uuid not null,
  to_warehouse_id uuid,
  kind text not null,
  quantity numeric(18,6) not null,
  note text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  lot_id uuid,
  lot_code text,
  lot_expires_on date);
create table public.supplier_items (company_id uuid not null,
  supplier_id uuid not null,
  item_id uuid not null,
  unit_price numeric(18,2) not null,
  supplier_sku text default ''::text not null,
  updated_at timestamp with time zone default now() not null,
  currency_code text default 'ARS'::text not null,
  exchange_rate_type_id uuid,
  adjustment_percent numeric(8,2) default 0 not null,
  preferred boolean default false not null);
create table public.supplier_payment_order_lines (company_id uuid not null,
  payment_order_id uuid not null,
  order_id uuid not null,
  amount numeric(18,2) not null,
  treasury_request_id uuid default gen_random_uuid() not null,
  treasury_entry_id uuid);
create table public.supplier_payment_orders (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  number bigint not null,
  supplier_id uuid not null,
  account_id uuid not null,
  request_id uuid not null,
  request_payload jsonb not null,
  amount numeric(18,2) not null,
  paid_on date not null,
  note text not null,
  reference text default ''::text not null,
  status text default 'draft'::text not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null,
  confirmed_at timestamp with time zone);
create table public.supplier_price_adjustments (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  request_id uuid not null,
  supplier_id uuid,
  item_id uuid,
  percent numeric(8,2) not null,
  changed_count integer not null,
  actor_id uuid not null,
  created_at timestamp with time zone default now() not null);
create table public.suppliers (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  name text not null,
  tax_id text default ''::text not null,
  email text default ''::text not null,
  phone text default ''::text not null,
  notes text default ''::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  lead_time_days integer default 7 not null,
  supplies_description text default ''::text not null);
create table public.treasury_accounts (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  name text not null,
  kind text not null,
  opening_balance numeric(18,2) default 0 not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table public.treasury_entries (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  account_id uuid not null,
  request_id uuid not null,
  kind text not null,
  amount numeric(18,2) not null,
  purchase_order_id uuid,
  note text not null,
  occurred_on date not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.treasury_sale_accounts (company_id uuid not null,
  payment_id uuid not null,
  account_id uuid not null,
  actor_id uuid not null,
  created_at timestamp with time zone default clock_timestamp() not null);
create table public.units (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  code text not null,
  name text not null,
  symbol text not null,
  dimension text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
create table public.warehouses (id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  code text not null,
  name text not null,
  location text default ''::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null);
CREATE OR REPLACE FUNCTION private.check_infinite_stock_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.infinite_stock and (tg_op='INSERT' or not old.infinite_stock) then
    if exists (select 1 from public.stock_balances b where b.company_id=new.company_id
      and b.item_id=new.id and b.quantity<>0) then
      raise exception 'Dejá el saldo físico en cero antes de activar stock infinito';
    end if;
    if exists (select 1 from public.production_job_reservations r
      join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
      where r.company_id=new.company_id and r.component_id=new.id
        and j.status in ('queued','in_progress')) then
      raise exception 'Terminá las órdenes pendientes antes de activar stock infinito';
    end if;
  end if;
  if tg_op='UPDATE' and old.infinite_stock and not new.infinite_stock then
    if exists (select 1 from public.production_job_reservations r
      join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
      where r.company_id=new.company_id and r.component_id=new.id
        and j.status in ('queued','in_progress')) then
      raise exception 'Terminá las órdenes pendientes antes de cambiar el modo de stock';
    end if;
  end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.check_item_catalogs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_check_unit boolean;
  v_check_category boolean;
begin
  if tg_op = 'INSERT' then
    v_check_unit := true;
    v_check_category := true;
  else
    v_check_unit := new.unit_id is distinct from old.unit_id;
    v_check_category := new.category_id is distinct from old.category_id;
  end if;

  if v_check_unit and not exists (
    select 1 from public.units u
    where u.id = new.unit_id and u.company_id = new.company_id and u.active
  ) then
    raise exception 'Seleccioná una unidad activa de esta empresa';
  end if;

  if v_check_category and new.category_id is not null and not exists (
    select 1 from public.item_categories c
    where c.id = new.category_id and c.company_id = new.company_id and c.active
  ) then
    raise exception 'Seleccioná una categoría activa de esta empresa';
  end if;

  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.check_reference_fx_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rate numeric;
begin
  if new.reference_cost_usd is not null then
    if not exists(select 1 from public.exchange_rate_types t where t.company_id=new.company_id
      and t.id=new.reference_exchange_rate_type_id and t.active) then
      raise exception 'Elegí un tipo de dólar activo';
    end if;
    v_rate:=private.current_fx_rate(new.company_id,new.reference_exchange_rate_type_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para ese tipo de dólar'; end if;
    new.reference_unit_cost:=round(new.reference_cost_usd*v_rate,2);
  end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.check_stock_catalog_deactivation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.active and not new.active then
    if tg_table_name = 'items' and exists (
      select 1 from public.stock_balances b
      where b.company_id = old.company_id
        and b.item_id = old.id and b.quantity > 0
    ) then
      raise exception 'Trasladá o consumí el stock antes de desactivar el ítem';
    end if;
    if tg_table_name = 'warehouses' and exists (
      select 1 from public.stock_balances b
      where b.company_id = old.company_id
        and b.warehouse_id = old.id and b.quantity > 0
    ) then
      raise exception 'Trasladá el stock antes de desactivar el depósito';
    end if;
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.check_supplier_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION private.cleanup_has_references(p_company uuid, p_resource text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_target record; v_fk record; v_join text; v_found boolean; v_skip text[]:='{}';
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if p_resource='items' then v_skip:=array['supplier_items']; end if;
  if p_resource='formulas' then v_skip:=array['production_formula_lines']; end if;
  if p_resource='jobs' then v_skip:=array['production_job_reservations']; end if;
  for v_fk in
    select c.conrelid,c.conkey,c.confkey,n.nspname,cl.relname
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class cl on cl.oid=c.conrelid
    join pg_catalog.pg_namespace n on n.oid=cl.relnamespace
    where c.contype='f' and c.confrelid=pg_catalog.to_regclass('public.'||v_target.table_name)
      and not (cl.relname=any(v_skip))
  loop
    select string_agg(format('c.%I=p.%I',ca.attname,pa.attname),' and ' order by keys.ordinality)
      into v_join from unnest(v_fk.conkey,v_fk.confkey) with ordinality keys(child_key,parent_key,ordinality)
      join pg_catalog.pg_attribute ca on ca.attrelid=v_fk.conrelid and ca.attnum=keys.child_key
      join pg_catalog.pg_attribute pa on pa.attrelid=pg_catalog.to_regclass('public.'||v_target.table_name)
        and pa.attnum=keys.parent_key;
    execute format('select exists(select 1 from %I.%I c join public.%I p on %s where p.company_id=$1 and p.%I=$2)',
      v_fk.nspname,v_fk.relname,v_target.table_name,v_join,v_target.id_field)
      into v_found using p_company,p_id;
    if v_found then return true; end if;
  end loop;
  if p_resource='items' and (exists(
    select 1 from public.production_jobs j cross join lateral jsonb_array_elements(j.formula_snapshot) x
      where j.company_id=p_company and x->>'component_id'=p_id::text)
    or exists(select 1 from public.production_plans p cross join lateral jsonb_array_elements(p.component_snapshot) x
      where p.company_id=p_company and x->>'component_id'=p_id::text)) then return true; end if;
  if p_resource='formulas' and (exists(select 1 from public.production_jobs where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_runs where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_plans where company_id=p_company and product_id=p_id)
    or exists(select 1 from public.production_formula_lines where company_id=p_company and component_id=p_id)) then return true; end if;
  return false;
end; $function$
;
CREATE OR REPLACE FUNCTION private.cleanup_target(p_resource text)
 RETURNS TABLE(table_name text, id_field text, permission text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select t.table_name,t.id_field,t.permission from (values
    ('items','items','id','items'),
    ('exchange_types','exchange_rate_types','id','purchases'),
    ('formulas','production_formulas','product_id','production'),
    ('jobs','production_jobs','id','production'),
    ('runs','production_runs','id','production'),
    ('plans','production_plans','id','production'),
    ('delivery_notes','delivery_notes','id','stock')
  ) t(resource,table_name,id_field,permission) where resource=p_resource
$function$
;
CREATE OR REPLACE FUNCTION private.current_fx_rate(p_company uuid, p_type uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select r.ars_per_usd from public.exchange_rates r
  where r.company_id=p_company and r.type_id=p_type and r.effective_on<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
  order by r.effective_on desc,r.created_at desc,r.id desc limit 1
$function$
;
CREATE OR REPLACE FUNCTION private.erp_production_alerts(p_company uuid)
 RETURNS TABLE(alert_key text, fingerprint text, severity text, title text, detail text, destination text, occurred_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'dashboard', 'read') then
    raise exception 'Sin acceso al centro operativo' using errcode = '42501';
  end if;

  if private.has_permission(p_company, 'production', 'read') then
    return query
    select 'job:' || j.id::text,
      j.status || ':' || coalesce(j.due_on::text, ''),
      case when j.due_on < v_today then 'critical' else 'warning' end,
      case when j.due_on < v_today then 'Fabricación fuera de plazo'
        else 'Fabricación próxima a vencer' end,
      i.name || ' · ' || j.planned_quantity::text || ' ' || u.symbol ||
        ' · Fecha prevista: ' || to_char(j.due_on, 'DD/MM/YYYY'),
      '/production/orders?job=' || j.id::text, j.due_on
    from public.production_jobs j
    join public.items i on i.company_id = j.company_id and i.id = j.product_id
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where j.company_id = p_company and j.status in ('queued', 'in_progress')
      and j.due_on <= v_today + 3;
  end if;

  if private.has_permission(p_company, 'stock', 'read')
    and private.has_permission(p_company, 'items', 'read') then
    return query
    select 'stock:' || i.id::text,
      i.minimum_stock::text || ':' || coalesce(b.total, 0)::text,
      case when coalesce(b.total, 0) <= 0 then 'critical' else 'warning' end,
      case when coalesce(b.total, 0) <= 0 then 'Ítem sin existencias'
        else 'Stock bajo el mínimo' end,
      i.name || ' · Disponible físico: ' || coalesce(b.total, 0)::text ||
        ' ' || u.symbol || ' · Mínimo: ' || i.minimum_stock::text || ' ' || u.symbol,
      '/inventory/stock', v_today
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    left join lateral (
      select sum(sb.quantity) as total from public.stock_balances sb
      where sb.company_id = i.company_id and sb.item_id = i.id
    ) b on true
    where i.company_id = p_company and i.active
      and i.item_type in ('raw_material', 'semi_finished', 'consumable', 'finished_product')
      and i.minimum_stock > 0 and coalesce(b.total, 0) < i.minimum_stock;
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.get_user_role(p_company uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((
    select r.code from public.company_users cu
    join public.companies c on c.id=cu.company_id
    join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active limit 1
  ),case when private.support_session_active(p_company) then 'support' end);
$function$
;
CREATE OR REPLACE FUNCTION private.guard_archived_formula_edit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin
  if old.archived then raise exception 'La fórmula está archivada. Recuperala antes de editarla'; end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.guard_archived_recipe()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$ begin
  if exists(select 1 from public.production_formulas where company_id=new.company_id and product_id=new.product_id and archived) then
    raise exception 'La fórmula está archivada. Recuperala antes de fabricar o planificar'; end if;
  if exists(select 1 from private.deleted_production_requests where company_id=new.company_id
    and request_id=new.request_id and resource=case tg_table_name when 'production_jobs' then 'jobs' when 'production_plans' then 'plans' else 'runs' end) then
    raise exception 'Esta solicitud corresponde a un registro eliminado. Generá una nueva orden'; end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.guard_purchase_supplier_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION private.guard_reversal_after_refund()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION private.guard_sale_payment_net()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION private.has_permission(p_company uuid, p_resource text, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.company_users cu
    join public.companies c on c.id=cu.company_id
    join public.role_permissions rp on rp.role_id=cu.role_id
      and rp.company_id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active and rp.resource=p_resource and rp.action=p_action
  ) or (
    p_action='read' and p_resource in (
      'dashboard','inventory','items','stock','warehouses','units','categories',
      'production','purchases','sales','finance','reports','settings','users','roles'
    ) and private.support_session_active(p_company)
  );
$function$
;
CREATE OR REPLACE FUNCTION private.is_company_member(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.company_users cu
    join public.companies c on c.id=cu.company_id
    where cu.company_id=p_company and cu.user_id=(select auth.uid())
      and cu.active and c.active
  ) or private.support_session_active(p_company);
$function$
;
CREATE OR REPLACE FUNCTION private.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype;
  v_previous public.production_job_events%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_component is null or p_warehouse is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá el insumo, cantidad, depósito y motivo'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.production_job_events
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.kind<>'issue'
      or v_previous.job_id<>p_job or v_previous.component_id<>p_component
      or v_previous.warehouse_id<>p_warehouse or v_previous.quantity<>p_quantity
      or v_previous.lot_code is distinct from v_lot
      or v_previous.note<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.status not in ('queued','in_progress') then
    raise exception 'La orden ya no admite insumos'; end if;
  if p_component=v_job.product_id then
    raise exception 'El producto fabricado no puede consumirse a sí mismo'; end if;
  perform 1 from public.items i where i.company_id=p_company and i.id=p_component
    and i.active and i.item_type in ('raw_material','semi_finished') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
  select round(r.estimated_cost/r.quantity,2) into v_cost
    from public.production_runs r
    where r.company_id=p_company and r.product_id=p_component
    order by r.created_at desc limit 1;
  v_cost:=coalesce(v_cost,private.production_unit_cost(p_company,p_component));
  v_operation:=public.post_stock_operation(p_company,p_component,p_warehouse,
    null,'issue',p_quantity,'Orden producción '||p_job::text,
    gen_random_uuid(),v_lot,null);
  insert into public.production_job_events(company_id,job_id,request_id,kind,
    component_id,warehouse_id,lot_code,quantity,unit_cost,stock_operation_id,
    note,actor_id)
  values(p_company,p_job,p_request_id,'issue',p_component,p_warehouse,
    v_lot,p_quantity,v_cost,v_operation,btrim(p_note),auth.uid())
  returning id into v_event;
  if v_job.status='queued' then
    update public.production_jobs set status='in_progress',started_at=clock_timestamp()
      where company_id=p_company and id=p_job;
  end if;
  return v_event;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_note text := btrim(p_note);
  v_code text := nullif(btrim(p_lot_code), '');
  v_operation uuid;
  v_existing public.stock_operations%rowtype;
  v_item_code text;
  v_unit_symbol text;
  v_track_lots boolean;
  v_warehouse_code text;
  v_target_code text;
  v_source_balance numeric(18, 6);
  v_target_balance numeric(18, 6);
  v_source_version bigint;
  v_target_version bigint;
  v_lot_id uuid;
  v_lot_code text;
  v_lot_expiry date;
  v_lot_balance numeric(18, 6);
begin
  if v_actor is null or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode = '42501';
  end if;
  if p_request_id is null or p_item is null or p_warehouse is null
     or p_kind is null or p_kind not in ('receipt', 'issue', 'transfer')
     or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
     or round(p_quantity, 6) <> p_quantity
     or v_note is null or length(v_note) not between 3 and 500
     or (p_kind = 'transfer' and (p_to_warehouse is null
       or p_to_warehouse = p_warehouse))
     or (p_kind <> 'transfer' and p_to_warehouse is not null)
     or length(coalesce(p_lot_code, '')) > 80
     or (p_kind <> 'receipt' and p_expires_on is not null) then
    raise exception 'Datos de movimiento inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'La empresa no está activa o no tenés permiso' using errcode = '42501';
  end if;

  -- Serializa todos los movimientos del mismo ítem y sus cambios de saldo.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  insert into public.stock_operations (
    company_id, request_id, item_id, warehouse_id, to_warehouse_id,
    kind, quantity, note, actor_id, lot_code, lot_expires_on
  ) values (
    p_company, p_request_id, p_item, p_warehouse, p_to_warehouse,
    p_kind, p_quantity, v_note, v_actor, v_code, p_expires_on
  ) on conflict (company_id, request_id) do nothing
  returning id into v_operation;

  if v_operation is null then
    select * into v_existing from public.stock_operations
    where company_id = p_company and request_id = p_request_id;
    if v_existing.item_id is distinct from p_item
       or v_existing.warehouse_id is distinct from p_warehouse
       or v_existing.to_warehouse_id is distinct from p_to_warehouse
       or v_existing.kind is distinct from p_kind
       or v_existing.quantity is distinct from p_quantity
       or v_existing.note is distinct from v_note
       or v_existing.actor_id is distinct from v_actor
       or v_existing.lot_code is distinct from v_code
       or v_existing.lot_expires_on is distinct from p_expires_on then
      raise exception 'La solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  select i.code, u.symbol, i.track_lots
  into v_item_code, v_unit_symbol, v_track_lots
  from public.items i
  join public.units u on u.id = i.unit_id and u.company_id = i.company_id
  where i.id = p_item and i.company_id = p_company and i.active
  for share of i;
  if not found then raise exception 'Ítem inactivo o inexistente'; end if;

  if v_track_lots then
    if v_code is null then raise exception 'Indicá el lote del ítem'; end if;
    if p_kind = 'receipt' then
      insert into public.stock_lots(company_id, item_id, code, expires_on)
      values (p_company, p_item, v_code, p_expires_on)
      on conflict do nothing;
    end if;
    select l.id, l.code, l.expires_on
    into v_lot_id, v_lot_code, v_lot_expiry
    from public.stock_lots l
    where l.company_id = p_company and l.item_id = p_item
      and lower(l.code) = lower(v_code);
    if v_lot_id is null then raise exception 'Lote inexistente para este ítem'; end if;
    if p_kind = 'receipt' and v_lot_expiry is distinct from p_expires_on then
      raise exception 'La fecha de vencimiento no coincide con la del lote existente';
    end if;
  elsif v_code is not null or p_expires_on is not null then
    raise exception 'El ítem no utiliza lotes';
  end if;

  select w.code into v_warehouse_code from public.warehouses w
  where w.id = p_warehouse and w.company_id = p_company and w.active
  for share of w;
  if not found then raise exception 'Depósito inactivo o inexistente'; end if;
  if p_kind = 'transfer' then
    select w.code into v_target_code from public.warehouses w
    where w.id = p_to_warehouse and w.company_id = p_company and w.active
    for share of w;
    if not found then raise exception 'Depósito destino inactivo o inexistente'; end if;
  end if;

  insert into public.stock_balances(company_id, item_id, warehouse_id)
  values (p_company, p_item, p_warehouse)
  on conflict (company_id, item_id, warehouse_id) do nothing;
  select b.quantity into v_source_balance from public.stock_balances b
  where b.company_id = p_company and b.item_id = p_item
    and b.warehouse_id = p_warehouse for update;
  if p_kind in ('issue', 'transfer') and v_source_balance < p_quantity then
    raise exception 'Stock insuficiente en el depósito de origen';
  end if;

  if v_track_lots then
    insert into public.stock_lot_balances(company_id, item_id, warehouse_id, lot_id)
    values (p_company, p_item, p_warehouse, v_lot_id)
    on conflict (company_id, item_id, warehouse_id, lot_id) do nothing;
    select b.quantity into v_lot_balance from public.stock_lot_balances b
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse and b.lot_id = v_lot_id for update;
    if p_kind in ('issue', 'transfer') and v_lot_balance < p_quantity then
      raise exception 'Stock insuficiente para el lote en el depósito de origen';
    end if;
    update public.stock_lot_balances b
    set quantity = b.quantity + case when p_kind = 'receipt'
      then p_quantity else -p_quantity end
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_warehouse and b.lot_id = v_lot_id;
  end if;

  update public.stock_balances b
  set quantity = b.quantity + case when p_kind = 'receipt'
      then p_quantity else -p_quantity end,
      version = b.version + 1, updated_at = clock_timestamp()
  where b.company_id = p_company and b.item_id = p_item
    and b.warehouse_id = p_warehouse
  returning b.quantity, b.version into v_source_balance, v_source_version;

  insert into public.stock_movements (
    company_id, operation_id, line_no, item_id, warehouse_id, kind,
    delta, balance_after, balance_version, item_code, warehouse_code,
    unit_symbol, note, actor_id, lot_id, lot_code, lot_expires_on
  ) values (
    p_company, v_operation, 1, p_item, p_warehouse,
    case p_kind when 'receipt' then 'receipt'
      when 'issue' then 'issue' else 'transfer_out' end,
    case when p_kind = 'receipt' then p_quantity else -p_quantity end,
    v_source_balance, v_source_version, v_item_code, v_warehouse_code,
    v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
  );

  if p_kind = 'transfer' then
    insert into public.stock_balances(company_id, item_id, warehouse_id)
    values (p_company, p_item, p_to_warehouse)
    on conflict (company_id, item_id, warehouse_id) do nothing;
    update public.stock_balances b
    set quantity = b.quantity + p_quantity, version = b.version + 1,
        updated_at = clock_timestamp()
    where b.company_id = p_company and b.item_id = p_item
      and b.warehouse_id = p_to_warehouse
    returning b.quantity, b.version into v_target_balance, v_target_version;

    if v_track_lots then
      insert into public.stock_lot_balances(company_id, item_id, warehouse_id, lot_id)
      values (p_company, p_item, p_to_warehouse, v_lot_id)
      on conflict (company_id, item_id, warehouse_id, lot_id) do nothing;
      update public.stock_lot_balances b
      set quantity = b.quantity + p_quantity
      where b.company_id = p_company and b.item_id = p_item
        and b.warehouse_id = p_to_warehouse and b.lot_id = v_lot_id;
    end if;

    insert into public.stock_movements (
      company_id, operation_id, line_no, item_id, warehouse_id, kind,
      delta, balance_after, balance_version, item_code, warehouse_code,
      unit_symbol, note, actor_id, lot_id, lot_code, lot_expires_on
    ) values (
      p_company, v_operation, 2, p_item, p_to_warehouse, 'transfer_in',
      p_quantity, v_target_balance, v_target_version, v_item_code, v_target_code,
      v_unit_symbol, v_note, v_actor, v_lot_id, v_lot_code, v_lot_expiry
    );
  end if;

  if v_lot_id is not null then
    update public.stock_operations o set lot_id = v_lot_id
    where o.id = v_operation;
  end if;

  return v_operation;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.prepare_item_import(p_company uuid, p_rows jsonb, p_existing uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row jsonb; v_index integer:=0; v_unit uuid; v_category uuid;
  v_code text; v_name text; v_type text; v_barcode text;
  v_cost numeric; v_price numeric; v_min numeric; v_lots boolean;
  v_infinite boolean; v_active boolean; v_description text;
  v_supplier uuid; v_fx_type uuid; v_usd numeric; v_rate numeric; v_matches integer;
  v_supplier_name text; v_fx_name text;
  v_result jsonb := '[]'::jsonb; v_codes text[] := '{}'; v_barcodes text[] := '{}';
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',case when p_existing is null then 'insert' else 'update' end) then
    raise exception 'No tenés permiso para importar ítems' using errcode='42501';
  end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array'
    or jsonb_array_length(p_rows) not between 1 and 200 then
    raise exception 'Importá entre 1 y 200 ítems por archivo';
  end if;
  if p_existing is not null and jsonb_array_length(p_rows)<>1 then
    raise exception 'La edición debe contener un solo ítem';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    v_index:=v_index+1;
    if jsonb_typeof(v_row)<>'object' then
      raise exception 'Fila %: formato inválido',v_index+1;
    end if;
    v_code:=btrim(coalesce(v_row->>'codigo',''));
    v_name:=btrim(coalesce(v_row->>'nombre',''));
    v_type:=btrim(coalesce(v_row->>'tipo',''));
    v_barcode:=nullif(btrim(coalesce(v_row->>'codigo_barras','')),'');
    v_description:=btrim(coalesce(v_row->>'descripcion',''));
    if v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'
      or length(v_name) not between 2 and 160
      or v_type not in ('raw_material','semi_finished','finished_product','consumable')
      or length(v_description)>1500
      or (v_barcode is not null and length(v_barcode) not between 4 and 80) then
      raise exception 'Fila %: revisá código, nombre, tipo, descripción y código de barras',v_index+1;
    end if;
    if coalesce(v_row->>'stock_minimo','') !~ '^\d+(\.\d{1,6})?$'
      or coalesce(v_row->>'costo_referencia_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'costo_referencia_ars','') is not null
      or coalesce(v_row->>'precio_venta_ars','') !~ '^\d+(\.\d{1,2})?$'
      and nullif(v_row->>'precio_venta_ars','') is not null then
      raise exception 'Fila %: números inválidos (usá punto decimal)',v_index+1;
    end if;
    v_min:=(v_row->>'stock_minimo')::numeric;
    v_cost:=nullif(v_row->>'costo_referencia_ars','')::numeric;
    v_price:=nullif(v_row->>'precio_venta_ars','')::numeric;
    if v_min>=1000000000000 or coalesce(v_cost,0)>=1000000000000
      or coalesce(v_price,0)>=1000000000000 then
      raise exception 'Fila %: importe o cantidad fuera de rango',v_index+1;
    end if;
    if coalesce(v_row->>'seguir_lotes','') not in ('true','false')
      or coalesce(v_row->>'stock_infinito','') not in ('true','false')
      or coalesce(v_row->>'activo','') not in ('true','false') then
      raise exception 'Fila %: usá SI o NO en las columnas de opciones',v_index+1;
    end if;
    v_lots:=(v_row->>'seguir_lotes')::boolean;
    v_infinite:=(v_row->>'stock_infinito')::boolean;
    v_active:=(v_row->>'activo')::boolean;
    if v_infinite and (v_lots or v_min<>0) then
      raise exception 'Fila %: stock infinito requiere sin lotes y stock mínimo cero',v_index+1;
    end if;
    if v_price is not null and (v_type<>'finished_product'
      or private.get_user_role(p_company)<>'admin'
      or not private.has_permission(p_company,'sales','update')) then
      raise exception 'Fila %: solo un administrador puede cargar precios de productos terminados',v_index+1;
    end if;
    v_supplier:=null; v_fx_type:=null; v_usd:=null; v_rate:=null;
    v_supplier_name:=nullif(btrim(coalesce(v_row->>'proveedor','')),'');
    v_fx_name:=nullif(btrim(coalesce(v_row->>'tipo_dolar','')),'');
    if nullif(btrim(coalesce(v_row->>'costo_usd','')),'') is not null then
      if btrim(v_row->>'costo_usd') !~ '^\d+(\.\d{1,2})?$' then
        raise exception 'Fila %: costo en dólares inválido, hasta dos decimales',v_index+1;
      end if;
      v_usd:=btrim(v_row->>'costo_usd')::numeric;
      if v_usd>=1000000000000 then raise exception 'Fila %: costo en dólares fuera de rango',v_index+1; end if;
      if v_fx_name is null then raise exception 'Fila %: indicá el tipo de dólar para el costo en dólares',v_index+1; end if;
    elsif v_fx_name is not null then
      raise exception 'Fila %: el tipo de dólar requiere un costo en dólares',v_index+1;
    end if;
    if v_fx_name is not null then
      select count(*), min(t.id::text)::uuid into v_matches,v_fx_type
        from public.exchange_rate_types t where t.company_id=p_company and t.active
          and lower(btrim(t.name))=lower(v_fx_name);
      if v_matches<>1 then raise exception 'Fila %: el tipo de dólar no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      v_rate:=private.current_fx_rate(p_company,v_fx_type);
      if v_rate is null then raise exception 'Fila %: cargá una cotización vigente para %',v_index+1,v_fx_name; end if;
      v_cost:=round(v_usd*v_rate,2);
      if v_cost>=1000000000000 then raise exception 'Fila %: costo convertido fuera de rango',v_index+1; end if;
    end if;
    if v_supplier_name is not null then
      if not private.has_permission(p_company,'purchases','update') then
        raise exception 'Necesitás permiso para editar Compras para asociar proveedores' using errcode='42501';
      end if;
      select count(*),min(s.id::text)::uuid into v_matches,v_supplier from public.suppliers s
        where s.company_id=p_company and s.active and lower(btrim(s.name))=lower(v_supplier_name);
      if v_matches<>1 then raise exception 'Fila %: el proveedor no existe, está inactivo o su nombre es ambiguo',v_index+1; end if;
      if v_cost is null then raise exception 'Fila %: indicá un costo en pesos o dólares para asociar el proveedor',v_index+1; end if;
      if not v_active then raise exception 'Fila %: el ítem debe estar activo para asociar un proveedor',v_index+1; end if;
      if p_existing is not null and exists(select 1 from public.supplier_items q
        where q.company_id=p_company and q.item_id=p_existing and q.supplier_id=v_supplier) then
        raise exception 'Este ítem ya está asociado al proveedor. Editá su precio en Compras';
      end if;
    end if;
    if v_type='raw_material' and v_cost is null then
      raise exception 'Fila %: la materia prima necesita costo de referencia',v_index+1;
    end if;
    select u.id into v_unit from public.units u
      where u.company_id=p_company and u.active
        and lower(u.code)=lower(btrim(coalesce(v_row->>'unidad_codigo','')));
    if v_unit is null then
      raise exception 'Fila %: la unidad no existe o está inactiva',v_index+1;
    end if;
    v_category:=null;
    if nullif(btrim(coalesce(v_row->>'categoria_codigo','')),'') is not null then
      select c.id into v_category from public.item_categories c
        where c.company_id=p_company and c.active
          and lower(c.code)=lower(btrim(v_row->>'categoria_codigo'));
      if v_category is null then
        raise exception 'Fila %: la categoría no existe o está inactiva',v_index+1;
      end if;
    end if;
    if exists (select 1 from public.items i where i.company_id=p_company
      and i.id is distinct from p_existing and lower(i.code)=lower(v_code)) then
      raise exception 'Fila %: el código % ya existe o está repetido',v_index+1,v_code;
    end if;
    if v_barcode is not null and exists (select 1 from public.items i
      where i.company_id=p_company and i.id is distinct from p_existing and i.barcode=v_barcode) then
      raise exception 'Fila %: el código de barras % ya existe o está repetido',v_index+1,v_barcode;
    end if;
    if lower(v_code)=any(v_codes) or (v_barcode is not null and v_barcode=any(v_barcodes)) then
      raise exception 'Fila %: código o código de barras repetido en el archivo',v_index+1;
    end if;
    v_codes:=array_append(v_codes,lower(v_code));
    if v_barcode is not null then v_barcodes:=array_append(v_barcodes,v_barcode); end if;
    v_result:=v_result || jsonb_build_array(v_row || jsonb_build_object(
      'unit_id',v_unit,'category_id',v_category,'supplier_id',v_supplier,
      'exchange_type_id',v_fx_type,'cost_ars',v_cost,'cost_usd',v_usd,'exchange_rate',v_rate));
  end loop;
  return v_result;
end; $function$
;
CREATE OR REPLACE FUNCTION private.prepare_production_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_factor numeric; v_options jsonb;
begin
  insert into private.production_job_numbers(company_id,next_number) values(new.company_id,2)
    on conflict(company_id) do update set next_number=private.production_job_numbers.next_number+1
    returning next_number-1 into new.number;
  select case when yield_enabled then yield_factor else 1 end into v_factor
    from public.items where company_id=new.company_id and id=new.product_id;
  new.yield_factor:=coalesce(v_factor,1);
  new.expected_output:=round(new.planned_quantity*new.yield_factor,6);
  if new.expected_output<=0 or new.expected_output>=1000000000000 then raise exception 'Salida esperada fuera de rango'; end if;
  select jsonb_build_object('code',document_code,'revision',revision,'labels',observation_labels)
    into new.document_snapshot from public.production_document_settings where company_id=new.company_id;
  new.document_snapshot:=coalesce(new.document_snapshot,'{}');
  v_options:=nullif(pg_catalog.current_setting('dromux.work_options',true),'')::jsonb;
  new.work_request_options:=coalesce(v_options,'{}');
  new.work_options:=private.snapshot_work_options(new.company_id,coalesce(v_options,'{}'));
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.prevent_infinite_physical_movement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_infinite boolean;
begin
  select i.infinite_stock into v_infinite from public.items i
    where i.company_id=new.company_id and i.id=new.item_id for share;
  if coalesce(v_infinite,false) then
    raise exception 'El ítem tiene stock infinito; no registra movimientos físicos';
  end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.prevent_late_lot_tracking()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.track_lots and not old.track_lots and exists (
    select 1 from public.stock_balances b
    where b.company_id = old.company_id and b.item_id = old.id
      and b.quantity <> coalesce((
        select sum(lb.quantity) from public.stock_lot_balances lb
        where lb.company_id = b.company_id and lb.item_id = b.item_id
          and lb.warehouse_id = b.warehouse_id
      ), 0)
  ) then
    raise exception 'El ítem tiene stock sin lotes: activá la trazabilidad desde la ficha';
  end if;

  if old.track_lots and not new.track_lots and exists (
    select 1 from public.stock_lots l
    where l.company_id = old.company_id and l.item_id = old.id
  ) then
    raise exception 'No se puede desactivar lotes en un ítem que ya tiene lotes';
  end if;

  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.prevent_preferred_quote_deletion()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if old.preferred then
    raise exception 'Elegí otro proveedor principal antes de quitar esta cotización';
  end if;
  return old;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.prevent_stock_unit_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.unit_id is distinct from old.unit_id and exists (
    select 1 from public.stock_movements m
    where m.company_id = old.company_id and m.item_id = old.id
  ) then
    raise exception 'La unidad no puede cambiarse si el ítem tiene movimientos';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.prevent_supplier_price_unit_mismatch()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION private.production_unit_cost(p_company uuid, p_item uuid, p_path uuid[] DEFAULT '{}'::uuid[])
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cost numeric;
  v_batch numeric;
  v_line record;
  v_total numeric := 0;
begin
  if p_item = any(p_path) or array_length(p_path,1) >= 15 then
    raise exception 'Se detectó un ciclo o demasiados niveles en la fórmula';
  end if;
  select f.batch_quantity * case when i.yield_enabled then i.yield_factor else 1 end into v_batch
  from public.production_formulas f join public.items i on i.company_id=f.company_id and i.id=f.product_id
  where f.company_id=p_company and f.product_id=p_item;
  if v_batch is null then
    select i.reference_unit_cost into v_cost from public.items i
    where i.company_id=p_company and i.id=p_item;
    if v_cost is null then raise exception 'Falta el costo de referencia de un componente sin fórmula'; end if;
    return v_cost;
  end if;
  for v_line in select component_id,quantity from public.production_formula_lines
    where company_id=p_company and product_id=p_item loop
    v_total := v_total + v_line.quantity * private.production_unit_cost(
      p_company,v_line.component_id,array_append(p_path,p_item));
  end loop;
  return round(v_total/v_batch,2);
end;
$function$
;
CREATE OR REPLACE FUNCTION private.protect_archived_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$ begin
  if new.archived and new.active then raise exception 'Recuperá el registro desde Archivados antes de activarlo'; end if;
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.protect_preferred_material_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if current_user='authenticated' and
    new.reference_unit_cost is distinct from old.reference_unit_cost and
    exists(select 1 from public.supplier_items si where si.company_id=old.company_id
      and si.item_id=old.id and si.preferred) then
    raise exception 'El costo se actualiza desde el proveedor principal. Modificá su cotización en Compras';
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.rebalance_production_on_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.rebalance_production_reservations(new.company_id);
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.rebalance_production_reservations(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record; v_slot record;
  v_needed numeric; v_remaining numeric; v_reserved numeric;
  v_taken numeric; v_assign numeric;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  delete from public.production_reservation_locations where company_id=p_company;
  for v_row in
    select r.company_id,r.job_id,r.component_id,r.required_quantity,j.status
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    where r.company_id=p_company
    order by r.component_id,j.due_on asc nulls last,j.created_at,j.id
  loop
    v_reserved:=0;
    if v_row.status in ('queued','in_progress') and not exists (
      select 1 from public.items i where i.company_id=p_company
        and i.id=v_row.component_id and i.infinite_stock) then
      select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
        into v_needed from public.production_job_events e
        where e.company_id=p_company and e.job_id=v_row.job_id
          and e.component_id=v_row.component_id;
      v_remaining:=greatest(0,v_row.required_quantity-v_needed);
      for v_slot in
        select slots.warehouse_id,slots.lot_id,slots.lot_code,slots.quantity
        from (
          select b.warehouse_id,null::uuid lot_id,null::text lot_code,
            null::date expires_on,b.quantity,w.name warehouse_name
          from public.stock_balances b
          join public.items i on i.company_id=b.company_id and i.id=b.item_id
          join public.warehouses w on w.company_id=b.company_id
            and w.id=b.warehouse_id and w.active
          where b.company_id=p_company and b.item_id=v_row.component_id
            and not i.track_lots and b.quantity>0
          union all
          select lb.warehouse_id,lb.lot_id,l.code,l.expires_on,
            lb.quantity,w.name
          from public.stock_lot_balances lb
          join public.items i on i.company_id=lb.company_id and i.id=lb.item_id
          join public.stock_lots l on l.company_id=lb.company_id
            and l.item_id=lb.item_id and l.id=lb.lot_id
          join public.warehouses w on w.company_id=lb.company_id
            and w.id=lb.warehouse_id and w.active
          where lb.company_id=p_company and lb.item_id=v_row.component_id
            and i.track_lots and lb.quantity>0
            and (l.expires_on is null or l.expires_on>=v_today)
        ) slots
        order by slots.expires_on asc nulls last,slots.warehouse_name,
          slots.warehouse_id,slots.lot_code nulls last
      loop
        exit when v_remaining<=0;
        select coalesce(sum(a.quantity),0) into v_taken
          from public.production_reservation_locations a
          where a.company_id=p_company and a.component_id=v_row.component_id
            and a.warehouse_id=v_slot.warehouse_id
            and a.lot_id is not distinct from v_slot.lot_id;
        v_assign:=least(v_remaining,greatest(0,v_slot.quantity-v_taken));
        if v_assign>0 then
          insert into public.production_reservation_locations(
            company_id,job_id,component_id,warehouse_id,lot_id,lot_code,quantity)
          values(p_company,v_row.job_id,v_row.component_id,v_slot.warehouse_id,
            v_slot.lot_id,v_slot.lot_code,v_assign);
          v_reserved:=v_reserved+v_assign;
          v_remaining:=v_remaining-v_assign;
        end if;
      end loop;
    end if;
    update public.production_job_reservations
      set reserved_quantity=v_reserved,updated_at=clock_timestamp()
      where company_id=p_company and job_id=v_row.job_id
        and component_id=v_row.component_id
        and reserved_quantity is distinct from v_reserved;
  end loop;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.refresh_fx_costs()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item record;
begin
  for v_item in select si.item_id from public.supplier_items si
    where si.company_id=new.company_id and si.exchange_rate_type_id=new.type_id and si.preferred loop
    perform private.sync_preferred_material_cost(new.company_id,v_item.item_id);
  end loop;
  update public.items i
    set reference_unit_cost=round(i.reference_cost_usd*private.current_fx_rate(i.company_id,new.type_id),2)
    where i.company_id=new.company_id and i.reference_exchange_rate_type_id=new.type_id
      and i.reference_cost_usd is not null and not exists(select 1 from public.supplier_items q
        where q.company_id=i.company_id and q.item_id=i.id and q.preferred);
  return new;
end; $function$
;
CREATE OR REPLACE FUNCTION private.refresh_quote_cost()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='DELETE' then
    perform private.sync_preferred_material_cost(old.company_id,old.item_id);
    return old;
  end if;
  perform private.sync_preferred_material_cost(new.company_id,new.item_id);
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.reject_stock_history_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$function$
;
CREATE OR REPLACE FUNCTION private.reject_stock_operation_mutation()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'UPDATE'
     and old.lot_id is null and new.lot_id is not null
     and (to_jsonb(new) - 'lot_id') = (to_jsonb(old) - 'lot_id') then
    return new;
  end if;
  raise exception 'El historial de stock es inmutable; registrá una operación compensatoria';
end;
$function$
;
CREATE OR REPLACE FUNCTION private.release_closed_production_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('completed','cancelled') and old.status <> new.status then
    perform private.rebalance_production_reservations(new.company_id);
  end if;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.reserve_new_production_job()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  insert into public.production_job_reservations
    (company_id,job_id,component_id,required_quantity)
  select new.company_id,new.id,(x->>'component_id')::uuid,
    sum((x->>'quantity')::numeric)
  from jsonb_array_elements(new.formula_snapshot) x
  group by (x->>'component_id')::uuid;
  perform private.rebalance_production_reservations(new.company_id);
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.snapshot_purchase_item_name()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_name text;
begin
  select i.name into v_name from public.items i
  where i.company_id = new.company_id and i.id = new.item_id;
  if v_name is null then raise exception 'Ítem inexistente'; end if;
  new.item_name := v_name;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.snapshot_work_options(p_company uuid, p_options jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pack jsonb; v_count numeric; v_type record; v_result jsonb:='[]'; v_obs jsonb; v_labels jsonb;
begin
  if p_options is null or jsonb_typeof(p_options)<>'object'
    or jsonb_typeof(coalesce(p_options->'packaging','[]'))<>'array'
    or jsonb_array_length(coalesce(p_options->'packaging','[]'))>40
    or jsonb_typeof(coalesce(p_options->'observations','{}'))<>'object'
    or length(coalesce(p_options->>'observations',''))>10000 then raise exception 'Datos de trabajo inválidos'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(p_options->'packaging','[]')) loop
    v_count:=(v_pack->>'count')::numeric;
    if v_count is null or v_count<1 or v_count>=1000000000 or v_count<>trunc(v_count) then
      raise exception 'Indicá una cantidad entera de envases'; end if;
    select t.*,u.symbol into v_type from public.production_packaging_types t
      join public.units u on u.company_id=t.company_id and u.id=t.unit_id
      where t.company_id=p_company and t.id=(v_pack->>'id')::uuid and t.active;
    if not found then raise exception 'Elegí un envasado activo de esta empresa'; end if;
    if exists(select 1 from jsonb_array_elements(v_result) x where x->>'id'=v_type.id::text) then
      raise exception 'No repitas el tipo de envasado'; end if;
    v_result:=v_result||jsonb_build_array(jsonb_build_object('id',v_type.id,'name',v_type.name,
      'capacity',v_type.capacity,'unit',v_type.symbol,'count',v_count));
  end loop;
  v_obs:=coalesce(p_options->'observations','{}');
  select observation_labels into v_labels from public.production_document_settings where company_id=p_company;
  if exists(select 1 from jsonb_each(v_obs) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_labels,'[]') ? e.key)) then
    raise exception 'Las observaciones deben corresponder a los campos configurados'; end if;
  return jsonb_build_object('packaging',v_result,'observations',v_obs);
end; $function$
;
CREATE OR REPLACE FUNCTION private.support_session_active(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (
    select 1 from private.support_sessions ss
    join private.support_operators so on so.user_id=ss.user_id and so.active
    join public.companies c on c.id=ss.company_id and c.active
    where ss.user_id=(select auth.uid()) and ss.company_id=p_company
      and ss.expires_at>now()
  );
$function$
;
CREATE OR REPLACE FUNCTION private.sync_preferred_material_cost(p_company uuid, p_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_quote public.supplier_items%rowtype; v_rate numeric; v_cost numeric;
begin
  select * into v_quote from public.supplier_items
    where company_id=p_company and item_id=p_item and preferred;
  if not found then return; end if;
  if v_quote.currency_code='USD' then
    v_rate:=private.current_fx_rate(p_company,v_quote.exchange_rate_type_id);
    if v_rate is null then raise exception 'Cargá una cotización vigente para el tipo de dólar seleccionado'; end if;
  else v_rate:=1; end if;
  v_cost:=round(v_quote.unit_price*v_rate*(1+v_quote.adjustment_percent/100),2);
  -- El proveedor principal pasa a ser la única fuente de costo.
  update public.items set reference_unit_cost=v_cost,reference_cost_usd=null,
    reference_exchange_rate_type_id=null
    where company_id=p_company and id=p_item and
      (reference_unit_cost is distinct from v_cost or reference_cost_usd is not null);
end; $function$
;
CREATE OR REPLACE FUNCTION private.touch_item_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.accept_company_invitation(p_token text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_invitation public.company_invitations%rowtype;
  v_user auth.users%rowtype;
begin
  if auth.uid() is null or p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invitación inválida';
  end if;
  select * into v_user from auth.users where id = auth.uid();
  if v_user.email_confirmed_at is null then
    raise exception 'Confirmá tu correo electrónico antes de aceptar';
  end if;
  select * into v_invitation from public.company_invitations
  where token_hash = encode(digest(p_token, 'sha256'), 'hex') for update;
  if not found or v_invitation.revoked_at is not null
     or v_invitation.used_at is not null
     or v_invitation.expires_at <= now()
     or lower(v_user.email) <> v_invitation.email
     or not exists (
       select 1 from public.companies c
       where c.id = v_invitation.company_id and c.active
     ) then
    raise exception 'Invitación vencida o empresa no disponible';
  end if;
  insert into public.company_users(company_id, user_id, role_id)
  values (v_invitation.company_id, v_user.id, v_invitation.role_id);
  insert into public.profiles(id, name)
  values (v_user.id, split_part(v_user.email, '@', 1))
  on conflict (id) do nothing;
  update public.company_invitations set used_at = now()
  where id = v_invitation.id;
  return v_invitation.company_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.activate_item_lots(p_company uuid, p_item uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := auth.uid();
  v_item public.items%rowtype;
  v_balance record;
  v_lot_id uuid;
begin
  if v_actor is null
     or not private.has_permission(p_company, 'items', 'update')
     or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para activar lotes' using errcode = '42501';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then
    raise exception 'La empresa no está activa' using errcode = '42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_company::text || ':' || p_item::text, 0)
  );

  select * into v_item from public.items i
  where i.company_id = p_company and i.id = p_item and i.active for update;
  if not found then raise exception 'Ítem inexistente o inactivo'; end if;
  if v_item.track_lots then return; end if;

  if exists (
    select 1 from public.stock_lots l
    where l.company_id = p_company and l.item_id = p_item
  ) then
    raise exception 'El ítem ya tiene lotes registrados';
  end if;

  for v_balance in
    select b.warehouse_id, b.quantity, w.code as warehouse_code
    from public.stock_balances b
    join public.warehouses w
      on w.company_id = b.company_id and w.id = b.warehouse_id
    where b.company_id = p_company and b.item_id = p_item
      and b.quantity > 0
    order by b.warehouse_id
  loop
    insert into public.stock_lots(company_id, item_id, code)
    values (
      p_company, p_item,
      'Inicial ' || left(v_balance.warehouse_code, 24)
        || ' ' || v_balance.warehouse_id::text
    ) returning id into v_lot_id;

    insert into public.stock_lot_balances(
      company_id, item_id, warehouse_id, lot_id, quantity
    ) values (p_company, p_item, v_balance.warehouse_id, v_lot_id,
      v_balance.quantity);

    insert into public.stock_lot_openings(
      company_id, item_id, warehouse_id, lot_id, quantity, actor_id
    ) values (p_company, p_item, v_balance.warehouse_id, v_lot_id,
      v_balance.quantity, v_actor);
  end loop;

  update public.items i set track_lots = true
  where i.company_id = p_company and i.id = p_item;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.add_exchange_rate_type(p_company uuid, p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para configurar tipos de cambio' using errcode='42501';
  end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 60 then
    raise exception 'Indicá un nombre de 2 a 60 caracteres'; end if;
  insert into public.exchange_rate_types(company_id,name) values(p_company,btrim(p_name))
  returning id into v_id;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.archived_records(p_company uuid, p_resource text, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_target record; v_label text; v_date text; v_count bigint; v_rows jsonb; v_filter text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'read') then
    raise exception 'Sin acceso a este archivo' using errcode='42501'; end if;
  if p_page is null or p_page<0 or p_page>100000 or length(coalesce(p_search,''))>100 then raise exception 'Búsqueda o página inválida'; end if;
  v_label:=case p_resource
    when 'items' then 't.code||'' · ''||t.name'
    when 'exchange_types' then 't.name'
    when 'formulas' then '(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)'
    when 'jobs' then '''OF ''||t.number::text||'' · ''||(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)'
    when 'delivery_notes' then '''Remito ''||t.number::text||'' · ''||t.recipient'
    else '(select i.name from public.items i where i.company_id=t.company_id and i.id=t.product_id)' end;
  v_date:=case when p_resource='formulas' then 't.updated_at' when p_resource='exchange_types' then '(select max(e.created_at) from public.exchange_rates e where e.company_id=t.company_id and e.type_id=t.id)' else 't.created_at' end;
  v_filter:='t.company_id=$1 and t.archived and ('||v_label||') ilike ''%''||$2||''%''';
  execute format('select count(*) from public.%I t where %s',v_target.table_name,v_filter) into v_count using p_company,coalesce(p_search,'');
  execute format('select coalesce(jsonb_agg(x),''[]''::jsonb) from (select t.%I id,%s label,%s created_at from public.%I t where %s order by %s desc,t.%I limit 25 offset $3) x',
    v_target.id_field,v_label,v_date,v_target.table_name,v_filter,v_date,v_target.id_field)
    into v_rows using p_company,coalesce(p_search,''),p_page*25;
  return jsonb_build_object('rows',v_rows,'count',v_count);
end; $function$
;
CREATE OR REPLACE FUNCTION public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','update') then
    raise exception 'Sin permiso para asignar cobros' using errcode='42501'; end if;
  perform 1 from public.sale_payments where company_id=p_company and id=p_payment;
  if not found then raise exception 'Cobro inexistente'; end if;
  perform 1 from public.treasury_accounts where company_id=p_company and id=p_account and active;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  insert into public.treasury_sale_accounts(company_id,payment_id,account_id,actor_id)
  values(p_company,p_payment,p_account,auth.uid());
end;
$function$
;
CREATE OR REPLACE FUNCTION public.begin_support_session(p_company uuid, p_reason text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_expires timestamptz := now()+interval '30 minutes';
begin
  if auth.uid() is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300
    or not exists (select 1 from private.support_operators so
      where so.user_id=auth.uid() and so.active)
    or not exists (select 1 from public.companies c
      where c.id=p_company and c.active) then
    raise exception 'Acceso de soporte no autorizado' using errcode='42501';
  end if;
  insert into private.support_sessions(user_id,company_id,expires_at)
  values(auth.uid(),p_company,v_expires)
  on conflict(user_id) do update set company_id=excluded.company_id,
    expires_at=excluded.expires_at;
  insert into private.support_access_log(user_id,company_id,reason,expires_at)
  values(auth.uid(),p_company,btrim(p_reason),v_expires);
  return v_expires;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_production_job(p_company uuid, p_job uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype; v_open numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reason,''))) not between 5 and 300 then
    raise exception 'Indicá un motivo de al menos cinco caracteres'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found or v_job.status not in ('queued','in_progress') then
    raise exception 'La orden no se puede cancelar'; end if;
  select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
    into v_open from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job;
  if v_open<>0 then
    raise exception 'Devolvé todos los insumos pendientes antes de cancelar la orden'; end if;
  update public.production_jobs set status='cancelled',cancelled_at=clock_timestamp(),
    cancel_reason=btrim(p_reason) where company_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.production_plans set status='cancelled',cancelled_at=clock_timestamp()
      where company_id=p_company and id=v_job.plan_id and status='planned';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_production_plan(p_company uuid, p_plan uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_plan public.production_plans%rowtype;
begin
  if not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para cancelar planes' using errcode='42501'; end if;
  select * into v_plan from public.production_plans
    where company_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if exists(select 1 from public.production_jobs j
    where j.company_id=p_company and j.plan_id=p_plan) then
    raise exception 'Este plan tiene una orden. Gestioná su estado desde Fabricación'; end if;
  if v_plan.status='completed' then
    raise exception 'Una fabricación registrada no se puede cancelar'; end if;
  if v_plan.status='planned' then
    update public.production_plans set status='cancelled',cancelled_at=clock_timestamp()
      where company_id=p_company and id=p_plan;
  end if;
  return p_plan;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_purchase_order(p_company uuid, p_order uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'purchases', 'update') then
    raise exception 'Sin permiso para cancelar órdenes' using errcode = '42501';
  end if;
  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  update public.purchase_orders o
  set status = 'cancelled', cancelled_at = clock_timestamp()
  where o.company_id = p_company and o.id = p_order
    and o.status in ('open', 'partial');
  if not found then raise exception 'Orden inexistente o cerrada'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.cancel_supplier_payment_order(p_company uuid, p_payment uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','update') then
    raise exception 'Sin permiso para anular' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  update public.supplier_payment_orders set status='cancelled'
    where company_id=p_company and id=p_payment and status='draft';
  if not found then raise exception 'Solo se pueden anular borradores sin pagos'; end if;
end; $function$
;
CREATE OR REPLACE FUNCTION public.cleanup_preview(p_company uuid, p_resource text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_target record; v_row jsonb; v_action text:='delete'; v_message text;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Necesitás permiso de eliminar en este módulo' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro no existe en esta empresa'; end if;
  if (v_row->>'archived')::boolean then raise exception 'El registro ya está archivado'; end if;
  if p_resource='items' then
    if exists(select 1 from public.stock_balances where company_id=p_company and item_id=p_id and quantity<>0) then
      v_action:='blocked'; v_message:='El ítem todavía tiene stock. Regularizá sus existencias antes de retirarlo.';
    elsif exists(select 1 from public.production_formula_lines l join public.production_formulas f
      on f.company_id=l.company_id and f.product_id=l.product_id where l.company_id=p_company
        and (l.component_id=p_id or l.product_id=p_id) and not f.archived) then
      v_action:='blocked'; v_message:='El ítem forma parte de una fórmula activa. Modificá o archivá esa fórmula primero.';
    elsif exists(select 1 from public.production_jobs j where j.company_id=p_company and j.status in ('queued','in_progress')
      and (j.product_id=p_id or exists(select 1 from jsonb_array_elements(j.formula_snapshot) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.production_plans p where p.company_id=p_company and p.status='planned'
        and (p.product_id=p_id or exists(select 1 from jsonb_array_elements(p.component_snapshot) x where x->>'component_id'=p_id::text)))
      or exists(select 1 from public.purchase_order_lines l join public.purchase_orders o on o.company_id=l.company_id and o.id=l.order_id
        where l.company_id=p_company and l.item_id=p_id and o.status in ('open','partial') and l.received_quantity<l.quantity) then
      v_action:='blocked'; v_message:='El ítem tiene fabricación, planificación o compras pendientes. Resolvé esas operaciones primero.';
    end if;
  elsif p_resource='exchange_types' then
    if exists(select 1 from public.items where company_id=p_company and active and reference_exchange_rate_type_id=p_id)
      or exists(select 1 from public.supplier_items q join public.items i on i.company_id=q.company_id and i.id=q.item_id
        join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id
        where q.company_id=p_company and q.exchange_rate_type_id=p_id and i.active and s.active) then
      v_action:='blocked'; v_message:='Este dólar se usa en costos actuales. Cambiá primero el tipo de dólar de esos ítems o proveedores.';
    end if;
  elsif p_resource='formulas' then
    if exists(select 1 from public.production_jobs where company_id=p_company and product_id=p_id and status in ('queued','in_progress'))
      or exists(select 1 from public.production_plans where company_id=p_company and product_id=p_id and status='planned') then
      v_action:='blocked'; v_message:='Hay órdenes o planes pendientes de este producto. Terminá o cancelá el trabajo primero.';
    end if;
  elsif p_resource='jobs' then
    if v_row->>'status'='in_progress' or (v_row->>'status'='queued' and exists(
      select 1 from public.production_job_events where company_id=p_company and job_id=p_id)) then
      v_action:='blocked'; v_message:='La orden está en proceso o tiene entregas. Completala o devolvé los materiales y cancelala antes de retirarla.';
    end if;
  elsif p_resource='runs' then v_action:='archive';
  elsif p_resource='plans' and v_row->>'status'='planned' and exists(
    select 1 from public.production_jobs where company_id=p_company and plan_id=p_id) then
    v_action:='blocked'; v_message:='El plan tiene una orden vinculada. Gestioná primero esa orden.';
  elsif p_resource='delivery_notes' then v_action:='archive';
  end if;
  if v_action='delete' and private.cleanup_has_references(p_company,p_resource,p_id) then v_action:='archive'; end if;
  if v_action='delete' then v_message:='Se eliminará definitivamente este registro sin uso. La acción no se puede deshacer.'; end if;
  if v_action='archive' then v_message:=case when p_resource='delivery_notes'
    then 'El remito saldrá del listado, conservando la entrega y su historial. Archivar NO devuelve mercadería al stock. Para devolverla usá Anular entrega.'
    else 'El registro tiene información relacionada. Saldrá del listado y conservará sus movimientos, costos y vínculos. Podés recuperarlo en Archivados.' end; end if;
  return jsonb_build_object('action',v_action,'message',v_message);
end; $function$
;
CREATE OR REPLACE FUNCTION public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_target record; v_preview jsonb; v_row jsonb; v_cost numeric;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Sin permiso para retirar el registro' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2 for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'El registro ya no existe'; end if;
  v_preview:=public.cleanup_preview(p_company,p_resource,p_id);
  if v_preview->>'action'='blocked' then raise exception '%',v_preview->>'message'; end if;
  if p_action is null or p_action<>v_preview->>'action' then raise exception 'Cambió el uso del registro. Reabrí la confirmación para revisar la acción'; end if;
  if p_action='archive' then
    if p_resource in ('items','exchange_types') then
      execute format('update public.%I set archive_previous_active=active,active=false,archived=true where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
        using p_company,p_id;
    else
      execute format('update public.%I set archived=true where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
    end if;
    return 'archive';
  end if;
  if p_resource='items' then
    update public.supplier_items set preferred=false where company_id=p_company and item_id=p_id and preferred;
    delete from public.supplier_items where company_id=p_company and item_id=p_id;
  elsif p_resource='formulas' then
    v_cost:=private.production_unit_cost(p_company,p_id);
    update public.items set reference_unit_cost=v_cost where company_id=p_company and id=p_id
      and reference_cost_usd is null and not exists(select 1 from public.supplier_items where company_id=p_company and item_id=p_id and preferred);
    delete from public.production_formula_lines where company_id=p_company and product_id=p_id;
  elsif p_resource='jobs' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
    delete from public.production_reservation_locations where company_id=p_company and job_id=p_id;
    delete from public.production_job_reservations where company_id=p_company and job_id=p_id;
  end if;
  if p_resource in ('jobs','plans') then
    insert into private.deleted_production_requests(company_id,resource,request_id,actor_id)
      values(p_company,p_resource,(v_row->>'request_id')::uuid,auth.uid()) on conflict do nothing;
  end if;
  execute format('delete from public.%I where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  if p_resource='jobs' then perform private.rebalance_production_reservations(p_company); end if;
  return 'delete';
exception when foreign_key_violation then
  raise exception 'El registro tiene nuevos vínculos. Reabrí la confirmación para revisar la acción';
end; $function$
;
CREATE OR REPLACE FUNCTION public.company_invitation_list(p_company uuid)
 RETURNS TABLE(id uuid, email text, role_name text, created_at timestamp with time zone, expires_at timestamp with time zone, used_at timestamp with time zone, revoked_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'users', 'read') then
    raise exception 'Sin permiso para ver invitaciones' using errcode = '42501';
  end if;

  return query
    select i.id, i.email, r.name, i.created_at, i.expires_at,
           i.used_at, i.revoked_at
    from public.company_invitations i
    join public.roles r on r.id = i.role_id and r.company_id = i.company_id
    where i.company_id = p_company
    order by i.created_at desc
    limit 100;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.company_members(p_company uuid)
 RETURNS TABLE(user_id uuid, email text, display_name text, role_id uuid, role_name text, active boolean, joined_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company, 'users', 'read') then
    raise exception 'Sin permiso para consultar usuarios' using errcode = '42501';
  end if;

  return query
    select cu.user_id, u.email::text, nullif(p.name, u.id::text),
      cu.role_id, r.name, cu.active, cu.created_at
    from public.company_users cu
    join auth.users u on u.id = cu.user_id
    join public.roles r on r.id = cu.role_id and r.company_id = cu.company_id
    left join public.profiles p on p.id = cu.user_id
    where cu.company_id = p_company
    order by cu.created_at desc
    limit 500;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_previous public.production_one_step_requests%rowtype;
  v_payload jsonb; v_job uuid; v_run uuid; v_input jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_finish_request_id is null
    or jsonb_typeof(p_inputs) is distinct from 'array'
    or jsonb_array_length(p_inputs) not between 1 and 40 then
    raise exception 'Revisá los insumos de la fabricación'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('job-create:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('product',p_product,'planned',p_planned_quantity,
    'actual',p_actual_quantity,'warehouse',p_warehouse,
    'lot',nullif(btrim(p_output_lot),''),'expires',p_expires_on,
    'note',btrim(p_note),'variance',nullif(btrim(p_variance_note),''),
    'inputs',p_inputs,'plan',p_plan,'finish',p_finish_request_id);
  select * into v_previous from public.production_one_step_requests
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.request_payload<>v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.run_id;
  end if;
  v_job:=public.create_production_job(p_company,p_product,p_planned_quantity,
    p_warehouse,null,p_note,p_request_id,p_plan);
  for v_input in select value from jsonb_array_elements(p_inputs) x(value) loop
    perform public.issue_production_material(p_company,v_job,
      (v_input->>'component_id')::uuid,(v_input->>'warehouse_id')::uuid,
      v_input->>'lot_code',(v_input->>'quantity')::numeric,
      'Fabricación completada',gen_random_uuid());
  end loop;
  v_run:=public.finish_production_job(p_company,v_job,p_actual_quantity,
    p_output_lot,p_expires_on,p_variance_note,p_finish_request_id);
  insert into public.production_one_step_requests(company_id,request_id,
    request_payload,job_id,run_id,actor_id)
  values(p_company,p_request_id,v_payload,v_job,v_run,auth.uid());
  return v_run;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.complete_production_plan(p_company uuid, p_plan uuid, p_request_id uuid, p_inputs jsonb, p_output_lot text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_plan public.production_plans%rowtype;
  v_run uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501';
  end if;
  if p_request_id is null then raise exception 'Solicitud inválida'; end if;
  select * into v_plan from public.production_plans
  where company_id=p_company and id=p_plan for update;
  if not found then raise exception 'Plan inexistente'; end if;
  if v_plan.status='completed' then
    if v_plan.completion_request_id <> p_request_id then
      raise exception 'Esta planificación ya fue completada';
    end if;
    return v_plan.run_id;
  end if;
  if v_plan.status<>'planned' then raise exception 'Esta planificación fue cancelada'; end if;
  perform 1 from public.production_formulas f
    where f.company_id=p_company and f.product_id=v_plan.product_id
      and f.version=v_plan.formula_version for share;
  if not found then
    raise exception 'La fórmula cambió. Creá un plan nuevo para revisar los insumos';
  end if;
  v_run := public.post_production_run(p_company,v_plan.product_id,p_request_id,
    v_plan.quantity,v_plan.warehouse_id,p_output_lot,p_expires_on,
    v_plan.note,p_inputs);
  update public.production_plans set status='completed',run_id=v_run,
    completion_request_id=p_request_id,completed_at=clock_timestamp()
  where company_id=p_company and id=p_plan;
  return v_run;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_supplier_payment_order(p_company uuid, p_payment uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.create_company(p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_company uuid; v_role uuid; v_user uuid := auth.uid(); v_name text := nullif(btrim(p_name),'');
begin
 if v_user is null then raise exception 'Iniciá sesión' using errcode='42501'; end if;
 if v_name is null or length(v_name) not between 2 and 100 then raise exception 'El nombre debe tener entre 2 y 100 caracteres'; end if;
 insert into public.companies(name,slug) values(v_name,'empresa-'||replace(gen_random_uuid()::text,'-','')) returning id into v_company;
 insert into public.roles(company_id,code,name) values(v_company,'admin','Administrador') returning id into v_role;
 insert into public.company_users(company_id,user_id,role_id) values(v_company,v_user,v_role);
 insert into public.company_settings(company_id) values(v_company);
 insert into public.company_modules(company_id,module,enabled) values
 (v_company,'inventory',true),(v_company,'production',true),(v_company,'purchases',true),
 (v_company,'sales',true),(v_company,'finance',true),(v_company,'reports',true);
 insert into public.role_permissions(company_id,role_id,resource,action)
 select v_company,v_role,resource,action from
 (values ('dashboard'),('inventory'),('production'),('purchases'),('sales'),('finance'),('reports'),('settings'),('users'),('roles'),('units'),('categories'),('warehouses'),('items'),('stock')) as r(resource)
 cross join (values ('read'),('insert'),('update'),('delete'),('manage')) as a(action);
 insert into public.profiles(id,name) values(v_user,coalesce(nullif(v_user::text,''),'Usuario')) on conflict (id) do nothing;
 return v_company;
end $function$
;
CREATE OR REPLACE FUNCTION public.create_company_invitation(p_company uuid, p_email text, p_role uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_email text := lower(btrim(p_email)); v_token text; v_code text;
begin
  if not private.has_permission(p_company, 'users', 'insert') then
    raise exception 'Sin permiso para invitar usuarios' using errcode = '42501';
  end if;
  if v_email is null or length(v_email) not between 3 and 320
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    raise exception 'Correo electrónico inválido';
  end if;
  select code into v_code from public.roles
  where id = p_role and company_id = p_company;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' and private.get_user_role(p_company) <> 'admin' then
    raise exception 'Sólo un administrador puede invitar administradores';
  end if;
  if exists (
    select 1 from public.company_users cu join auth.users u on u.id = cu.user_id
    where cu.company_id = p_company and lower(u.email) = v_email
  ) then raise exception 'Este correo ya pertenece a la empresa'; end if;

  v_token := encode(gen_random_bytes(32), 'hex');
  insert into public.company_invitations(
    company_id, email, role_id, token_hash, created_by
  ) values (
    p_company, v_email, p_role, encode(digest(v_token, 'sha256'), 'hex'), auth.uid()
  );
  return v_token;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_role uuid; v_name text := btrim(p_name); v_entry jsonb;
begin
  if not private.has_permission(p_company, 'roles', 'insert') then
    raise exception 'Sin permiso para crear roles' using errcode = '42501';
  end if;
  if v_name is null or length(v_name) not between 2 and 60
     or p_code is null or p_code !~ '^[a-z][a-z0-9_]{1,39}$' then
    raise exception 'Nombre o código inválido';
  end if;
  if jsonb_typeof(p_permissions) is distinct from 'array'
     or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Lista de permisos inválida';
  end if;

  insert into public.roles(company_id, code, name)
  values (p_company, p_code, v_name) returning id into v_role;

  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, v_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses', 'items', 'stock')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;

  -- Rechazamos entradas desconocidas en vez de descartarlas silenciosamente.
  if (select count(*) from public.role_permissions where role_id = v_role)
     <> (select count(distinct (entry->>'resource', entry->>'action'))
         from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
  return v_role;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_formula public.production_formulas%rowtype;
  v_plan public.production_plans%rowtype; v_previous public.production_jobs%rowtype;
  v_payload jsonb; v_snapshot jsonb; v_job uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para crear órdenes de fabricación' using errcode='42501'; end if;
  if p_product is null or p_warehouse is null or p_request_id is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 400 then
    raise exception 'Revisá producto, cantidad, depósito y nota'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('job-create:'||p_company::text||':'||p_request_id::text,0));
  v_payload:=jsonb_build_object('product',p_product,'quantity',p_quantity,
    'warehouse',p_warehouse,'date',p_due_on,'note',btrim(p_note),'plan',p_plan);
  select * into v_previous from public.production_jobs
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.request_payload<>v_payload then
      raise exception 'La solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items i where i.company_id=p_company and i.id=p_product
    and i.active and i.item_type in ('semi_finished','finished_product') for share;
  if not found then raise exception 'Producto inactivo o no fabricable'; end if;
  perform 1 from public.warehouses w where w.company_id=p_company
    and w.id=p_warehouse and w.active for share;
  if not found then raise exception 'Depósito de destino inactivo'; end if;
  if p_plan is not null then
    select * into v_plan from public.production_plans
      where company_id=p_company and id=p_plan for update;
    if not found or v_plan.status<>'planned' or v_plan.product_id<>p_product
      or v_plan.warehouse_id<>p_warehouse or v_plan.quantity<>p_quantity
      or v_plan.formula_version<>v_formula.version then
      raise exception 'La planificación cambió. Revisá su fórmula y cantidades'; end if;
    if exists(select 1 from public.production_jobs
      where company_id=p_company and plan_id=p_plan) then
      raise exception 'La planificación ya tiene una orden de fabricación'; end if;
    v_snapshot:=v_plan.component_snapshot;
  else
    select jsonb_agg(jsonb_build_object('component_id',l.component_id,
      'quantity',l.quantity*p_quantity/v_formula.batch_quantity,
      'unit_cost',private.production_unit_cost(p_company,l.component_id))
      order by l.component_id) into v_snapshot
    from public.production_formula_lines l
    where l.company_id=p_company and l.product_id=p_product;
  end if;
  if v_snapshot is null or jsonb_array_length(v_snapshot)=0
    or exists(select 1 from jsonb_array_elements(v_snapshot) entry
      where (entry->>'quantity')::numeric<=0
        or (entry->>'quantity')::numeric<>round((entry->>'quantity')::numeric,6)) then
    raise exception 'La fórmula necesita componentes con hasta seis decimales'; end if;
  insert into public.production_jobs(company_id,request_id,request_payload,
    product_id,plan_id,planned_quantity,warehouse_id,due_on,
    formula_version,formula_snapshot,note,actor_id)
  values(p_company,p_request_id,v_payload,p_product,p_plan,p_quantity,p_warehouse,
    p_due_on,v_formula.version,v_snapshot,btrim(p_note),auth.uid())
  returning id into v_job;
  return v_job;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_formula public.production_formulas%rowtype;
  v_previous public.production_plans%rowtype;
  v_snapshot jsonb;
  v_cost numeric;
  v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para planificar producción' using errcode='42501';
  end if;
  if p_request_id is null or p_product is null or p_warehouse is null
    or p_quantity is null or p_quantity <= 0 or p_quantity >= 1000000000000
    or p_quantity <> round(p_quantity,6)
    or p_note is null or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Revisá producto, cantidad, depósito y nota';
  end if;
  select * into v_previous from public.production_plans
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id <> auth.uid() or v_previous.product_id <> p_product
      or v_previous.quantity <> p_quantity or v_previous.warehouse_id <> p_warehouse
      or v_previous.due_on is distinct from p_due_on or v_previous.note <> btrim(p_note) then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_previous.id;
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items where company_id=p_company and id=p_product
    and active and item_type in ('semi_finished','finished_product') for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  perform 1 from public.warehouses where company_id=p_company
    and id=p_warehouse and active for share;
  if not found then raise exception 'El depósito está inactivo'; end if;
  select jsonb_agg(jsonb_build_object('component_id',l.component_id,
    'quantity',l.quantity*p_quantity/v_formula.batch_quantity,
    'unit_cost',private.production_unit_cost(p_company,l.component_id))
    order by l.component_id)
  into v_snapshot from public.production_formula_lines l
  where l.company_id=p_company and l.product_id=p_product;
  if v_snapshot is null then raise exception 'La fórmula no tiene componentes'; end if;
  if exists (select 1 from jsonb_array_elements(v_snapshot) component
    where (component->>'quantity')::numeric <= 0
      or (component->>'quantity')::numeric >= 1000000000000
      or (component->>'quantity')::numeric <> round((component->>'quantity')::numeric,6)) then
    raise exception 'Esta cantidad genera consumos con más de seis decimales';
  end if;
  v_cost := round(private.production_unit_cost(p_company,p_product)*p_quantity,2);
  insert into public.production_plans(company_id,request_id,product_id,warehouse_id,
    quantity,formula_version,estimated_cost,component_snapshot,due_on,note,actor_id)
  values(p_company,p_request_id,p_product,p_warehouse,p_quantity,
    v_formula.version,v_cost,v_snapshot,p_due_on,btrim(p_note),auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.production_jobs%rowtype; v_snapshot jsonb; v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert') then
    raise exception 'Sin permiso para crear órdenes' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('work-order:'||p_company::text||':'||p_request::text,0));
  select * into v_old from public.production_jobs where company_id=p_company and request_id=p_request;
  if found then
    if v_old.work_request_options is distinct from p_options then raise exception 'Solicitud usada con otro envasado u observaciones'; end if;
  else
    v_snapshot:=private.snapshot_work_options(p_company,p_options);
  end if;
  perform pg_catalog.set_config('dromux.work_options',p_options::text,true);
  if p_finish is null then
    v_id:=public.create_production_job(p_company,p_product,p_quantity,p_warehouse,p_due,p_note,p_request,p_plan);
  else
    v_id:=public.complete_production_now(p_company,p_product,p_quantity,(p_finish->>'actual')::numeric,
      p_warehouse,nullif(p_finish->>'lot',''),nullif(p_finish->>'expiry','')::date,p_note,
      nullif(p_finish->>'variance',''),p_finish->'inputs',p_request,(p_finish->>'request')::uuid,p_plan);
    -- La función de fabricación inmediata devuelve la orden según la versión 020.
    select id into v_id from public.production_jobs where company_id=p_company and request_id=p_request;
  end if;
  perform pg_catalog.set_config('dromux.work_options','',true);
  return v_id;
end; $function$
;
CREATE OR REPLACE FUNCTION public.create_purchase_order(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_number bigint;
  v_order uuid;
  v_line jsonb;
  v_item uuid;
  v_quantity numeric;
  v_price numeric;
  v_code text;
  v_unit text;
  v_supplier_name text;
  v_index smallint := 0;
begin
  if not private.has_permission(p_company, 'purchases', 'insert') then
    raise exception 'Sin permiso para crear órdenes' using errcode = '42501';
  end if;
  if p_supplier is null or length(coalesce(p_note, '')) > 500
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Datos de orden inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'Empresa inactiva'; end if;
  select s.name into v_supplier_name from public.suppliers s
  where s.id = p_supplier and s.company_id = p_company and s.active for share;
  if not found then raise exception 'Elegí un proveedor activo'; end if;

  insert into public.purchase_counters(company_id) values (p_company)
  on conflict (company_id) do nothing;
  update public.purchase_counters c
  set next_number = c.next_number + 1
  where c.company_id = p_company
  returning c.next_number - 1 into v_number;

  insert into public.purchase_orders(
    company_id, number, supplier_id, supplier_name, note, actor_id
  ) values (
    p_company, v_number, p_supplier, v_supplier_name,
    btrim(coalesce(p_note, '')), auth.uid()
  )
  returning id into v_order;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_line) is distinct from 'object'
       or coalesce(v_line->>'item_id', '') !~
         '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or coalesce(v_line->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_line->>'unit_price', '') !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Línea de compra inválida';
    end if;
    v_item := (v_line->>'item_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    if v_quantity <= 0 or v_quantity >= 1000000000000
       or v_price >= 10000000000000000 then
      raise exception 'Cantidad o precio fuera de rango';
    end if;

    select i.code, u.symbol into v_code, v_unit
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where i.company_id = p_company and i.id = v_item and i.active
    for share of i;
    if not found then raise exception 'La orden contiene un ítem inactivo'; end if;

    v_index := v_index + 1;
    insert into public.purchase_order_lines(
      company_id, order_id, line_no, item_id, item_code,
      unit_symbol, quantity, unit_price
    ) values (p_company, v_order, v_index, v_item, v_code,
      v_unit, v_quantity, v_price);
  end loop;

  return v_order;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert') then
    raise exception 'Sin permiso para crear cuentas' using errcode='42501'; end if;
  if p_name is null or length(btrim(p_name)) not between 2 and 100
    or p_kind not in ('cash','bank','other') or p_opening is null
    or p_opening<>round(p_opening,2) then raise exception 'Revisá los datos de la cuenta'; end if;
  insert into public.treasury_accounts(company_id,name,kind,opening_balance)
  values(p_company,btrim(p_name),p_kind,p_opening) returning id into v_id;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_admin_product_costs(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, code text, name text, item_type text, unit_symbol text, cost numeric, price numeric, margin numeric, margin_percent numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company)<>'admin'
    or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'items','read') then
    raise exception 'Solo un administrador puede consultar costos y márgenes'
      using errcode='42501'; end if;
  return query select * from public.erp_product_costs(p_company,p_search);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(sale_id uuid, sale_number bigint, customer_name text, sold_at timestamp with time zone, product_summary text, net_revenue numeric, known_cost numeric, gross_profit numeric, missing_lines bigint, cancelled boolean, total_rows bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'admin'
    or not private.has_permission(p_company, 'finance', 'read')
    or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Solo el administrador puede consultar la rentabilidad por venta'
      using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from
    or p_to - p_from > 366 or p_page is null or p_page < 0 or p_page > 10000
    or length(coalesce(p_search, '')) > 100 then
    raise exception 'Revisá el período y la búsqueda';
  end if;

  return query
  with selected_sales as (
    select s.id, s.number, s.customer_name, s.created_at
    from public.sales s
    where s.company_id = p_company
      and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
      and (btrim(coalesce(p_search, '')) = ''
        or s.customer_name ilike '%' || btrim(p_search) || '%'
        or s.number::text ilike '%' || btrim(p_search) || '%'
        or exists (
          select 1 from public.sale_lines sl
          where sl.company_id = p_company and sl.sale_id = s.id
            and (sl.item_name ilike '%' || btrim(p_search) || '%'
              or sl.item_code ilike '%' || btrim(p_search) || '%')
        ))
  ), line_values as (
    select sl.sale_id, sl.item_name, sl.line_no,
      sl.line_total - coalesce(adj.credit_amount, 0) as revenue,
      sl.quantity - coalesce(adj.restocked_quantity, 0) as retained_quantity,
      sl.estimated_unit_cost
    from public.sale_lines sl
    join selected_sales ss on ss.id = sl.sale_id
    left join lateral (
      select sum(al.credit_amount) as credit_amount,
        sum(al.quantity) filter (where al.restocked) as restocked_quantity
      from public.sale_adjustment_lines al
      where al.company_id = sl.company_id
        and al.sale_id = sl.sale_id and al.sale_line_no = sl.line_no
    ) adj on true
    where sl.company_id = p_company
  ), amounts as (
    select lv.sale_id,
      string_agg(lv.item_name, ', ' order by lv.line_no) as products,
      sum(lv.revenue) as revenue,
      sum(lv.retained_quantity * lv.estimated_unit_cost)
        filter (where lv.estimated_unit_cost is not null) as cost,
      count(*) filter (where lv.estimated_unit_cost is null
        and lv.retained_quantity > 0) as missing
    from line_values lv group by lv.sale_id
  ), details as (
    select ss.id, ss.number, ss.customer_name, ss.created_at,
      a.products, a.revenue, a.cost, a.missing,
      exists (select 1 from public.sale_adjustments sa
        where sa.company_id = p_company and sa.sale_id = ss.id
          and sa.kind = 'cancel') as is_cancelled
    from selected_sales ss join amounts a on a.sale_id = ss.id
  )
  select d.id, d.number, d.customer_name, d.created_at, d.products,
    d.revenue, d.cost,
    case when d.missing = 0 then d.revenue - coalesce(d.cost, 0)
      else null end,
    d.missing, d.is_cancelled, count(*) over()
  from details d
  order by d.created_at desc, d.id desc
  limit 25 offset p_page * 25;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_admin_sales_profit_summary(p_company uuid)
 RETURNS TABLE(sales_total numeric, covered_revenue numeric, covered_cost numeric, estimated_profit numeric, missing_lines bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or private.get_user_role(p_company) <> 'admin'
    or not private.has_permission(p_company, 'finance', 'read')
    or not private.has_permission(p_company, 'sales', 'read') then
    raise exception 'Solo el administrador puede consultar ganancias'
      using errcode = '42501';
  end if;
  return query
  with line_values as (
    select l.sale_id,
      l.line_total - coalesce(a.credit_amount, 0) as revenue,
      l.quantity - coalesce(a.restocked_quantity, 0) as retained_quantity,
      l.estimated_unit_cost
    from public.sale_lines l
    left join lateral (
      select sum(al.credit_amount) credit_amount,
        sum(al.quantity) filter (where al.restocked) restocked_quantity
      from public.sale_adjustment_lines al
      where al.company_id = l.company_id and al.sale_id = l.sale_id
        and al.sale_line_no = l.line_no
    ) a on true
    where l.company_id = p_company
  ), sale_totals as (
    select lv.sale_id, sum(lv.revenue) revenue,
      sum(lv.retained_quantity * lv.estimated_unit_cost)
        filter (where lv.estimated_unit_cost is not null) cost,
      count(*) filter (where lv.estimated_unit_cost is null
        and lv.retained_quantity > 0) missing
    from line_values lv group by lv.sale_id
  )
  select coalesce(sum(st.revenue), 0),
    coalesce(sum(st.revenue) filter (where st.missing = 0), 0),
    coalesce(sum(st.cost) filter (where st.missing = 0), 0),
    coalesce(sum(st.revenue - coalesce(st.cost, 0)) filter (where st.missing = 0), 0),
    coalesce(sum(st.missing), 0)::bigint
  from sale_totals st;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_formula public.production_formulas%rowtype; v_lines jsonb;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company,'production','read')
    or not private.has_permission(p_company,'stock','read') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  if p_product is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6) then
    raise exception 'Indicá una cantidad válida con hasta seis decimales';
  end if;
  select * into v_formula from public.production_formulas
    where company_id=p_company and product_id=p_product;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  select jsonb_agg(jsonb_build_object(
    'item_id',n.item_id,'item_code',n.item_code,'item_name',n.item_name,
    'item_type',n.item_type,'unit_symbol',n.unit_symbol,
    'required',n.required,'infinite_stock',n.infinite_stock,'physical',coalesce(b.physical,0),
    'usable',coalesce(sl.usable,0),'reserved',coalesce(r.reserved,0),
    'free',case when n.infinite_stock then n.required else greatest(0,coalesce(sl.usable,0)-coalesce(r.reserved,0)) end,
    'locations',coalesce(sl.locations,'[]'::jsonb)) order by n.item_name)
    into v_lines
  from (
    select i.company_id,i.id item_id,i.code item_code,i.name item_name,
      i.item_type,i.track_lots,i.infinite_stock,u.symbol unit_symbol,
      round(sum(l.quantity)*p_quantity/v_formula.batch_quantity,6) required
    from public.production_formula_lines l
    join public.items i on i.company_id=l.company_id and i.id=l.component_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    where l.company_id=p_company and l.product_id=p_product
    group by i.company_id,i.id,u.symbol
  ) n
  left join lateral (
    select sum(b.quantity) physical from public.stock_balances b
    where b.company_id=p_company and b.item_id=n.item_id
  ) b on true
  left join lateral (
    select sum(a.quantity) reserved from public.production_reservation_locations a
    join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
    where a.company_id=p_company and a.component_id=n.item_id
      and j.status in ('queued','in_progress')
  ) r on true
  left join lateral (
    select sum(s.quantity) usable,
      jsonb_agg(jsonb_build_object(
        'warehouse_id',s.warehouse_id,'warehouse_name',s.warehouse_name,
        'lot_code',s.lot_code,'expires_on',s.expires_on,
        'physical',s.quantity,'reserved',coalesce(ar.reserved,0),
        'free',greatest(0,s.quantity-coalesce(ar.reserved,0)))
        order by s.expires_on asc nulls last,s.warehouse_name,s.lot_code) locations
    from (
      select sb.warehouse_id,w.name warehouse_name,
        null::uuid lot_id,null::text lot_code,null::date expires_on,sb.quantity
      from public.stock_balances sb
      join public.warehouses w on w.company_id=sb.company_id
        and w.id=sb.warehouse_id and w.active
      where sb.company_id=p_company and sb.item_id=n.item_id
        and not n.track_lots and sb.quantity>0
      union all
      select lb.warehouse_id,w.name,lb.lot_id,l.code,l.expires_on,lb.quantity
      from public.stock_lot_balances lb
      join public.stock_lots l on l.company_id=lb.company_id
        and l.item_id=lb.item_id and l.id=lb.lot_id
      join public.warehouses w on w.company_id=lb.company_id
        and w.id=lb.warehouse_id and w.active
      where lb.company_id=p_company and lb.item_id=n.item_id
        and n.track_lots and lb.quantity>0
        and (l.expires_on is null or l.expires_on>=v_today)
    ) s
    left join lateral (
      select sum(a.quantity) reserved from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=n.item_id
        and a.warehouse_id=s.warehouse_id
        and a.lot_id is not distinct from s.lot_id
        and j.status in ('queued','in_progress')
    ) ar on true
  ) sl on true;
  return jsonb_build_object('product_id',p_product,'quantity',p_quantity,
    'formula_version',v_formula.version,'lines',coalesce(v_lines,'[]'::jsonb));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb:='{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al inicio' using errcode='42501'; end if;
  if private.has_permission(p_company,'items','read') then
    v_result:=v_result||jsonb_build_object('items',
      (select count(*) from public.items where company_id=p_company and active));
  end if;
  if private.has_permission(p_company,'purchases','read') then
    v_result:=v_result||jsonb_build_object('purchases',
      (select count(*) from public.purchase_orders where company_id=p_company and status='open'));
  end if;
  if private.has_permission(p_company,'production','read') then
    v_result:=v_result||jsonb_build_object('formulas',
      (select count(*) from public.production_formulas where company_id=p_company));
  end if;
  if private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object('sales',
      (select count(*) from public.sales where company_id=p_company));
  end if;
  if private.has_permission(p_company,'finance','read') and
    private.has_permission(p_company,'sales','read') then
    v_result:=v_result||jsonb_build_object('receivables',
      (select coalesce(sum(s.total-coalesce(p.paid,0)),0)
        from public.sales s left join lateral (
          select sum(sp.amount) paid from public.sale_payments sp
          where sp.company_id=s.company_id and sp.sale_id=s.id and not exists(
            select 1 from public.sale_payment_reversals r
            where r.company_id=sp.company_id and r.payment_id=sp.id)
        ) p on true where s.company_id=p_company));
  end if;
  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_operational_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.erp_operational_report(p_company uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_result jsonb := '{}'::jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'reports', 'read') then
    raise exception 'Sin acceso a informes' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 366 then
    raise exception 'Elegí un período de hasta un año';
  end if;
  if private.has_permission(p_company, 'sales', 'read') then
    v_result := v_result || jsonb_build_object(
      'sales', (select count(*) from public.sales s
        where s.company_id = p_company
          and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'revenue', (select coalesce(sum(s.total - coalesce(a.credits, 0)), 0)
        from public.sales s
        left join lateral (select sum(sa.credit_total) as credits
          from public.sale_adjustments sa
          where sa.company_id = s.company_id and sa.sale_id = s.id) a on true
        where s.company_id = p_company
          and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'top_products', (select coalesce(jsonb_agg(t.entry order by t.qty desc), '[]'::jsonb)
        from (select jsonb_build_object('name', l.item_name,
            'quantity', sum(l.quantity - coalesce(a.returned, 0))) as entry,
            sum(l.quantity - coalesce(a.returned, 0)) as qty
          from public.sale_lines l
          join public.sales s on s.company_id = l.company_id and s.id = l.sale_id
          left join lateral (select sum(al.quantity) as returned
            from public.sale_adjustment_lines al
            where al.company_id = l.company_id and al.sale_id = l.sale_id
              and al.sale_line_no = l.line_no) a on true
          where s.company_id = p_company
            and s.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
            and s.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')
          group by l.item_id, l.item_name
          order by qty desc limit 5) t)
    );
  end if;
  if private.has_permission(p_company, 'production', 'read') then
    v_result := v_result || jsonb_build_object(
      'finished_jobs', (select count(*) from public.production_runs r
        where r.company_id = p_company
          and r.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and r.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires')),
      'jobs_in_progress', (select count(*) from public.production_jobs j
        where j.company_id = p_company
          and j.status in ('queued', 'in_progress'))
    );
  end if;
  if private.has_permission(p_company, 'purchases', 'read') then
    v_result := v_result || jsonb_build_object(
      'purchase_orders', (select count(*) from public.purchase_orders o
        where o.company_id = p_company
          and o.created_at >= (p_from::timestamp at time zone 'America/Argentina/Buenos_Aires')
          and o.created_at < ((p_to + 1)::timestamp at time zone 'America/Argentina/Buenos_Aires'))
    );
  end if;
  return v_result;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_product_costs(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, code text, name text, item_type text, unit_symbol text, cost numeric, price numeric, margin numeric, margin_percent numeric, status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_item record; v_cost numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read')
    or not private.has_permission(p_company,'items','read') then
    raise exception 'Necesitás acceso a finanzas y productos' using errcode='42501'; end if;
  if length(coalesce(p_search,''))>100 then raise exception 'Búsqueda demasiado larga'; end if;
  for v_item in select i.id,i.code,i.name,i.item_type,i.sale_unit_price,u.symbol,
    i.reference_unit_cost,f.product_id has_formula
    from public.items i join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    left join public.production_formulas f on f.company_id=i.company_id and f.product_id=i.id
    where i.company_id=p_company and i.active and i.item_type in ('finished_product','semi_finished')
    and (coalesce(p_search,'')='' or i.name ilike '%'||p_search||'%'
      or i.code ilike '%'||p_search||'%') order by i.name limit 100 loop
    v_cost:=null;
    if v_item.has_formula is not null then
      begin
        v_cost:=private.production_unit_cost(p_company,v_item.id);
      exception when raise_exception then v_cost:=null;
      end;
    else v_cost:=v_item.reference_unit_cost; end if;
    item_id:=v_item.id; code:=v_item.code; name:=v_item.name;
    item_type:=v_item.item_type; unit_symbol:=v_item.symbol;
    cost:=v_cost; price:=v_item.sale_unit_price;
    margin:=case when v_cost is not null and price is not null then price-v_cost end;
    margin_percent:=case when price>0 and v_cost is not null
      then round(100*(price-v_cost)/price,2) end;
    status:=case when v_cost is null then 'Costo incompleto'
      when price is null then 'Sin precio de venta' else 'Listo' end;
    return next;
  end loop;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_production_alerts(p_company uuid)
 RETURNS TABLE(alert_key text, fingerprint text, severity text, title text, detail text, destination text, occurred_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'dashboard','read') then
    raise exception 'Sin acceso al centro operativo' using errcode='42501';
  end if;
  return query select base.alert_key,base.fingerprint,base.severity,
    base.title,base.detail,base.destination,base.occurred_on
    from private.erp_production_alerts(p_company) base;
  if private.has_permission(p_company,'production','read')
    and private.has_permission(p_company,'stock','read') then
    return query
    select 'reservation:'||j.id::text||':'||r.component_id::text,
      greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||':'||coalesce(j.due_on::text,''),
      case when j.due_on <= v_today+3 then 'critical' else 'warning' end,
      'Faltan insumos para una orden',
      i.name||' · Faltan '||
        greatest(0,r.required_quantity-coalesce(e.consumed,0)-r.reserved_quantity)::text
        ||' '||u.symbol||' para '||p.name,
      '/production/orders?job='||j.id::text,
      coalesce(j.due_on,v_today)
    from public.production_job_reservations r
    join public.production_jobs j on j.company_id=r.company_id and j.id=r.job_id
    join public.items i on i.company_id=r.company_id and i.id=r.component_id
    join public.items p on p.company_id=j.company_id and p.id=j.product_id
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    left join lateral (
      select sum(case when ev.kind='issue' then ev.quantity else -ev.quantity end) consumed
      from public.production_job_events ev
      where ev.company_id=r.company_id and ev.job_id=r.job_id
        and ev.component_id=r.component_id
    ) e on true
    where r.company_id=p_company and not i.infinite_stock
      and j.status in ('queued','in_progress')
      and r.required_quantity-coalesce(e.consumed,0)>r.reserved_quantity;
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_production_dashboard(p_company uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'production', 'read') then
    raise exception 'Sin acceso a producción' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'queued', (select count(*) from public.production_jobs
      where company_id = p_company and status = 'queued'),
    'in_progress', (select count(*) from public.production_jobs
      where company_id = p_company and status = 'in_progress'),
    'overdue', (select count(*) from public.production_jobs
      where company_id = p_company and status in ('queued', 'in_progress')
        and due_on < v_today),
    'next', (select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb)
      from (select j.id, j.status, j.due_on, j.note,
        j.planned_quantity, i.name as product_name
        from public.production_jobs j
        join public.items i on i.company_id = j.company_id and i.id = j.product_id
        where j.company_id = p_company and j.status in ('queued', 'in_progress')
        order by j.due_on asc nulls last, j.created_at asc
        limit 5) p)
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_public_price_list(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, price numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.erp_replenishment_forecast(p_company uuid)
 RETURNS TABLE(item_id uuid, item_code text, item_name text, unit_symbol text, physical numeric, usable numeric, reserved numeric, free numeric, pending_purchase numeric, minimum_stock numeric, consumed_60d numeric, history_days integer, daily_use numeric, days_left numeric, supplier_id uuid, supplier_name text, lead_time_days integer, suggested_quantity numeric, alert_level text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with scope as (
    select i.id, i.code, i.name, i.minimum_stock, i.track_lots, u.symbol
    from public.items i
    join public.units u on u.company_id=i.company_id and u.id=i.unit_id
    where i.company_id=p_company and i.active and not i.infinite_stock
      and i.item_type in ('raw_material','semi_finished','consumable')
      and auth.uid() is not null
      and private.has_permission(p_company,'stock','read')
      and private.has_permission(p_company,'purchases','read')
      and private.has_permission(p_company,'production','read')
  ), snapshot as (
    select i.*,
      coalesce(b.physical,0) as physical,
      coalesce(us.usable,0) as usable,
      coalesce(r.reserved,0) as reserved,
      coalesce(po.pending,0) as pending_purchase,
      coalesce(m.consumed,0) as consumed_60d,
      m.first_issue,
      s.supplier_id,s.supplier_name,coalesce(s.lead_days,7) as lead_days
    from scope i
    left join lateral (
      select sum(b.quantity) physical from public.stock_balances b
      where b.company_id=p_company and b.item_id=i.id
    ) b on true
    left join lateral (
      select sum(q.quantity) usable from (
        select b.quantity from public.stock_balances b
        join public.warehouses w on w.company_id=b.company_id
          and w.id=b.warehouse_id and w.active
        where b.company_id=p_company and b.item_id=i.id and not i.track_lots
        union all
        select lb.quantity from public.stock_lot_balances lb
        join public.warehouses w on w.company_id=lb.company_id
          and w.id=lb.warehouse_id and w.active
        join public.stock_lots l on l.company_id=lb.company_id
          and l.item_id=lb.item_id and l.id=lb.lot_id
        where lb.company_id=p_company and lb.item_id=i.id and i.track_lots
          and (l.expires_on is null or l.expires_on >=
            (now() at time zone 'America/Argentina/Buenos_Aires')::date)
      ) q
    ) us on true
    left join lateral (
      select sum(a.quantity) reserved from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=i.id
        and j.status in ('queued','in_progress')
    ) r on true
    left join lateral (
      select sum(l.quantity-l.received_quantity) pending
      from public.purchase_order_lines l
      join public.purchase_orders o on o.company_id=l.company_id and o.id=l.order_id
      where l.company_id=p_company and l.item_id=i.id
        and o.status in ('open','partial')
    ) po on true
    left join lateral (
      select sum(-m.delta) consumed, min(m.created_at) first_issue
      from public.stock_movements m
      where m.company_id=p_company and m.item_id=i.id and m.kind='issue'
        and m.created_at >= now()-interval '60 days'
    ) m on true
    left join lateral (
      select si.supplier_id,s.name supplier_name,s.lead_time_days lead_days
      from public.supplier_items si
      join public.suppliers s on s.company_id=si.company_id
        and s.id=si.supplier_id and s.active
      where si.company_id=p_company and si.item_id=i.id
      order by si.preferred desc,s.name,s.id limit 1
    ) s on true
  ), metrics as (
    select x.*,
      greatest(0,x.usable-x.reserved) as free_stock,
      case when x.first_issue is null then 0
        else least(60,greatest(1,
          (now() at time zone 'America/Argentina/Buenos_Aires')::date
            - (x.first_issue at time zone 'America/Argentina/Buenos_Aires')::date + 1))
      end as observation_days
    from snapshot x
  ), demand as (
    select x.*,
      case when observation_days>=14 then round(consumed_60d/observation_days,6)
        else 0::numeric end as rate
    from metrics x
  )
  select d.id,d.code,d.name,d.symbol,d.physical,d.usable,d.reserved,d.free_stock,
    d.pending_purchase,d.minimum_stock,d.consumed_60d,d.observation_days,d.rate,
    case when d.rate>0 then round(d.free_stock/d.rate,1) else null end,
    d.supplier_id,d.supplier_name,d.lead_days,
    greatest(0,ceil(greatest(d.minimum_stock,
      d.rate*(d.lead_days+7)) - d.free_stock-d.pending_purchase)),
    case
      when d.free_stock<=0 and d.pending_purchase<=0 then 'critical'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 'critical'
      when d.free_stock<d.minimum_stock then 'warning'
      when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 'warning'
      else 'ok'
    end
  from demand d
  order by case
    when d.free_stock<=0 and d.pending_purchase<=0 then 0
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days then 0
    when d.free_stock<d.minimum_stock then 1
    when d.rate>0 and d.free_stock/d.rate<=d.lead_days+7 then 1
    else 2 end,d.name;
$function$
;
CREATE OR REPLACE FUNCTION public.erp_sales_profit_summary(p_company uuid)
 RETURNS TABLE(sales_total numeric, covered_revenue numeric, covered_cost numeric, estimated_profit numeric, missing_lines bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.exchange_rate_overview(p_company uuid)
 RETURNS TABLE(id uuid, name text, active boolean, current_rate numeric, effective_on date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a cotizaciones' using errcode='42501'; end if;
  return query select t.id,t.name,t.active,r.ars_per_usd,r.effective_on
    from public.exchange_rate_types t left join lateral (
      select e.ars_per_usd,e.effective_on from public.exchange_rates e
      where e.company_id=t.company_id and e.type_id=t.id
        and e.effective_on<=(now() at time zone 'America/Argentina/Buenos_Aires')::date
      order by e.effective_on desc,e.created_at desc,e.id desc limit 1
    ) r on true where t.company_id=p_company and not t.archived order by t.name;
end; $function$
;
CREATE OR REPLACE FUNCTION public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype;
  v_track_lots boolean; v_expected record; v_cost numeric; v_output uuid;
  v_run uuid; v_mismatch boolean:=false; v_lot text:=nullif(btrim(p_output_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_actual_quantity is null or p_actual_quantity<=0
    or p_actual_quantity>=1000000000000
    or p_actual_quantity<>round(p_actual_quantity,6)
    or length(coalesce(p_variance_note,''))>400 then
    raise exception 'Indicá el rendimiento real con hasta seis decimales'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  if v_job.status='completed' then
    if v_job.completion_request_id<>p_request_id
      or v_job.actual_quantity<>p_actual_quantity
      or v_job.output_lot is distinct from v_lot
      or v_job.output_expiry is distinct from p_expires_on
      or v_job.variance_note is distinct from nullif(btrim(p_variance_note),'') then
      raise exception 'Esta orden ya fue completada con otros datos'; end if;
    return v_job.run_id;
  end if;
  if v_job.status<>'in_progress' then
    raise exception 'Iniciá la orden y registrá sus insumos antes de terminar'; end if;
  select i.track_lots into v_track_lots from public.items i
    where i.company_id=p_company and i.id=v_job.product_id and i.active for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if v_track_lots and v_lot is null then
    raise exception 'Indicá el lote del producto que vas a ingresar'; end if;
  if not v_track_lots and (v_lot is not null or p_expires_on is not null) then
    raise exception 'Este producto no usa lotes; dejá lote y vencimiento vacíos'; end if;
  if p_actual_quantity<>v_job.expected_output then v_mismatch:=true; end if;
  for v_expected in select (x->>'component_id')::uuid component_id,
    (x->>'quantity')::numeric quantity
    from jsonb_array_elements(v_job.formula_snapshot) x loop
    if (select coalesce(sum(case when e.kind='issue' then e.quantity else -e.quantity end),0)
      from public.production_job_events e where e.company_id=p_company and e.job_id=p_job
        and e.component_id=v_expected.component_id)<>v_expected.quantity then
      v_mismatch:=true; end if;
  end loop;
  if exists(select 1 from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job
      and not exists(select 1 from jsonb_array_elements(v_job.formula_snapshot) x
        where x->>'component_id'=e.component_id::text)
    group by e.component_id
    having sum(case when e.kind='issue' then e.quantity else -e.quantity end)>0) then
    v_mismatch:=true; end if;
  if v_mismatch and length(btrim(coalesce(p_variance_note,'')))<5 then
    raise exception 'Explicá la diferencia entre lo previsto y lo fabricado'; end if;
  select round(coalesce(sum(case when e.kind='issue' then 1 else -1 end
    *e.quantity*e.unit_cost),0),2) into v_cost
    from public.production_job_events e where e.company_id=p_company and e.job_id=p_job;
  if v_cost<0 then raise exception 'Los consumos de la orden son inconsistentes'; end if;
  if not exists(select 1 from public.production_job_events e
    where e.company_id=p_company and e.job_id=p_job and e.kind='issue'
      and e.quantity>(select coalesce(sum(r.quantity),0)
        from public.production_job_events r where r.company_id=e.company_id
          and r.issue_id=e.id)) then
    raise exception 'No quedan insumos consumidos para fabricar el producto'; end if;
  v_run:=gen_random_uuid();
  v_output:=public.post_stock_operation(p_company,v_job.product_id,
    v_job.warehouse_id,null,'receipt',p_actual_quantity,
    'Fabricación orden '||p_job::text,gen_random_uuid(),v_lot,p_expires_on);
  insert into public.production_runs(id,company_id,product_id,formula_version,
    quantity,warehouse_id,output_operation_id,estimated_cost,request_id,
    request_payload,note,actor_id)
  values(v_run,p_company,v_job.product_id,v_job.formula_version,
    p_actual_quantity,v_job.warehouse_id,v_output,v_cost,p_request_id,
    jsonb_build_object('job',p_job,'actual_quantity',p_actual_quantity,
      'output_lot',v_lot,'expiry',p_expires_on),v_job.note,auth.uid());
  update public.production_jobs set status='completed',actual_quantity=p_actual_quantity,
    output_lot=v_lot,output_expiry=p_expires_on,
    variance_note=nullif(btrim(p_variance_note),''),run_id=v_run,
    completion_request_id=p_request_id,completed_at=clock_timestamp()
    where company_id=p_company and id=p_job;
  if v_job.plan_id is not null then
    update public.production_plans set status='completed',run_id=v_run,
      completion_request_id=p_request_id,completed_at=clock_timestamp()
      where company_id=p_company and id=v_job.plan_id and status='planned';
    if not found then raise exception 'La planificación fue modificada'; end if;
  end if;
  return v_run;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.import_items(p_company uuid, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rows jsonb; v_row jsonb; v_id uuid; v_supplier uuid; v_fx uuid; v_usd numeric;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  v_rows:=private.prepare_item_import(p_company,p_rows);
  for v_row in select value from jsonb_array_elements(v_rows) loop
    v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
    v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
    v_usd:=nullif(v_row->>'cost_usd','')::numeric;
    insert into public.items(company_id,code,name,item_type,category_id,unit_id,barcode,
      description,minimum_stock,track_lots,infinite_stock,reference_unit_cost,sale_unit_price,
      active,reference_cost_usd,reference_exchange_rate_type_id)
    values(p_company,btrim(v_row->>'codigo'),btrim(v_row->>'nombre'),v_row->>'tipo',
      nullif(v_row->>'category_id','')::uuid,(v_row->>'unit_id')::uuid,
      nullif(btrim(v_row->>'codigo_barras'),''),btrim(v_row->>'descripcion'),
      (v_row->>'stock_minimo')::numeric,(v_row->>'seguir_lotes')::boolean,
      (v_row->>'stock_infinito')::boolean,nullif(v_row->>'cost_ars','')::numeric,
      nullif(v_row->>'precio_venta_ars','')::numeric,(v_row->>'activo')::boolean,
      case when v_supplier is null then v_usd end,
      case when v_supplier is null then v_fx end) returning id into v_id;
    if v_supplier is not null then
      perform public.save_supplier_quote(p_company,v_supplier,v_id,
        coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
        case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
      perform public.set_preferred_supplier(p_company,v_id,v_supplier);
    end if;
  end loop;
  return jsonb_array_length(v_rows);
end; $function$
;
CREATE OR REPLACE FUNCTION public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
  v_existing public.delivery_notes%rowtype;
  v_job public.production_jobs%rowtype;
  v_line jsonb;
  v_item public.items%rowtype;
  v_warehouse text;
  v_symbol text;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_warehouse_id uuid;
  v_lot text;
  v_operation uuid;
  v_event uuid;
begin
  if auth.uid() is null
    or not private.has_permission(p_company, 'stock', 'insert')
    or (p_kind = 'production' and
      not private.has_permission(p_company, 'production', 'insert')) then
    raise exception 'Necesitás permiso para entregar stock y registrar fabricación'
      using errcode = '42501';
  end if;
  if p_kind is null or p_kind not in ('production','materials','products')
    or (p_kind = 'production') is distinct from (p_job is not null)
    or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá tipo de remito, destinatario e insumos';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', p_kind, 'job', p_job,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_existing from public.delivery_notes
    where company_id = p_company and request_id = p_request;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  if p_job is not null then
    select * into v_job from public.production_jobs
      where company_id = p_company and id = p_job for update;
    if not found or v_job.status not in ('queued', 'in_progress') then
      raise exception 'La orden de fabricación no admite más entregas';
    end if;
  end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.delivery_note_counters(company_id) values (p_company)
    on conflict do nothing;
  update public.delivery_note_counters set next_number = next_number + 1
    where company_id = p_company returning next_number - 1 into v_number;
  insert into public.delivery_notes(company_id, number, request_id,
    request_payload, kind, job_id, recipient, note, actor_id)
  values (p_company, v_number, p_request, v_payload,
    p_kind, p_job, btrim(p_recipient), btrim(p_note), auth.uid())
  returning id into v_id;

  for v_line in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'Cada renglón debe contener un ítem'; end if;
    v_quantity := (v_line ->> 'quantity')::numeric;
    v_warehouse_id := (v_line ->> 'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_line ->> 'lot_code'), '');
    if (v_line ->> 'item_id') is null or v_warehouse_id is null
      or v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) or length(coalesce(v_lot, '')) > 80 then
      raise exception 'Revisá ítem, cantidad, depósito y lote de cada renglón';
    end if;
    select * into v_item from public.items
      where company_id = p_company and id = (v_line ->> 'item_id')::uuid
        and active for share;
    if not found then raise exception 'El ítem está inactivo o no existe'; end if;
    if (p_kind = 'production'
        and v_item.item_type not in ('raw_material', 'semi_finished', 'consumable'))
      or (p_kind = 'materials'
        and v_item.item_type not in ('raw_material', 'semi_finished', 'consumable'))
      or (p_kind = 'products'
        and v_item.item_type not in ('semi_finished', 'finished_product')) then
      raise exception 'El tipo de ítem no corresponde a este remito';
    end if;
    select w.name into v_warehouse from public.warehouses w
      where w.company_id = p_company and w.id = v_warehouse_id and w.active for share;
    if not found then raise exception 'Elegí un depósito de origen activo'; end if;
    select u.symbol into v_symbol from public.units u
      where u.company_id = p_company and u.id = v_item.unit_id;
    if p_kind = 'production' then
      v_event := public.issue_production_material(p_company, p_job,
        v_item.id, v_warehouse_id, v_lot, v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid());
      select stock_operation_id into v_operation from public.production_job_events
        where company_id = p_company and id = v_event;
    else
      v_event := null;
      v_operation := public.post_stock_operation(p_company, v_item.id,
        v_warehouse_id, null, 'issue', v_quantity,
        'Remito Nº ' || v_number || ' · ' || left(btrim(p_note), 250),
        gen_random_uuid(), v_lot, null);
    end if;
    insert into public.delivery_note_lines(company_id, note_id, line_no,
      item_id, item_code, item_name, unit_symbol, warehouse_id,
      warehouse_name, lot_code, quantity, stock_operation_id, production_event_id)
    values (p_company, v_id, v_line_no, v_item.id, v_item.code, v_item.name,
      coalesce(v_symbol, ''), v_warehouse_id, v_warehouse, v_lot,
      v_quantity, v_operation, v_event);
  end loop;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype;
  v_previous public.production_job_events%rowtype;
  v_cost numeric; v_operation uuid; v_event uuid;
  v_lot text:=nullif(btrim(p_lot),'');
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso de producción y stock' using errcode='42501'; end if;
  if p_request_id is null or p_component is null or p_warehouse is null
    or p_quantity is null or p_quantity<=0 or p_quantity>=1000000000000
    or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá el insumo, cantidad, depósito y motivo'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.production_job_events
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.kind<>'issue'
      or v_previous.job_id<>p_job or v_previous.component_id<>p_component
      or v_previous.warehouse_id<>p_warehouse or v_previous.quantity<>p_quantity
      or v_previous.lot_code is distinct from v_lot
      or v_previous.note<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.status not in ('queued','in_progress') then
    raise exception 'La orden ya no admite insumos'; end if;
  if p_component=v_job.product_id then
    raise exception 'El producto fabricado no puede consumirse a sí mismo'; end if;
  perform 1 from public.items i where i.company_id=p_company and i.id=p_component
    and i.active and i.item_type in ('raw_material','semi_finished','consumable') for share;
  if not found then raise exception 'Elegí una materia prima o un semielaborado activo'; end if;
  select round(r.estimated_cost/r.quantity,2) into v_cost
    from public.production_runs r
    where r.company_id=p_company and r.product_id=p_component
    order by r.created_at desc limit 1;
  v_cost:=coalesce(v_cost,private.production_unit_cost(p_company,p_component));
  v_operation:=public.post_stock_operation(p_company,p_component,p_warehouse,
    null,'issue',p_quantity,'Orden producción '||p_job::text,
    gen_random_uuid(),v_lot,null);
  insert into public.production_job_events(company_id,job_id,request_id,kind,
    component_id,warehouse_id,lot_code,quantity,unit_cost,stock_operation_id,
    note,actor_id)
  values(p_company,p_job,p_request_id,'issue',p_component,p_warehouse,
    v_lot,p_quantity,v_cost,v_operation,btrim(p_note),auth.uid())
  returning id into v_event;
  if v_job.status='queued' then
    update public.production_jobs set status='in_progress',started_at=clock_timestamp()
      where company_id=p_company and id=p_job;
  end if;
  return v_event;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_sale public.sales%rowtype;
  v_previous public.delivery_notes%rowtype;
  v_line public.sale_lines%rowtype;
  v_entry jsonb;
  v_payload jsonb;
  v_id uuid;
  v_number bigint;
  v_line_no integer := 0;
  v_quantity numeric;
  v_already numeric;
  v_returned numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'sales', 'read')
    or not private.has_permission(p_company, 'stock', 'read')
    or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Necesitás acceso a ventas y stock para emitir el remito'
      using errcode = '42501'; end if;
  if p_sale is null or p_request is null
    or length(btrim(coalesce(p_recipient, ''))) not between 3 and 120
    or length(btrim(coalesce(p_note, ''))) not between 3 and 300
    or jsonb_typeof(p_lines) is distinct from 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá la venta, el destinatario y los renglones'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('delivery:' || p_company::text || ':' || p_request::text, 0));
  v_payload := jsonb_build_object('kind', 'sale', 'sale', p_sale,
    'recipient', btrim(p_recipient), 'note', btrim(p_note), 'lines', p_lines);
  select * into v_previous from public.delivery_notes
    where company_id = p_company and request_id = p_request;
  if found then
    if v_previous.actor_id <> auth.uid() or v_previous.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  select * into v_sale from public.sales
    where company_id = p_company and id = p_sale for update;
  if not found then raise exception 'Venta inexistente'; end if;
  if exists (select 1 from public.sale_adjustments a
    where a.company_id = p_company and a.sale_id = p_sale and a.kind = 'cancel') then
    raise exception 'Una venta anulada no puede generar nuevos remitos'; end if;
  perform 1 from public.companies where id = p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  insert into public.delivery_note_counters(company_id) values (p_company)
    on conflict do nothing;
  update public.delivery_note_counters set next_number = next_number + 1
    where company_id = p_company returning next_number - 1 into v_number;
  insert into public.delivery_notes(company_id, number, request_id,
    request_payload, kind, sale_id, recipient, note, actor_id)
  values (p_company, v_number, p_request, v_payload, 'sale', p_sale,
    btrim(p_recipient), btrim(p_note), auth.uid()) returning id into v_id;
  for v_entry in select value from jsonb_array_elements(p_lines) x(value) loop
    v_line_no := v_line_no + 1;
    if jsonb_typeof(v_entry) <> 'object' then
      raise exception 'Renglón de venta inválido'; end if;
    v_quantity := (v_entry ->> 'quantity')::numeric;
    if (v_entry ->> 'line_no') is null or v_quantity is null
      or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity, 6) then
      raise exception 'Revisá las cantidades entregadas'; end if;
    select * into v_line from public.sale_lines
      where company_id = p_company and sale_id = p_sale
        and line_no = (v_entry ->> 'line_no')::smallint;
    if not found then raise exception 'Producto no incluido en la venta'; end if;
    if exists (select 1 from public.delivery_note_lines l
      where l.company_id = p_company and l.note_id = v_id
        and l.sale_line_no = v_line.line_no) then
      raise exception 'Cada producto de la venta puede figurar una vez por remito'; end if;
    select coalesce(sum(l.quantity), 0) into v_already
      from public.delivery_note_lines l
      join public.delivery_notes d on d.company_id = l.company_id and d.id = l.note_id
      where d.company_id = p_company and d.sale_id = p_sale
        and d.status = 'issued' and l.sale_line_no = v_line.line_no;
    select coalesce(sum(a.quantity), 0) into v_returned
      from public.sale_adjustment_lines a
      where a.company_id = p_company and a.sale_id = p_sale
        and a.sale_line_no = v_line.line_no;
    if v_quantity > v_line.quantity - v_returned - v_already then
      raise exception 'Esta entrega supera el saldo disponible del producto vendido'; end if;
    insert into public.delivery_note_lines(company_id, note_id, line_no,
      item_id, item_code, item_name, unit_symbol, warehouse_id, warehouse_name,
      lot_code, quantity, stock_operation_id, sale_id, sale_line_no)
    values (p_company, v_id, v_line_no, v_line.item_id, v_line.item_code,
      v_line.item_name, v_line.unit_symbol, v_line.warehouse_id,
      v_line.warehouse_code, v_line.lot_code, v_quantity,
      v_line.stock_operation_id, p_sale, v_line.line_no);
  end loop;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.item_cost_context(p_company uuid, p_item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'items','read')
    or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin acceso a los costos del proveedor' using errcode='42501'; end if;
  return (select jsonb_build_object('supplier_id',q.supplier_id,'supplier_name',s.name,
    'currency_code',q.currency_code,'unit_price',q.unit_price)
    from public.supplier_items q join public.suppliers s on s.company_id=q.company_id and s.id=q.supplier_id
    where q.company_id=p_company and q.item_id=p_item and q.preferred);
end; $function$
;
CREATE OR REPLACE FUNCTION public.my_company_access()
 RETURNS TABLE(company_id uuid, company_name text, company_slug text, company_active boolean, role_id uuid, role_name text, role_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select cu.company_id,c.name,c.slug,c.active,cu.role_id,r.name,r.code
  from public.company_users cu
  join public.companies c on c.id=cu.company_id
  join public.roles r on r.id=cu.role_id and r.company_id=cu.company_id
  where cu.user_id=(select auth.uid()) and cu.active
  union all
  select c.id,c.name,c.slug,c.active,null::uuid,'Soporte Dromux','support'
  from public.companies c
  where c.active and exists (
    select 1 from private.support_operators so
    where so.user_id=(select auth.uid()) and so.active
  ) and not exists (
    select 1 from public.company_users cu
    where cu.company_id=c.id and cu.user_id=(select auth.uid()) and cu.active
  );
$function$
;
CREATE OR REPLACE FUNCTION public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payload jsonb;
  v_existing public.production_runs%rowtype;
  v_formula public.production_formulas%rowtype;
  v_line record;
  v_input jsonb;
  v_required numeric;
  v_cost numeric;
  v_run uuid;
  v_operation uuid;
  v_output uuid;
  v_wh uuid;
  v_lot text;
  v_posted jsonb := '[]'::jsonb;
  v_post jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos de producción y movimientos de stock' using errcode='42501';
  end if;
  if p_request_id is null or p_quantity is null or p_quantity <= 0
    or p_quantity >= 1000000000000 or p_quantity <> round(p_quantity,6)
    or p_product is null or p_warehouse is null or p_inputs is null
    or jsonb_typeof(p_inputs) <> 'array' or length(btrim(p_note)) not between 3 and 400 then
    raise exception 'Datos de producción inválidos';
  end if;
  v_payload := jsonb_build_object('product',p_product,'quantity',p_quantity,
    'warehouse',p_warehouse,'lot',nullif(btrim(p_output_lot),''),
    'expiry',p_expires_on,'note',btrim(p_note),'inputs',p_inputs);
  select * into v_existing from public.production_runs
  where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.request_payload <> v_payload or v_existing.actor_id <> auth.uid() then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;
  select * into v_formula from public.production_formulas
  where company_id=p_company and product_id=p_product for share;
  if not found then raise exception 'El producto no tiene fórmula'; end if;
  perform 1 from public.items where company_id=p_company and id=p_product and active for share;
  if not found then raise exception 'El producto está inactivo'; end if;
  if jsonb_array_length(p_inputs) <> (select count(*) from public.production_formula_lines
    where company_id=p_company and product_id=p_product) then
    raise exception 'Seleccioná depósito y lote para cada componente';
  end if;
  v_cost := private.production_unit_cost(p_company,p_product);
  -- Se registra todo dentro de la misma transacción de PostgreSQL.
  v_run := gen_random_uuid();
  for v_line in select l.component_id,l.quantity,i.track_lots
    from public.production_formula_lines l join public.items i
      on i.company_id=l.company_id and i.id=l.component_id
    where l.company_id=p_company and l.product_id=p_product order by l.component_id loop
    select value into v_input from jsonb_array_elements(p_inputs) value
    where value->>'component_id'=v_line.component_id::text;
    if not found or (select count(*) from jsonb_array_elements(p_inputs) value
      where value->>'component_id'=v_line.component_id::text) <> 1 then
      raise exception 'Cada componente debe figurar una sola vez';
    end if;
    v_wh := (v_input->>'warehouse_id')::uuid;
    v_lot := nullif(btrim(v_input->>'lot_code'),'');
    v_required := v_line.quantity*p_quantity/v_formula.batch_quantity;
    if v_required <= 0 or v_required >= 1000000000000 or v_required <> round(v_required,6) then
      raise exception 'La cantidad requerida no admite más de seis decimales';
    end if;
    v_operation := public.post_stock_operation(p_company,v_line.component_id,v_wh,null,
      'issue',v_required,'Producción '||v_run::text,gen_random_uuid(),v_lot,null);
    v_posted := v_posted || jsonb_build_array(jsonb_build_object(
      'component',v_line.component_id,'warehouse',v_wh,'quantity',v_required,
      'lot',v_lot,'cost',private.production_unit_cost(p_company,v_line.component_id),
      'operation',v_operation));
  end loop;
  v_output := public.post_stock_operation(p_company,p_product,p_warehouse,null,
    'receipt',p_quantity,'Producción '||v_run::text,gen_random_uuid(),
    nullif(btrim(p_output_lot),''),p_expires_on);
  insert into public.production_runs(id,company_id,product_id,formula_version,quantity,
    warehouse_id,output_operation_id,estimated_cost,request_id,request_payload,note,actor_id)
  values(v_run,p_company,p_product,v_formula.version,p_quantity,p_warehouse,
    v_output,round(v_cost*p_quantity,2),p_request_id,v_payload,btrim(p_note),auth.uid());
  for v_post in select value from jsonb_array_elements(v_posted) loop
    insert into public.production_run_lines(company_id,run_id,component_id,warehouse_id,
      quantity,lot_code,unit_cost,stock_operation_id)
    values(p_company,v_run,(v_post->>'component')::uuid,(v_post->>'warehouse')::uuid,
      (v_post->>'quantity')::numeric,v_post->>'lot',(v_post->>'cost')::numeric,
      (v_post->>'operation')::uuid);
  end loop;
  return v_run;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.sales%rowtype;
  v_payload jsonb;
  v_customer public.customers%rowtype;
  v_line jsonb;
  v_item public.items%rowtype;
  v_warehouse_code text;
  v_unit_symbol text;
  v_sale uuid;
  v_number bigint;
  v_line_no smallint := 0;
  v_item_id uuid;
  v_warehouse uuid;
  v_quantity numeric;
  v_lot text;
  v_unit_price numeric;
  v_line_total numeric;
  v_total numeric := 0;
  v_operation uuid;
  v_cost numeric;
  v_posted jsonb := '[]'::jsonb;
  v_post jsonb;
begin
  if auth.uid() is null or not private.has_permission(p_company,'sales','insert')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permisos de ventas y stock' using errcode='42501';
  end if;
  if p_request_id is null or p_customer is null or p_note is null
    or length(btrim(p_note)) not between 3 and 500
    or p_lines is null or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Revisá cliente, observaciones y productos';
  end if;
  -- Serializa reintentos simultáneos con la misma clave de solicitud.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('sale:'||p_company::text||':'||p_request_id::text,0));
  v_payload := jsonb_build_object('customer',p_customer,'note',btrim(p_note),'lines',p_lines);
  select * into v_existing from public.sales
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.request_payload <> v_payload then
      raise exception 'Esta solicitud ya se utilizó con otros datos';
    end if;
    return v_existing.id;
  end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa no está activa'; end if;
  select * into v_customer from public.customers
    where company_id=p_company and id=p_customer and active for share;
  if not found then raise exception 'Elegí un cliente activo'; end if;
  v_sale := gen_random_uuid();
  -- Orden estable de ítems para reducir conflictos entre ventas concurrentes.
  for v_line in select value from jsonb_array_elements(p_lines) as t(value)
      order by value->>'item_id' loop
    v_line_no := v_line_no+1;
    v_item_id := (v_line->>'item_id')::uuid;
    v_warehouse := (v_line->>'warehouse_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    v_lot := nullif(btrim(v_line->>'lot_code'),'');
    if v_item_id is null or v_warehouse is null or v_quantity is null
      or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity,6)
      or length(coalesce(v_lot,'')) > 80 then
      raise exception 'La cantidad, el depósito o el lote son inválidos';
    end if;
    if exists(select 1 from jsonb_array_elements(v_posted) as x(entry)
      where entry->>'item_id'=v_item_id::text) then
      raise exception 'Cada producto puede figurar una sola vez por venta';
    end if;
    select * into v_item from public.items
      where company_id=p_company and id=v_item_id and active
        and item_type='finished_product' for share;
    if not found then raise exception 'El producto está inactivo o no es terminado'; end if;
    if v_item.sale_unit_price is null then
      raise exception 'Definí el precio de venta de %',v_item.name;
    end if;
    if (v_line->>'expected_unit_price') is null
      or (v_line->>'expected_unit_price')::numeric <> v_item.sale_unit_price then
      raise exception 'El precio de % cambió. Actualizá la pantalla y revisá la venta',v_item.name;
    end if;
    select symbol into v_unit_symbol from public.units
      where company_id=p_company and id=v_item.unit_id;
    select code into v_warehouse_code from public.warehouses
      where company_id=p_company and id=v_warehouse and active for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_unit_price := v_item.sale_unit_price;
    v_line_total := round(v_quantity*v_unit_price,2);
    v_total := v_total+v_line_total;
    if v_total >= 10000000000000000 then
      raise exception 'El total supera el máximo permitido';
    end if;
    select round(r.estimated_cost/r.quantity,2) into v_cost
    from public.production_runs r where r.company_id=p_company and r.product_id=v_item_id
    order by r.created_at desc limit 1;
    v_cost := coalesce(v_cost,v_item.reference_unit_cost);
    v_operation := public.post_stock_operation(p_company,v_item_id,v_warehouse,null,
      'issue',v_quantity,'Venta '||v_sale::text,gen_random_uuid(),v_lot,null);
    v_posted := v_posted || jsonb_build_array(jsonb_build_object(
      'item_id',v_item_id,'warehouse_id',v_warehouse,'warehouse_code',v_warehouse_code,
      'item_code',v_item.code,'item_name',v_item.name,'unit_symbol',v_unit_symbol,
      'lot_code',v_lot,'quantity',v_quantity,'unit_price',v_unit_price,
      'line_total',v_line_total,'estimated_unit_cost',v_cost,'operation',v_operation));
  end loop;
  insert into public.sale_counters(company_id) values(p_company) on conflict do nothing;
  update public.sale_counters set next_number=next_number+1
    where company_id=p_company returning next_number-1 into v_number;
  insert into public.sales(id,company_id,number,request_id,request_payload,
    customer_id,customer_name,customer_tax_id,note,total,actor_id)
  values(v_sale,p_company,v_number,p_request_id,v_payload,p_customer,
    v_customer.name,v_customer.tax_id,btrim(p_note),v_total,auth.uid());
  v_line_no := 0;
  for v_post in select value from jsonb_array_elements(v_posted) loop
    v_line_no := v_line_no+1;
    insert into public.sale_lines(company_id,sale_id,line_no,item_id,item_code,item_name,
      unit_symbol,warehouse_id,warehouse_code,lot_code,quantity,unit_price,
      line_total,estimated_unit_cost,stock_operation_id)
    values(p_company,v_sale,v_line_no,
      (v_post->>'item_id')::uuid,v_post->>'item_code',v_post->>'item_name',
      v_post->>'unit_symbol',(v_post->>'warehouse_id')::uuid,v_post->>'warehouse_code',
      v_post->>'lot_code',(v_post->>'quantity')::numeric,(v_post->>'unit_price')::numeric,
      (v_post->>'line_total')::numeric,(v_post->>'estimated_unit_cost')::numeric,
      (v_post->>'operation')::uuid);
  end loop;
  return v_sale;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_existing public.sale_payments%rowtype;
  v_sale public.sales%rowtype;
  v_paid numeric;
  v_payment uuid;
  v_reference text := btrim(p_reference);
  v_note text := btrim(p_note);
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert')
    or not private.has_permission(p_company,'sales','read') then
    raise exception 'Necesitás permisos de Finanzas y Ventas' using errcode='42501';
  end if;
  if p_sale is null or p_request_id is null or p_amount is null or p_amount <= 0
    or p_amount >= 10000000000000000 or p_amount <> round(p_amount,2)
    or p_method is null or p_method not in ('cash','transfer','card','check','other')
    or p_paid_on is null or v_reference is null or length(v_reference) > 100
    or v_note is null or length(v_note) > 500 then
    raise exception 'Revisá monto, fecha, medio de pago y referencia';
  end if;
  -- Bloquea cobros y anulaciones de una misma venta, también si hay dos operadores.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||p_sale::text,0));
  select * into v_existing from public.sale_payments
  where company_id=p_company and request_id=p_request_id;
  if found then
    if v_existing.actor_id <> auth.uid() or v_existing.sale_id <> p_sale
      or v_existing.amount <> p_amount or v_existing.method <> p_method
      or v_existing.paid_on <> p_paid_on or v_existing.reference <> v_reference
      or v_existing.note <> v_note then
      raise exception 'La solicitud ya fue utilizada con otros datos';
    end if;
    return v_existing.id;
  end if;
  select * into v_sale from public.sales where company_id=p_company and id=p_sale;
  if not found then raise exception 'Venta inexistente'; end if;
  select coalesce(sum(p.amount),0) into v_paid from public.sale_payments p
  where p.company_id=p_company and p.sale_id=p_sale
    and not exists(select 1 from public.sale_payment_reversals r
      where r.company_id=p.company_id and r.payment_id=p.id);
  if p_amount > v_sale.total-v_paid then
    raise exception 'El cobro supera el saldo pendiente de la venta';
  end if;
  insert into public.sale_payments(company_id,sale_id,request_id,amount,method,
    paid_on,reference,note,actor_id)
  values(p_company,p_sale,p_request_id,p_amount,p_method,
    p_paid_on,v_reference,v_note,auth.uid()) returning id into v_payment;
  return v_payment;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid; v_saved uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','insert') then
    raise exception 'Sin permiso para registrar cobros' using errcode='42501'; end if;
  perform 1 from public.treasury_accounts where company_id=p_company and id=p_account and active;
  if not found then raise exception 'Elegí una cuenta activa'; end if;
  v_id := public.post_sale_payment(p_company,p_sale,p_amount,p_method,p_paid_on,
    p_reference,p_note,p_request_id);
  select account_id into v_saved from public.treasury_sale_accounts
    where company_id=p_company and payment_id=v_id;
  if found and v_saved<>p_account then raise exception 'Este cobro ya pertenece a otra cuenta'; end if;
  insert into public.treasury_sale_accounts(company_id,payment_id,account_id,actor_id)
  values(p_company,v_id,p_account,auth.uid()) on conflict do nothing;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_reserved numeric; v_own numeric; v_usable numeric;
  v_slot_reserved numeric; v_slot_own numeric; v_slot_physical numeric;
  v_track boolean; v_lot uuid; v_expiry date;
  v_job uuid; v_operation uuid; v_infinite boolean; v_existing public.stock_operations%rowtype;
  v_today date := (now() at time zone 'America/Argentina/Buenos_Aires')::date;
begin
  if auth.uid() is null or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Sin permiso para registrar movimientos' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('production-reservations:'||p_company::text,0));
  if p_request_id is not null and exists (
    select 1 from public.stock_operations o
    where o.company_id=p_company and o.request_id=p_request_id
  ) then
    return private.post_stock_operation(p_company,p_item,p_warehouse,
      p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  end if;
  select i.infinite_stock into v_infinite from public.items i
    where i.company_id=p_company and i.id=p_item and i.active for share;
  if coalesce(v_infinite,false) then
    if p_request_id is null or p_warehouse is null or p_kind not in ('receipt','issue')
      or p_to_warehouse is not null or p_quantity is null or p_quantity<=0
      or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
      or length(btrim(coalesce(p_note,''))) not between 3 and 500
      or nullif(btrim(coalesce(p_lot_code,'')),'') is not null
      or p_expires_on is not null then
      raise exception 'Movimiento inválido para un ítem de stock infinito';
    end if;
    perform 1 from public.companies c where c.id=p_company and c.active for share;
    if not found then raise exception 'La empresa está suspendida'; end if;
    perform 1 from public.warehouses w where w.company_id=p_company
      and w.id=p_warehouse and w.active for share;
    if not found then raise exception 'Elegí un depósito activo'; end if;
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='issue' and not exists (
      select 1 from public.production_jobs j where j.company_id=p_company
        and j.id=v_job and j.status in ('queued','in_progress')) then
      raise exception 'Orden de fabricación no activa';
    end if;
    insert into public.stock_operations(company_id,request_id,item_id,warehouse_id,
      kind,quantity,note,actor_id)
    values(p_company,p_request_id,p_item,p_warehouse,p_kind,p_quantity,btrim(p_note),auth.uid())
    on conflict(company_id,request_id) do nothing returning id into v_operation;
    if v_operation is null then
      select * into v_existing from public.stock_operations o
        where o.company_id=p_company and o.request_id=p_request_id;
      if v_existing.item_id is distinct from p_item
        or v_existing.warehouse_id is distinct from p_warehouse
        or v_existing.to_warehouse_id is not null or v_existing.kind<>p_kind
        or v_existing.quantity<>p_quantity or v_existing.note<>btrim(p_note)
        or v_existing.actor_id<>auth.uid() then
        raise exception 'Esta solicitud ya se usó con otros datos';
      end if;
      return v_existing.id;
    end if;
    return v_operation;
  end if;
  perform private.rebalance_production_reservations(p_company);
  if p_kind in ('issue','transfer') and p_item is not null
    and p_warehouse is not null and p_quantity>0 then
    v_job:=nullif(pg_catalog.current_setting('dromux.production_job',true),'')::uuid;
    if v_job is not null and p_kind='issue' then
      perform 1 from public.production_jobs j where j.company_id=p_company
        and j.id=v_job and j.status in ('queued','in_progress');
      if not found then raise exception 'Orden de fabricación no activa'; end if;
    end if;
    select i.track_lots into v_track from public.items i
      where i.company_id=p_company and i.id=p_item;
    if v_track then
      select l.id,l.expires_on into v_lot,v_expiry from public.stock_lots l
        where l.company_id=p_company and l.item_id=p_item
          and lower(l.code)=lower(btrim(p_lot_code));
      if v_lot is null then raise exception 'Elegí un lote existente'; end if;
      if p_kind='issue' and v_expiry<v_today then
        raise exception 'El lote está vencido. Elegí uno vigente'; end if;
      select coalesce(b.quantity,0) into v_slot_physical
        from public.stock_lot_balances b where b.company_id=p_company
          and b.item_id=p_item and b.warehouse_id=p_warehouse and b.lot_id=v_lot;
    else
      select coalesce(b.quantity,0) into v_slot_physical
        from public.stock_balances b where b.company_id=p_company
          and b.item_id=p_item and b.warehouse_id=p_warehouse;
    end if;
    v_slot_physical:=coalesce(v_slot_physical,0);
    select coalesce(sum(a.quantity),0),
      coalesce(sum(a.quantity) filter(where a.job_id=v_job),0)
      into v_slot_reserved,v_slot_own
      from public.production_reservation_locations a
      join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
      where a.company_id=p_company and a.component_id=p_item
        and a.warehouse_id=p_warehouse
        and a.lot_id is not distinct from v_lot
        and j.status in ('queued','in_progress');
    if p_quantity>greatest(0,v_slot_physical-v_slot_reserved
      +case when p_kind='issue' then v_slot_own else 0 end) then
      raise exception 'Stock libre insuficiente en el depósito y lote elegidos';
    end if;
    if p_kind='issue' then
      select coalesce(sum(a.quantity),0),
        coalesce(sum(a.quantity) filter(where a.job_id=v_job),0)
        into v_reserved,v_own from public.production_reservation_locations a
        join public.production_jobs j on j.company_id=a.company_id and j.id=a.job_id
        where a.company_id=p_company and a.component_id=p_item
          and j.status in ('queued','in_progress');
      if v_track then
        select coalesce(sum(lb.quantity),0) into v_usable
          from public.stock_lot_balances lb
          join public.warehouses w on w.company_id=lb.company_id
            and w.id=lb.warehouse_id and w.active
          join public.stock_lots l on l.company_id=lb.company_id
            and l.item_id=lb.item_id and l.id=lb.lot_id
          where lb.company_id=p_company and lb.item_id=p_item
            and (l.expires_on is null or l.expires_on>=v_today);
      else
        select coalesce(sum(b.quantity),0) into v_usable
          from public.stock_balances b
          join public.warehouses w on w.company_id=b.company_id
            and w.id=b.warehouse_id and w.active
          where b.company_id=p_company and b.item_id=p_item;
      end if;
      if p_quantity>greatest(0,v_usable-v_reserved+v_own) then
        raise exception 'Stock comprometido para fabricación: saldo libre insuficiente';
      end if;
    end if;
  end if;
  v_operation:=private.post_stock_operation(p_company,p_item,p_warehouse,
    p_to_warehouse,p_kind,p_quantity,p_note,p_request_id,p_lot_code,p_expires_on);
  if p_kind in ('receipt','issue','transfer') then
    perform private.rebalance_production_reservations(p_company);
  end if;
  return v_operation;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.preview_item_import(p_company uuid, p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return private.prepare_item_import(p_company,p_rows);
end; $function$
;
CREATE OR REPLACE FUNCTION public.production_formula_cost(p_company uuid, p_product uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','read') then
    raise exception 'Sin permiso para consultar costos' using errcode='42501';
  end if;
  return private.production_unit_cost(p_company,p_product);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.purchase_item_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para consultar ítems de compra' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol
    from public.items i
    join public.units u on u.company_id = i.company_id and u.id = i.unit_id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%'
        or i.barcode ilike '%' || p_search || '%')
    order by i.name, i.id
    limit 30;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.purchase_material_options(p_company uuid, p_search text DEFAULT ''::text, p_supplier uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, item_type text, reference_unit_cost numeric, supplier_unit_price numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.purchase_receivable_lines(p_company uuid, p_order uuid)
 RETURNS TABLE(line_no smallint, item_id uuid, item_code text, item_name text, unit_symbol text, quantity numeric, received_quantity numeric, unit_price numeric, track_lots boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'purchases', 'read') then
    raise exception 'Sin permiso para consultar órdenes' using errcode = '42501';
  end if;
  return query
    select l.line_no, l.item_id, l.item_code, l.item_name,
      l.unit_symbol, l.quantity, l.received_quantity, l.unit_price,
      i.track_lots
    from public.purchase_order_lines l
    join public.items i on i.company_id = l.company_id and i.id = l.item_id
    where l.company_id = p_company and l.order_id = p_order
    order by l.line_no;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.purchase_supplier_quotes(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, unit_symbol text, reference_unit_cost numeric, unit_price numeric, supplier_sku text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.purchase_suppliers_for_items(p_company uuid, p_items uuid[])
 RETURNS TABLE(id uuid, name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.recalculate_production_reservations(p_company uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','read')
    or not private.has_permission(p_company,'stock','read') then
    raise exception 'Necesitás acceso a producción y stock' using errcode='42501';
  end if;
  perform private.rebalance_production_reservations(p_company);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note text := btrim(p_note);
  v_order public.purchase_orders%rowtype;
  v_existing public.purchase_receipts%rowtype;
  v_receipt uuid;
  v_entry jsonb;
  v_line_no smallint;
  v_item uuid;
  v_order_quantity numeric(18, 6);
  v_received numeric(18, 6);
  v_price numeric(18, 2);
  v_quantity numeric(18, 6);
  v_warehouse uuid;
  v_warehouse_code text;
  v_lot_code text;
  v_expires date;
  v_operation uuid;
  v_count integer := 0;
begin
  if auth.uid() is null
     or not private.has_permission(p_company, 'purchases', 'insert')
     or not private.has_permission(p_company, 'stock', 'insert') then
    raise exception 'Sin permiso para recibir compras y registrar stock'
      using errcode = '42501';
  end if;

  if p_request_id is null or p_order is null or v_note is null
     or length(v_note) not between 3 and 430
     or jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Datos de recepción inválidos';
  end if;

  perform 1 from public.companies c
  where c.id = p_company and c.active for share;
  if not found then raise exception 'La empresa no está activa'; end if;

  -- Todas las recepciones de una orden compiten por la misma fila.
  select * into v_order from public.purchase_orders o
  where o.company_id = p_company and o.id = p_order for update;
  if not found then raise exception 'Orden inexistente'; end if;

  select * into v_existing from public.purchase_receipts r
  where r.company_id = p_company and r.request_id = p_request_id;
  if found then
    if v_existing.order_id is distinct from p_order
       or v_existing.actor_id is distinct from auth.uid()
       or v_existing.note is distinct from v_note
       or v_existing.request_payload is distinct from p_lines then
      raise exception 'Esta solicitud ya se usó con otros datos';
    end if;
    return v_existing.id;
  end if;

  if v_order.status not in ('open', 'partial') then
    raise exception 'La orden ya no admite recepciones';
  end if;

  insert into public.purchase_receipts(
    company_id, order_id, request_id, request_payload, note, actor_id
  ) values (p_company, p_order, p_request_id, p_lines, v_note, auth.uid())
  returning id into v_receipt;

  for v_entry in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(v_entry) is distinct from 'object'
       or coalesce(v_entry->>'line_no', '') !~ '^[1-9][0-9]?$'
       or coalesce(v_entry->>'quantity', '') !~ '^[0-9]+(\.[0-9]{1,6})?$'
       or coalesce(v_entry->>'warehouse_id', '') !~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or length(coalesce(v_entry->>'lot_code', '')) > 80
       or (v_entry->>'expires_on' is not null
         and (v_entry->>'expires_on') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') then
      raise exception 'Línea de recepción inválida';
    end if;

    v_line_no := (v_entry->>'line_no')::smallint;
    v_quantity := (v_entry->>'quantity')::numeric;
    v_warehouse := (v_entry->>'warehouse_id')::uuid;
    v_lot_code := nullif(btrim(v_entry->>'lot_code'), '');
    v_expires := nullif(v_entry->>'expires_on', '')::date;

    if v_quantity <= 0 or v_quantity >= 1000000000000 then
      raise exception 'La cantidad debe ser mayor a cero';
    end if;

    select l.item_id, l.quantity, l.received_quantity, l.unit_price
    into v_item, v_order_quantity, v_received, v_price
    from public.purchase_order_lines l
    where l.company_id = p_company and l.order_id = p_order
      and l.line_no = v_line_no for update;
    if not found then raise exception 'Línea inexistente en la orden'; end if;
    if v_received + v_quantity > v_order_quantity then
      raise exception 'La cantidad supera lo pendiente en la línea %', v_line_no;
    end if;

    -- Reutiliza la operación transaccional y las reglas de depósito/lote.
    v_operation := public.post_stock_operation(
      p_company, v_item, v_warehouse, null, 'receipt', v_quantity,
      'Recepción OC #' || v_order.number::text || ' · ' || v_note,
      gen_random_uuid(), v_lot_code, v_expires
    );

    select op.lot_code, op.lot_expires_on
    into v_lot_code, v_expires
    from public.stock_operations op
    where op.company_id = p_company and op.id = v_operation;

    select w.code into v_warehouse_code from public.warehouses w
    where w.company_id = p_company and w.id = v_warehouse;

    insert into public.purchase_receipt_lines(
      company_id, receipt_id, order_id, line_no, item_id,
      warehouse_id, warehouse_code, quantity, unit_price, lot_code, expires_on,
      stock_operation_id
    ) values (
      p_company, v_receipt, p_order, v_line_no, v_item,
      v_warehouse, v_warehouse_code, v_quantity, v_price, v_lot_code, v_expires,
      v_operation
    );

    update public.purchase_order_lines l
    set received_quantity = l.received_quantity + v_quantity
    where l.company_id = p_company and l.order_id = p_order
      and l.line_no = v_line_no;

    v_count := v_count + 1;
  end loop;

  update public.purchase_orders o
  set status = case
    when not exists (
      select 1 from public.purchase_order_lines l
      where l.company_id = p_company and l.order_id = p_order
        and l.received_quantity < l.quantity
    ) then 'received' else 'partial' end
  where o.company_id = p_company and o.id = p_order;

  return v_receipt;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.restore_archived_record(p_company uuid, p_resource text, p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_target record; v_row jsonb;
begin
  select * into v_target from private.cleanup_target(p_resource);
  if not found then raise exception 'Recurso desconocido'; end if;
  if auth.uid() is null or not private.has_permission(p_company,v_target.permission,'delete') then
    raise exception 'Sin permiso para recuperar el registro' using errcode='42501'; end if;
  execute format('select to_jsonb(t) from public.%I t where company_id=$1 and %I=$2 and archived for update',v_target.table_name,v_target.id_field)
    into v_row using p_company,p_id;
  if v_row is null then raise exception 'No se encontró el registro archivado'; end if;
  if p_resource='items' and coalesce((v_row->>'archive_previous_active')::boolean,true) then
    perform 1 from public.exchange_rate_types t where t.company_id=p_company and (
      t.id=(v_row->>'reference_exchange_rate_type_id')::uuid or exists(
        select 1 from public.supplier_items q where q.company_id=p_company and q.item_id=p_id and q.exchange_rate_type_id=t.id)) for share;
    if exists(select 1 from public.exchange_rate_types t where t.company_id=p_company and not t.active and (
      t.id=(v_row->>'reference_exchange_rate_type_id')::uuid or exists(
        select 1 from public.supplier_items q where q.company_id=p_company and q.item_id=p_id and q.exchange_rate_type_id=t.id))) then
      raise exception 'Recuperá primero los tipos de dólar que usa este ítem'; end if;
  elsif p_resource='formulas' then
    perform 1 from public.items i where i.company_id=p_company and (i.id=p_id or exists(
      select 1 from public.production_formula_lines l where l.company_id=p_company and l.product_id=p_id and l.component_id=i.id)) for share;
    if exists(select 1 from public.items i where i.company_id=p_company and not i.active and (i.id=p_id or exists(
      select 1 from public.production_formula_lines l where l.company_id=p_company and l.product_id=p_id and l.component_id=i.id))) then
      raise exception 'Recuperá o activá primero el producto y sus componentes'; end if;
  end if;
  if p_resource in ('items','exchange_types') then
    execute format('update public.%I set archived=false,active=coalesce(archive_previous_active,true),archive_previous_active=null where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field)
      using p_company,p_id;
  else
    execute format('update public.%I set archived=false where company_id=$1 and %I=$2',v_target.table_name,v_target.id_field) using p_company,p_id;
  end if;
end; $function$
;
CREATE OR REPLACE FUNCTION public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype;
  v_issue public.production_job_events%rowtype;
  v_previous public.production_job_events%rowtype;
  v_open numeric; v_expiry date; v_operation uuid; v_event uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update')
    or not private.has_permission(p_company,'stock','insert') then
    raise exception 'Necesitás permiso para devolver insumos al stock' using errcode='42501'; end if;
  if p_request_id is null or p_quantity is null or p_quantity<=0
    or p_quantity>=1000000000000 or p_quantity<>round(p_quantity,6)
    or length(btrim(coalesce(p_note,''))) not between 3 and 300 then
    raise exception 'Revisá cantidad y motivo de devolución'; end if;
  select * into v_job from public.production_jobs
    where company_id=p_company and id=p_job for update;
  if not found then raise exception 'Orden inexistente'; end if;
  select * into v_previous from public.production_job_events
    where company_id=p_company and request_id=p_request_id;
  if found then
    if v_previous.actor_id<>auth.uid() or v_previous.kind<>'return'
      or v_previous.job_id<>p_job or v_previous.issue_id<>p_issue
      or v_previous.quantity<>p_quantity or v_previous.note<>btrim(p_note) then
      raise exception 'Esta solicitud ya se usó con otros datos'; end if;
    return v_previous.id;
  end if;
  if v_job.status<>'in_progress' then raise exception 'La orden ya no admite devoluciones'; end if;
  select * into v_issue from public.production_job_events
    where company_id=p_company and job_id=p_job and id=p_issue and kind='issue';
  if not found then raise exception 'Elegí una salida de insumo de esta orden'; end if;
  select v_issue.quantity-coalesce(sum(e.quantity),0) into v_open
    from public.production_job_events e
    where e.company_id=p_company and e.issue_id=p_issue and e.kind='return';
  if p_quantity>v_open then raise exception 'La devolución supera el saldo de esa salida'; end if;
  if v_issue.lot_code is not null then
    select l.expires_on into v_expiry from public.stock_lots l
      where l.company_id=p_company and l.item_id=v_issue.component_id
        and lower(l.code)=lower(v_issue.lot_code);
    if not found then raise exception 'No se encuentra el lote de origen'; end if;
  end if;
  v_operation:=public.post_stock_operation(p_company,v_issue.component_id,
    v_issue.warehouse_id,null,'receipt',p_quantity,
    'Devolución orden '||p_job::text,gen_random_uuid(),v_issue.lot_code,v_expiry);
  insert into public.production_job_events(company_id,job_id,request_id,kind,
    issue_id,component_id,warehouse_id,lot_code,quantity,unit_cost,
    stock_operation_id,note,actor_id)
  values(p_company,p_job,p_request_id,'return',p_issue,v_issue.component_id,
    v_issue.warehouse_id,v_issue.lot_code,p_quantity,v_issue.unit_cost,
    v_operation,btrim(p_note),auth.uid()) returning id into v_event;
  return v_event;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_payment public.sale_payments%rowtype;
  v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','update') then
    raise exception 'Sin permiso para anular cobros' using errcode='42501';
  end if;
  if p_payment is null or p_reason is null or length(btrim(p_reason)) not between 5 and 300 then
    raise exception 'Indicá un motivo de anulación de al menos cinco caracteres';
  end if;
  select * into v_payment from public.sale_payments
    where company_id=p_company and id=p_payment;
  if not found then raise exception 'Cobro inexistente'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('receivable:'||p_company::text||':'||v_payment.sale_id::text,0));
  if exists(select 1 from public.sale_payment_reversals
    where company_id=p_company and payment_id=p_payment) then
    raise exception 'Este cobro ya fue anulado';
  end if;
  insert into public.sale_payment_reversals(company_id,sale_id,payment_id,reason,actor_id)
  values(p_company,v_payment.sale_id,p_payment,btrim(p_reason),auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.revoke_company_invitation(p_company uuid, p_invitation uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'users', 'delete') then
    raise exception 'Sin permiso para revocar invitaciones' using errcode = '42501';
  end if;
  update public.company_invitations set revoked_at = now()
  where id = p_invitation and company_id = p_company
    and used_at is null and revoked_at is null;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$
;
CREATE OR REPLACE FUNCTION public.sale_credit_balance(p_company uuid, p_sale uuid)
 RETURNS TABLE(net_total numeric, paid numeric, refunded numeric, credit_due numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.sale_receivables(p_company uuid, p_page integer DEFAULT 0, p_search text DEFAULT ''::text)
 RETURNS TABLE(sale_id uuid, sale_number bigint, customer_name text, total numeric, paid numeric, outstanding numeric, created_at timestamp with time zone, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_preserve_cost boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_old public.items%rowtype; v_row jsonb; v_supplier uuid; v_fx uuid; v_usd numeric;
  v_primary boolean; v_id uuid; v_unit_code text; v_category_code text;
begin
  if auth.uid() is null or not private.has_permission(p_company,'items',
    case when p_item is null then 'insert' else 'update' end) then
    raise exception 'Sin permiso para guardar el ítem' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('import-items:'||p_company::text,0));
  if p_item is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('preferred:'||p_company::text||':'||p_item::text,0));
    select * into v_old from public.items where company_id=p_company and id=p_item for update;
    if not found then raise exception 'El ítem no existe en esta empresa'; end if;
    if p_expected_updated_at is null or v_old.updated_at<>p_expected_updated_at then
      raise exception 'La ficha cambió mientras la editabas. Recargá antes de guardar'; end if;
  end if;
  -- El formulario selecciona IDs; Excel usa códigos/nombres. Resolverlos siempre en la empresa.
  select u.code into v_unit_code from public.units u
    where u.company_id=p_company and u.id=nullif(p_row->>'unit_id','')::uuid;
  select c.code into v_category_code from public.item_categories c
    where c.company_id=p_company and c.id=nullif(p_row->>'category_id','')::uuid;
  if nullif(p_row->>'category_id','') is not null and v_category_code is null then
    raise exception 'La categoría no pertenece a esta empresa'; end if;
  v_row:=p_row || jsonb_build_object('unidad_codigo',v_unit_code,'categoria_codigo',coalesce(v_category_code,''));
  if nullif(p_row->>'supplier_id','') is not null then
    select s.name into v_unit_code from public.suppliers s where s.company_id=p_company
      and s.id=(p_row->>'supplier_id')::uuid and s.active;
    if not found then raise exception 'Elegí un proveedor activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('proveedor',v_unit_code);
  end if;
  if nullif(p_row->>'exchange_type_id','') is not null then
    select t.name into v_unit_code from public.exchange_rate_types t where t.company_id=p_company
      and t.id=(p_row->>'exchange_type_id')::uuid and t.active;
    if not found then raise exception 'Elegí un tipo de dólar activo de esta empresa'; end if;
    v_row:=v_row || jsonb_build_object('tipo_dolar',v_unit_code);
  end if;
  select exists(select 1 from public.supplier_items q where q.company_id=p_company
    and q.item_id=p_item and q.preferred) into v_primary;
  if p_item is not null and (p_preserve_cost or v_primary) and nullif(p_row->>'supplier_id','') is null then
    v_row:=v_row || jsonb_build_object('costo_referencia_ars',v_old.reference_unit_cost,
      'costo_usd','','tipo_dolar','');
  end if;
  v_row:=private.prepare_item_import(p_company,jsonb_build_array(v_row),p_item)->0;
  v_supplier:=nullif(v_row->>'supplier_id','')::uuid;
  v_fx:=nullif(v_row->>'exchange_type_id','')::uuid;
  v_usd:=nullif(v_row->>'cost_usd','')::numeric;
  if p_item is null then
    -- Importación de una fila reutiliza las mismas reglas y triggers.
    perform public.import_items(p_company,jsonb_build_array(v_row));
    select id into v_id from public.items where company_id=p_company and code=btrim(v_row->>'codigo');
    return v_id;
  end if;
  update public.items set code=btrim(v_row->>'codigo'),name=btrim(v_row->>'nombre'),
    item_type=v_row->>'tipo',category_id=nullif(v_row->>'category_id','')::uuid,
    unit_id=(v_row->>'unit_id')::uuid,barcode=nullif(btrim(v_row->>'codigo_barras'),''),
    description=btrim(v_row->>'descripcion'),minimum_stock=(v_row->>'stock_minimo')::numeric,
    track_lots=(v_row->>'seguir_lotes')::boolean,infinite_stock=(v_row->>'stock_infinito')::boolean,
    reference_unit_cost=case when v_primary or p_preserve_cost then v_old.reference_unit_cost else nullif(v_row->>'cost_ars','')::numeric end,
    reference_cost_usd=case when v_primary or p_preserve_cost then v_old.reference_cost_usd
      when v_supplier is null then v_usd end,
    reference_exchange_rate_type_id=case when v_primary or p_preserve_cost then v_old.reference_exchange_rate_type_id
      when v_supplier is null then v_fx end
    where company_id=p_company and id=p_item;
  if v_supplier is not null then
    perform public.save_supplier_quote(p_company,v_supplier,p_item,
      coalesce(v_usd,(v_row->>'cost_ars')::numeric),'',
      case when v_usd is null then 'ARS' else 'USD' end,v_fx,0,null,true);
    if not v_primary then perform public.set_preferred_supplier(p_company,p_item,v_supplier); end if;
  end if;
  return p_item;
end; $function$
;
CREATE OR REPLACE FUNCTION public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_label jsonb;
begin
  if auth.uid() is null or private.get_user_role(p_company) is distinct from 'admin' then
    raise exception 'Solo el administrador configura el formato' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if p_logo is null or length(p_logo)>120000 or length(btrim(coalesce(p_code,''))) not between 1 and 40
    or length(btrim(coalesce(p_revision,''))) not between 1 and 20
    or p_labels is null or jsonb_typeof(p_labels)<>'array' or jsonb_array_length(p_labels)>12 then
    raise exception 'Revisá logo, código, revisión y hasta doce campos'; end if;
  if p_logo<>'' and p_logo !~ '^data:image/png;base64,[A-Za-z0-9+/]+={0,2}$' then
    raise exception 'El logo debe ser PNG'; end if;
  if p_logo<>'' and encode(substring(decode(split_part(p_logo,',',2),'base64') from 1 for 8),'hex')<>'89504e470d0a1a0a' then
    raise exception 'El archivo no es un logo PNG válido'; end if;
  for v_label in select value from jsonb_array_elements(p_labels) loop
    if jsonb_typeof(v_label)<>'string' or length(btrim(v_label#>>'{}')) not between 2 and 80 then
      raise exception 'Cada título debe tener entre 2 y 80 caracteres'; end if;
  end loop;
  if (select count(distinct lower(btrim(value))) from jsonb_array_elements_text(p_labels))<>jsonb_array_length(p_labels) then
    raise exception 'No repitas títulos de observaciones'; end if;
  insert into public.production_document_settings(company_id,logo_data,document_code,revision,observation_labels)
    values(p_company,p_logo,btrim(p_code),btrim(p_revision),p_labels)
  on conflict(company_id) do update set logo_data=excluded.logo_data,document_code=excluded.document_code,
    revision=excluded.revision,observation_labels=excluded.observation_labels,updated_at=clock_timestamp();
end; $function$
;
CREATE OR REPLACE FUNCTION public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_line jsonb;
  v_component uuid;
  v_quantity numeric;
  v_version integer;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501';
  end if;
  if p_batch_quantity is null or p_batch_quantity <= 0 or p_batch_quantity >= 1000000000000
    or p_batch_quantity <> round(p_batch_quantity,6)
    or p_lines is null or jsonb_typeof(p_lines) <> 'array'
    or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'Indicá rendimiento y componentes válidos';
  end if;
  -- Una sola edición de fórmulas por empresa evita ciclos por escrituras simultáneas.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('formula:'||p_company::text,0));
  perform 1 from public.items i where i.company_id=p_company and i.id=p_product
    and i.active and i.item_type in ('finished_product','semi_finished') for share;
  if not found then raise exception 'Elegí un producto terminado o semielaborado activo'; end if;
  insert into public.production_formulas(company_id,product_id,batch_quantity)
  values(p_company,p_product,p_batch_quantity)
  on conflict(company_id,product_id) do update set
    batch_quantity=excluded.batch_quantity,version=production_formulas.version+1,updated_at=now()
  returning version into v_version;
  delete from public.production_formula_lines where company_id=p_company and product_id=p_product;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_component := (v_line->>'component_id')::uuid;
    v_quantity := (v_line->>'quantity')::numeric;
    if v_quantity is null or v_quantity <= 0 or v_quantity >= 1000000000000
      or v_quantity <> round(v_quantity,6) then raise exception 'Cantidad de componente inválida'; end if;
    perform 1 from public.items i where i.company_id=p_company and i.id=v_component
      and i.active and i.item_type in ('raw_material','semi_finished','consumable') for share;
    if not found then raise exception 'Elegí materias primas, semielaborados o insumos activos'; end if;
    insert into public.production_formula_lines(company_id,product_id,component_id,quantity)
    values(p_company,p_product,v_component,v_quantity);
  end loop;
  -- Calcula recursivamente y revierte la transacción si aparece un ciclo o falta un costo.
  perform private.production_unit_cost(p_company,p_product);
  return v_version;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para editar fórmulas' using errcode='42501'; end if;
  if p_yield_enabled is null or p_yield_factor is null or p_yield_factor<=0 or p_yield_factor>1000
    or p_yield_factor<>round(p_yield_factor,6) then raise exception 'Factor de rendimiento inválido'; end if;
  perform public.save_production_formula(p_company,p_product,p_batch_quantity,p_lines);
  update public.items set yield_enabled=p_yield_enabled,
    yield_factor=case when p_yield_enabled then p_yield_factor else 1 end
    where company_id=p_company and id=p_product;
end; $function$
;
CREATE OR REPLACE FUNCTION public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para gestionar envasados' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  if length(btrim(coalesce(p_name,''))) not between 2 and 100 or p_capacity is null or p_capacity<=0
    or p_capacity>=1000000000000 or p_capacity<>round(p_capacity,6) or p_active is null then
    raise exception 'Nombre y capacidad inválidos'; end if;
  perform 1 from public.units where company_id=p_company and id=p_unit and active;
  if not found then raise exception 'Elegí una unidad activa'; end if;
  if p_id is null then
    insert into public.production_packaging_types(company_id,name,capacity,unit_id,active)
      values(p_company,btrim(p_name),p_capacity,p_unit,p_active) returning id into v_id;
  else
    update public.production_packaging_types set name=btrim(p_name),capacity=p_capacity,unit_id=p_unit,active=p_active
      where company_id=p_company and id=p_id returning id into v_id;
    if v_id is null then raise exception 'Envasado inexistente'; end if;
  end if;
  return v_id;
end; $function$
;
CREATE OR REPLACE FUNCTION public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_job public.production_jobs%rowtype; v_pack jsonb; v_result jsonb:='[]'; v_count numeric;
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para actualizar la orden' using errcode='42501'; end if;
  perform 1 from public.companies where id=p_company and active for share;
  if not found then raise exception 'La empresa está suspendida'; end if;
  select * into v_job from public.production_jobs where company_id=p_company and id=p_job for update;
  if not found or v_job.status='cancelled' then raise exception 'Orden inexistente o cancelada'; end if;
  if p_expected is null or v_job.details_updated_at<>p_expected then raise exception 'Los controles cambiaron. Reabrí el formulario'; end if;
  if jsonb_typeof(p_counts) is distinct from 'object' or jsonb_typeof(p_observations) is distinct from 'object'
    or length(p_observations::text)>10000 or length(p_counts::text)>5000 then raise exception 'Datos de controles inválidos'; end if;
  if exists(select 1 from jsonb_each(p_observations) e where jsonb_typeof(e.value)<>'string'
    or length(e.value#>>'{}')>500 or not (coalesce(v_job.document_snapshot->'labels','[]') ? e.key)) then
    raise exception 'Usá los campos originales de la orden'; end if;
  if exists(select 1 from jsonb_each(p_counts) e where not exists(
    select 1 from jsonb_array_elements(coalesce(v_job.work_options->'packaging','[]')) x where x->>'id'=e.key)) then
    raise exception 'Envasado no asociado a esta orden'; end if;
  for v_pack in select value from jsonb_array_elements(coalesce(v_job.work_options->'packaging','[]')) loop
    v_count:=nullif(p_counts->>(v_pack->>'id'),'')::numeric;
    if v_count is not null and (v_count<0 or v_count>=1000000000 or v_count<>trunc(v_count)) then
      raise exception 'La cantidad real de envases debe ser entera y no negativa'; end if;
    v_result:=v_result||jsonb_build_array(v_pack||jsonb_build_object('actual_count',v_count));
  end loop;
  update public.production_jobs set work_options=jsonb_build_object('packaging',v_result,'observations',p_observations),
    details_updated_at=clock_timestamp() where company_id=p_company and id=p_job;
end; $function$
;
CREATE OR REPLACE FUNCTION public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_create_only boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_quote public.supplier_items%rowtype;
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','update') then
    raise exception 'Sin permiso para elegir proveedor principal' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('preferred:'||p_company::text||':'||p_item::text,0));
  select * into v_quote from public.supplier_items
    where company_id=p_company and item_id=p_item and supplier_id=p_supplier;
  if not found then raise exception 'Cotización inexistente'; end if;
  perform 1 from public.suppliers where company_id=p_company and id=p_supplier and active;
  if not found then raise exception 'Elegí un proveedor activo'; end if;
  if v_quote.currency_code='USD' and
    private.current_fx_rate(p_company,v_quote.exchange_rate_type_id) is null then
    raise exception 'Cargá primero la cotización de ese dólar';
  end if;
  update public.supplier_items set preferred=false
    where company_id=p_company and item_id=p_item and preferred;
  update public.supplier_items set preferred=true
    where company_id=p_company and item_id=p_item and supplier_id=p_supplier;
  perform private.sync_preferred_material_cost(p_company,p_item);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.start_production_job(p_company uuid, p_job uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'production','update') then
    raise exception 'Sin permiso para iniciar fabricación' using errcode='42501'; end if;
  update public.production_jobs set status='in_progress',started_at=clock_timestamp()
    where company_id=p_company and id=p_job and status='queued';
  if not found and not exists(select 1 from public.production_jobs
    where company_id=p_company and id=p_job and status='in_progress') then
    raise exception 'La orden no está pendiente'; end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.stock_item_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text, unit_symbol text, barcode text, track_lots boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para ver ítems de stock' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.barcode, i.track_lots
    from public.items i
    join public.units u on u.id = i.unit_id and u.company_id = i.company_id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%'
        or i.barcode ilike '%' || p_search || '%')
    order by i.name, i.id
    limit 30;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.stock_lot_breakdown(p_company uuid, p_item uuid)
 RETURNS TABLE(warehouse_id uuid, warehouse_name text, lot_code text, expires_on date, quantity numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select b.warehouse_id, w.name, l.code, l.expires_on, b.quantity
    from public.stock_lot_balances b
    join public.stock_lots l on l.id = b.lot_id
      and l.company_id = b.company_id and l.item_id = b.item_id
    join public.warehouses w on w.id = b.warehouse_id
      and w.company_id = b.company_id
    where b.company_id = p_company and b.item_id = p_item and b.quantity > 0
    order by w.name, l.expires_on nulls last, l.code
    limit 500;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, code text, expires_on date, available numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar lotes' using errcode = '42501';
  end if;
  return query
    select l.id, l.code, l.expires_on,
      coalesce(sum(b.quantity), 0)::numeric
    from public.stock_lots l
    left join public.stock_lot_balances b
      on b.company_id = l.company_id and b.item_id = l.item_id
      and b.lot_id = l.id
      and (p_warehouse is null or b.warehouse_id = p_warehouse)
    where l.company_id = p_company and l.item_id = p_item
    group by l.id
    order by l.expires_on nulls last, l.code
    limit 200;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.stock_summary(p_company uuid, p_page integer DEFAULT 0, p_search text DEFAULT ''::text)
 RETURNS TABLE(item_id uuid, item_code text, item_name text, unit_symbol text, track_lots boolean, minimum_stock numeric, total_quantity numeric, warehouse_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para consultar stock' using errcode = '42501';
  end if;
  if p_page is null or p_page < 0 or p_page > 100000
     or length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda inválida';
  end if;
  return query
    select i.id, i.code, i.name, u.symbol, i.track_lots, i.minimum_stock,
           coalesce(sum(b.quantity), 0)::numeric,
           count(b.warehouse_id) filter (where b.quantity > 0),
           count(*) over ()
    from public.items i
    join public.units u on u.id = i.unit_id and u.company_id = i.company_id
    left join public.stock_balances b
      on b.company_id = i.company_id and b.item_id = i.id
    where i.company_id = p_company and i.active
      and (coalesce(p_search, '') = ''
        or i.name ilike '%' || p_search || '%'
        or i.code ilike '%' || p_search || '%')
    group by i.id, u.symbol
    order by i.name, i.id
    limit 25 offset p_page * 25;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.stock_warehouse_options(p_company uuid, p_search text DEFAULT ''::text)
 RETURNS TABLE(id uuid, code text, name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.has_permission(p_company, 'stock', 'read') then
    raise exception 'Sin permiso para ver depósitos' using errcode = '42501';
  end if;
  if length(coalesce(p_search, '')) > 100 then
    raise exception 'Búsqueda demasiado larga';
  end if;
  return query
    select w.id, w.code, w.name
    from public.warehouses w
    where w.company_id = p_company and w.active
      and (coalesce(p_search, '') = ''
        or w.name ilike '%' || p_search || '%'
        or w.code ilike '%' || p_search || '%')
    order by w.name, w.id
    limit 30;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.supplier_cost_comparison(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, unit_symbol text, unit_price numeric, currency_code text, exchange_rate_type_id uuid, exchange_rate_type text, exchange_rate numeric, adjustment_percent numeric, unit_cost_ars numeric, preferred boolean, supplier_sku text, updated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'purchases','read') then
    raise exception 'Sin permiso para comparar costos' using errcode='42501'; end if;
  return query select si.supplier_id,s.name,s.active,si.item_id,i.code,i.name,u.symbol,
    si.unit_price,si.currency_code,si.exchange_rate_type_id,fx.name,
    case when si.currency_code='USD' then private.current_fx_rate(p_company,si.exchange_rate_type_id)
      else 1::numeric end,
    si.adjustment_percent,
    case when si.currency_code='USD' then
      round(si.unit_price*private.current_fx_rate(p_company,si.exchange_rate_type_id)
        *(1+si.adjustment_percent/100),2)
    else round(si.unit_price*(1+si.adjustment_percent/100),2) end,
    si.preferred,si.supplier_sku,si.updated_at
  from public.supplier_items si
  join public.suppliers s on s.company_id=si.company_id and s.id=si.supplier_id
  join public.items i on i.company_id=si.company_id and i.id=si.item_id
  join public.units u on u.company_id=i.company_id and u.id=i.unit_id
  left join public.exchange_rate_types fx on fx.company_id=si.company_id
    and fx.id=si.exchange_rate_type_id
  where si.company_id=p_company and (p_supplier is null or si.supplier_id=p_supplier)
    and (p_item is null or si.item_id=p_item)
  order by i.name,si.preferred desc,si.unit_price,s.name limit 500;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.supplier_directory(p_company uuid, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(id uuid, name text, tax_id text, email text, phone text, notes text, active boolean, lead_time_days integer, supplies_description text, item_count bigint, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.supplier_quote_catalog(p_company uuid, p_supplier uuid DEFAULT NULL::uuid, p_item uuid DEFAULT NULL::uuid, p_search text DEFAULT ''::text, p_page integer DEFAULT 0)
 RETURNS TABLE(supplier_id uuid, supplier_name text, supplier_active boolean, item_id uuid, item_code text, item_name text, item_type text, item_active boolean, unit_symbol text, unit_price numeric, currency_code text, exchange_rate_type_id uuid, exchange_rate_type text, exchange_rate numeric, adjustment_percent numeric, unit_cost_ars numeric, preferred boolean, supplier_sku text, updated_at timestamp with time zone, is_best_price boolean, total_count bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end; $function$
;
CREATE OR REPLACE FUNCTION public.treasury_activity(p_company uuid)
 RETURNS TABLE(id uuid, account_id uuid, kind text, amount numeric, note text, occurred_on date, created_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read') then
    raise exception 'Sin permiso para consultar tesorería' using errcode='42501'; end if;
  return query select x.id,x.account_id,x.kind,x.amount,x.note,x.occurred_on,x.created_at
  from (
    select t.id,t.account_id,t.kind,t.amount,t.note,t.occurred_on,t.created_at
      from public.treasury_entries t where t.company_id=p_company
    union all
    select sp.id,psa.account_id,
      case when r.payment_id is null then 'customer_payment' else 'annulled_payment' end,
      case when r.payment_id is null then sp.amount else 0::numeric end,
      'Venta Nº '||s.number::text||' · '||s.customer_name,
      sp.paid_on,sp.created_at
    from public.treasury_sale_accounts psa
    join public.sale_payments sp on sp.company_id=psa.company_id and sp.id=psa.payment_id
    join public.sales s on s.company_id=sp.company_id and s.id=sp.sale_id
    left join public.sale_payment_reversals r on r.company_id=sp.company_id
      and r.payment_id=sp.id
    where psa.company_id=p_company
  ) x order by x.created_at desc limit 100;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.treasury_balances(p_company uuid)
 RETURNS TABLE(account_id uuid, name text, kind text, active boolean, opening_balance numeric, income numeric, expense numeric, balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if auth.uid() is null or not private.has_permission(p_company,'finance','read') then
    raise exception 'Sin permiso para consultar tesorería' using errcode='42501'; end if;
  return query select a.id,a.name,a.kind,a.active,a.opening_balance,
    coalesce(e.credits,0)+coalesce(p.credits,0),coalesce(e.debits,0),
    a.opening_balance+coalesce(e.credits,0)+coalesce(p.credits,0)-coalesce(e.debits,0)
  from public.treasury_accounts a
  left join lateral (select
    coalesce(sum(t.amount) filter(where t.kind in ('income','transfer_in')),0) credits,
    coalesce(sum(t.amount) filter(where t.kind in ('expense','supplier_payment','transfer_out')),0) debits
    from public.treasury_entries t where t.company_id=a.company_id and t.account_id=a.id) e on true
  left join lateral (select coalesce(sum(sp.amount),0) credits
    from public.treasury_sale_accounts psa join public.sale_payments sp
      on sp.company_id=psa.company_id and sp.id=psa.payment_id
    where psa.company_id=a.company_id and psa.account_id=a.id and not exists(
      select 1 from public.sale_payment_reversals spr
      where spr.company_id=sp.company_id and spr.payment_id=sp.id)) p on true
  where a.company_id=p_company order by a.name;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_code text; v_name text := btrim(p_name);
begin
  if not private.has_permission(p_company, 'roles', 'update') then
    raise exception 'Sin permiso para editar roles' using errcode = '42501';
  end if;
  select code into v_code from public.roles
  where id = p_role and company_id = p_company for update;
  if v_code is null then raise exception 'Rol inexistente'; end if;
  if v_code = 'admin' then raise exception 'El rol administrador está protegido'; end if;
  if v_name is null or length(v_name) not between 2 and 60
     or jsonb_typeof(p_permissions) is distinct from 'array'
     or jsonb_array_length(p_permissions) > 100 then
    raise exception 'Datos del rol inválidos';
  end if;

  update public.roles set name = v_name where id = p_role;
  delete from public.role_permissions where role_id = p_role;
  insert into public.role_permissions(company_id, role_id, resource, action)
  select p_company, p_role, p.resource, p.action
  from jsonb_to_recordset(p_permissions) as p(resource text, action text)
  where p.resource in ('dashboard', 'inventory', 'production', 'purchases', 'sales',
                       'finance', 'reports', 'settings', 'users', 'roles',
                       'units', 'categories', 'warehouses', 'items', 'stock')
    and p.action in ('read', 'insert', 'update', 'delete', 'manage')
  on conflict do nothing;

  if (select count(*) from public.role_permissions where role_id = p_role)
     <> (select count(distinct (entry->>'resource', entry->>'action'))
         from jsonb_array_elements(p_permissions) as entry) then
    raise exception 'Permisos desconocidos o repetidos';
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.void_delivery_note(p_company uuid, p_note uuid, p_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_note public.delivery_notes%rowtype;
  v_line public.delivery_note_lines%rowtype;
  v_operation uuid;
  v_event uuid;
  v_expiry date;
begin
  if auth.uid() is null or not private.has_permission(p_company, 'stock', 'insert')
    or not private.has_permission(p_company, 'stock', 'delete') then
    raise exception 'Necesitás permiso para anular entregas y reingresar stock'
      using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_reason, ''))) not between 5 and 300 then
    raise exception 'Escribí un motivo de al menos cinco caracteres'; end if;
  select * into v_note from public.delivery_notes
    where company_id = p_company and id = p_note for update;
  if not found then raise exception 'Remito inexistente'; end if;
  if v_note.status = 'voided' then
    if v_note.void_reason <> btrim(p_reason) then
      raise exception 'El remito ya fue anulado con otro motivo'; end if;
    return v_note.id;
  end if;
  if v_note.kind = 'sale' then
    if not private.has_permission(p_company, 'sales', 'read') then
      raise exception 'Necesitás acceso a ventas' using errcode = '42501'; end if;
    update public.delivery_notes set status = 'voided',
      void_reason = btrim(p_reason), voided_at = clock_timestamp()
      where company_id = p_company and id = p_note;
    return p_note;
  end if;
  if v_note.kind = 'production' then
    if not private.has_permission(p_company, 'production', 'update') then
      raise exception 'Necesitás permiso para devolver insumos de producción'
        using errcode = '42501'; end if;
    perform 1 from public.production_jobs
      where company_id = p_company and id = v_note.job_id
        and status = 'in_progress' for update;
    if not found then
      raise exception 'La fabricación ya fue cerrada. No se puede anular esta entrega'; end if;
  end if;
  for v_line in select * from public.delivery_note_lines
    where company_id = p_company and note_id = p_note order by line_no loop
    if v_note.kind = 'production' then
      if exists(select 1 from public.production_job_events e
        where e.company_id = p_company and e.issue_id = v_line.production_event_id) then
        raise exception 'Ya se devolvió parte de esta entrega. Ajustá la orden manualmente';
      end if;
      v_event := public.return_production_material(p_company, v_note.job_id,
        v_line.production_event_id, v_line.quantity,
        'Anulación remito Nº ' || v_note.number || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid());
      select stock_operation_id into v_operation from public.production_job_events
        where company_id = p_company and id = v_event;
    else
      v_event := null;
      v_expiry := null;
      if v_line.lot_code is not null then
        select l.expires_on into v_expiry from public.stock_lots l
          where l.company_id = p_company and l.item_id = v_line.item_id
            and lower(l.code) = lower(v_line.lot_code);
        if not found then raise exception 'No se encuentra el lote de origen'; end if;
      end if;
      v_operation := public.post_stock_operation(p_company, v_line.item_id,
        v_line.warehouse_id, null, 'receipt', v_line.quantity,
        'Anulación remito Nº ' || v_note.number || ' · ' || left(btrim(p_reason), 245),
        gen_random_uuid(), v_line.lot_code, v_expiry);
    end if;
    insert into public.delivery_note_reversals(company_id, note_id, line_no,
      stock_operation_id, production_event_id)
    values (p_company, p_note, v_line.line_no, v_operation, v_event);
  end loop;
  update public.delivery_notes set status = 'voided',
    void_reason = btrim(p_reason), voided_at = clock_timestamp()
    where company_id = p_company and id = p_note;
  return p_note;
end;
$function$
;
alter table private.deleted_production_requests add constraint deleted_production_requests_pkey PRIMARY KEY (company_id, resource, request_id);
alter table private.production_job_numbers add constraint production_job_numbers_pkey PRIMARY KEY (company_id);
alter table private.supplier_payment_numbers add constraint supplier_payment_numbers_next_number_check CHECK ((next_number > 0));
alter table private.supplier_payment_numbers add constraint supplier_payment_numbers_pkey PRIMARY KEY (company_id);
alter table private.support_access_log add constraint support_access_log_pkey PRIMARY KEY (id);
alter table private.support_access_log add constraint support_access_log_reason_check CHECK (((length(btrim(reason)) >= 8) AND (length(btrim(reason)) <= 300)));
alter table private.support_operators add constraint support_operators_pkey PRIMARY KEY (user_id);
alter table private.support_sessions add constraint support_sessions_pkey PRIMARY KEY (user_id);
alter table public.companies add constraint companies_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 100)));
alter table public.companies add constraint companies_pkey PRIMARY KEY (id);
alter table public.companies add constraint companies_slug_key UNIQUE (slug);
alter table public.company_invitations add constraint company_invitations_email_check CHECK (((length(email) >= 3) AND (length(email) <= 320)));
alter table public.company_invitations add constraint company_invitations_pkey PRIMARY KEY (id);
alter table public.company_invitations add constraint company_invitations_token_hash_key UNIQUE (token_hash);
alter table public.company_modules add constraint company_modules_module_check CHECK ((module ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.company_modules add constraint company_modules_pkey PRIMARY KEY (company_id, module);
alter table public.company_settings add constraint company_settings_currency_code_check CHECK ((currency_code ~ '^[A-Z]{3}$'::text));
alter table public.company_settings add constraint company_settings_pkey PRIMARY KEY (company_id);
alter table public.company_users add constraint company_users_company_id_user_id_key UNIQUE (company_id, user_id);
alter table public.company_users add constraint company_users_pkey PRIMARY KEY (id);
alter table public.customers add constraint customers_address_check CHECK ((length(address) <= 240));
alter table public.customers add constraint customers_company_id_id_key UNIQUE (company_id, id);
alter table public.customers add constraint customers_email_check CHECK ((length(email) <= 160));
alter table public.customers add constraint customers_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 160)));
alter table public.customers add constraint customers_notes_check CHECK ((length(notes) <= 500));
alter table public.customers add constraint customers_phone_check CHECK ((length(phone) <= 40));
alter table public.customers add constraint customers_pkey PRIMARY KEY (id);
alter table public.customers add constraint customers_tax_id_check CHECK ((length(tax_id) <= 30));
alter table public.delivery_note_counters add constraint delivery_note_counters_next_number_check CHECK ((next_number > 0));
alter table public.delivery_note_counters add constraint delivery_note_counters_pkey PRIMARY KEY (company_id);
alter table public.delivery_note_lines add constraint delivery_note_lines_check CHECK (((sale_id IS NULL) = (sale_line_no IS NULL)));
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_production_event_id_key UNIQUE (company_id, production_event_id);
alter table public.delivery_note_lines add constraint delivery_note_lines_line_no_check CHECK (((line_no >= 1) AND (line_no <= 40)));
alter table public.delivery_note_lines add constraint delivery_note_lines_pkey PRIMARY KEY (company_id, note_id, line_no);
alter table public.delivery_note_lines add constraint delivery_note_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.delivery_note_reversals add constraint delivery_note_reversals_check CHECK (((sale_id IS NULL) = (sale_line_no IS NULL)));
alter table public.delivery_note_reversals add constraint delivery_note_reversals_pkey PRIMARY KEY (company_id, note_id, line_no);
alter table public.delivery_notes add constraint delivery_notes_check CHECK (((kind = 'production'::text) = (job_id IS NOT NULL)));
alter table public.delivery_notes add constraint delivery_notes_check1 CHECK (((kind = 'sale'::text) = (sale_id IS NOT NULL)));
alter table public.delivery_notes add constraint delivery_notes_check2 CHECK (((status = 'voided'::text) = ((voided_at IS NOT NULL) AND (void_reason IS NOT NULL))));
alter table public.delivery_notes add constraint delivery_notes_company_id_id_key UNIQUE (company_id, id);
alter table public.delivery_notes add constraint delivery_notes_company_id_number_key UNIQUE (company_id, number);
alter table public.delivery_notes add constraint delivery_notes_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.delivery_notes add constraint delivery_notes_kind_check CHECK ((kind = ANY (ARRAY['production'::text, 'materials'::text, 'products'::text, 'sale'::text])));
alter table public.delivery_notes add constraint delivery_notes_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 300)));
alter table public.delivery_notes add constraint delivery_notes_number_check CHECK ((number > 0));
alter table public.delivery_notes add constraint delivery_notes_pkey PRIMARY KEY (id);
alter table public.delivery_notes add constraint delivery_notes_recipient_check CHECK (((length(btrim(recipient)) >= 3) AND (length(btrim(recipient)) <= 120)));
alter table public.delivery_notes add constraint delivery_notes_status_check CHECK ((status = ANY (ARRAY['issued'::text, 'voided'::text])));
alter table public.exchange_rate_types add constraint exchange_rate_types_company_id_id_key UNIQUE (company_id, id);
alter table public.exchange_rate_types add constraint exchange_rate_types_company_id_name_key UNIQUE (company_id, name);
alter table public.exchange_rate_types add constraint exchange_rate_types_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 60)));
alter table public.exchange_rate_types add constraint exchange_rate_types_pkey PRIMARY KEY (id);
alter table public.exchange_rates add constraint exchange_rates_ars_per_usd_check CHECK ((ars_per_usd > (0)::numeric));
alter table public.exchange_rates add constraint exchange_rates_company_id_id_key UNIQUE (company_id, id);
alter table public.exchange_rates add constraint exchange_rates_pkey PRIMARY KEY (id);
alter table public.item_categories add constraint item_categories_code_check CHECK ((code ~ '^[a-z][a-z0-9_]{0,39}$'::text));
alter table public.item_categories add constraint item_categories_company_id_code_key UNIQUE (company_id, code);
alter table public.item_categories add constraint item_categories_company_id_id_key UNIQUE (company_id, id);
alter table public.item_categories add constraint item_categories_description_check CHECK ((length(description) <= 500));
alter table public.item_categories add constraint item_categories_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 100)));
alter table public.item_categories add constraint item_categories_pkey PRIMARY KEY (id);
alter table public.items add constraint items_barcode_check CHECK (((barcode IS NULL) OR ((length(btrim(barcode)) >= 4) AND (length(btrim(barcode)) <= 80))));
alter table public.items add constraint items_code_check CHECK ((code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'::text));
alter table public.items add constraint items_company_code_unique UNIQUE (company_id, code);
alter table public.items add constraint items_company_id_unique UNIQUE (company_id, id);
alter table public.items add constraint items_description_check CHECK ((length(description) <= 1500));
alter table public.items add constraint items_infinite_rules CHECK (((NOT infinite_stock) OR ((NOT track_lots) AND (minimum_stock = (0)::numeric))));
alter table public.items add constraint items_item_type_check CHECK ((item_type = ANY (ARRAY['raw_material'::text, 'semi_finished'::text, 'finished_product'::text, 'consumable'::text])));
alter table public.items add constraint items_minimum_stock_check CHECK ((minimum_stock >= (0)::numeric));
alter table public.items add constraint items_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 160)));
alter table public.items add constraint items_pkey PRIMARY KEY (id);
alter table public.items add constraint items_reference_unit_cost_check CHECK (((reference_unit_cost IS NULL) OR (reference_unit_cost >= (0)::numeric)));
alter table public.items add constraint items_reference_usd_pair CHECK ((((reference_cost_usd IS NULL) AND (reference_exchange_rate_type_id IS NULL)) OR ((reference_cost_usd IS NOT NULL) AND (reference_cost_usd >= (0)::numeric) AND (reference_exchange_rate_type_id IS NOT NULL))));
alter table public.items add constraint items_sale_unit_price_check CHECK (((sale_unit_price IS NULL) OR (sale_unit_price >= (0)::numeric)));
alter table public.items add constraint items_yield_factor_check CHECK (((yield_factor > (0)::numeric) AND (yield_factor <= (1000)::numeric)));
alter table public.operational_alert_reads add constraint operational_alert_reads_alert_key_check CHECK (((length(alert_key) >= 5) AND (length(alert_key) <= 120)));
alter table public.operational_alert_reads add constraint operational_alert_reads_fingerprint_check CHECK (((length(fingerprint) >= 1) AND (length(fingerprint) <= 150)));
alter table public.operational_alert_reads add constraint operational_alert_reads_pkey PRIMARY KEY (company_id, user_id, alert_key);
alter table public.production_document_settings add constraint production_document_settings_pkey PRIMARY KEY (company_id);
alter table public.production_formula_lines add constraint production_formula_lines_check CHECK ((product_id <> component_id));
alter table public.production_formula_lines add constraint production_formula_lines_pkey PRIMARY KEY (company_id, product_id, component_id);
alter table public.production_formula_lines add constraint production_formula_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.production_formulas add constraint production_formulas_batch_quantity_check CHECK ((batch_quantity > (0)::numeric));
alter table public.production_formulas add constraint production_formulas_pkey PRIMARY KEY (company_id, product_id);
alter table public.production_job_events add constraint production_job_events_check CHECK (((kind = 'return'::text) = (issue_id IS NOT NULL)));
alter table public.production_job_events add constraint production_job_events_company_id_id_key UNIQUE (company_id, id);
alter table public.production_job_events add constraint production_job_events_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.production_job_events add constraint production_job_events_kind_check CHECK ((kind = ANY (ARRAY['issue'::text, 'return'::text])));
alter table public.production_job_events add constraint production_job_events_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 300)));
alter table public.production_job_events add constraint production_job_events_pkey PRIMARY KEY (id);
alter table public.production_job_events add constraint production_job_events_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.production_job_events add constraint production_job_events_unit_cost_check CHECK ((unit_cost >= (0)::numeric));
alter table public.production_job_reservations add constraint production_job_reservations_pkey PRIMARY KEY (company_id, job_id, component_id);
alter table public.production_job_reservations add constraint production_job_reservations_required_quantity_check CHECK ((required_quantity > (0)::numeric));
alter table public.production_job_reservations add constraint production_job_reservations_reserved_quantity_check CHECK ((reserved_quantity >= (0)::numeric));
alter table public.production_jobs add constraint production_job_number_unique UNIQUE (company_id, number);
alter table public.production_jobs add constraint production_jobs_actual_quantity_check CHECK ((actual_quantity > (0)::numeric));
alter table public.production_jobs add constraint production_jobs_check CHECK (((status = 'completed'::text) = ((run_id IS NOT NULL) AND (completed_at IS NOT NULL) AND (actual_quantity IS NOT NULL) AND (completion_request_id IS NOT NULL))));
alter table public.production_jobs add constraint production_jobs_check1 CHECK (((status = 'cancelled'::text) = (cancelled_at IS NOT NULL)));
alter table public.production_jobs add constraint production_jobs_company_id_id_key UNIQUE (company_id, id);
alter table public.production_jobs add constraint production_jobs_company_id_plan_id_key UNIQUE (company_id, plan_id);
alter table public.production_jobs add constraint production_jobs_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.production_jobs add constraint production_jobs_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 400)));
alter table public.production_jobs add constraint production_jobs_pkey PRIMARY KEY (id);
alter table public.production_jobs add constraint production_jobs_planned_quantity_check CHECK ((planned_quantity > (0)::numeric));
alter table public.production_jobs add constraint production_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])));
alter table public.production_one_step_requests add constraint production_one_step_requests_pkey PRIMARY KEY (company_id, request_id);
alter table public.production_packaging_types add constraint production_packaging_types_capacity_check CHECK ((capacity > (0)::numeric));
alter table public.production_packaging_types add constraint production_packaging_types_company_id_id_key UNIQUE (company_id, id);
alter table public.production_packaging_types add constraint production_packaging_types_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 100)));
alter table public.production_packaging_types add constraint production_packaging_types_pkey PRIMARY KEY (id);
alter table public.production_plans add constraint production_plans_check CHECK ((((status = 'completed'::text) AND (run_id IS NOT NULL) AND (completed_at IS NOT NULL) AND (completion_request_id IS NOT NULL)) OR ((status <> 'completed'::text) AND (run_id IS NULL) AND (completed_at IS NULL) AND (completion_request_id IS NULL))));
alter table public.production_plans add constraint production_plans_check1 CHECK (((status = 'cancelled'::text) = (cancelled_at IS NOT NULL)));
alter table public.production_plans add constraint production_plans_company_id_id_key UNIQUE (company_id, id);
alter table public.production_plans add constraint production_plans_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.production_plans add constraint production_plans_company_id_run_id_key UNIQUE (company_id, run_id);
alter table public.production_plans add constraint production_plans_estimated_cost_check CHECK ((estimated_cost >= (0)::numeric));
alter table public.production_plans add constraint production_plans_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 400)));
alter table public.production_plans add constraint production_plans_pkey PRIMARY KEY (id);
alter table public.production_plans add constraint production_plans_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.production_plans add constraint production_plans_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'completed'::text, 'cancelled'::text])));
alter table public.production_reservation_locations add constraint production_reservation_locations_check CHECK (((lot_id IS NULL) = (lot_code IS NULL)));
alter table public.production_reservation_locations add constraint production_reservation_locations_pkey PRIMARY KEY (id);
alter table public.production_reservation_locations add constraint production_reservation_locations_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.production_run_lines add constraint production_run_lines_pkey PRIMARY KEY (company_id, run_id, component_id);
alter table public.production_run_lines add constraint production_run_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.production_runs add constraint production_runs_company_id_id_key UNIQUE (company_id, id);
alter table public.production_runs add constraint production_runs_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.production_runs add constraint production_runs_pkey PRIMARY KEY (id);
alter table public.production_runs add constraint production_runs_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.purchase_counters add constraint purchase_counters_next_number_check CHECK ((next_number > 0));
alter table public.purchase_counters add constraint purchase_counters_pkey PRIMARY KEY (company_id);
alter table public.purchase_order_lines add constraint purchase_lines_item_unique UNIQUE (company_id, order_id, item_id);
alter table public.purchase_order_lines add constraint purchase_order_lines_check CHECK (((received_quantity >= (0)::numeric) AND (received_quantity <= quantity)));
alter table public.purchase_order_lines add constraint purchase_order_lines_line_no_check CHECK (((line_no >= 1) AND (line_no <= 40)));
alter table public.purchase_order_lines add constraint purchase_order_lines_pkey PRIMARY KEY (company_id, order_id, line_no);
alter table public.purchase_order_lines add constraint purchase_order_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.purchase_order_lines add constraint purchase_order_lines_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.purchase_order_requests add constraint purchase_order_requests_company_id_order_id_key UNIQUE (company_id, order_id);
alter table public.purchase_order_requests add constraint purchase_order_requests_pkey PRIMARY KEY (company_id, request_id);
alter table public.purchase_orders add constraint purchase_orders_company_id_unique UNIQUE (company_id, id);
alter table public.purchase_orders add constraint purchase_orders_company_number_unique UNIQUE (company_id, number);
alter table public.purchase_orders add constraint purchase_orders_note_check CHECK ((length(note) <= 500));
alter table public.purchase_orders add constraint purchase_orders_number_check CHECK ((number > 0));
alter table public.purchase_orders add constraint purchase_orders_pkey PRIMARY KEY (id);
alter table public.purchase_orders add constraint purchase_orders_status_check CHECK ((status = ANY (ARRAY['open'::text, 'partial'::text, 'received'::text, 'cancelled'::text])));
alter table public.purchase_receipt_lines add constraint purchase_receipt_lines_pkey PRIMARY KEY (company_id, receipt_id, line_no);
alter table public.purchase_receipt_lines add constraint purchase_receipt_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.purchase_receipt_lines add constraint purchase_receipt_lines_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.purchase_receipts add constraint purchase_receipts_company_id_unique UNIQUE (company_id, id);
alter table public.purchase_receipts add constraint purchase_receipts_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 430)));
alter table public.purchase_receipts add constraint purchase_receipts_pkey PRIMARY KEY (id);
alter table public.purchase_receipts add constraint purchase_receipts_request_unique UNIQUE (company_id, request_id);
alter table public.role_permissions add constraint role_permissions_action_check CHECK ((action = ANY (ARRAY['read'::text, 'insert'::text, 'update'::text, 'delete'::text, 'manage'::text])));
alter table public.role_permissions add constraint role_permissions_pkey PRIMARY KEY (role_id, resource, action);
alter table public.role_permissions add constraint role_permissions_resource_check CHECK ((resource ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.roles add constraint roles_code_check CHECK ((code ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.roles add constraint roles_company_id_code_key UNIQUE (company_id, code);
alter table public.roles add constraint roles_company_id_id_key UNIQUE (company_id, id);
alter table public.roles add constraint roles_pkey PRIMARY KEY (id);
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_check CHECK ((restocked = (stock_operation_id IS NOT NULL)));
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_credit_amount_check CHECK ((credit_amount >= (0)::numeric));
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_pkey PRIMARY KEY (company_id, adjustment_id, sale_line_no);
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.sale_adjustments add constraint sale_adjustments_company_id_id_key UNIQUE (company_id, id);
alter table public.sale_adjustments add constraint sale_adjustments_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.sale_adjustments add constraint sale_adjustments_credit_total_check CHECK ((credit_total >= (0)::numeric));
alter table public.sale_adjustments add constraint sale_adjustments_kind_check CHECK ((kind = ANY (ARRAY['cancel'::text, 'return'::text])));
alter table public.sale_adjustments add constraint sale_adjustments_pkey PRIMARY KEY (id);
alter table public.sale_adjustments add constraint sale_adjustments_reason_check CHECK (((length(btrim(reason)) >= 5) AND (length(btrim(reason)) <= 300)));
alter table public.sale_checkouts add constraint sale_checkouts_company_id_sale_id_key UNIQUE (company_id, sale_id);
alter table public.sale_checkouts add constraint sale_checkouts_payment_mode_check CHECK ((payment_mode = ANY (ARRAY['pending'::text, 'partial'::text, 'paid'::text])));
alter table public.sale_checkouts add constraint sale_checkouts_pkey PRIMARY KEY (company_id, request_id);
alter table public.sale_counters add constraint sale_counters_next_number_check CHECK ((next_number > 0));
alter table public.sale_counters add constraint sale_counters_pkey PRIMARY KEY (company_id);
alter table public.sale_lines add constraint sale_lines_company_id_sale_id_item_id_key UNIQUE (company_id, sale_id, item_id);
alter table public.sale_lines add constraint sale_lines_line_no_check CHECK (((line_no >= 1) AND (line_no <= 40)));
alter table public.sale_lines add constraint sale_lines_line_total_check CHECK ((line_total >= (0)::numeric));
alter table public.sale_lines add constraint sale_lines_pkey PRIMARY KEY (company_id, sale_id, line_no);
alter table public.sale_lines add constraint sale_lines_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.sale_lines add constraint sale_lines_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.sale_payment_reversals add constraint sale_payment_reversals_company_id_payment_id_key UNIQUE (company_id, payment_id);
alter table public.sale_payment_reversals add constraint sale_payment_reversals_pkey PRIMARY KEY (id);
alter table public.sale_payment_reversals add constraint sale_payment_reversals_reason_check CHECK (((length(btrim(reason)) >= 5) AND (length(btrim(reason)) <= 300)));
alter table public.sale_payments add constraint sale_payments_amount_check CHECK ((amount > (0)::numeric));
alter table public.sale_payments add constraint sale_payments_company_id_id_key UNIQUE (company_id, id);
alter table public.sale_payments add constraint sale_payments_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.sale_payments add constraint sale_payments_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'transfer'::text, 'card'::text, 'check'::text, 'other'::text])));
alter table public.sale_payments add constraint sale_payments_note_check CHECK ((length(note) <= 500));
alter table public.sale_payments add constraint sale_payments_pkey PRIMARY KEY (id);
alter table public.sale_payments add constraint sale_payments_reference_check CHECK ((length(reference) <= 100));
alter table public.sale_refunds add constraint sale_refunds_amount_check CHECK ((amount > (0)::numeric));
alter table public.sale_refunds add constraint sale_refunds_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.sale_refunds add constraint sale_refunds_company_id_treasury_entry_id_key UNIQUE (company_id, treasury_entry_id);
alter table public.sale_refunds add constraint sale_refunds_pkey PRIMARY KEY (id);
alter table public.sale_refunds add constraint sale_refunds_reason_check CHECK (((length(btrim(reason)) >= 5) AND (length(btrim(reason)) <= 240)));
alter table public.sales add constraint sales_company_id_id_key UNIQUE (company_id, id);
alter table public.sales add constraint sales_company_id_number_key UNIQUE (company_id, number);
alter table public.sales add constraint sales_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.sales add constraint sales_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 500)));
alter table public.sales add constraint sales_number_check CHECK ((number > 0));
alter table public.sales add constraint sales_pkey PRIMARY KEY (id);
alter table public.sales add constraint sales_total_check CHECK ((total >= (0)::numeric));
alter table public.stock_balances add constraint stock_balances_pkey PRIMARY KEY (company_id, item_id, warehouse_id);
alter table public.stock_balances add constraint stock_balances_quantity_check CHECK ((quantity >= (0)::numeric));
alter table public.stock_balances add constraint stock_balances_version_check CHECK ((version >= 0));
alter table public.stock_lot_balances add constraint stock_lot_balances_pkey PRIMARY KEY (company_id, item_id, warehouse_id, lot_id);
alter table public.stock_lot_balances add constraint stock_lot_balances_quantity_check CHECK ((quantity >= (0)::numeric));
alter table public.stock_lot_openings add constraint stock_lot_openings_pkey PRIMARY KEY (company_id, item_id, warehouse_id);
alter table public.stock_lot_openings add constraint stock_lot_openings_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.stock_lots add constraint stock_lots_code_check CHECK ((((length(btrim(code)) >= 1) AND (length(btrim(code)) <= 80)) AND (code = btrim(code))));
alter table public.stock_lots add constraint stock_lots_company_item_id_unique UNIQUE (company_id, item_id, id);
alter table public.stock_lots add constraint stock_lots_pkey PRIMARY KEY (id);
alter table public.stock_movements add constraint stock_movements_balance_after_check CHECK ((balance_after >= (0)::numeric));
alter table public.stock_movements add constraint stock_movements_balance_version_check CHECK ((balance_version > 0));
alter table public.stock_movements add constraint stock_movements_delta_check CHECK ((delta <> (0)::numeric));
alter table public.stock_movements add constraint stock_movements_kind_check CHECK ((kind = ANY (ARRAY['receipt'::text, 'issue'::text, 'transfer_out'::text, 'transfer_in'::text])));
alter table public.stock_movements add constraint stock_movements_line_no_check CHECK ((line_no = ANY (ARRAY[1, 2])));
alter table public.stock_movements add constraint stock_movements_operation_id_line_no_key UNIQUE (operation_id, line_no);
alter table public.stock_movements add constraint stock_movements_pkey PRIMARY KEY (id);
alter table public.stock_movements add constraint stock_movements_sign_check CHECK ((((kind = ANY (ARRAY['receipt'::text, 'transfer_in'::text])) AND (delta > (0)::numeric)) OR ((kind = ANY (ARRAY['issue'::text, 'transfer_out'::text])) AND (delta < (0)::numeric))));
alter table public.stock_operations add constraint stock_operations_company_id_unique UNIQUE (company_id, id);
alter table public.stock_operations add constraint stock_operations_destination_check CHECK ((((kind = 'transfer'::text) AND (to_warehouse_id IS NOT NULL) AND (to_warehouse_id <> warehouse_id)) OR ((kind <> 'transfer'::text) AND (to_warehouse_id IS NULL))));
alter table public.stock_operations add constraint stock_operations_kind_check CHECK ((kind = ANY (ARRAY['receipt'::text, 'issue'::text, 'transfer'::text])));
alter table public.stock_operations add constraint stock_operations_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 500)));
alter table public.stock_operations add constraint stock_operations_pkey PRIMARY KEY (id);
alter table public.stock_operations add constraint stock_operations_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.stock_operations add constraint stock_operations_request_unique UNIQUE (company_id, request_id);
alter table public.supplier_items add constraint supplier_items_adjustment_percent_check CHECK (((adjustment_percent >= '-99.99'::numeric) AND (adjustment_percent <= (1000)::numeric)));
alter table public.supplier_items add constraint supplier_items_currency_check CHECK ((((currency_code = 'ARS'::text) AND (exchange_rate_type_id IS NULL)) OR ((currency_code = 'USD'::text) AND (exchange_rate_type_id IS NOT NULL))));
alter table public.supplier_items add constraint supplier_items_currency_code_check CHECK ((currency_code = ANY (ARRAY['ARS'::text, 'USD'::text])));
alter table public.supplier_items add constraint supplier_items_pkey PRIMARY KEY (company_id, supplier_id, item_id);
alter table public.supplier_items add constraint supplier_items_supplier_sku_check CHECK ((length(supplier_sku) <= 80));
alter table public.supplier_items add constraint supplier_items_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.supplier_payment_order_lines add constraint supplier_payment_order_lines_amount_check CHECK ((amount > (0)::numeric));
alter table public.supplier_payment_order_lines add constraint supplier_payment_order_lines_pkey PRIMARY KEY (company_id, payment_order_id, order_id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_amount_check CHECK ((amount > (0)::numeric));
alter table public.supplier_payment_orders add constraint supplier_payment_orders_check CHECK (((status = 'paid'::text) = (confirmed_at IS NOT NULL)));
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_id_key UNIQUE (company_id, id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_number_key UNIQUE (company_id, number);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 240)));
alter table public.supplier_payment_orders add constraint supplier_payment_orders_number_check CHECK ((number > 0));
alter table public.supplier_payment_orders add constraint supplier_payment_orders_pkey PRIMARY KEY (id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_reference_check CHECK ((length(reference) <= 120));
alter table public.supplier_payment_orders add constraint supplier_payment_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'paid'::text, 'cancelled'::text])));
alter table public.supplier_price_adjustments add constraint supplier_price_adjustments_company_id_request_id_key UNIQUE (company_id, request_id);
alter table public.supplier_price_adjustments add constraint supplier_price_adjustments_percent_check CHECK (((percent >= '-99.99'::numeric) AND (percent <= (1000)::numeric)));
alter table public.supplier_price_adjustments add constraint supplier_price_adjustments_pkey PRIMARY KEY (id);
alter table public.suppliers add constraint suppliers_company_id_unique UNIQUE (company_id, id);
alter table public.suppliers add constraint suppliers_email_check CHECK ((length(email) <= 160));
alter table public.suppliers add constraint suppliers_lead_time_days_check CHECK (((lead_time_days >= 0) AND (lead_time_days <= 365)));
alter table public.suppliers add constraint suppliers_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 160)));
alter table public.suppliers add constraint suppliers_notes_check CHECK ((length(notes) <= 500));
alter table public.suppliers add constraint suppliers_phone_check CHECK ((length(phone) <= 40));
alter table public.suppliers add constraint suppliers_pkey PRIMARY KEY (id);
alter table public.suppliers add constraint suppliers_supplies_description_check CHECK ((length(supplies_description) <= 200));
alter table public.suppliers add constraint suppliers_tax_id_check CHECK ((length(tax_id) <= 30));
alter table public.treasury_accounts add constraint treasury_accounts_company_id_id_key UNIQUE (company_id, id);
alter table public.treasury_accounts add constraint treasury_accounts_kind_check CHECK ((kind = ANY (ARRAY['cash'::text, 'bank'::text, 'other'::text])));
alter table public.treasury_accounts add constraint treasury_accounts_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 100)));
alter table public.treasury_accounts add constraint treasury_accounts_pkey PRIMARY KEY (id);
alter table public.treasury_entries add constraint treasury_entries_amount_check CHECK ((amount > (0)::numeric));
alter table public.treasury_entries add constraint treasury_entries_check CHECK (((kind = 'supplier_payment'::text) = (purchase_order_id IS NOT NULL)));
alter table public.treasury_entries add constraint treasury_entries_company_id_id_key UNIQUE (company_id, id);
alter table public.treasury_entries add constraint treasury_entries_company_id_request_id_kind_key UNIQUE (company_id, request_id, kind);
alter table public.treasury_entries add constraint treasury_entries_kind_check CHECK ((kind = ANY (ARRAY['income'::text, 'expense'::text, 'supplier_payment'::text, 'transfer_in'::text, 'transfer_out'::text])));
alter table public.treasury_entries add constraint treasury_entries_note_check CHECK (((length(btrim(note)) >= 3) AND (length(btrim(note)) <= 240)));
alter table public.treasury_entries add constraint treasury_entries_pkey PRIMARY KEY (id);
alter table public.treasury_sale_accounts add constraint treasury_sale_accounts_pkey PRIMARY KEY (company_id, payment_id);
alter table public.units add constraint units_code_check CHECK ((code ~ '^[a-z][a-z0-9_]{0,19}$'::text));
alter table public.units add constraint units_company_id_code_key UNIQUE (company_id, code);
alter table public.units add constraint units_company_id_id_key UNIQUE (company_id, id);
alter table public.units add constraint units_dimension_check CHECK ((dimension = ANY (ARRAY['count'::text, 'mass'::text, 'volume'::text, 'length'::text, 'area'::text, 'time'::text])));
alter table public.units add constraint units_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 80)));
alter table public.units add constraint units_pkey PRIMARY KEY (id);
alter table public.units add constraint units_symbol_check CHECK (((length(btrim(symbol)) >= 1) AND (length(btrim(symbol)) <= 12)));
alter table public.warehouses add constraint warehouses_code_check CHECK ((code ~ '^[a-z][a-z0-9_]{0,39}$'::text));
alter table public.warehouses add constraint warehouses_company_id_code_key UNIQUE (company_id, code);
alter table public.warehouses add constraint warehouses_company_id_id_key UNIQUE (company_id, id);
alter table public.warehouses add constraint warehouses_location_check CHECK ((length(location) <= 250));
alter table public.warehouses add constraint warehouses_name_check CHECK (((length(btrim(name)) >= 2) AND (length(btrim(name)) <= 100)));
alter table public.warehouses add constraint warehouses_pkey PRIMARY KEY (id);
alter table private.deleted_production_requests add constraint deleted_production_requests_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table private.deleted_production_requests add constraint deleted_production_requests_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table private.production_job_numbers add constraint production_job_numbers_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table private.supplier_payment_numbers add constraint supplier_payment_numbers_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table private.support_access_log add constraint support_access_log_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table private.support_access_log add constraint support_access_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table private.support_operators add constraint support_operators_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table private.support_sessions add constraint support_sessions_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table private.support_sessions add constraint support_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.company_invitations add constraint company_invitations_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_invitations add constraint company_invitations_company_id_role_id_fkey FOREIGN KEY (company_id, role_id) REFERENCES roles(company_id, id);
alter table public.company_invitations add constraint company_invitations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.company_modules add constraint company_modules_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_settings add constraint company_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_users add constraint company_users_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_users add constraint company_users_company_id_role_id_fkey FOREIGN KEY (company_id, role_id) REFERENCES roles(company_id, id);
alter table public.company_users add constraint company_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.customers add constraint customers_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.delivery_note_counters add constraint delivery_note_counters_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_item_id_fkey FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_note_id_fkey FOREIGN KEY (company_id, note_id) REFERENCES delivery_notes(company_id, id);
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_production_event_id_fkey FOREIGN KEY (company_id, production_event_id) REFERENCES production_job_events(company_id, id);
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_sale_id_sale_line_no_fkey FOREIGN KEY (company_id, sale_id, sale_line_no) REFERENCES sale_lines(company_id, sale_id, line_no);
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.delivery_note_lines add constraint delivery_note_lines_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.delivery_note_reversals add constraint delivery_note_reversals_company_id_note_id_line_no_fkey FOREIGN KEY (company_id, note_id, line_no) REFERENCES delivery_note_lines(company_id, note_id, line_no);
alter table public.delivery_note_reversals add constraint delivery_note_reversals_company_id_production_event_id_fkey FOREIGN KEY (company_id, production_event_id) REFERENCES production_job_events(company_id, id);
alter table public.delivery_note_reversals add constraint delivery_note_reversals_company_id_sale_id_sale_line_no_fkey FOREIGN KEY (company_id, sale_id, sale_line_no) REFERENCES sale_lines(company_id, sale_id, line_no);
alter table public.delivery_note_reversals add constraint delivery_note_reversals_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.delivery_notes add constraint delivery_notes_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.delivery_notes add constraint delivery_notes_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.delivery_notes add constraint delivery_notes_company_id_job_id_fkey FOREIGN KEY (company_id, job_id) REFERENCES production_jobs(company_id, id);
alter table public.delivery_notes add constraint delivery_notes_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.exchange_rate_types add constraint exchange_rate_types_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.exchange_rates add constraint exchange_rates_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.exchange_rates add constraint exchange_rates_company_id_type_id_fkey FOREIGN KEY (company_id, type_id) REFERENCES exchange_rate_types(company_id, id);
alter table public.item_categories add constraint item_categories_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.items add constraint items_category_company_fk FOREIGN KEY (company_id, category_id) REFERENCES item_categories(company_id, id);
alter table public.items add constraint items_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.items add constraint items_reference_fx_company_fk FOREIGN KEY (company_id, reference_exchange_rate_type_id) REFERENCES exchange_rate_types(company_id, id);
alter table public.items add constraint items_unit_company_fk FOREIGN KEY (company_id, unit_id) REFERENCES units(company_id, id);
alter table public.operational_alert_reads add constraint operational_alert_reads_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.operational_alert_reads add constraint operational_alert_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.production_document_settings add constraint production_document_settings_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.production_formula_lines add constraint production_formula_lines_company_id_component_id_fkey FOREIGN KEY (company_id, component_id) REFERENCES items(company_id, id);
alter table public.production_formula_lines add constraint production_formula_lines_company_id_product_id_fkey FOREIGN KEY (company_id, product_id) REFERENCES production_formulas(company_id, product_id);
alter table public.production_formulas add constraint production_formulas_company_id_product_id_fkey FOREIGN KEY (company_id, product_id) REFERENCES items(company_id, id);
alter table public.production_job_events add constraint production_job_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.production_job_events add constraint production_job_events_company_id_component_id_fkey FOREIGN KEY (company_id, component_id) REFERENCES items(company_id, id);
alter table public.production_job_events add constraint production_job_events_company_id_issue_id_fkey FOREIGN KEY (company_id, issue_id) REFERENCES production_job_events(company_id, id);
alter table public.production_job_events add constraint production_job_events_company_id_job_id_fkey FOREIGN KEY (company_id, job_id) REFERENCES production_jobs(company_id, id);
alter table public.production_job_events add constraint production_job_events_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.production_job_events add constraint production_job_events_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.production_job_reservations add constraint production_job_reservations_company_id_component_id_fkey FOREIGN KEY (company_id, component_id) REFERENCES items(company_id, id);
alter table public.production_job_reservations add constraint production_job_reservations_company_id_job_id_fkey FOREIGN KEY (company_id, job_id) REFERENCES production_jobs(company_id, id);
alter table public.production_jobs add constraint production_jobs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.production_jobs add constraint production_jobs_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.production_jobs add constraint production_jobs_company_id_plan_id_fkey FOREIGN KEY (company_id, plan_id) REFERENCES production_plans(company_id, id);
alter table public.production_jobs add constraint production_jobs_company_id_product_id_fkey FOREIGN KEY (company_id, product_id) REFERENCES items(company_id, id);
alter table public.production_jobs add constraint production_jobs_company_id_run_id_fkey FOREIGN KEY (company_id, run_id) REFERENCES production_runs(company_id, id);
alter table public.production_jobs add constraint production_jobs_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.production_one_step_requests add constraint production_one_step_requests_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.production_one_step_requests add constraint production_one_step_requests_company_id_job_id_fkey FOREIGN KEY (company_id, job_id) REFERENCES production_jobs(company_id, id);
alter table public.production_one_step_requests add constraint production_one_step_requests_company_id_run_id_fkey FOREIGN KEY (company_id, run_id) REFERENCES production_runs(company_id, id);
alter table public.production_packaging_types add constraint production_packaging_types_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.production_packaging_types add constraint production_packaging_types_company_id_unit_id_fkey FOREIGN KEY (company_id, unit_id) REFERENCES units(company_id, id);
alter table public.production_plans add constraint production_plans_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.production_plans add constraint production_plans_company_id_product_id_fkey FOREIGN KEY (company_id, product_id) REFERENCES items(company_id, id);
alter table public.production_plans add constraint production_plans_company_id_run_id_fkey FOREIGN KEY (company_id, run_id) REFERENCES production_runs(company_id, id);
alter table public.production_plans add constraint production_plans_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.production_reservation_locations add constraint production_reservation_locati_company_id_job_id_component__fkey FOREIGN KEY (company_id, job_id, component_id) REFERENCES production_job_reservations(company_id, job_id, component_id);
alter table public.production_reservation_locations add constraint production_reservation_locations_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.production_reservation_locations add constraint production_reservation_locations_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES stock_lots(id);
alter table public.production_run_lines add constraint production_run_lines_company_id_component_id_fkey FOREIGN KEY (company_id, component_id) REFERENCES items(company_id, id);
alter table public.production_run_lines add constraint production_run_lines_company_id_run_id_fkey FOREIGN KEY (company_id, run_id) REFERENCES production_runs(company_id, id);
alter table public.production_run_lines add constraint production_run_lines_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.production_run_lines add constraint production_run_lines_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.production_runs add constraint production_runs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.production_runs add constraint production_runs_company_id_output_operation_id_fkey FOREIGN KEY (company_id, output_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.production_runs add constraint production_runs_company_id_product_id_fkey FOREIGN KEY (company_id, product_id) REFERENCES items(company_id, id);
alter table public.production_runs add constraint production_runs_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.purchase_counters add constraint purchase_counters_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.purchase_order_lines add constraint purchase_lines_item_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.purchase_order_lines add constraint purchase_lines_order_fk FOREIGN KEY (company_id, order_id) REFERENCES purchase_orders(company_id, id);
alter table public.purchase_order_requests add constraint purchase_order_requests_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.purchase_order_requests add constraint purchase_order_requests_company_id_order_id_fkey FOREIGN KEY (company_id, order_id) REFERENCES purchase_orders(company_id, id);
alter table public.purchase_orders add constraint purchase_orders_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.purchase_orders add constraint purchase_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.purchase_orders add constraint purchase_orders_supplier_fk FOREIGN KEY (company_id, supplier_id) REFERENCES suppliers(company_id, id);
alter table public.purchase_receipt_lines add constraint receipt_lines_item_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.purchase_receipt_lines add constraint receipt_lines_order_fk FOREIGN KEY (company_id, order_id, line_no) REFERENCES purchase_order_lines(company_id, order_id, line_no);
alter table public.purchase_receipt_lines add constraint receipt_lines_receipt_fk FOREIGN KEY (company_id, receipt_id) REFERENCES purchase_receipts(company_id, id);
alter table public.purchase_receipt_lines add constraint receipt_lines_stock_fk FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.purchase_receipt_lines add constraint receipt_lines_warehouse_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.purchase_receipts add constraint purchase_receipts_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.purchase_receipts add constraint purchase_receipts_order_fk FOREIGN KEY (company_id, order_id) REFERENCES purchase_orders(company_id, id);
alter table public.role_permissions add constraint role_permissions_company_id_role_id_fkey FOREIGN KEY (company_id, role_id) REFERENCES roles(company_id, id) ON DELETE CASCADE;
alter table public.roles add constraint roles_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_company_id_adjustment_id_fkey FOREIGN KEY (company_id, adjustment_id) REFERENCES sale_adjustments(company_id, id);
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_company_id_sale_id_sale_line_no_fkey FOREIGN KEY (company_id, sale_id, sale_line_no) REFERENCES sale_lines(company_id, sale_id, line_no);
alter table public.sale_adjustment_lines add constraint sale_adjustment_lines_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.sale_adjustments add constraint sale_adjustments_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sale_adjustments add constraint sale_adjustments_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_checkouts add constraint sale_checkouts_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sale_checkouts add constraint sale_checkouts_company_id_account_id_fkey FOREIGN KEY (company_id, account_id) REFERENCES treasury_accounts(company_id, id);
alter table public.sale_checkouts add constraint sale_checkouts_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_counters add constraint sale_counters_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.sale_lines add constraint sale_lines_company_id_item_id_fkey FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.sale_lines add constraint sale_lines_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_lines add constraint sale_lines_company_id_stock_operation_id_fkey FOREIGN KEY (company_id, stock_operation_id) REFERENCES stock_operations(company_id, id);
alter table public.sale_lines add constraint sale_lines_company_id_warehouse_id_fkey FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.sale_payment_reversals add constraint sale_payment_reversals_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sale_payment_reversals add constraint sale_payment_reversals_company_id_payment_id_fkey FOREIGN KEY (company_id, payment_id) REFERENCES sale_payments(company_id, id);
alter table public.sale_payment_reversals add constraint sale_payment_reversals_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_payments add constraint sale_payments_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sale_payments add constraint sale_payments_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_refunds add constraint sale_refunds_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sale_refunds add constraint sale_refunds_company_id_account_id_fkey FOREIGN KEY (company_id, account_id) REFERENCES treasury_accounts(company_id, id);
alter table public.sale_refunds add constraint sale_refunds_company_id_sale_id_fkey FOREIGN KEY (company_id, sale_id) REFERENCES sales(company_id, id);
alter table public.sale_refunds add constraint sale_refunds_company_id_treasury_entry_id_fkey FOREIGN KEY (company_id, treasury_entry_id) REFERENCES treasury_entries(company_id, id);
alter table public.sales add constraint sales_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.sales add constraint sales_company_id_customer_id_fkey FOREIGN KEY (company_id, customer_id) REFERENCES customers(company_id, id);
alter table public.stock_balances add constraint stock_balances_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.stock_balances add constraint stock_balances_item_company_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.stock_balances add constraint stock_balances_warehouse_company_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.stock_lot_balances add constraint stock_lot_balances_lot_fk FOREIGN KEY (company_id, item_id, lot_id) REFERENCES stock_lots(company_id, item_id, id);
alter table public.stock_lot_balances add constraint stock_lot_balances_warehouse_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.stock_lot_openings add constraint stock_lot_openings_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.stock_lot_openings add constraint stock_lot_openings_lot_fk FOREIGN KEY (company_id, item_id, lot_id) REFERENCES stock_lots(company_id, item_id, id);
alter table public.stock_lot_openings add constraint stock_lot_openings_warehouse_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.stock_lots add constraint stock_lots_item_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.stock_movements add constraint stock_movements_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.stock_movements add constraint stock_movements_item_company_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.stock_movements add constraint stock_movements_lot_fk FOREIGN KEY (company_id, item_id, lot_id) REFERENCES stock_lots(company_id, item_id, id);
alter table public.stock_movements add constraint stock_movements_operation_company_fk FOREIGN KEY (company_id, operation_id) REFERENCES stock_operations(company_id, id);
alter table public.stock_movements add constraint stock_movements_warehouse_company_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.stock_operations add constraint stock_operations_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.stock_operations add constraint stock_operations_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.stock_operations add constraint stock_operations_item_company_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.stock_operations add constraint stock_operations_lot_fk FOREIGN KEY (company_id, item_id, lot_id) REFERENCES stock_lots(company_id, item_id, id);
alter table public.stock_operations add constraint stock_operations_target_company_fk FOREIGN KEY (company_id, to_warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.stock_operations add constraint stock_operations_warehouse_company_fk FOREIGN KEY (company_id, warehouse_id) REFERENCES warehouses(company_id, id);
alter table public.supplier_items add constraint supplier_items_fx_fk FOREIGN KEY (company_id, exchange_rate_type_id) REFERENCES exchange_rate_types(company_id, id);
alter table public.supplier_items add constraint supplier_items_item_fk FOREIGN KEY (company_id, item_id) REFERENCES items(company_id, id);
alter table public.supplier_items add constraint supplier_items_supplier_fk FOREIGN KEY (company_id, supplier_id) REFERENCES suppliers(company_id, id);
alter table public.supplier_payment_order_lines add constraint supplier_payment_order_lines_company_id_order_id_fkey FOREIGN KEY (company_id, order_id) REFERENCES purchase_orders(company_id, id);
alter table public.supplier_payment_order_lines add constraint supplier_payment_order_lines_company_id_payment_order_id_fkey FOREIGN KEY (company_id, payment_order_id) REFERENCES supplier_payment_orders(company_id, id) ON DELETE CASCADE;
alter table public.supplier_payment_order_lines add constraint supplier_payment_order_lines_company_id_treasury_entry_id_fkey FOREIGN KEY (company_id, treasury_entry_id) REFERENCES treasury_entries(company_id, id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_account_id_fkey FOREIGN KEY (company_id, account_id) REFERENCES treasury_accounts(company_id, id);
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.supplier_payment_orders add constraint supplier_payment_orders_company_id_supplier_id_fkey FOREIGN KEY (company_id, supplier_id) REFERENCES suppliers(company_id, id);
alter table public.supplier_price_adjustments add constraint supplier_price_adjustments_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.supplier_price_adjustments add constraint supplier_price_adjustments_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id);
alter table public.suppliers add constraint suppliers_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.treasury_accounts add constraint treasury_accounts_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.treasury_entries add constraint treasury_entries_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.treasury_entries add constraint treasury_entries_company_id_account_id_fkey FOREIGN KEY (company_id, account_id) REFERENCES treasury_accounts(company_id, id);
alter table public.treasury_entries add constraint treasury_entries_company_id_purchase_order_id_fkey FOREIGN KEY (company_id, purchase_order_id) REFERENCES purchase_orders(company_id, id);
alter table public.treasury_sale_accounts add constraint treasury_sale_accounts_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id);
alter table public.treasury_sale_accounts add constraint treasury_sale_accounts_company_id_account_id_fkey FOREIGN KEY (company_id, account_id) REFERENCES treasury_accounts(company_id, id);
alter table public.treasury_sale_accounts add constraint treasury_sale_accounts_company_id_payment_id_fkey FOREIGN KEY (company_id, payment_id) REFERENCES sale_payments(company_id, id);
alter table public.units add constraint units_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.warehouses add constraint warehouses_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
CREATE INDEX company_users_user_idx ON public.company_users USING btree (user_id, company_id) WHERE active;
CREATE INDEX role_permissions_company_idx ON public.role_permissions USING btree (company_id, role_id);
CREATE INDEX company_invitations_company_idx ON public.company_invitations USING btree (company_id, created_at DESC);
CREATE INDEX companies_active_idx ON public.companies USING btree (id) WHERE active;
CREATE INDEX units_listing_idx ON public.units USING btree (company_id, active, name);
CREATE INDEX categories_listing_idx ON public.item_categories USING btree (company_id, active, name);
CREATE INDEX warehouses_listing_idx ON public.warehouses USING btree (company_id, active, name);
CREATE INDEX items_company_type_name_idx ON public.items USING btree (company_id, item_type, active, name, id);
CREATE INDEX items_company_name_idx ON public.items USING btree (company_id, name, id);
CREATE INDEX items_category_idx ON public.items USING btree (company_id, category_id);
CREATE UNIQUE INDEX items_company_code_casefold_unique ON public.items USING btree (company_id, lower(code));
CREATE UNIQUE INDEX items_company_barcode_unique ON public.items USING btree (company_id, barcode) WHERE (barcode IS NOT NULL);
CREATE INDEX stock_balances_warehouse_idx ON public.stock_balances USING btree (company_id, warehouse_id, item_id);
CREATE INDEX stock_operations_company_date_idx ON public.stock_operations USING btree (company_id, created_at DESC);
CREATE INDEX stock_movements_company_date_idx ON public.stock_movements USING btree (company_id, created_at DESC, id DESC);
CREATE INDEX stock_movements_item_date_idx ON public.stock_movements USING btree (company_id, item_id, created_at DESC);
CREATE INDEX stock_movements_warehouse_date_idx ON public.stock_movements USING btree (company_id, warehouse_id, created_at DESC);
CREATE UNIQUE INDEX stock_movements_balance_version_unique ON public.stock_movements USING btree (company_id, item_id, warehouse_id, balance_version);
CREATE UNIQUE INDEX stock_lots_code_unique ON public.stock_lots USING btree (company_id, item_id, lower(code));
CREATE INDEX stock_lot_balances_available_idx ON public.stock_lot_balances USING btree (company_id, item_id, warehouse_id) WHERE (quantity > (0)::numeric);
CREATE INDEX suppliers_company_active_idx ON public.suppliers USING btree (company_id, active, name);
CREATE UNIQUE INDEX suppliers_company_name_unique ON public.suppliers USING btree (company_id, lower(name));
CREATE INDEX purchase_orders_company_date_idx ON public.purchase_orders USING btree (company_id, created_at DESC);
CREATE INDEX supplier_items_item_price_idx ON public.supplier_items USING btree (company_id, item_id, unit_price, supplier_id);
CREATE INDEX purchase_receipts_order_date_idx ON public.purchase_receipts USING btree (company_id, order_id, created_at DESC);
CREATE INDEX production_runs_recent ON public.production_runs USING btree (company_id, created_at DESC);
CREATE INDEX production_plans_queue ON public.production_plans USING btree (company_id, status, due_on, created_at);
CREATE INDEX customers_listing ON public.customers USING btree (company_id, active, name);
CREATE UNIQUE INDEX customers_tax_unique ON public.customers USING btree (company_id, lower(tax_id)) WHERE (btrim(tax_id) <> ''::text);
CREATE INDEX sales_recent ON public.sales USING btree (company_id, created_at DESC);
CREATE INDEX sale_payments_sale_date ON public.sale_payments USING btree (company_id, sale_id, created_at DESC);
CREATE UNIQUE INDEX exchange_rate_types_unique_name ON public.exchange_rate_types USING btree (company_id, lower(name));
CREATE INDEX exchange_rates_current ON public.exchange_rates USING btree (company_id, type_id, effective_on DESC, created_at DESC);
CREATE UNIQUE INDEX supplier_items_one_preferred ON public.supplier_items USING btree (company_id, item_id) WHERE preferred;
CREATE UNIQUE INDEX treasury_accounts_unique_name ON public.treasury_accounts USING btree (company_id, lower(name));
CREATE INDEX treasury_entries_recent ON public.treasury_entries USING btree (company_id, occurred_on DESC, created_at DESC);
CREATE INDEX sale_adjustments_sale ON public.sale_adjustments USING btree (company_id, sale_id);
CREATE UNIQUE INDEX sale_one_cancellation ON public.sale_adjustments USING btree (company_id, sale_id) WHERE (kind = 'cancel'::text);
CREATE INDEX production_jobs_queue ON public.production_jobs USING btree (company_id, status, due_on, created_at);
CREATE INDEX production_job_events_list ON public.production_job_events USING btree (company_id, job_id, created_at, id);
CREATE INDEX delivery_notes_recent ON public.delivery_notes USING btree (company_id, created_at DESC);
CREATE INDEX delivery_notes_job ON public.delivery_notes USING btree (company_id, job_id, created_at) WHERE (job_id IS NOT NULL);
CREATE INDEX production_reservation_component ON public.production_job_reservations USING btree (company_id, component_id);
CREATE INDEX production_reservation_location_slot ON public.production_reservation_locations USING btree (company_id, component_id, warehouse_id, lot_id);
CREATE INDEX production_reservation_location_job ON public.production_reservation_locations USING btree (company_id, job_id);
CREATE INDEX support_access_log_company_time ON private.support_access_log USING btree (company_id, started_at DESC);
CREATE INDEX supplier_payment_orders_recent ON public.supplier_payment_orders USING btree (company_id, created_at DESC, id);
CREATE INDEX purchase_receipts_statistics ON public.purchase_receipts USING btree (company_id, created_at);
CREATE INDEX treasury_supplier_order ON public.treasury_entries USING btree (company_id, purchase_order_id, occurred_on);
CREATE UNIQUE INDEX packaging_names ON public.production_packaging_types USING btree (company_id, lower(name));
alter table public.companies enable row level security;
alter table public.company_invitations enable row level security;
alter table public.company_modules enable row level security;
alter table public.company_settings enable row level security;
alter table public.company_users enable row level security;
alter table public.customers enable row level security;
alter table public.delivery_note_counters enable row level security;
alter table public.delivery_note_lines enable row level security;
alter table public.delivery_note_reversals enable row level security;
alter table public.delivery_notes enable row level security;
alter table public.exchange_rate_types enable row level security;
alter table public.exchange_rates enable row level security;
alter table public.item_categories enable row level security;
alter table public.items enable row level security;
alter table public.operational_alert_reads enable row level security;
alter table public.production_document_settings enable row level security;
alter table public.production_formula_lines enable row level security;
alter table public.production_formulas enable row level security;
alter table public.production_job_events enable row level security;
alter table public.production_job_reservations enable row level security;
alter table public.production_jobs enable row level security;
alter table public.production_one_step_requests enable row level security;
alter table public.production_packaging_types enable row level security;
alter table public.production_plans enable row level security;
alter table public.production_reservation_locations enable row level security;
alter table public.production_run_lines enable row level security;
alter table public.production_runs enable row level security;
alter table public.profiles enable row level security;
alter table public.purchase_counters enable row level security;
alter table public.purchase_order_lines enable row level security;
alter table public.purchase_order_requests enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_receipt_lines enable row level security;
alter table public.purchase_receipts enable row level security;
alter table public.role_permissions enable row level security;
alter table public.roles enable row level security;
alter table public.sale_adjustment_lines enable row level security;
alter table public.sale_adjustments enable row level security;
alter table public.sale_checkouts enable row level security;
alter table public.sale_counters enable row level security;
alter table public.sale_lines enable row level security;
alter table public.sale_payment_reversals enable row level security;
alter table public.sale_payments enable row level security;
alter table public.sale_refunds enable row level security;
alter table public.sales enable row level security;
alter table public.stock_balances enable row level security;
alter table public.stock_lot_balances enable row level security;
alter table public.stock_lot_openings enable row level security;
alter table public.stock_lots enable row level security;
alter table public.stock_movements enable row level security;
alter table public.stock_operations enable row level security;
alter table public.supplier_items enable row level security;
alter table public.supplier_payment_order_lines enable row level security;
alter table public.supplier_payment_orders enable row level security;
alter table public.supplier_price_adjustments enable row level security;
alter table public.suppliers enable row level security;
alter table public.treasury_accounts enable row level security;
alter table public.treasury_entries enable row level security;
alter table public.treasury_sale_accounts enable row level security;
alter table public.units enable row level security;
alter table public.warehouses enable row level security;
create policy companies_admin_update on public.companies as permissive for update to authenticated using (( SELECT private.has_permission(companies.id, 'settings'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(companies.id, 'settings'::text, 'update'::text) AS has_permission));
create policy companies_member_select on public.companies as permissive for select to authenticated using (( SELECT private.is_company_member(companies.id) AS is_company_member));
create policy company_modules_member_select on public.company_modules as permissive for select to authenticated using (( SELECT private.is_company_member(company_modules.company_id) AS is_company_member));
create policy company_settings_admin_update on public.company_settings as permissive for update to authenticated using (( SELECT private.has_permission(company_settings.company_id, 'settings'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(company_settings.company_id, 'settings'::text, 'update'::text) AS has_permission));
create policy company_settings_member_select on public.company_settings as permissive for select to authenticated using (( SELECT private.is_company_member(company_settings.company_id) AS is_company_member));
create policy company_users_self_or_admin_select on public.company_users as permissive for select to authenticated using ((((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_company_member(company_users.company_id) AS is_company_member)) OR ( SELECT private.has_permission(company_users.company_id, 'users'::text, 'read'::text) AS has_permission)));
create policy customers_insert on public.customers as permissive for insert to authenticated with check (( SELECT private.has_permission(customers.company_id, 'sales'::text, 'insert'::text) AS has_permission));
create policy customers_read on public.customers as permissive for select to authenticated using (( SELECT private.has_permission(customers.company_id, 'sales'::text, 'read'::text) AS has_permission));
create policy customers_update on public.customers as permissive for update to authenticated using (( SELECT private.has_permission(customers.company_id, 'sales'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(customers.company_id, 'sales'::text, 'update'::text) AS has_permission));
create policy delivery_lines_read on public.delivery_note_lines as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM delivery_notes d
  WHERE ((d.company_id = delivery_note_lines.company_id) AND (d.id = delivery_note_lines.note_id) AND (private.has_permission(d.company_id, 'stock'::text, 'read'::text) OR ((d.kind = 'production'::text) AND private.has_permission(d.company_id, 'production'::text, 'read'::text)))))));
create policy delivery_reversals_read on public.delivery_note_reversals as permissive for select to authenticated using ((EXISTS ( SELECT 1
   FROM delivery_notes d
  WHERE ((d.company_id = delivery_note_reversals.company_id) AND (d.id = delivery_note_reversals.note_id) AND (private.has_permission(d.company_id, 'stock'::text, 'read'::text) OR ((d.kind = 'production'::text) AND private.has_permission(d.company_id, 'production'::text, 'read'::text)))))));
create policy delivery_notes_read on public.delivery_notes as permissive for select to authenticated using ((( SELECT private.has_permission(delivery_notes.company_id, 'stock'::text, 'read'::text) AS has_permission) OR ((kind = 'production'::text) AND ( SELECT private.has_permission(delivery_notes.company_id, 'production'::text, 'read'::text) AS has_permission))));
create policy exchange_rate_types_read on public.exchange_rate_types as permissive for select to authenticated using (( SELECT private.has_permission(exchange_rate_types.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy exchange_rates_read on public.exchange_rates as permissive for select to authenticated using (( SELECT private.has_permission(exchange_rates.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy categories_insert on public.item_categories as permissive for insert to authenticated with check (( SELECT private.has_permission(item_categories.company_id, 'categories'::text, 'insert'::text) AS has_permission));
create policy categories_read on public.item_categories as permissive for select to authenticated using (( SELECT private.has_permission(item_categories.company_id, 'categories'::text, 'read'::text) AS has_permission));
create policy categories_update on public.item_categories as permissive for update to authenticated using (( SELECT private.has_permission(item_categories.company_id, 'categories'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(item_categories.company_id, 'categories'::text, 'update'::text) AS has_permission));
create policy items_insert on public.items as permissive for insert to authenticated with check (( SELECT private.has_permission(items.company_id, 'items'::text, 'insert'::text) AS has_permission));
create policy items_read on public.items as permissive for select to authenticated using (( SELECT private.has_permission(items.company_id, 'items'::text, 'read'::text) AS has_permission));
create policy items_update on public.items as permissive for update to authenticated using (( SELECT private.has_permission(items.company_id, 'items'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(items.company_id, 'items'::text, 'update'::text) AS has_permission));
create policy operational_alert_reads_insert on public.operational_alert_reads as permissive for insert to authenticated with check (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(operational_alert_reads.company_id, 'dashboard'::text, 'read'::text) AS has_permission)));
create policy operational_alert_reads_select on public.operational_alert_reads as permissive for select to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(operational_alert_reads.company_id, 'dashboard'::text, 'read'::text) AS has_permission)));
create policy operational_alert_reads_update on public.operational_alert_reads as permissive for update to authenticated using (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(operational_alert_reads.company_id, 'dashboard'::text, 'read'::text) AS has_permission))) with check (((user_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(operational_alert_reads.company_id, 'dashboard'::text, 'read'::text) AS has_permission)));
create policy document_settings_read on public.production_document_settings as permissive for select to authenticated using ((private.has_permission(company_id, 'production'::text, 'read'::text) OR ((private.get_user_role(company_id) = 'admin'::text) AND private.has_permission(company_id, 'dashboard'::text, 'read'::text))));
create policy production_formula_lines_read on public.production_formula_lines as permissive for select to authenticated using (( SELECT private.has_permission(production_formula_lines.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy production_formulas_read on public.production_formulas as permissive for select to authenticated using (( SELECT private.has_permission(production_formulas.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy production_job_events_read on public.production_job_events as permissive for select to authenticated using (( SELECT private.has_permission(production_job_events.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy production_reservations_read on public.production_job_reservations as permissive for select to authenticated using ((( SELECT private.has_permission(production_job_reservations.company_id, 'production'::text, 'read'::text) AS has_permission) AND ( SELECT private.has_permission(production_job_reservations.company_id, 'stock'::text, 'read'::text) AS has_permission)));
create policy production_jobs_read on public.production_jobs as permissive for select to authenticated using (( SELECT private.has_permission(production_jobs.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy packaging_types_read on public.production_packaging_types as permissive for select to authenticated using (private.has_permission(company_id, 'production'::text, 'read'::text));
create policy production_plans_read on public.production_plans as permissive for select to authenticated using (( SELECT private.has_permission(production_plans.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy reservation_locations_read on public.production_reservation_locations as permissive for select to authenticated using ((( SELECT private.has_permission(production_reservation_locations.company_id, 'production'::text, 'read'::text) AS has_permission) AND ( SELECT private.has_permission(production_reservation_locations.company_id, 'stock'::text, 'read'::text) AS has_permission)));
create policy production_run_lines_read on public.production_run_lines as permissive for select to authenticated using (( SELECT private.has_permission(production_run_lines.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy production_runs_read on public.production_runs as permissive for select to authenticated using (( SELECT private.has_permission(production_runs.company_id, 'production'::text, 'read'::text) AS has_permission));
create policy profiles_self_select on public.profiles as permissive for select to authenticated using ((id = ( SELECT auth.uid() AS uid)));
create policy profiles_self_update on public.profiles as permissive for update to authenticated using ((id = ( SELECT auth.uid() AS uid))) with check ((id = ( SELECT auth.uid() AS uid)));
create policy purchase_lines_read on public.purchase_order_lines as permissive for select to authenticated using (( SELECT private.has_permission(purchase_order_lines.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy purchase_orders_read on public.purchase_orders as permissive for select to authenticated using (( SELECT private.has_permission(purchase_orders.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy purchase_receipt_lines_read on public.purchase_receipt_lines as permissive for select to authenticated using (( SELECT private.has_permission(purchase_receipt_lines.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy purchase_receipts_read on public.purchase_receipts as permissive for select to authenticated using (( SELECT private.has_permission(purchase_receipts.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy role_permissions_member_select on public.role_permissions as permissive for select to authenticated using (( SELECT private.is_company_member(role_permissions.company_id) AS is_company_member));
create policy roles_member_select on public.roles as permissive for select to authenticated using (( SELECT private.is_company_member(roles.company_id) AS is_company_member));
create policy sale_adjustment_lines_read on public.sale_adjustment_lines as permissive for select to authenticated using (( SELECT private.has_permission(sale_adjustment_lines.company_id, 'sales'::text, 'read'::text) AS has_permission));
create policy sale_adjustments_read on public.sale_adjustments as permissive for select to authenticated using (( SELECT private.has_permission(sale_adjustments.company_id, 'sales'::text, 'read'::text) AS has_permission));
create policy sale_lines_read on public.sale_lines as permissive for select to authenticated using (( SELECT private.has_permission(sale_lines.company_id, 'sales'::text, 'read'::text) AS has_permission));
create policy sale_payment_reversals_read on public.sale_payment_reversals as permissive for select to authenticated using (( SELECT private.has_permission(sale_payment_reversals.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy sale_payments_read on public.sale_payments as permissive for select to authenticated using (( SELECT private.has_permission(sale_payments.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy sale_refunds_read on public.sale_refunds as permissive for select to authenticated using (( SELECT private.has_permission(sale_refunds.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy sales_read on public.sales as permissive for select to authenticated using (( SELECT private.has_permission(sales.company_id, 'sales'::text, 'read'::text) AS has_permission));
create policy stock_balances_read on public.stock_balances as permissive for select to authenticated using (( SELECT private.has_permission(stock_balances.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy stock_lot_balances_read on public.stock_lot_balances as permissive for select to authenticated using (( SELECT private.has_permission(stock_lot_balances.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy stock_lot_openings_read on public.stock_lot_openings as permissive for select to authenticated using (( SELECT private.has_permission(stock_lot_openings.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy stock_lots_read on public.stock_lots as permissive for select to authenticated using (( SELECT private.has_permission(stock_lots.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy stock_movements_read on public.stock_movements as permissive for select to authenticated using (( SELECT private.has_permission(stock_movements.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy stock_operations_read on public.stock_operations as permissive for select to authenticated using (( SELECT private.has_permission(stock_operations.company_id, 'stock'::text, 'read'::text) AS has_permission));
create policy supplier_items_delete on public.supplier_items as permissive for delete to authenticated using (( SELECT private.has_permission(supplier_items.company_id, 'purchases'::text, 'update'::text) AS has_permission));
create policy supplier_items_insert on public.supplier_items as permissive for insert to authenticated with check (( SELECT private.has_permission(supplier_items.company_id, 'purchases'::text, 'update'::text) AS has_permission));
create policy supplier_items_read on public.supplier_items as permissive for select to authenticated using (( SELECT private.has_permission(supplier_items.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy supplier_items_update on public.supplier_items as permissive for update to authenticated using (( SELECT private.has_permission(supplier_items.company_id, 'purchases'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(supplier_items.company_id, 'purchases'::text, 'update'::text) AS has_permission));
create policy payment_order_lines_read on public.supplier_payment_order_lines as permissive for select to authenticated using ((private.has_permission(company_id, 'finance'::text, 'read'::text) AND private.has_permission(company_id, 'purchases'::text, 'read'::text)));
create policy payment_orders_read on public.supplier_payment_orders as permissive for select to authenticated using ((private.has_permission(company_id, 'finance'::text, 'read'::text) AND private.has_permission(company_id, 'purchases'::text, 'read'::text)));
create policy supplier_price_adjustments_read on public.supplier_price_adjustments as permissive for select to authenticated using (( SELECT private.has_permission(supplier_price_adjustments.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy suppliers_insert on public.suppliers as permissive for insert to authenticated with check (( SELECT private.has_permission(suppliers.company_id, 'purchases'::text, 'insert'::text) AS has_permission));
create policy suppliers_read on public.suppliers as permissive for select to authenticated using (( SELECT private.has_permission(suppliers.company_id, 'purchases'::text, 'read'::text) AS has_permission));
create policy suppliers_update on public.suppliers as permissive for update to authenticated using (( SELECT private.has_permission(suppliers.company_id, 'purchases'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(suppliers.company_id, 'purchases'::text, 'update'::text) AS has_permission));
create policy treasury_accounts_read on public.treasury_accounts as permissive for select to authenticated using (( SELECT private.has_permission(treasury_accounts.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy treasury_entries_read on public.treasury_entries as permissive for select to authenticated using (( SELECT private.has_permission(treasury_entries.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy treasury_sale_accounts_read on public.treasury_sale_accounts as permissive for select to authenticated using (( SELECT private.has_permission(treasury_sale_accounts.company_id, 'finance'::text, 'read'::text) AS has_permission));
create policy units_insert on public.units as permissive for insert to authenticated with check (( SELECT private.has_permission(units.company_id, 'units'::text, 'insert'::text) AS has_permission));
create policy units_read on public.units as permissive for select to authenticated using (( SELECT private.has_permission(units.company_id, 'units'::text, 'read'::text) AS has_permission));
create policy units_update on public.units as permissive for update to authenticated using (( SELECT private.has_permission(units.company_id, 'units'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(units.company_id, 'units'::text, 'update'::text) AS has_permission));
create policy warehouses_insert on public.warehouses as permissive for insert to authenticated with check (( SELECT private.has_permission(warehouses.company_id, 'warehouses'::text, 'insert'::text) AS has_permission));
create policy warehouses_read on public.warehouses as permissive for select to authenticated using (( SELECT private.has_permission(warehouses.company_id, 'warehouses'::text, 'read'::text) AS has_permission));
create policy warehouses_update on public.warehouses as permissive for update to authenticated using (( SELECT private.has_permission(warehouses.company_id, 'warehouses'::text, 'update'::text) AS has_permission)) with check (( SELECT private.has_permission(warehouses.company_id, 'warehouses'::text, 'update'::text) AS has_permission));
CREATE TRIGGER delivery_note_lines_immutable BEFORE DELETE OR UPDATE ON public.delivery_note_lines FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER delivery_note_reversals_immutable BEFORE DELETE OR UPDATE ON public.delivery_note_reversals FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER exchange_archived_activity BEFORE INSERT OR UPDATE OF active, archived ON public.exchange_rate_types FOR EACH ROW EXECUTE FUNCTION private.protect_archived_activity();
CREATE TRIGGER exchange_rates_immutable BEFORE DELETE OR UPDATE ON public.exchange_rates FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER fx_rate_cost_changed AFTER INSERT ON public.exchange_rates FOR EACH ROW EXECUTE FUNCTION private.refresh_fx_costs();
CREATE TRIGGER item_archived_activity BEFORE INSERT OR UPDATE OF active, archived ON public.items FOR EACH ROW EXECUTE FUNCTION private.protect_archived_activity();
CREATE TRIGGER items_check_catalogs BEFORE INSERT OR UPDATE OF company_id, category_id, unit_id ON public.items FOR EACH ROW EXECUTE FUNCTION private.check_item_catalogs();
CREATE TRIGGER items_infinite_transition BEFORE INSERT OR UPDATE OF infinite_stock ON public.items FOR EACH ROW EXECUTE FUNCTION private.check_infinite_stock_change();
CREATE TRIGGER items_preferred_cost_protect BEFORE UPDATE OF reference_unit_cost ON public.items FOR EACH ROW EXECUTE FUNCTION private.protect_preferred_material_cost();
CREATE TRIGGER items_prevent_late_lot_tracking BEFORE UPDATE OF track_lots ON public.items FOR EACH ROW EXECUTE FUNCTION private.prevent_late_lot_tracking();
CREATE TRIGGER items_prevent_stock_stranding BEFORE UPDATE OF active ON public.items FOR EACH ROW EXECUTE FUNCTION private.check_stock_catalog_deactivation();
CREATE TRIGGER items_prevent_unit_change BEFORE UPDATE OF unit_id ON public.items FOR EACH ROW EXECUTE FUNCTION private.prevent_stock_unit_change();
CREATE TRIGGER items_protect_supplier_prices BEFORE UPDATE OF unit_id, item_type ON public.items FOR EACH ROW EXECUTE FUNCTION private.prevent_supplier_price_unit_mismatch();
CREATE TRIGGER items_reference_fx_cost BEFORE INSERT OR UPDATE OF reference_unit_cost, reference_cost_usd, reference_exchange_rate_type_id ON public.items FOR EACH ROW EXECUTE FUNCTION private.check_reference_fx_cost();
CREATE TRIGGER items_touch_updated_at BEFORE UPDATE ON public.items FOR EACH ROW EXECUTE FUNCTION private.touch_item_updated_at();
CREATE TRIGGER guard_archived_formula_edit BEFORE UPDATE OF batch_quantity, version ON public.production_formulas FOR EACH ROW EXECUTE FUNCTION private.guard_archived_formula_edit();
CREATE TRIGGER production_job_events_immutable BEFORE DELETE OR UPDATE ON public.production_job_events FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER rebalance_production_after_event AFTER INSERT ON public.production_job_events FOR EACH ROW EXECUTE FUNCTION private.rebalance_production_on_event();
CREATE TRIGGER guard_archived_job_recipe BEFORE INSERT ON public.production_jobs FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_job_document BEFORE INSERT ON public.production_jobs FOR EACH ROW EXECUTE FUNCTION private.prepare_production_document();
CREATE TRIGGER release_production_job_after_update AFTER UPDATE OF status ON public.production_jobs FOR EACH ROW EXECUTE FUNCTION private.release_closed_production_job();
CREATE TRIGGER reserve_production_job_after_insert AFTER INSERT ON public.production_jobs FOR EACH ROW EXECUTE FUNCTION private.reserve_new_production_job();
CREATE TRIGGER guard_archived_plan_recipe BEFORE INSERT ON public.production_plans FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_run_lines_immutable BEFORE DELETE OR UPDATE ON public.production_run_lines FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_archived_run_recipe BEFORE INSERT ON public.production_runs FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_runs_immutable BEFORE DELETE OR UPDATE ON public.production_runs FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_purchase_supplier_item BEFORE INSERT ON public.purchase_order_lines FOR EACH ROW EXECUTE FUNCTION private.guard_purchase_supplier_item();
CREATE TRIGGER purchase_lines_snapshot_name BEFORE INSERT ON public.purchase_order_lines FOR EACH ROW EXECUTE FUNCTION private.snapshot_purchase_item_name();
CREATE TRIGGER purchase_receipt_lines_immutable BEFORE DELETE OR UPDATE ON public.purchase_receipt_lines FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER purchase_receipts_immutable BEFORE DELETE OR UPDATE ON public.purchase_receipts FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_adjustment_lines_immutable BEFORE DELETE OR UPDATE ON public.sale_adjustment_lines FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_adjustments_immutable BEFORE DELETE ON public.sale_adjustments FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_lines_immutable BEFORE DELETE OR UPDATE ON public.sale_lines FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_reversal_after_refund BEFORE INSERT ON public.sale_payment_reversals FOR EACH ROW EXECUTE FUNCTION private.guard_reversal_after_refund();
CREATE TRIGGER sale_payment_reversals_immutable BEFORE DELETE OR UPDATE ON public.sale_payment_reversals FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_sale_payment_net BEFORE INSERT ON public.sale_payments FOR EACH ROW EXECUTE FUNCTION private.guard_sale_payment_net();
CREATE TRIGGER sale_payments_immutable BEFORE DELETE OR UPDATE ON public.sale_payments FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_refunds_immutable BEFORE DELETE OR UPDATE ON public.sale_refunds FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sales_immutable BEFORE DELETE OR UPDATE ON public.sales FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_lot_openings_immutable BEFORE DELETE OR UPDATE ON public.stock_lot_openings FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_lots_immutable BEFORE DELETE OR UPDATE ON public.stock_lots FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_movements_immutable BEFORE DELETE OR UPDATE ON public.stock_movements FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_movements_infinite_guard BEFORE INSERT ON public.stock_movements FOR EACH ROW EXECUTE FUNCTION private.prevent_infinite_physical_movement();
CREATE TRIGGER stock_operations_immutable BEFORE DELETE OR UPDATE ON public.stock_operations FOR EACH ROW EXECUTE FUNCTION private.reject_stock_operation_mutation();
CREATE TRIGGER supplier_items_check BEFORE INSERT OR UPDATE ON public.supplier_items FOR EACH ROW EXECUTE FUNCTION private.check_supplier_item();
CREATE TRIGGER supplier_preferred_protect BEFORE DELETE ON public.supplier_items FOR EACH ROW EXECUTE FUNCTION private.prevent_preferred_quote_deletion();
CREATE TRIGGER supplier_quote_cost_changed AFTER INSERT OR DELETE OR UPDATE ON public.supplier_items FOR EACH ROW EXECUTE FUNCTION private.refresh_quote_cost();
CREATE TRIGGER supplier_adjustments_immutable BEFORE DELETE OR UPDATE ON public.supplier_price_adjustments FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER treasury_entries_immutable BEFORE DELETE OR UPDATE ON public.treasury_entries FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER treasury_sale_accounts_immutable BEFORE DELETE OR UPDATE ON public.treasury_sale_accounts FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER warehouses_prevent_stock_stranding BEFORE UPDATE OF active ON public.warehouses FOR EACH ROW EXECUTE FUNCTION private.check_stock_catalog_deactivation();
revoke all on table private.deleted_production_requests from public, anon, authenticated;
revoke all on table private.production_job_numbers from public, anon, authenticated;
revoke all on table private.supplier_payment_numbers from public, anon, authenticated;
revoke all on table private.support_access_log from public, anon, authenticated;
revoke all on table private.support_operators from public, anon, authenticated;
revoke all on table private.support_sessions from public, anon, authenticated;
revoke all on table public.companies from public, anon, authenticated;
revoke all on table public.company_invitations from public, anon, authenticated;
revoke all on table public.company_modules from public, anon, authenticated;
revoke all on table public.company_settings from public, anon, authenticated;
revoke all on table public.company_users from public, anon, authenticated;
revoke all on table public.customers from public, anon, authenticated;
revoke all on table public.delivery_note_counters from public, anon, authenticated;
revoke all on table public.delivery_note_lines from public, anon, authenticated;
revoke all on table public.delivery_note_reversals from public, anon, authenticated;
revoke all on table public.delivery_notes from public, anon, authenticated;
revoke all on table public.exchange_rate_types from public, anon, authenticated;
revoke all on table public.exchange_rates from public, anon, authenticated;
revoke all on table public.item_categories from public, anon, authenticated;
revoke all on table public.items from public, anon, authenticated;
revoke all on table public.operational_alert_reads from public, anon, authenticated;
revoke all on table public.production_document_settings from public, anon, authenticated;
revoke all on table public.production_formula_lines from public, anon, authenticated;
revoke all on table public.production_formulas from public, anon, authenticated;
revoke all on table public.production_job_events from public, anon, authenticated;
revoke all on table public.production_job_reservations from public, anon, authenticated;
revoke all on table public.production_jobs from public, anon, authenticated;
revoke all on table public.production_one_step_requests from public, anon, authenticated;
revoke all on table public.production_packaging_types from public, anon, authenticated;
revoke all on table public.production_plans from public, anon, authenticated;
revoke all on table public.production_reservation_locations from public, anon, authenticated;
revoke all on table public.production_run_lines from public, anon, authenticated;
revoke all on table public.production_runs from public, anon, authenticated;
revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.purchase_counters from public, anon, authenticated;
revoke all on table public.purchase_order_lines from public, anon, authenticated;
revoke all on table public.purchase_order_requests from public, anon, authenticated;
revoke all on table public.purchase_orders from public, anon, authenticated;
revoke all on table public.purchase_receipt_lines from public, anon, authenticated;
revoke all on table public.purchase_receipts from public, anon, authenticated;
revoke all on table public.role_permissions from public, anon, authenticated;
revoke all on table public.roles from public, anon, authenticated;
revoke all on table public.sale_adjustment_lines from public, anon, authenticated;
revoke all on table public.sale_adjustments from public, anon, authenticated;
revoke all on table public.sale_checkouts from public, anon, authenticated;
revoke all on table public.sale_counters from public, anon, authenticated;
revoke all on table public.sale_lines from public, anon, authenticated;
revoke all on table public.sale_payment_reversals from public, anon, authenticated;
revoke all on table public.sale_payments from public, anon, authenticated;
revoke all on table public.sale_refunds from public, anon, authenticated;
revoke all on table public.sales from public, anon, authenticated;
revoke all on table public.stock_balances from public, anon, authenticated;
revoke all on table public.stock_lot_balances from public, anon, authenticated;
revoke all on table public.stock_lot_openings from public, anon, authenticated;
revoke all on table public.stock_lots from public, anon, authenticated;
revoke all on table public.stock_movements from public, anon, authenticated;
revoke all on table public.stock_operations from public, anon, authenticated;
revoke all on table public.supplier_items from public, anon, authenticated;
revoke all on table public.supplier_payment_order_lines from public, anon, authenticated;
revoke all on table public.supplier_payment_orders from public, anon, authenticated;
revoke all on table public.supplier_price_adjustments from public, anon, authenticated;
revoke all on table public.suppliers from public, anon, authenticated;
revoke all on table public.treasury_accounts from public, anon, authenticated;
revoke all on table public.treasury_entries from public, anon, authenticated;
revoke all on table public.treasury_sale_accounts from public, anon, authenticated;
revoke all on table public.units from public, anon, authenticated;
revoke all on table public.warehouses from public, anon, authenticated;
grant SELECT on table public.companies to authenticated;
grant SELECT on table public.company_modules to authenticated;
grant SELECT on table public.company_settings to authenticated;
grant SELECT on table public.company_users to authenticated;
grant SELECT on table public.customers to authenticated;
grant SELECT on table public.delivery_note_lines to authenticated;
grant SELECT on table public.delivery_note_reversals to authenticated;
grant SELECT on table public.delivery_notes to authenticated;
grant SELECT on table public.exchange_rate_types to authenticated;
grant SELECT on table public.exchange_rates to authenticated;
grant SELECT on table public.item_categories to authenticated;
grant SELECT on table public.items to authenticated;
grant INSERT, SELECT, UPDATE on table public.operational_alert_reads to authenticated;
grant SELECT on table public.production_document_settings to authenticated;
grant SELECT on table public.production_formula_lines to authenticated;
grant SELECT on table public.production_formulas to authenticated;
grant SELECT on table public.production_job_events to authenticated;
grant SELECT on table public.production_job_reservations to authenticated;
grant SELECT on table public.production_jobs to authenticated;
grant SELECT on table public.production_packaging_types to authenticated;
grant SELECT on table public.production_plans to authenticated;
grant SELECT on table public.production_reservation_locations to authenticated;
grant SELECT on table public.production_run_lines to authenticated;
grant SELECT on table public.production_runs to authenticated;
grant SELECT on table public.profiles to authenticated;
grant SELECT on table public.purchase_order_lines to authenticated;
grant SELECT on table public.purchase_orders to authenticated;
grant SELECT on table public.purchase_receipt_lines to authenticated;
grant SELECT on table public.purchase_receipts to authenticated;
grant SELECT on table public.role_permissions to authenticated;
grant SELECT on table public.roles to authenticated;
grant SELECT on table public.sale_adjustment_lines to authenticated;
grant SELECT on table public.sale_adjustments to authenticated;
grant SELECT on table public.sale_lines to authenticated;
grant SELECT on table public.sale_payment_reversals to authenticated;
grant SELECT on table public.sale_payments to authenticated;
grant SELECT on table public.sale_refunds to authenticated;
grant SELECT on table public.sales to authenticated;
grant SELECT on table public.stock_balances to authenticated;
grant SELECT on table public.stock_lot_balances to authenticated;
grant SELECT on table public.stock_lot_openings to authenticated;
grant SELECT on table public.stock_lots to authenticated;
grant SELECT on table public.stock_movements to authenticated;
grant SELECT on table public.stock_operations to authenticated;
grant DELETE, SELECT on table public.supplier_items to authenticated;
grant SELECT on table public.supplier_payment_order_lines to authenticated;
grant SELECT on table public.supplier_payment_orders to authenticated;
grant SELECT on table public.supplier_price_adjustments to authenticated;
grant SELECT on table public.suppliers to authenticated;
grant SELECT on table public.treasury_accounts to authenticated;
grant SELECT on table public.treasury_entries to authenticated;
grant SELECT on table public.treasury_sale_accounts to authenticated;
grant SELECT on table public.units to authenticated;
grant SELECT on table public.warehouses to authenticated;
grant UPDATE (name) on table public.companies to authenticated;
grant UPDATE (currency_code, timezone) on table public.company_settings to authenticated;
grant INSERT (company_id, name, tax_id, email, phone, address, notes, active) on table public.customers to authenticated;
grant UPDATE (name, tax_id, email, phone, address, notes, active) on table public.customers to authenticated;
grant INSERT (company_id, code, name, description, active) on table public.item_categories to authenticated;
grant UPDATE (code, name, description, active) on table public.item_categories to authenticated;
grant INSERT (company_id, code, name, item_type, category_id, unit_id, barcode, description, minimum_stock, track_lots, active, reference_unit_cost, infinite_stock) on table public.items to authenticated;
grant UPDATE (code, name, item_type, category_id, unit_id, barcode, description, minimum_stock, track_lots, active, reference_unit_cost, infinite_stock) on table public.items to authenticated;
grant UPDATE (name) on table public.profiles to authenticated;
grant INSERT (company_id, supplier_id, item_id, unit_price, supplier_sku, currency_code, exchange_rate_type_id, adjustment_percent, preferred) on table public.supplier_items to authenticated;
grant UPDATE (unit_price, supplier_sku, currency_code, exchange_rate_type_id, adjustment_percent, preferred) on table public.supplier_items to authenticated;
grant INSERT (company_id, name, tax_id, email, phone, notes, active, lead_time_days, supplies_description) on table public.suppliers to authenticated;
grant UPDATE (name, tax_id, email, phone, notes, active, lead_time_days, supplies_description) on table public.suppliers to authenticated;
grant INSERT (company_id, code, name, symbol, dimension, active) on table public.units to authenticated;
grant UPDATE (code, name, symbol, dimension, active) on table public.units to authenticated;
grant INSERT (company_id, code, name, location, active) on table public.warehouses to authenticated;
grant UPDATE (code, name, location, active) on table public.warehouses to authenticated;
revoke all on function private.check_infinite_stock_change() from public, anon, authenticated;
revoke all on function private.check_item_catalogs() from public, anon, authenticated;
revoke all on function private.check_reference_fx_cost() from public, anon, authenticated;
revoke all on function private.check_stock_catalog_deactivation() from public, anon, authenticated;
revoke all on function private.check_supplier_item() from public, anon, authenticated;
revoke all on function private.cleanup_has_references(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated;
revoke all on function private.cleanup_target(p_resource text) from public, anon, authenticated;
revoke all on function private.current_fx_rate(p_company uuid, p_type uuid) from public, anon, authenticated;
revoke all on function private.erp_production_alerts(p_company uuid) from public, anon, authenticated;
revoke all on function private.get_user_role(p_company uuid) from public, anon, authenticated;
revoke all on function private.guard_archived_formula_edit() from public, anon, authenticated;
revoke all on function private.guard_archived_recipe() from public, anon, authenticated;
revoke all on function private.guard_purchase_supplier_item() from public, anon, authenticated;
revoke all on function private.guard_reversal_after_refund() from public, anon, authenticated;
revoke all on function private.guard_sale_payment_net() from public, anon, authenticated;
revoke all on function private.has_permission(p_company uuid, p_resource text, p_action text) from public, anon, authenticated;
revoke all on function private.is_company_member(p_company uuid) from public, anon, authenticated;
revoke all on function private.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function private.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) from public, anon, authenticated;
revoke all on function private.prepare_item_import(p_company uuid, p_rows jsonb, p_existing uuid) from public, anon, authenticated;
revoke all on function private.prepare_production_document() from public, anon, authenticated;
revoke all on function private.prevent_infinite_physical_movement() from public, anon, authenticated;
revoke all on function private.prevent_late_lot_tracking() from public, anon, authenticated;
revoke all on function private.prevent_preferred_quote_deletion() from public, anon, authenticated;
revoke all on function private.prevent_stock_unit_change() from public, anon, authenticated;
revoke all on function private.prevent_supplier_price_unit_mismatch() from public, anon, authenticated;
revoke all on function private.production_unit_cost(p_company uuid, p_item uuid, p_path uuid[]) from public, anon, authenticated;
revoke all on function private.protect_archived_activity() from public, anon, authenticated;
revoke all on function private.protect_preferred_material_cost() from public, anon, authenticated;
revoke all on function private.rebalance_production_on_event() from public, anon, authenticated;
revoke all on function private.rebalance_production_reservations(p_company uuid) from public, anon, authenticated;
revoke all on function private.refresh_fx_costs() from public, anon, authenticated;
revoke all on function private.refresh_quote_cost() from public, anon, authenticated;
revoke all on function private.reject_stock_history_mutation() from public, anon, authenticated;
revoke all on function private.reject_stock_operation_mutation() from public, anon, authenticated;
revoke all on function private.release_closed_production_job() from public, anon, authenticated;
revoke all on function private.reserve_new_production_job() from public, anon, authenticated;
revoke all on function private.snapshot_purchase_item_name() from public, anon, authenticated;
revoke all on function private.snapshot_work_options(p_company uuid, p_options jsonb) from public, anon, authenticated;
revoke all on function private.support_session_active(p_company uuid) from public, anon, authenticated;
revoke all on function private.sync_preferred_material_cost(p_company uuid, p_item uuid) from public, anon, authenticated;
revoke all on function private.touch_item_updated_at() from public, anon, authenticated;
revoke all on function public.accept_company_invitation(p_token text) from public, anon, authenticated;
revoke all on function public.activate_item_lots(p_company uuid, p_item uuid) from public, anon, authenticated;
revoke all on function public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date) from public, anon, authenticated;
revoke all on function public.add_exchange_rate_type(p_company uuid, p_name text) from public, anon, authenticated;
revoke all on function public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.archived_records(p_company uuid, p_resource text, p_search text, p_page integer) from public, anon, authenticated;
revoke all on function public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid) from public, anon, authenticated;
revoke all on function public.begin_support_session(p_company uuid, p_reason text) from public, anon, authenticated;
revoke all on function public.cancel_production_job(p_company uuid, p_job uuid, p_reason text) from public, anon, authenticated;
revoke all on function public.cancel_production_plan(p_company uuid, p_plan uuid) from public, anon, authenticated;
revoke all on function public.cancel_purchase_order(p_company uuid, p_order uuid) from public, anon, authenticated;
revoke all on function public.cancel_supplier_payment_order(p_company uuid, p_payment uuid) from public, anon, authenticated;
revoke all on function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated;
revoke all on function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text) from public, anon, authenticated;
revoke all on function public.company_invitation_list(p_company uuid) from public, anon, authenticated;
revoke all on function public.company_members(p_company uuid) from public, anon, authenticated;
revoke all on function public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid) from public, anon, authenticated;
revoke all on function public.complete_production_plan(p_company uuid, p_plan uuid, p_request_id uuid, p_inputs jsonb, p_output_lot text, p_expires_on date) from public, anon, authenticated;
revoke all on function public.confirm_supplier_payment_order(p_company uuid, p_payment uuid) from public, anon, authenticated;
revoke all on function public.create_company(p_name text) from public, anon, authenticated;
revoke all on function public.create_company_invitation(p_company uuid, p_email text, p_role uuid) from public, anon, authenticated;
revoke all on function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb) from public, anon, authenticated;
revoke all on function public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid) from public, anon, authenticated;
revoke all on function public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb) from public, anon, authenticated;
revoke all on function public.create_purchase_order(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb) from public, anon, authenticated;
revoke all on function public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid) from public, anon, authenticated;
revoke all on function public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric) from public, anon, authenticated;
revoke all on function public.erp_admin_product_costs(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text, p_page integer) from public, anon, authenticated;
revoke all on function public.erp_admin_sales_profit_summary(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric) from public, anon, authenticated;
revoke all on function public.erp_dashboard(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_operational_dashboard(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_operational_report(p_company uuid, p_from date, p_to date) from public, anon, authenticated;
revoke all on function public.erp_product_costs(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.erp_production_alerts(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_production_dashboard(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_public_price_list(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.erp_replenishment_forecast(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_sales_profit_summary(p_company uuid) from public, anon, authenticated;
revoke all on function public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric) from public, anon, authenticated;
revoke all on function public.exchange_rate_overview(p_company uuid) from public, anon, authenticated;
revoke all on function public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.import_items(p_company uuid, p_rows jsonb) from public, anon, authenticated;
revoke all on function public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) from public, anon, authenticated;
revoke all on function public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) from public, anon, authenticated;
revoke all on function public.item_cost_context(p_company uuid, p_item uuid) from public, anon, authenticated;
revoke all on function public.my_company_access() from public, anon, authenticated;
revoke all on function public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb) from public, anon, authenticated;
revoke all on function public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid) from public, anon, authenticated;
revoke all on function public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid) from public, anon, authenticated;
revoke all on function public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) from public, anon, authenticated;
revoke all on function public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid) from public, anon, authenticated;
revoke all on function public.preview_item_import(p_company uuid, p_rows jsonb) from public, anon, authenticated;
revoke all on function public.production_formula_cost(p_company uuid, p_product uuid) from public, anon, authenticated;
revoke all on function public.purchase_item_options(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.purchase_material_options(p_company uuid, p_search text, p_supplier uuid) from public, anon, authenticated;
revoke all on function public.purchase_receivable_lines(p_company uuid, p_order uuid) from public, anon, authenticated;
revoke all on function public.purchase_supplier_quotes(p_company uuid, p_supplier uuid, p_item uuid) from public, anon, authenticated;
revoke all on function public.purchase_suppliers_for_items(p_company uuid, p_items uuid[]) from public, anon, authenticated;
revoke all on function public.recalculate_production_reservations(p_company uuid) from public, anon, authenticated;
revoke all on function public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb) from public, anon, authenticated;
revoke all on function public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated;
revoke all on function public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated;
revoke all on function public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text) from public, anon, authenticated;
revoke all on function public.revoke_company_invitation(p_company uuid, p_invitation uuid) from public, anon, authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated;
revoke all on function public.sale_credit_balance(p_company uuid, p_sale uuid) from public, anon, authenticated;
revoke all on function public.sale_receivables(p_company uuid, p_page integer, p_search text) from public, anon, authenticated;
revoke all on function public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean) from public, anon, authenticated;
revoke all on function public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb) from public, anon, authenticated;
revoke all on function public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb) from public, anon, authenticated;
revoke all on function public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric) from public, anon, authenticated;
revoke all on function public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean) from public, anon, authenticated;
revoke all on function public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone) from public, anon, authenticated;
revoke all on function public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone, p_create_only boolean) from public, anon, authenticated;
revoke all on function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean) from public, anon, authenticated;
revoke all on function public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid) from public, anon, authenticated;
revoke all on function public.start_production_job(p_company uuid, p_job uuid) from public, anon, authenticated;
revoke all on function public.stock_item_options(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.stock_lot_breakdown(p_company uuid, p_item uuid) from public, anon, authenticated;
revoke all on function public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid) from public, anon, authenticated;
revoke all on function public.stock_summary(p_company uuid, p_page integer, p_search text) from public, anon, authenticated;
revoke all on function public.stock_warehouse_options(p_company uuid, p_search text) from public, anon, authenticated;
revoke all on function public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer) from public, anon, authenticated;
revoke all on function public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric) from public, anon, authenticated;
revoke all on function public.supplier_cost_comparison(p_company uuid, p_supplier uuid, p_item uuid) from public, anon, authenticated;
revoke all on function public.supplier_directory(p_company uuid, p_search text, p_page integer) from public, anon, authenticated;
revoke all on function public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer) from public, anon, authenticated;
revoke all on function public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date) from public, anon, authenticated;
revoke all on function public.supplier_quote_catalog(p_company uuid, p_supplier uuid, p_item uuid, p_search text, p_page integer) from public, anon, authenticated;
revoke all on function public.treasury_activity(p_company uuid) from public, anon, authenticated;
revoke all on function public.treasury_balances(p_company uuid) from public, anon, authenticated;
revoke all on function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb) from public, anon, authenticated;
revoke all on function public.void_delivery_note(p_company uuid, p_note uuid, p_reason text) from public, anon, authenticated;
grant execute on function private.get_user_role(p_company uuid) to authenticated;
grant execute on function private.has_permission(p_company uuid, p_resource text, p_action text) to authenticated;
grant execute on function private.is_company_member(p_company uuid) to authenticated;
grant execute on function private.rebalance_production_on_event() to public;
grant execute on function private.release_closed_production_job() to public;
grant execute on function private.reserve_new_production_job() to public;
grant execute on function public.activate_item_lots(p_company uuid, p_item uuid) to authenticated;
grant execute on function public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date) to authenticated;
grant execute on function public.add_exchange_rate_type(p_company uuid, p_name text) to authenticated;
grant execute on function public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid) to authenticated;
grant execute on function public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid) to authenticated;
grant execute on function public.archived_records(p_company uuid, p_resource text, p_search text, p_page integer) to authenticated;
grant execute on function public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid) to authenticated;
grant execute on function public.begin_support_session(p_company uuid, p_reason text) to authenticated;
grant execute on function public.cancel_production_job(p_company uuid, p_job uuid, p_reason text) to authenticated;
grant execute on function public.cancel_production_plan(p_company uuid, p_plan uuid) to authenticated;
grant execute on function public.cancel_purchase_order(p_company uuid, p_order uuid) to authenticated;
grant execute on function public.cancel_supplier_payment_order(p_company uuid, p_payment uuid) to authenticated;
grant execute on function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid) to authenticated;
grant execute on function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text) to authenticated;
grant execute on function public.company_invitation_list(p_company uuid) to authenticated;
grant execute on function public.company_members(p_company uuid) to authenticated;
grant execute on function public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid) to authenticated;
grant execute on function public.confirm_supplier_payment_order(p_company uuid, p_payment uuid) to authenticated;
grant execute on function public.create_company(p_name text) to authenticated;
grant execute on function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb) to authenticated;
grant execute on function public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid) to authenticated;
grant execute on function public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid) to authenticated;
grant execute on function public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb) to authenticated;
grant execute on function public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) to authenticated;
grant execute on function public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid) to authenticated;
grant execute on function public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric) to authenticated;
grant execute on function public.erp_admin_product_costs(p_company uuid, p_search text) to authenticated;
grant execute on function public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text, p_page integer) to authenticated;
grant execute on function public.erp_admin_sales_profit_summary(p_company uuid) to authenticated;
grant execute on function public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric) to authenticated;
grant execute on function public.erp_dashboard(p_company uuid) to authenticated;
grant execute on function public.erp_operational_dashboard(p_company uuid) to authenticated;
grant execute on function public.erp_operational_report(p_company uuid, p_from date, p_to date) to authenticated;
grant execute on function public.erp_production_alerts(p_company uuid) to authenticated;
grant execute on function public.erp_production_dashboard(p_company uuid) to authenticated;
grant execute on function public.erp_public_price_list(p_company uuid, p_search text) to authenticated;
grant execute on function public.erp_replenishment_forecast(p_company uuid) to authenticated;
grant execute on function public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric) to authenticated;
grant execute on function public.exchange_rate_overview(p_company uuid) to authenticated;
grant execute on function public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid) to authenticated;
grant execute on function public.import_items(p_company uuid, p_rows jsonb) to authenticated;
grant execute on function public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) to authenticated;
grant execute on function public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) to authenticated;
grant execute on function public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) to authenticated;
grant execute on function public.item_cost_context(p_company uuid, p_item uuid) to authenticated;
grant execute on function public.my_company_access() to authenticated;
grant execute on function public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb) to authenticated;
grant execute on function public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid) to authenticated;
grant execute on function public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid) to authenticated;
grant execute on function public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid) to authenticated;
grant execute on function public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid) to authenticated;
grant execute on function public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) to authenticated;
grant execute on function public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid) to authenticated;
grant execute on function public.preview_item_import(p_company uuid, p_rows jsonb) to authenticated;
grant execute on function public.production_formula_cost(p_company uuid, p_product uuid) to authenticated;
grant execute on function public.purchase_item_options(p_company uuid, p_search text) to authenticated;
grant execute on function public.purchase_material_options(p_company uuid, p_search text, p_supplier uuid) to authenticated;
grant execute on function public.purchase_receivable_lines(p_company uuid, p_order uuid) to authenticated;
grant execute on function public.purchase_supplier_quotes(p_company uuid, p_supplier uuid, p_item uuid) to authenticated;
grant execute on function public.purchase_suppliers_for_items(p_company uuid, p_items uuid[]) to authenticated;
grant execute on function public.recalculate_production_reservations(p_company uuid) to authenticated;
grant execute on function public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb) to authenticated;
grant execute on function public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid) to authenticated;
grant execute on function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid) to authenticated;
grant execute on function public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid) to authenticated;
grant execute on function public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text) to authenticated;
grant execute on function public.rls_auto_enable() to public;
grant execute on function public.sale_credit_balance(p_company uuid, p_sale uuid) to authenticated;
grant execute on function public.sale_receivables(p_company uuid, p_page integer, p_search text) to authenticated;
grant execute on function public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean) to authenticated;
grant execute on function public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb) to authenticated;
grant execute on function public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb) to authenticated;
grant execute on function public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric) to authenticated;
grant execute on function public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean) to authenticated;
grant execute on function public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone) to authenticated;
grant execute on function public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone, p_create_only boolean) to authenticated;
grant execute on function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean) to authenticated;
grant execute on function public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid) to authenticated;
grant execute on function public.start_production_job(p_company uuid, p_job uuid) to authenticated;
grant execute on function public.stock_item_options(p_company uuid, p_search text) to authenticated;
grant execute on function public.stock_lot_breakdown(p_company uuid, p_item uuid) to authenticated;
grant execute on function public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid) to authenticated;
grant execute on function public.stock_summary(p_company uuid, p_page integer, p_search text) to authenticated;
grant execute on function public.stock_warehouse_options(p_company uuid, p_search text) to authenticated;
grant execute on function public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer) to authenticated;
grant execute on function public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric) to authenticated;
grant execute on function public.supplier_cost_comparison(p_company uuid, p_supplier uuid, p_item uuid) to authenticated;
grant execute on function public.supplier_directory(p_company uuid, p_search text, p_page integer) to authenticated;
grant execute on function public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer) to authenticated;
grant execute on function public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date) to authenticated;
grant execute on function public.supplier_quote_catalog(p_company uuid, p_supplier uuid, p_item uuid, p_search text, p_page integer) to authenticated;
grant execute on function public.treasury_activity(p_company uuid) to authenticated;
grant execute on function public.treasury_balances(p_company uuid) to authenticated;
grant execute on function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb) to authenticated;
grant execute on function public.void_delivery_note(p_company uuid, p_note uuid, p_reason text) to authenticated;
grant usage on schema private to authenticated;
