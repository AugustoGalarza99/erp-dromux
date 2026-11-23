-- Fase 2 de 2 para ocultar costos. NO aplicar hasta que:
--   1) 035_costos_funciones.sql esté aplicada y comprobada,
--   2) el frontend que usa list_production_jobs/plans/runs/items y get_item_detail esté publicado,
--   3) no queden pestañas con la versión anterior (el VersionMonitor avisa de la nueva versión).
-- Después de esta migración, un select directo de las columnas de costo falla con "permission denied".
-- Reversión: ver el bloque al final. Las funciones SECURITY DEFINER no se ven afectadas.
begin;

-- Costo de referencia del ítem: lectura solo por get_item_detail/list_production_items y las
-- funciones de compras; escritura solo por save_item_with_cost e import_items.
revoke select on public.items from authenticated;
grant select (id,company_id,code,name,item_type,category_id,unit_id,barcode,description,
  minimum_stock,track_lots,active,created_at,updated_at,sale_unit_price,infinite_stock,
  reference_exchange_rate_type_id,yield_enabled,yield_factor,archived,archive_previous_active)
  on public.items to authenticated;
revoke insert (reference_unit_cost,reference_cost_usd) on public.items from authenticated;
revoke update (reference_unit_cost,reference_cost_usd) on public.items from authenticated;

-- Costos de producción: lectura solo por list_production_jobs/plans/runs (admin con finance:read).
revoke select on public.production_job_events from authenticated;
grant select (id,company_id,job_id,request_id,kind,issue_id,component_id,warehouse_id,lot_code,
  quantity,stock_operation_id,note,actor_id,created_at)
  on public.production_job_events to authenticated;

revoke select on public.production_plans from authenticated;
grant select (id,company_id,request_id,product_id,warehouse_id,quantity,formula_version,due_on,note,
  status,run_id,completion_request_id,actor_id,created_at,completed_at,cancelled_at,archived)
  on public.production_plans to authenticated;

revoke select on public.production_run_lines from authenticated;
grant select (company_id,run_id,component_id,warehouse_id,quantity,lot_code,stock_operation_id)
  on public.production_run_lines to authenticated;

revoke select on public.production_runs from authenticated;
grant select (id,company_id,product_id,formula_version,quantity,warehouse_id,output_operation_id,
  request_id,request_payload,note,actor_id,created_at,archived)
  on public.production_runs to authenticated;

revoke select on public.production_jobs from authenticated;
grant select (id,company_id,request_id,request_payload,product_id,plan_id,planned_quantity,
  actual_quantity,warehouse_id,due_on,formula_version,status,note,cancel_reason,variance_note,
  output_lot,output_expiry,run_id,completion_request_id,actor_id,created_at,started_at,completed_at,
  cancelled_at,number,yield_factor,expected_output,document_snapshot,work_options,
  work_request_options,details_updated_at,archived)
  on public.production_jobs to authenticated;

revoke select on public.sale_lines from authenticated;
grant select (company_id,sale_id,line_no,item_id,item_code,item_name,unit_symbol,warehouse_id,
  warehouse_code,lot_code,quantity,unit_price,line_total,stock_operation_id)
  on public.sale_lines to authenticated;

commit;

-- Reversión (solo si hay que volver atrás):
--   grant select on public.items,public.production_job_events,public.production_plans,
--     public.production_run_lines,public.production_runs,public.production_jobs,public.sale_lines
--     to authenticated;
--   grant insert (reference_unit_cost,reference_cost_usd),update (reference_unit_cost,reference_cost_usd)
--     on public.items to authenticated;
