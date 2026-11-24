-- Deshacer 043. Solo quita lo que creó 043 (3 funciones y 8 índices). No toca datos, stock ni funciones anteriores.
-- Efecto sobre el frontend: sin estas funciones la pestaña "Estadística" y el cierre con ajustes dejan de funcionar
-- (volver al frontend anterior o seguir con entregas/devoluciones manuales antes de terminar).
-- Las órdenes terminadas con la función nueva conservan sus movimientos: son eventos normales de la orden.
begin;
drop function if exists public.finish_production_job_adjusted(uuid, uuid, numeric, text, date, text, uuid, jsonb, jsonb);
drop function if exists public.production_output_by_product(uuid, date, date, text, integer, integer, text);
drop function if exists public.production_output_summary(uuid, date, date, text, uuid, text);
drop index if exists public.production_jobs_done_idx;
drop index if exists public.production_jobs_product_idx;
drop index if exists public.production_job_events_issue_idx;
drop index if exists public.production_job_events_component_idx;
drop index if exists public.production_runs_product_idx;
drop index if exists public.production_run_lines_component_idx;
drop index if exists public.production_formula_lines_component_idx;
drop index if exists public.stock_lots_expiry_idx;
commit;
