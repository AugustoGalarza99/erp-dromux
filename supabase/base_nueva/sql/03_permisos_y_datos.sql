-- 03. Disparadores, políticas, permisos y catálogo de permisos.
begin;


CREATE TRIGGER access_audit_no_change BEFORE DELETE OR UPDATE ON public.ajustes_auditoria_accesos FOR EACH ROW EXECUTE FUNCTION private.access_audit_immutable();
CREATE TRIGGER access_audit_no_truncate BEFORE TRUNCATE ON public.ajustes_auditoria_accesos FOR EACH STATEMENT EXECUTE FUNCTION private.access_audit_immutable();
CREATE TRIGGER delivery_note_lines_immutable BEFORE DELETE OR UPDATE ON public.stock_remitos_lineas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER delivery_note_reversals_immutable BEFORE DELETE OR UPDATE ON public.stock_remitos_reversiones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER exchange_archived_activity BEFORE INSERT OR UPDATE OF activo, archivado ON public.finanzas_tipos_cambio FOR EACH ROW EXECUTE FUNCTION private.protect_archived_activity();
CREATE TRIGGER exchange_rates_immutable BEFORE DELETE OR UPDATE ON public.finanzas_cotizaciones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER fx_rate_cost_changed AFTER INSERT ON public.finanzas_cotizaciones FOR EACH ROW EXECUTE FUNCTION private.refresh_fx_costs();
CREATE TRIGGER item_archived_activity BEFORE INSERT OR UPDATE OF activo, archivado ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.protect_archived_activity();
CREATE TRIGGER items_check_catalogs BEFORE INSERT OR UPDATE OF empresa_id, categoria_id, unidad_id ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.check_item_catalogs();
CREATE TRIGGER items_infinite_transition BEFORE INSERT OR UPDATE OF stock_infinito ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.check_infinite_stock_change();
CREATE TRIGGER items_preferred_cost_protect BEFORE UPDATE OF costo_unitario_referencia ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.protect_preferred_material_cost();
CREATE TRIGGER items_prevent_late_lot_tracking BEFORE UPDATE OF usa_lotes ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.prevent_late_lot_tracking();
CREATE TRIGGER items_prevent_stock_stranding BEFORE UPDATE OF activo ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.check_stock_catalog_deactivation();
CREATE TRIGGER items_prevent_unit_change BEFORE UPDATE OF unidad_id ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.prevent_stock_unit_change();
CREATE TRIGGER items_protect_supplier_prices BEFORE UPDATE OF unidad_id, tipo_item ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.prevent_supplier_price_unit_mismatch();
CREATE TRIGGER items_reference_fx_cost BEFORE INSERT OR UPDATE OF costo_unitario_referencia, costo_referencia_usd, tipo_cambio_referencia_id ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.check_reference_fx_cost();
CREATE TRIGGER items_touch_updated_at BEFORE UPDATE ON public.stock_items FOR EACH ROW EXECUTE FUNCTION private.touch_item_updated_at();
CREATE TRIGGER price_history_immutable BEFORE DELETE OR UPDATE ON public.ventas_listas_items_historial FOR EACH ROW EXECUTE FUNCTION private.price_history_immutable();
CREATE TRIGGER price_lists_guard BEFORE INSERT OR UPDATE ON public.ventas_listas_precios FOR EACH ROW EXECUTE FUNCTION private.price_lists_guard();
CREATE TRIGGER guard_archived_formula_edit BEFORE UPDATE OF cantidad_base, version ON public.produccion_formulas FOR EACH ROW EXECUTE FUNCTION private.guard_archived_formula_edit();
CREATE TRIGGER production_job_events_immutable BEFORE DELETE OR UPDATE ON public.produccion_ordenes_eventos FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER rebalance_production_after_event AFTER INSERT ON public.produccion_ordenes_eventos FOR EACH ROW EXECUTE FUNCTION private.rebalance_production_on_event();
CREATE TRIGGER guard_archived_job_recipe BEFORE INSERT ON public.produccion_ordenes FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_job_document BEFORE INSERT ON public.produccion_ordenes FOR EACH ROW EXECUTE FUNCTION private.prepare_production_document();
CREATE TRIGGER release_production_job_after_update AFTER UPDATE OF estado ON public.produccion_ordenes FOR EACH ROW EXECUTE FUNCTION private.release_closed_production_job();
CREATE TRIGGER reserve_production_job_after_insert AFTER INSERT ON public.produccion_ordenes FOR EACH ROW EXECUTE FUNCTION private.reserve_new_production_job();
CREATE TRIGGER guard_archived_plan_recipe BEFORE INSERT ON public.produccion_planes FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_run_lines_immutable BEFORE DELETE OR UPDATE ON public.produccion_fabricaciones_lineas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_archived_run_recipe BEFORE INSERT ON public.produccion_fabricaciones FOR EACH ROW EXECUTE FUNCTION private.guard_archived_recipe();
CREATE TRIGGER production_runs_immutable BEFORE DELETE OR UPDATE ON public.produccion_fabricaciones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_purchase_supplier_item BEFORE INSERT ON public.compras_ordenes_lineas FOR EACH ROW EXECUTE FUNCTION private.guard_purchase_supplier_item();
CREATE TRIGGER purchase_lines_snapshot_name BEFORE INSERT ON public.compras_ordenes_lineas FOR EACH ROW EXECUTE FUNCTION private.snapshot_purchase_item_name();
CREATE TRIGGER purchase_receipt_lines_immutable BEFORE DELETE OR UPDATE ON public.compras_recepciones_lineas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER purchase_receipts_immutable BEFORE DELETE OR UPDATE ON public.compras_recepciones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER purchase_request_lines_immutable BEFORE DELETE OR UPDATE ON public.compras_pedidos_lineas FOR EACH ROW EXECUTE FUNCTION private.purchase_request_lines_immutable();
CREATE TRIGGER purchase_requests_guard BEFORE DELETE OR UPDATE ON public.compras_pedidos FOR EACH ROW EXECUTE FUNCTION private.purchase_requests_guard();
CREATE TRIGGER quote_lines_immutable BEFORE DELETE OR UPDATE ON public.ventas_presupuestos_lineas FOR EACH ROW EXECUTE FUNCTION private.quote_lines_immutable();
CREATE TRIGGER quote_status_events_immutable BEFORE DELETE OR UPDATE ON public.ventas_presupuestos_estados FOR EACH ROW EXECUTE FUNCTION private.quote_lines_immutable();
CREATE TRIGGER quotes_guard BEFORE DELETE OR UPDATE ON public.ventas_presupuestos FOR EACH ROW EXECUTE FUNCTION private.quotes_guard();
CREATE TRIGGER sale_adjustment_lines_immutable BEFORE DELETE OR UPDATE ON public.ventas_ajustes_lineas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_adjustments_immutable BEFORE DELETE ON public.ventas_ajustes FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_lines_immutable BEFORE DELETE OR UPDATE ON public.ventas_lineas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_reversal_after_refund BEFORE INSERT ON public.ventas_cobros_reversiones FOR EACH ROW EXECUTE FUNCTION private.guard_reversal_after_refund();
CREATE TRIGGER sale_payment_reversals_immutable BEFORE DELETE OR UPDATE ON public.ventas_cobros_reversiones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER guard_sale_payment_net BEFORE INSERT ON public.ventas_cobros FOR EACH ROW EXECUTE FUNCTION private.guard_sale_payment_net();
CREATE TRIGGER sale_payments_immutable BEFORE DELETE OR UPDATE ON public.ventas_cobros FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sale_refunds_immutable BEFORE DELETE OR UPDATE ON public.ventas_reintegros FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER sales_immutable BEFORE DELETE OR UPDATE ON public.ventas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_lot_openings_immutable BEFORE DELETE OR UPDATE ON public.stock_lotes_aperturas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_lots_immutable BEFORE DELETE OR UPDATE ON public.stock_lotes FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_movements_immutable BEFORE DELETE OR UPDATE ON public.stock_movimientos FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER stock_movements_infinite_guard BEFORE INSERT ON public.stock_movimientos FOR EACH ROW EXECUTE FUNCTION private.prevent_infinite_physical_movement();
CREATE TRIGGER stock_operations_immutable BEFORE DELETE OR UPDATE ON public.stock_operaciones FOR EACH ROW EXECUTE FUNCTION private.reject_stock_operation_mutation();
CREATE TRIGGER supplier_items_check BEFORE INSERT OR UPDATE ON public.compras_proveedores_items FOR EACH ROW EXECUTE FUNCTION private.check_supplier_item();
CREATE TRIGGER supplier_preferred_protect BEFORE DELETE ON public.compras_proveedores_items FOR EACH ROW EXECUTE FUNCTION private.prevent_preferred_quote_deletion();
CREATE TRIGGER supplier_quote_cost_changed AFTER INSERT OR DELETE OR UPDATE ON public.compras_proveedores_items FOR EACH ROW EXECUTE FUNCTION private.refresh_quote_cost();
CREATE TRIGGER supplier_adjustments_immutable BEFORE DELETE OR UPDATE ON public.compras_proveedores_ajustes_precio FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER treasury_entries_immutable BEFORE DELETE OR UPDATE ON public.finanzas_movimientos FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER treasury_sale_accounts_immutable BEFORE DELETE OR UPDATE ON public.finanzas_cobros_cuentas FOR EACH ROW EXECUTE FUNCTION private.reject_stock_history_mutation();
CREATE TRIGGER warehouses_prevent_stock_stranding BEFORE UPDATE OF activo ON public.stock_depositos FOR EACH ROW EXECUTE FUNCTION private.check_stock_catalog_deactivation();

create policy empresas_member_select on public.empresas as permissive for select to authenticated
  using (( SELECT private.is_company_member(empresas.id) AS is_company_member));
create policy empresas_usuarios_self_or_admin_select on public.empresas_usuarios as permissive for select to authenticated
  using ((((usuario_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.is_company_member(empresas_usuarios.empresa_id) AS is_company_member)) OR ( SELECT private.has_permission(empresas_usuarios.empresa_id, 'usuarios'::text, 'ver'::text) AS has_permission)));
create policy ventas_clientes_insert on public.ventas_clientes as permissive for insert to authenticated
  with check (( SELECT private.has_permission(ventas_clientes.empresa_id, 'ventas'::text, 'crear'::text) AS has_permission));
create policy ventas_clientes_read on public.ventas_clientes as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_clientes.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_clientes_update on public.ventas_clientes as permissive for update to authenticated
  using (( SELECT private.has_permission(ventas_clientes.empresa_id, 'ventas'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(ventas_clientes.empresa_id, 'ventas'::text, 'editar'::text) AS has_permission));
create policy stock_remitos_lineas_delivery_lines_read on public.stock_remitos_lineas as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM stock_remitos d
  WHERE ((d.empresa_id = stock_remitos_lineas.empresa_id) AND (d.id = stock_remitos_lineas.remito_id) AND (private.has_permission(d.empresa_id, 'stock_remitos'::text, 'ver'::text) OR ((d.tipo = 'produccion'::text) AND private.has_permission(d.empresa_id, 'produccion_ordenes'::text, 'ver'::text)))))));
create policy stock_remitos_reversiones_delivery_reversals_read on public.stock_remitos_reversiones as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM stock_remitos d
  WHERE ((d.empresa_id = stock_remitos_reversiones.empresa_id) AND (d.id = stock_remitos_reversiones.remito_id) AND (private.has_permission(d.empresa_id, 'stock_remitos'::text, 'ver'::text) OR ((d.tipo = 'produccion'::text) AND private.has_permission(d.empresa_id, 'produccion_ordenes'::text, 'ver'::text)))))));
create policy stock_remitos_read on public.stock_remitos as permissive for select to authenticated
  using ((( SELECT private.has_permission(stock_remitos.empresa_id, 'stock_remitos'::text, 'ver'::text) AS has_permission) OR ((tipo = 'produccion'::text) AND ( SELECT private.has_permission(stock_remitos.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission))));
create policy finanzas_tipos_cambio_read on public.finanzas_tipos_cambio as permissive for select to authenticated
  using ((( SELECT private.has_permission(finanzas_tipos_cambio.empresa_id, 'compras_proveedores'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(finanzas_tipos_cambio.empresa_id, 'costos_materiales'::text, 'ver'::text) AS has_permission)));
create policy finanzas_cotizaciones_read on public.finanzas_cotizaciones as permissive for select to authenticated
  using ((( SELECT private.has_permission(finanzas_cotizaciones.empresa_id, 'compras_proveedores'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(finanzas_cotizaciones.empresa_id, 'costos_materiales'::text, 'ver'::text) AS has_permission)));
create policy stock_categorias_categories_insert on public.stock_categorias as permissive for insert to authenticated
  with check (( SELECT private.has_permission(stock_categorias.empresa_id, 'categorias'::text, 'crear'::text) AS has_permission));
create policy stock_categorias_categories_read on public.stock_categorias as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_categorias.empresa_id, 'categorias'::text, 'ver'::text) AS has_permission));
create policy stock_categorias_categories_update on public.stock_categorias as permissive for update to authenticated
  using (( SELECT private.has_permission(stock_categorias.empresa_id, 'categorias'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(stock_categorias.empresa_id, 'categorias'::text, 'editar'::text) AS has_permission));
create policy ventas_items_config_read on public.ventas_items_config as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_items_config.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy stock_items_insert on public.stock_items as permissive for insert to authenticated
  with check (( SELECT private.has_permission(stock_items.empresa_id, 'items'::text, 'crear'::text) AS has_permission));
create policy stock_items_read on public.stock_items as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_items.empresa_id, 'items'::text, 'ver'::text) AS has_permission));
create policy stock_items_update on public.stock_items as permissive for update to authenticated
  using (( SELECT private.has_permission(stock_items.empresa_id, 'items'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(stock_items.empresa_id, 'items'::text, 'editar'::text) AS has_permission));
create policy inicio_alertas_leidas_insert on public.inicio_alertas_leidas as permissive for insert to authenticated
  with check (((usuario_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(inicio_alertas_leidas.empresa_id, 'inicio'::text, 'ver'::text) AS has_permission)));
create policy inicio_alertas_leidas_select on public.inicio_alertas_leidas as permissive for select to authenticated
  using (((usuario_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(inicio_alertas_leidas.empresa_id, 'inicio'::text, 'ver'::text) AS has_permission)));
create policy inicio_alertas_leidas_update on public.inicio_alertas_leidas as permissive for update to authenticated
  using (((usuario_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(inicio_alertas_leidas.empresa_id, 'inicio'::text, 'ver'::text) AS has_permission)))
  with check (((usuario_id = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(inicio_alertas_leidas.empresa_id, 'inicio'::text, 'ver'::text) AS has_permission)));
create policy ajustes_permisos_catalogo_read on public.ajustes_permisos_catalogo as permissive for select to authenticated
  using (true);
create policy ventas_listas_items_read on public.ventas_listas_items as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_listas_items.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_listas_precios_read on public.ventas_listas_precios as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_listas_precios.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy produccion_documentos_config_document_settings_read on public.produccion_documentos_config as permissive for select to authenticated
  using ((private.has_permission(empresa_id, 'produccion_documentos'::text, 'ver'::text) OR private.has_permission(empresa_id, 'produccion_ordenes'::text, 'ver'::text) OR ((private.get_user_role(empresa_id) = 'administrador'::text) AND private.has_permission(empresa_id, 'inicio'::text, 'ver'::text))));
create policy produccion_formulas_lineas_read on public.produccion_formulas_lineas as permissive for select to authenticated
  using ((( SELECT private.has_permission(produccion_formulas_lineas.empresa_id, 'produccion_formulas'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas_lineas.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas_lineas.empresa_id, 'produccion_planificacion'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas_lineas.empresa_id, 'produccion_disponibilidad'::text, 'ver'::text) AS has_permission)));
create policy produccion_formulas_read on public.produccion_formulas as permissive for select to authenticated
  using ((( SELECT private.has_permission(produccion_formulas.empresa_id, 'produccion_formulas'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas.empresa_id, 'produccion_planificacion'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_formulas.empresa_id, 'produccion_disponibilidad'::text, 'ver'::text) AS has_permission)));
create policy produccion_ordenes_eventos_read on public.produccion_ordenes_eventos as permissive for select to authenticated
  using (( SELECT private.has_permission(produccion_ordenes_eventos.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission));
create policy produccion_ordenes_reservas_production_reservations_read on public.produccion_ordenes_reservas as permissive for select to authenticated
  using (((( SELECT private.has_permission(produccion_ordenes_reservas.empresa_id, 'produccion_disponibilidad'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_ordenes_reservas.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission)) AND ( SELECT private.has_permission(produccion_ordenes_reservas.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission)));
create policy produccion_ordenes_read on public.produccion_ordenes as permissive for select to authenticated
  using ((( SELECT private.has_permission(produccion_ordenes.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_ordenes.empresa_id, 'produccion_resumen'::text, 'ver'::text) AS has_permission)));
create policy produccion_tipos_envase_packaging_types_read on public.produccion_tipos_envase as permissive for select to authenticated
  using ((private.has_permission(empresa_id, 'produccion_envasado'::text, 'ver'::text) OR private.has_permission(empresa_id, 'produccion_ordenes'::text, 'ver'::text)));
create policy produccion_planes_read on public.produccion_planes as permissive for select to authenticated
  using (( SELECT private.has_permission(produccion_planes.empresa_id, 'produccion_planificacion'::text, 'ver'::text) AS has_permission));
create policy produccion_reservas_ubicaciones_reservation_locations_read on public.produccion_reservas_ubicaciones as permissive for select to authenticated
  using (((( SELECT private.has_permission(produccion_reservas_ubicaciones.empresa_id, 'produccion_disponibilidad'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_reservas_ubicaciones.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission)) AND ( SELECT private.has_permission(produccion_reservas_ubicaciones.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission)));
create policy produccion_fabricaciones_lineas_read on public.produccion_fabricaciones_lineas as permissive for select to authenticated
  using ((( SELECT private.has_permission(produccion_fabricaciones_lineas.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_fabricaciones_lineas.empresa_id, 'produccion_resumen'::text, 'ver'::text) AS has_permission)));
create policy produccion_fabricaciones_read on public.produccion_fabricaciones as permissive for select to authenticated
  using ((( SELECT private.has_permission(produccion_fabricaciones.empresa_id, 'produccion_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(produccion_fabricaciones.empresa_id, 'produccion_resumen'::text, 'ver'::text) AS has_permission)));
create policy ajustes_perfiles_self_select on public.ajustes_perfiles as permissive for select to authenticated
  using ((id = ( SELECT auth.uid() AS uid)));
create policy ajustes_perfiles_self_update on public.ajustes_perfiles as permissive for update to authenticated
  using ((id = ( SELECT auth.uid() AS uid)))
  with check ((id = ( SELECT auth.uid() AS uid)));
create policy compras_ordenes_lineas_purchase_lines_read on public.compras_ordenes_lineas as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_ordenes_lineas.empresa_id, 'compras_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_ordenes_lineas.empresa_id, 'compras_resumen'::text, 'ver'::text) AS has_permission)));
create policy compras_ordenes_read on public.compras_ordenes as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_ordenes.empresa_id, 'compras_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_ordenes.empresa_id, 'compras_resumen'::text, 'ver'::text) AS has_permission)));
create policy compras_recepciones_lineas_read on public.compras_recepciones_lineas as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_recepciones_lineas.empresa_id, 'compras_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_recepciones_lineas.empresa_id, 'compras_resumen'::text, 'ver'::text) AS has_permission)));
create policy compras_recepciones_read on public.compras_recepciones as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_recepciones.empresa_id, 'compras_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_recepciones.empresa_id, 'compras_resumen'::text, 'ver'::text) AS has_permission)));
create policy compras_pedidos_lineas_read on public.compras_pedidos_lineas as permissive for select to authenticated
  using ((EXISTS ( SELECT 1
   FROM compras_pedidos r
  WHERE ((r.empresa_id = compras_pedidos_lineas.empresa_id) AND (r.id = compras_pedidos_lineas.pedido_id)))));
create policy compras_pedidos_read on public.compras_pedidos as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_pedidos.empresa_id, 'compras_pedidos'::text, 'gestionar'::text) AS has_permission) OR ((solicitado_por = ( SELECT auth.uid() AS uid)) AND ( SELECT private.has_permission(compras_pedidos.empresa_id, 'compras_pedidos'::text, 'ver'::text) AS has_permission))));
create policy ventas_presupuestos_lineas_read on public.ventas_presupuestos_lineas as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_presupuestos_lineas.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_presupuestos_estados_read on public.ventas_presupuestos_estados as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_presupuestos_estados.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_presupuestos_read on public.ventas_presupuestos as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_presupuestos.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ajustes_roles_permisos_member_select on public.ajustes_roles_permisos as permissive for select to authenticated
  using (( SELECT private.is_company_member(ajustes_roles_permisos.empresa_id) AS is_company_member));
create policy ajustes_roles_member_select on public.ajustes_roles as permissive for select to authenticated
  using (( SELECT private.is_company_member(ajustes_roles.empresa_id) AS is_company_member));
create policy ventas_ajustes_lineas_read on public.ventas_ajustes_lineas as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_ajustes_lineas.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_ajustes_read on public.ventas_ajustes as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_ajustes.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_lineas_read on public.ventas_lineas as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_lineas.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy ventas_cobros_reversiones_read on public.ventas_cobros_reversiones as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_cobros_reversiones.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy ventas_cobros_read on public.ventas_cobros as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_cobros.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy ventas_reintegros_read on public.ventas_reintegros as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas_reintegros.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy ventas_read on public.ventas as permissive for select to authenticated
  using (( SELECT private.has_permission(ventas.empresa_id, 'ventas'::text, 'ver'::text) AS has_permission));
create policy stock_saldos_read on public.stock_saldos as permissive for select to authenticated
  using ((( SELECT private.has_permission(stock_saldos.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_saldos.empresa_id, 'inventario'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_saldos.empresa_id, 'stock_remitos'::text, 'ver'::text) AS has_permission)));
create policy stock_lotes_saldos_read on public.stock_lotes_saldos as permissive for select to authenticated
  using ((( SELECT private.has_permission(stock_lotes_saldos.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes_saldos.empresa_id, 'inventario'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes_saldos.empresa_id, 'stock_remitos'::text, 'ver'::text) AS has_permission)));
create policy stock_lotes_aperturas_read on public.stock_lotes_aperturas as permissive for select to authenticated
  using ((( SELECT private.has_permission(stock_lotes_aperturas.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes_aperturas.empresa_id, 'inventario'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes_aperturas.empresa_id, 'stock_remitos'::text, 'ver'::text) AS has_permission)));
create policy stock_lotes_read on public.stock_lotes as permissive for select to authenticated
  using ((( SELECT private.has_permission(stock_lotes.empresa_id, 'stock_saldos'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes.empresa_id, 'inventario'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(stock_lotes.empresa_id, 'stock_remitos'::text, 'ver'::text) AS has_permission)));
create policy stock_movimientos_read on public.stock_movimientos as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_movimientos.empresa_id, 'stock_movimientos'::text, 'ver'::text) AS has_permission));
create policy stock_operaciones_read on public.stock_operaciones as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_operaciones.empresa_id, 'stock_movimientos'::text, 'ver'::text) AS has_permission));
create policy compras_proveedores_items_delete on public.compras_proveedores_items as permissive for delete to authenticated
  using (( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission));
create policy compras_proveedores_items_insert on public.compras_proveedores_items as permissive for insert to authenticated
  with check (( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission));
create policy compras_proveedores_items_read on public.compras_proveedores_items as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'compras_proveedores'::text, 'ver'::text) AS has_permission) AND ( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'costos_materiales'::text, 'ver'::text) AS has_permission)));
create policy compras_proveedores_items_update on public.compras_proveedores_items as permissive for update to authenticated
  using (( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(compras_proveedores_items.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission));
create policy compras_pagos_lineas_payment_order_lines_read on public.compras_pagos_lineas as permissive for select to authenticated
  using ((private.has_permission(empresa_id, 'finanzas'::text, 'ver'::text) AND private.has_permission(empresa_id, 'compras_cuentas'::text, 'ver'::text)));
create policy compras_pagos_payment_orders_read on public.compras_pagos as permissive for select to authenticated
  using ((private.has_permission(empresa_id, 'finanzas'::text, 'ver'::text) AND private.has_permission(empresa_id, 'compras_cuentas'::text, 'ver'::text)));
create policy compras_proveedores_ajustes_precio_read on public.compras_proveedores_ajustes_precio as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_proveedores_ajustes_precio.empresa_id, 'compras_proveedores'::text, 'ver'::text) AS has_permission) AND ( SELECT private.has_permission(compras_proveedores_ajustes_precio.empresa_id, 'costos_materiales'::text, 'ver'::text) AS has_permission)));
create policy compras_proveedores_insert on public.compras_proveedores as permissive for insert to authenticated
  with check (( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_proveedores'::text, 'crear'::text) AS has_permission));
create policy compras_proveedores_read on public.compras_proveedores as permissive for select to authenticated
  using ((( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_proveedores'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_ordenes'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_cuentas'::text, 'ver'::text) AS has_permission) OR ( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_resumen'::text, 'ver'::text) AS has_permission)));
create policy compras_proveedores_update on public.compras_proveedores as permissive for update to authenticated
  using (( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(compras_proveedores.empresa_id, 'compras_proveedores'::text, 'editar'::text) AS has_permission));
create policy finanzas_cuentas_read on public.finanzas_cuentas as permissive for select to authenticated
  using (( SELECT private.has_permission(finanzas_cuentas.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy finanzas_movimientos_read on public.finanzas_movimientos as permissive for select to authenticated
  using (( SELECT private.has_permission(finanzas_movimientos.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy finanzas_cobros_cuentas_read on public.finanzas_cobros_cuentas as permissive for select to authenticated
  using (( SELECT private.has_permission(finanzas_cobros_cuentas.empresa_id, 'finanzas'::text, 'ver'::text) AS has_permission));
create policy stock_unidades_insert on public.stock_unidades as permissive for insert to authenticated
  with check (( SELECT private.has_permission(stock_unidades.empresa_id, 'unidades'::text, 'crear'::text) AS has_permission));
create policy stock_unidades_read on public.stock_unidades as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_unidades.empresa_id, 'unidades'::text, 'ver'::text) AS has_permission));
create policy stock_unidades_update on public.stock_unidades as permissive for update to authenticated
  using (( SELECT private.has_permission(stock_unidades.empresa_id, 'unidades'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(stock_unidades.empresa_id, 'unidades'::text, 'editar'::text) AS has_permission));
create policy stock_depositos_insert on public.stock_depositos as permissive for insert to authenticated
  with check (( SELECT private.has_permission(stock_depositos.empresa_id, 'depositos'::text, 'crear'::text) AS has_permission));
create policy stock_depositos_read on public.stock_depositos as permissive for select to authenticated
  using (( SELECT private.has_permission(stock_depositos.empresa_id, 'depositos'::text, 'ver'::text) AS has_permission));
create policy stock_depositos_update on public.stock_depositos as permissive for update to authenticated
  using (( SELECT private.has_permission(stock_depositos.empresa_id, 'depositos'::text, 'editar'::text) AS has_permission))
  with check (( SELECT private.has_permission(stock_depositos.empresa_id, 'depositos'::text, 'editar'::text) AS has_permission));

revoke all on table private.produccion_solicitudes_eliminadas from public, anon, authenticated, service_role;
revoke all on table private.soporte_accesos from public, anon, authenticated, service_role;
revoke all on table private.soporte_operadores from public, anon, authenticated, service_role;
revoke all on table private.soporte_sesiones from public, anon, authenticated, service_role;
revoke all on table public.ajustes_auditoria_accesos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ajustes_auditoria_accesos to service_role;
revoke all on table public.empresas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.empresas to service_role;
grant select on table public.empresas to authenticated;
revoke all on table public.empresas_perfil from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.empresas_perfil to service_role;
revoke all on table public.empresas_usuarios from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.empresas_usuarios to service_role;
grant select on table public.empresas_usuarios to authenticated;
revoke all on table public.ventas_clientes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_clientes to service_role;
grant select on table public.ventas_clientes to authenticated;
grant insert (empresa_id) on table public.ventas_clientes to authenticated;
grant insert (nombre) on table public.ventas_clientes to authenticated;
grant update (nombre) on table public.ventas_clientes to authenticated;
grant insert (identificacion_fiscal) on table public.ventas_clientes to authenticated;
grant update (identificacion_fiscal) on table public.ventas_clientes to authenticated;
grant insert (email) on table public.ventas_clientes to authenticated;
grant update (email) on table public.ventas_clientes to authenticated;
grant insert (telefono) on table public.ventas_clientes to authenticated;
grant update (telefono) on table public.ventas_clientes to authenticated;
grant insert (direccion) on table public.ventas_clientes to authenticated;
grant update (direccion) on table public.ventas_clientes to authenticated;
grant insert (nota) on table public.ventas_clientes to authenticated;
grant update (nota) on table public.ventas_clientes to authenticated;
grant insert (activo) on table public.ventas_clientes to authenticated;
grant update (activo) on table public.ventas_clientes to authenticated;
revoke all on table public.stock_remitos_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_remitos_lineas to service_role;
grant select on table public.stock_remitos_lineas to authenticated;
revoke all on table public.stock_remitos_reversiones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_remitos_reversiones to service_role;
grant select on table public.stock_remitos_reversiones to authenticated;
revoke all on table public.stock_remitos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_remitos to service_role;
grant select on table public.stock_remitos to authenticated;
revoke all on table public.finanzas_tipos_cambio from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.finanzas_tipos_cambio to service_role;
grant select on table public.finanzas_tipos_cambio to authenticated;
revoke all on table public.finanzas_cotizaciones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.finanzas_cotizaciones to service_role;
grant select on table public.finanzas_cotizaciones to authenticated;
revoke all on table public.stock_categorias from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_categorias to service_role;
grant select on table public.stock_categorias to authenticated;
grant insert (empresa_id) on table public.stock_categorias to authenticated;
grant insert (codigo) on table public.stock_categorias to authenticated;
grant update (codigo) on table public.stock_categorias to authenticated;
grant insert (nombre) on table public.stock_categorias to authenticated;
grant update (nombre) on table public.stock_categorias to authenticated;
grant insert (descripcion) on table public.stock_categorias to authenticated;
grant update (descripcion) on table public.stock_categorias to authenticated;
grant insert (activo) on table public.stock_categorias to authenticated;
grant update (activo) on table public.stock_categorias to authenticated;
revoke all on table public.ventas_items_config from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_items_config to service_role;
grant select on table public.ventas_items_config to authenticated;
revoke all on table public.stock_items from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_items to service_role;
grant select (id) on table public.stock_items to authenticated;
grant insert (empresa_id) on table public.stock_items to authenticated;
grant select (empresa_id) on table public.stock_items to authenticated;
grant insert (codigo) on table public.stock_items to authenticated;
grant select (codigo) on table public.stock_items to authenticated;
grant update (codigo) on table public.stock_items to authenticated;
grant insert (nombre) on table public.stock_items to authenticated;
grant select (nombre) on table public.stock_items to authenticated;
grant update (nombre) on table public.stock_items to authenticated;
grant insert (tipo_item) on table public.stock_items to authenticated;
grant select (tipo_item) on table public.stock_items to authenticated;
grant update (tipo_item) on table public.stock_items to authenticated;
grant insert (categoria_id) on table public.stock_items to authenticated;
grant select (categoria_id) on table public.stock_items to authenticated;
grant update (categoria_id) on table public.stock_items to authenticated;
grant insert (unidad_id) on table public.stock_items to authenticated;
grant select (unidad_id) on table public.stock_items to authenticated;
grant update (unidad_id) on table public.stock_items to authenticated;
grant insert (codigo_barras) on table public.stock_items to authenticated;
grant select (codigo_barras) on table public.stock_items to authenticated;
grant update (codigo_barras) on table public.stock_items to authenticated;
grant insert (descripcion) on table public.stock_items to authenticated;
grant select (descripcion) on table public.stock_items to authenticated;
grant update (descripcion) on table public.stock_items to authenticated;
grant insert (stock_minimo) on table public.stock_items to authenticated;
grant select (stock_minimo) on table public.stock_items to authenticated;
grant update (stock_minimo) on table public.stock_items to authenticated;
grant insert (usa_lotes) on table public.stock_items to authenticated;
grant select (usa_lotes) on table public.stock_items to authenticated;
grant update (usa_lotes) on table public.stock_items to authenticated;
grant insert (activo) on table public.stock_items to authenticated;
grant select (activo) on table public.stock_items to authenticated;
grant update (activo) on table public.stock_items to authenticated;
grant select (creado_en) on table public.stock_items to authenticated;
grant select (actualizado_en) on table public.stock_items to authenticated;
grant select (precio_venta_unitario) on table public.stock_items to authenticated;
grant insert (stock_infinito) on table public.stock_items to authenticated;
grant select (stock_infinito) on table public.stock_items to authenticated;
grant update (stock_infinito) on table public.stock_items to authenticated;
grant select (tipo_cambio_referencia_id) on table public.stock_items to authenticated;
grant select (usa_rendimiento) on table public.stock_items to authenticated;
grant select (factor_rendimiento) on table public.stock_items to authenticated;
grant select (archivado) on table public.stock_items to authenticated;
grant select (activo_antes_de_archivar) on table public.stock_items to authenticated;
revoke all on table public.inicio_alertas_leidas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.inicio_alertas_leidas to service_role;
grant insert, select, update on table public.inicio_alertas_leidas to authenticated;
revoke all on table public.ajustes_permisos_catalogo from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ajustes_permisos_catalogo to service_role;
grant select on table public.ajustes_permisos_catalogo to authenticated;
revoke all on table public.ventas_precios_antiduplicado from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_precios_antiduplicado to service_role;
revoke all on table public.ventas_listas_items_historial from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_listas_items_historial to service_role;
revoke all on table public.ventas_listas_items_metodo from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_listas_items_metodo to service_role;
revoke all on table public.ventas_listas_items from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_listas_items to service_role;
grant select on table public.ventas_listas_items to authenticated;
revoke all on table public.ventas_listas_precios from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_listas_precios to service_role;
grant select on table public.ventas_listas_precios to authenticated;
revoke all on table public.ventas_precios_config from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_precios_config to service_role;
revoke all on table public.produccion_documentos_config from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_documentos_config to service_role;
grant select on table public.produccion_documentos_config to authenticated;
revoke all on table public.produccion_formulas_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_formulas_lineas to service_role;
grant select on table public.produccion_formulas_lineas to authenticated;
revoke all on table public.produccion_formulas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_formulas to service_role;
grant select on table public.produccion_formulas to authenticated;
revoke all on table public.produccion_ordenes_eventos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_ordenes_eventos to service_role;
grant select (id) on table public.produccion_ordenes_eventos to authenticated;
grant select (empresa_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (orden_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (solicitud_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (tipo) on table public.produccion_ordenes_eventos to authenticated;
grant select (entrega_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (componente_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (deposito_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (lote_codigo) on table public.produccion_ordenes_eventos to authenticated;
grant select (cantidad) on table public.produccion_ordenes_eventos to authenticated;
grant select (operacion_stock_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (nota) on table public.produccion_ordenes_eventos to authenticated;
grant select (autor_id) on table public.produccion_ordenes_eventos to authenticated;
grant select (creado_en) on table public.produccion_ordenes_eventos to authenticated;
revoke all on table public.produccion_ordenes_reservas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_ordenes_reservas to service_role;
grant select on table public.produccion_ordenes_reservas to authenticated;
revoke all on table public.produccion_ordenes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_ordenes to service_role;
grant select (id) on table public.produccion_ordenes to authenticated;
grant select (empresa_id) on table public.produccion_ordenes to authenticated;
grant select (solicitud_id) on table public.produccion_ordenes to authenticated;
grant select (solicitud_datos) on table public.produccion_ordenes to authenticated;
grant select (producto_id) on table public.produccion_ordenes to authenticated;
grant select (plan_id) on table public.produccion_ordenes to authenticated;
grant select (cantidad_planificada) on table public.produccion_ordenes to authenticated;
grant select (cantidad_real) on table public.produccion_ordenes to authenticated;
grant select (deposito_id) on table public.produccion_ordenes to authenticated;
grant select (fecha_limite) on table public.produccion_ordenes to authenticated;
grant select (formula_version) on table public.produccion_ordenes to authenticated;
grant select (estado) on table public.produccion_ordenes to authenticated;
grant select (nota) on table public.produccion_ordenes to authenticated;
grant select (motivo_cancelacion) on table public.produccion_ordenes to authenticated;
grant select (nota_diferencia) on table public.produccion_ordenes to authenticated;
grant select (producto_lote) on table public.produccion_ordenes to authenticated;
grant select (producto_vencimiento) on table public.produccion_ordenes to authenticated;
grant select (fabricacion_id) on table public.produccion_ordenes to authenticated;
grant select (solicitud_cierre_id) on table public.produccion_ordenes to authenticated;
grant select (autor_id) on table public.produccion_ordenes to authenticated;
grant select (creado_en) on table public.produccion_ordenes to authenticated;
grant select (iniciado_en) on table public.produccion_ordenes to authenticated;
grant select (terminado_en) on table public.produccion_ordenes to authenticated;
grant select (cancelado_en) on table public.produccion_ordenes to authenticated;
grant select (numero) on table public.produccion_ordenes to authenticated;
grant select (factor_rendimiento) on table public.produccion_ordenes to authenticated;
grant select (cantidad_esperada) on table public.produccion_ordenes to authenticated;
grant select (documento_copia) on table public.produccion_ordenes to authenticated;
grant select (opciones_trabajo) on table public.produccion_ordenes to authenticated;
grant select (opciones_trabajo_solicitadas) on table public.produccion_ordenes to authenticated;
grant select (detalles_actualizado_en) on table public.produccion_ordenes to authenticated;
grant select (archivado) on table public.produccion_ordenes to authenticated;
revoke all on table public.produccion_fabricaciones_antiduplicado from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_fabricaciones_antiduplicado to service_role;
revoke all on table public.produccion_tipos_envase from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_tipos_envase to service_role;
grant select on table public.produccion_tipos_envase to authenticated;
revoke all on table public.produccion_planes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_planes to service_role;
grant select (id) on table public.produccion_planes to authenticated;
grant select (empresa_id) on table public.produccion_planes to authenticated;
grant select (solicitud_id) on table public.produccion_planes to authenticated;
grant select (producto_id) on table public.produccion_planes to authenticated;
grant select (deposito_id) on table public.produccion_planes to authenticated;
grant select (cantidad) on table public.produccion_planes to authenticated;
grant select (formula_version) on table public.produccion_planes to authenticated;
grant select (fecha_limite) on table public.produccion_planes to authenticated;
grant select (nota) on table public.produccion_planes to authenticated;
grant select (estado) on table public.produccion_planes to authenticated;
grant select (fabricacion_id) on table public.produccion_planes to authenticated;
grant select (solicitud_cierre_id) on table public.produccion_planes to authenticated;
grant select (autor_id) on table public.produccion_planes to authenticated;
grant select (creado_en) on table public.produccion_planes to authenticated;
grant select (terminado_en) on table public.produccion_planes to authenticated;
grant select (cancelado_en) on table public.produccion_planes to authenticated;
grant select (archivado) on table public.produccion_planes to authenticated;
revoke all on table public.produccion_reservas_ubicaciones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_reservas_ubicaciones to service_role;
grant select on table public.produccion_reservas_ubicaciones to authenticated;
revoke all on table public.produccion_fabricaciones_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_fabricaciones_lineas to service_role;
grant select (empresa_id) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (fabricacion_id) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (componente_id) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (deposito_id) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (cantidad) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (lote_codigo) on table public.produccion_fabricaciones_lineas to authenticated;
grant select (operacion_stock_id) on table public.produccion_fabricaciones_lineas to authenticated;
revoke all on table public.produccion_fabricaciones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.produccion_fabricaciones to service_role;
grant select (id) on table public.produccion_fabricaciones to authenticated;
grant select (empresa_id) on table public.produccion_fabricaciones to authenticated;
grant select (producto_id) on table public.produccion_fabricaciones to authenticated;
grant select (formula_version) on table public.produccion_fabricaciones to authenticated;
grant select (cantidad) on table public.produccion_fabricaciones to authenticated;
grant select (deposito_id) on table public.produccion_fabricaciones to authenticated;
grant select (operacion_producto_id) on table public.produccion_fabricaciones to authenticated;
grant select (solicitud_id) on table public.produccion_fabricaciones to authenticated;
grant select (solicitud_datos) on table public.produccion_fabricaciones to authenticated;
grant select (nota) on table public.produccion_fabricaciones to authenticated;
grant select (autor_id) on table public.produccion_fabricaciones to authenticated;
grant select (creado_en) on table public.produccion_fabricaciones to authenticated;
grant select (archivado) on table public.produccion_fabricaciones to authenticated;
revoke all on table public.ajustes_perfiles from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ajustes_perfiles to service_role;
grant select on table public.ajustes_perfiles to authenticated;
grant update (nombre) on table public.ajustes_perfiles to authenticated;
revoke all on table public.compras_ordenes_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_ordenes_lineas to service_role;
grant select on table public.compras_ordenes_lineas to authenticated;
revoke all on table public.compras_ordenes_antiduplicado from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_ordenes_antiduplicado to service_role;
revoke all on table public.compras_ordenes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_ordenes to service_role;
grant select on table public.compras_ordenes to authenticated;
revoke all on table public.compras_recepciones_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_recepciones_lineas to service_role;
grant select on table public.compras_recepciones_lineas to authenticated;
revoke all on table public.compras_recepciones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_recepciones to service_role;
grant select on table public.compras_recepciones to authenticated;
revoke all on table public.compras_pedidos_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_pedidos_lineas to service_role;
grant select on table public.compras_pedidos_lineas to authenticated;
revoke all on table public.compras_pedidos_antiduplicado from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_pedidos_antiduplicado to service_role;
revoke all on table public.compras_pedidos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_pedidos to service_role;
grant select on table public.compras_pedidos to authenticated;
revoke all on table public.ventas_presupuestos_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_presupuestos_lineas to service_role;
grant select on table public.ventas_presupuestos_lineas to authenticated;
revoke all on table public.ventas_presupuestos_estados from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_presupuestos_estados to service_role;
grant select on table public.ventas_presupuestos_estados to authenticated;
revoke all on table public.ventas_presupuestos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_presupuestos to service_role;
grant select (id) on table public.ventas_presupuestos to authenticated;
grant select (empresa_id) on table public.ventas_presupuestos to authenticated;
grant select (numero) on table public.ventas_presupuestos to authenticated;
grant select (cliente_id) on table public.ventas_presupuestos to authenticated;
grant select (cliente_nombre) on table public.ventas_presupuestos to authenticated;
grant select (cliente_identificacion_fiscal) on table public.ventas_presupuestos to authenticated;
grant select (cliente_email) on table public.ventas_presupuestos to authenticated;
grant select (cliente_telefono) on table public.ventas_presupuestos to authenticated;
grant select (cliente_direccion) on table public.ventas_presupuestos to authenticated;
grant select (estado) on table public.ventas_presupuestos to authenticated;
grant select (vigente_hasta) on table public.ventas_presupuestos to authenticated;
grant select (nota) on table public.ventas_presupuestos to authenticated;
grant select (mostrar_impuesto) on table public.ventas_presupuestos to authenticated;
grant select (total_neto) on table public.ventas_presupuestos to authenticated;
grant select (total_impuesto) on table public.ventas_presupuestos to authenticated;
grant select (total_bruto) on table public.ventas_presupuestos to authenticated;
grant select (impuestos_detalle) on table public.ventas_presupuestos to authenticated;
grant select (creado_por_nombre) on table public.ventas_presupuestos to authenticated;
grant select (creado_en) on table public.ventas_presupuestos to authenticated;
grant select (estado_cambiado_en) on table public.ventas_presupuestos to authenticated;
grant select (impuesto_incluido) on table public.ventas_presupuestos to authenticated;
revoke all on table public.ajustes_roles_permisos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ajustes_roles_permisos to service_role;
grant select on table public.ajustes_roles_permisos to authenticated;
revoke all on table public.ajustes_roles from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ajustes_roles to service_role;
grant select on table public.ajustes_roles to authenticated;
revoke all on table public.ventas_ajustes_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_ajustes_lineas to service_role;
grant select on table public.ventas_ajustes_lineas to authenticated;
revoke all on table public.ventas_ajustes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_ajustes to service_role;
grant select on table public.ventas_ajustes to authenticated;
revoke all on table public.ventas_cobros_antiduplicado from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_cobros_antiduplicado to service_role;
revoke all on table public.ventas_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_lineas to service_role;
grant select (empresa_id) on table public.ventas_lineas to authenticated;
grant select (venta_id) on table public.ventas_lineas to authenticated;
grant select (linea) on table public.ventas_lineas to authenticated;
grant select (item_id) on table public.ventas_lineas to authenticated;
grant select (item_codigo) on table public.ventas_lineas to authenticated;
grant select (item_nombre) on table public.ventas_lineas to authenticated;
grant select (unidad_simbolo) on table public.ventas_lineas to authenticated;
grant select (deposito_id) on table public.ventas_lineas to authenticated;
grant select (deposito_codigo) on table public.ventas_lineas to authenticated;
grant select (lote_codigo) on table public.ventas_lineas to authenticated;
grant select (cantidad) on table public.ventas_lineas to authenticated;
grant select (precio_unitario) on table public.ventas_lineas to authenticated;
grant select (total_linea) on table public.ventas_lineas to authenticated;
grant select (operacion_stock_id) on table public.ventas_lineas to authenticated;
grant select (lista_precio_id) on table public.ventas_lineas to authenticated;
grant select (precio_unitario_lista) on table public.ventas_lineas to authenticated;
grant select (descuento_porcentaje) on table public.ventas_lineas to authenticated;
grant select (descuento_motivo) on table public.ventas_lineas to authenticated;
grant select (impuesto_porcentaje) on table public.ventas_lineas to authenticated;
revoke all on table public.ventas_cobros_reversiones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_cobros_reversiones to service_role;
grant select on table public.ventas_cobros_reversiones to authenticated;
revoke all on table public.ventas_cobros from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_cobros to service_role;
grant select on table public.ventas_cobros to authenticated;
revoke all on table public.ventas_reintegros from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas_reintegros to service_role;
grant select on table public.ventas_reintegros to authenticated;
revoke all on table public.ventas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.ventas to service_role;
grant select on table public.ventas to authenticated;
revoke all on table public.stock_saldos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_saldos to service_role;
grant select on table public.stock_saldos to authenticated;
revoke all on table public.stock_lotes_saldos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_lotes_saldos to service_role;
grant select on table public.stock_lotes_saldos to authenticated;
revoke all on table public.stock_lotes_aperturas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_lotes_aperturas to service_role;
grant select on table public.stock_lotes_aperturas to authenticated;
revoke all on table public.stock_lotes from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_lotes to service_role;
grant select on table public.stock_lotes to authenticated;
revoke all on table public.stock_movimientos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_movimientos to service_role;
grant select on table public.stock_movimientos to authenticated;
revoke all on table public.stock_operaciones from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_operaciones to service_role;
grant select on table public.stock_operaciones to authenticated;
revoke all on table public.compras_proveedores_items from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_proveedores_items to service_role;
grant select, delete on table public.compras_proveedores_items to authenticated;
grant insert (empresa_id) on table public.compras_proveedores_items to authenticated;
grant insert (proveedor_id) on table public.compras_proveedores_items to authenticated;
grant insert (item_id) on table public.compras_proveedores_items to authenticated;
grant insert (precio_unitario) on table public.compras_proveedores_items to authenticated;
grant update (precio_unitario) on table public.compras_proveedores_items to authenticated;
grant insert (proveedor_codigo) on table public.compras_proveedores_items to authenticated;
grant update (proveedor_codigo) on table public.compras_proveedores_items to authenticated;
grant insert (moneda) on table public.compras_proveedores_items to authenticated;
grant update (moneda) on table public.compras_proveedores_items to authenticated;
grant insert (tipo_cambio_id) on table public.compras_proveedores_items to authenticated;
grant update (tipo_cambio_id) on table public.compras_proveedores_items to authenticated;
grant insert (ajuste_porcentaje) on table public.compras_proveedores_items to authenticated;
grant update (ajuste_porcentaje) on table public.compras_proveedores_items to authenticated;
grant insert (preferido) on table public.compras_proveedores_items to authenticated;
grant update (preferido) on table public.compras_proveedores_items to authenticated;
revoke all on table public.compras_pagos_lineas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_pagos_lineas to service_role;
grant select on table public.compras_pagos_lineas to authenticated;
revoke all on table public.compras_pagos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_pagos to service_role;
grant select on table public.compras_pagos to authenticated;
revoke all on table public.compras_proveedores_ajustes_precio from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_proveedores_ajustes_precio to service_role;
grant select on table public.compras_proveedores_ajustes_precio to authenticated;
revoke all on table public.compras_proveedores from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.compras_proveedores to service_role;
grant select on table public.compras_proveedores to authenticated;
grant insert (empresa_id) on table public.compras_proveedores to authenticated;
grant insert (nombre) on table public.compras_proveedores to authenticated;
grant update (nombre) on table public.compras_proveedores to authenticated;
grant insert (identificacion_fiscal) on table public.compras_proveedores to authenticated;
grant update (identificacion_fiscal) on table public.compras_proveedores to authenticated;
grant insert (email) on table public.compras_proveedores to authenticated;
grant update (email) on table public.compras_proveedores to authenticated;
grant insert (telefono) on table public.compras_proveedores to authenticated;
grant update (telefono) on table public.compras_proveedores to authenticated;
grant insert (nota) on table public.compras_proveedores to authenticated;
grant update (nota) on table public.compras_proveedores to authenticated;
grant insert (activo) on table public.compras_proveedores to authenticated;
grant update (activo) on table public.compras_proveedores to authenticated;
grant insert (demora_dias) on table public.compras_proveedores to authenticated;
grant update (demora_dias) on table public.compras_proveedores to authenticated;
grant insert (provee_descripcion) on table public.compras_proveedores to authenticated;
grant update (provee_descripcion) on table public.compras_proveedores to authenticated;
revoke all on table public.finanzas_cuentas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.finanzas_cuentas to service_role;
grant select on table public.finanzas_cuentas to authenticated;
revoke all on table public.finanzas_movimientos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.finanzas_movimientos to service_role;
grant select on table public.finanzas_movimientos to authenticated;
revoke all on table public.finanzas_cobros_cuentas from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.finanzas_cobros_cuentas to service_role;
grant select on table public.finanzas_cobros_cuentas to authenticated;
revoke all on table public.stock_unidades from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_unidades to service_role;
grant select on table public.stock_unidades to authenticated;
grant insert (empresa_id) on table public.stock_unidades to authenticated;
grant insert (codigo) on table public.stock_unidades to authenticated;
grant update (codigo) on table public.stock_unidades to authenticated;
grant insert (nombre) on table public.stock_unidades to authenticated;
grant update (nombre) on table public.stock_unidades to authenticated;
grant insert (simbolo) on table public.stock_unidades to authenticated;
grant update (simbolo) on table public.stock_unidades to authenticated;
grant insert (magnitud) on table public.stock_unidades to authenticated;
grant update (magnitud) on table public.stock_unidades to authenticated;
grant insert (activo) on table public.stock_unidades to authenticated;
grant update (activo) on table public.stock_unidades to authenticated;
revoke all on table public.stock_depositos from public, anon, authenticated, service_role;
grant truncate, references, trigger, maintain on table public.stock_depositos to service_role;
grant select on table public.stock_depositos to authenticated;
grant insert (empresa_id) on table public.stock_depositos to authenticated;
grant insert (codigo) on table public.stock_depositos to authenticated;
grant update (codigo) on table public.stock_depositos to authenticated;
grant insert (nombre) on table public.stock_depositos to authenticated;
grant update (nombre) on table public.stock_depositos to authenticated;
grant insert (ubicacion) on table public.stock_depositos to authenticated;
grant update (ubicacion) on table public.stock_depositos to authenticated;
grant insert (activo) on table public.stock_depositos to authenticated;
grant update (activo) on table public.stock_depositos to authenticated;
revoke all on table public.empresas_numeradores from public, anon, authenticated, service_role;

revoke all on function private.access_audit_immutable() from public, anon, authenticated, service_role;
revoke all on function private.can_see_production_costs(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.can_see_reference_cost(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.check_infinite_stock_change() from public, anon, authenticated, service_role;
revoke all on function private.check_item_catalogs() from public, anon, authenticated, service_role;
revoke all on function private.check_reference_fx_cost() from public, anon, authenticated, service_role;
revoke all on function private.check_stock_catalog_deactivation() from public, anon, authenticated, service_role;
revoke all on function private.check_supplier_item() from public, anon, authenticated, service_role;
revoke all on function private.cleanup_has_references(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated, service_role;
revoke all on function private.cleanup_target(p_resource text) from public, anon, authenticated, service_role;
revoke all on function private.current_fx_rate(p_company uuid, p_type uuid) from public, anon, authenticated, service_role;
revoke all on function private.erp_production_alerts(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.get_user_role(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function private.get_user_role(p_company uuid) to authenticated;
revoke all on function private.guard_archived_formula_edit() from public, anon, authenticated, service_role;
revoke all on function private.guard_archived_recipe() from public, anon, authenticated, service_role;
revoke all on function private.guard_purchase_supplier_item() from public, anon, authenticated, service_role;
revoke all on function private.guard_reversal_after_refund() from public, anon, authenticated, service_role;
revoke all on function private.guard_sale_payment_net() from public, anon, authenticated, service_role;
revoke all on function private.has_permission(p_company uuid, p_resource text, p_action text) from public, anon, authenticated, service_role;
grant execute on function private.has_permission(p_company uuid, p_resource text, p_action text) to authenticated;
revoke all on function private.import_items(p_company uuid, p_rows jsonb) from public, anon, authenticated, service_role;
revoke all on function private.is_company_member(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function private.is_company_member(p_company uuid) to authenticated;
revoke all on function private.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated, service_role;
revoke all on function private.log_access_event(p_company uuid, p_action text, p_user uuid, p_role uuid, p_detail jsonb) from public, anon, authenticated, service_role;
revoke all on function private.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) from public, anon, authenticated, service_role;
revoke all on function private.prepare_item_import(p_company uuid, p_rows jsonb, p_existing uuid) from public, anon, authenticated, service_role;
revoke all on function private.prepare_production_document() from public, anon, authenticated, service_role;
revoke all on function private.prevent_infinite_physical_movement() from public, anon, authenticated, service_role;
revoke all on function private.prevent_late_lot_tracking() from public, anon, authenticated, service_role;
revoke all on function private.prevent_preferred_quote_deletion() from public, anon, authenticated, service_role;
revoke all on function private.prevent_stock_unit_change() from public, anon, authenticated, service_role;
revoke all on function private.prevent_supplier_price_unit_mismatch() from public, anon, authenticated, service_role;
revoke all on function private.price_compute(p_method text, p_value numeric, p_cost numeric, p_step numeric) from public, anon, authenticated, service_role;
revoke all on function private.price_costs(p_company uuid, p_items uuid[]) from public, anon, authenticated, service_role;
revoke all on function private.price_effective(p_company uuid, p_list uuid, p_term text) from public, anon, authenticated, service_role;
revoke all on function private.price_history_immutable() from public, anon, authenticated, service_role;
revoke all on function private.price_item_cost(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
revoke all on function private.price_lists_guard() from public, anon, authenticated, service_role;
revoke all on function private.price_require_admin(p_company uuid, p_cost boolean) from public, anon, authenticated, service_role;
revoke all on function private.price_require_cost_view(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.price_round(p numeric, p_step numeric) from public, anon, authenticated, service_role;
revoke all on function private.price_write(p_company uuid, p_list uuid, p_item uuid, p_new numeric, p_method text, p_value numeric, p_cost numeric, p_keep_cost boolean, p_source text, p_reason text) from public, anon, authenticated, service_role;
revoke all on function private.production_unit_cost(p_company uuid, p_item uuid, p_path uuid[]) from public, anon, authenticated, service_role;
revoke all on function private.protect_archived_activity() from public, anon, authenticated, service_role;
revoke all on function private.protect_preferred_material_cost() from public, anon, authenticated, service_role;
revoke all on function private.purchase_request_lines_immutable() from public, anon, authenticated, service_role;
revoke all on function private.purchase_requests_guard() from public, anon, authenticated, service_role;
revoke all on function private.quote_lines_immutable() from public, anon, authenticated, service_role;
revoke all on function private.quotes_guard() from public, anon, authenticated, service_role;
revoke all on function private.rebalance_production_on_event() from public, anon, authenticated, service_role;
grant execute on function private.rebalance_production_on_event() to public;
revoke all on function private.rebalance_production_reservations(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.refresh_fx_costs() from public, anon, authenticated, service_role;
revoke all on function private.refresh_quote_cost() from public, anon, authenticated, service_role;
revoke all on function private.reject_stock_history_mutation() from public, anon, authenticated, service_role;
revoke all on function private.reject_stock_operation_mutation() from public, anon, authenticated, service_role;
revoke all on function private.release_closed_production_job() from public, anon, authenticated, service_role;
grant execute on function private.release_closed_production_job() to public;
revoke all on function private.reserve_new_production_job() from public, anon, authenticated, service_role;
grant execute on function private.reserve_new_production_job() to public;
revoke all on function private.row_has_cost(p_row jsonb) from public, anon, authenticated, service_role;
revoke all on function private.sale_resolve_price(p_company uuid, p_customer uuid, p_item uuid) from public, anon, authenticated, service_role;
revoke all on function private.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean) from public, anon, authenticated, service_role;
revoke all on function private.save_role_permissions(p_company uuid, p_role uuid, p_permissions jsonb) from public, anon, authenticated, service_role;
revoke all on function private.snapshot_purchase_item_name() from public, anon, authenticated, service_role;
revoke all on function private.snapshot_work_options(p_company uuid, p_options jsonb) from public, anon, authenticated, service_role;
revoke all on function private.strip_snapshot_cost(p_snapshot jsonb) from public, anon, authenticated, service_role;
revoke all on function private.support_session_active(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function private.sync_preferred_material_cost(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
revoke all on function private.touch_item_updated_at() from public, anon, authenticated, service_role;
revoke all on function public.access_audit_events_list(p_company uuid, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.access_audit_events_list(p_company uuid, p_page integer) to authenticated;
revoke all on function public.activate_item_lots(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.activate_item_lots(p_company uuid, p_item uuid) to authenticated;
revoke all on function public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date) from public, anon, authenticated, service_role;
grant execute on function public.add_exchange_rate(p_company uuid, p_type uuid, p_rate numeric, p_date date) to authenticated;
revoke all on function public.add_exchange_rate_type(p_company uuid, p_name text) from public, anon, authenticated, service_role;
grant execute on function public.add_exchange_rate_type(p_company uuid, p_name text) to authenticated;
revoke all on function public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.adjust_sale(p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid) to authenticated;
revoke all on function public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.adjust_supplier_prices(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid) to authenticated;
revoke all on function public.archived_records(p_company uuid, p_resource text, p_search text, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.archived_records(p_company uuid, p_resource text, p_search text, p_page integer) to authenticated;
revoke all on function public.assign_customer_price_list(p_company uuid, p_customer uuid, p_list uuid) from public, anon, authenticated, service_role;
grant execute on function public.assign_customer_price_list(p_company uuid, p_customer uuid, p_list uuid) to authenticated;
revoke all on function public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid) from public, anon, authenticated, service_role;
grant execute on function public.assign_sale_payment_account(p_company uuid, p_payment uuid, p_account uuid) to authenticated;
revoke all on function public.begin_support_session(p_company uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.begin_support_session(p_company uuid, p_reason text) to authenticated;
revoke all on function public.bulk_price_change(p_company uuid, p_list uuid, p_mode text, p_percent numeric, p_item_ids uuid[], p_apply boolean, p_reason text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.bulk_price_change(p_company uuid, p_list uuid, p_mode text, p_percent numeric, p_item_ids uuid[], p_apply boolean, p_reason text, p_request_id uuid) to authenticated;
revoke all on function public.cancel_production_job(p_company uuid, p_job uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.cancel_production_job(p_company uuid, p_job uuid, p_reason text) to authenticated;
revoke all on function public.cancel_production_plan(p_company uuid, p_plan uuid) from public, anon, authenticated, service_role;
grant execute on function public.cancel_production_plan(p_company uuid, p_plan uuid) to authenticated;
revoke all on function public.cancel_purchase_order(p_company uuid, p_order uuid) from public, anon, authenticated, service_role;
grant execute on function public.cancel_purchase_order(p_company uuid, p_order uuid) to authenticated;
revoke all on function public.cancel_purchase_request(p_company uuid, p_request uuid) from public, anon, authenticated, service_role;
grant execute on function public.cancel_purchase_request(p_company uuid, p_request uuid) to authenticated;
revoke all on function public.cancel_supplier_payment_order(p_company uuid, p_payment uuid) from public, anon, authenticated, service_role;
grant execute on function public.cancel_supplier_payment_order(p_company uuid, p_payment uuid) to authenticated;
revoke all on function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.cleanup_preview(p_company uuid, p_resource text, p_id uuid) to authenticated;
revoke all on function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text) from public, anon, authenticated, service_role;
grant execute on function public.cleanup_record(p_company uuid, p_resource text, p_id uuid, p_action text) to authenticated;
revoke all on function public.company_members(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.company_members(p_company uuid) to authenticated;
revoke all on function public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid) from public, anon, authenticated, service_role;
grant execute on function public.complete_production_now(p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid) to authenticated;
revoke all on function public.complete_production_plan(p_company uuid, p_plan uuid, p_request_id uuid, p_inputs jsonb, p_output_lot text, p_expires_on date) from public, anon, authenticated, service_role;
revoke all on function public.confirm_supplier_payment_order(p_company uuid, p_payment uuid) from public, anon, authenticated, service_role;
grant execute on function public.confirm_supplier_payment_order(p_company uuid, p_payment uuid) to authenticated;
revoke all on function public.convert_purchase_request(p_company uuid, p_request uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.convert_purchase_request(p_company uuid, p_request uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) to authenticated;
revoke all on function public.create_company(p_name text) from public, anon, authenticated, service_role;
grant execute on function public.create_company(p_name text) to authenticated;
revoke all on function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb) from public, anon, authenticated, service_role;
grant execute on function public.create_company_role(p_company uuid, p_name text, p_code text, p_permissions jsonb) to authenticated;
revoke all on function public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_production_job(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid) to authenticated;
revoke all on function public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_production_plan(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid) to authenticated;
revoke all on function public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb) from public, anon, authenticated, service_role;
grant execute on function public.create_production_work_order(p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb) to authenticated;
revoke all on function public.create_purchase_order(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb) from public, anon, authenticated, service_role;
revoke all on function public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_purchase_order_once(p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid) to authenticated;
revoke all on function public.create_purchase_request(p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_purchase_request(p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid) to authenticated;
revoke all on function public.create_quote(p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text, p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid, p_tax_included boolean) from public, anon, authenticated, service_role;
grant execute on function public.create_quote(p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text, p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid, p_tax_included boolean) to authenticated;
revoke all on function public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid) from public, anon, authenticated, service_role;
grant execute on function public.create_supplier_payment_order(p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid) to authenticated;
revoke all on function public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric) from public, anon, authenticated, service_role;
grant execute on function public.create_treasury_account(p_company uuid, p_name text, p_kind text, p_opening numeric) to authenticated;
revoke all on function public.erp_admin_price_list_rows(p_company uuid, p_list uuid, p_search text, p_filter text, p_page integer, p_page_size integer) from public, anon, authenticated, service_role;
grant execute on function public.erp_admin_price_list_rows(p_company uuid, p_list uuid, p_search text, p_filter text, p_page integer, p_page_size integer) to authenticated;
revoke all on function public.erp_admin_product_costs(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.erp_admin_product_costs(p_company uuid, p_search text) to authenticated;
revoke all on function public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.erp_admin_sales_profit_detail(p_company uuid, p_from date, p_to date, p_search text, p_page integer) to authenticated;
revoke all on function public.erp_admin_sales_profit_summary(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_admin_sales_profit_summary(p_company uuid) to authenticated;
revoke all on function public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric) from public, anon, authenticated, service_role;
grant execute on function public.erp_can_manufacture(p_company uuid, p_product uuid, p_quantity numeric) to authenticated;
revoke all on function public.erp_company_profile(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_company_profile(p_company uuid) to authenticated;
revoke all on function public.erp_dashboard(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_dashboard(p_company uuid) to authenticated;
revoke all on function public.erp_operational_dashboard(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_operational_dashboard(p_company uuid) to authenticated;
revoke all on function public.erp_operational_report(p_company uuid, p_from date, p_to date) from public, anon, authenticated, service_role;
grant execute on function public.erp_operational_report(p_company uuid, p_from date, p_to date) to authenticated;
revoke all on function public.erp_price_list_history(p_company uuid, p_list uuid, p_item uuid, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.erp_price_list_history(p_company uuid, p_list uuid, p_item uuid, p_page integer) to authenticated;
revoke all on function public.erp_price_list_rows(p_company uuid, p_list uuid, p_search text, p_only_missing boolean, p_page integer, p_page_size integer) from public, anon, authenticated, service_role;
grant execute on function public.erp_price_list_rows(p_company uuid, p_list uuid, p_search text, p_only_missing boolean, p_page integer, p_page_size integer) to authenticated;
revoke all on function public.erp_price_settings(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_price_settings(p_company uuid) to authenticated;
revoke all on function public.erp_product_costs(p_company uuid, p_search text) from public, anon, authenticated, service_role;
revoke all on function public.erp_production_alerts(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_production_alerts(p_company uuid) to authenticated;
revoke all on function public.erp_production_dashboard(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_production_dashboard(p_company uuid) to authenticated;
revoke all on function public.erp_public_price_list(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.erp_public_price_list(p_company uuid, p_search text) to authenticated;
revoke all on function public.erp_quote_detail(p_company uuid, p_quote uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_quote_detail(p_company uuid, p_quote uuid) to authenticated;
revoke all on function public.erp_quotes_page(p_company uuid, p_search text, p_status text, p_page integer, p_size integer) from public, anon, authenticated, service_role;
grant execute on function public.erp_quotes_page(p_company uuid, p_search text, p_status text, p_page integer, p_size integer) to authenticated;
revoke all on function public.erp_replenishment_forecast(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_replenishment_forecast(p_company uuid) to authenticated;
revoke all on function public.erp_resolve_sale_price(p_company uuid, p_customer uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_resolve_sale_price(p_company uuid, p_customer uuid, p_item uuid) to authenticated;
revoke all on function public.erp_sale_discount_policy(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.erp_sale_discount_policy(p_company uuid) to authenticated;
revoke all on function public.erp_sale_prices(p_company uuid, p_customer uuid, p_items uuid[]) from public, anon, authenticated, service_role;
grant execute on function public.erp_sale_prices(p_company uuid, p_customer uuid, p_items uuid[]) to authenticated;
revoke all on function public.erp_sales_profit_summary(p_company uuid) from public, anon, authenticated, service_role;
revoke all on function public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric) from public, anon, authenticated, service_role;
grant execute on function public.erp_set_finished_product_price(p_company uuid, p_item uuid, p_price numeric) to authenticated;
revoke all on function public.exchange_rate_overview(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.exchange_rate_overview(p_company uuid) to authenticated;
revoke all on function public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.finish_production_job(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid) to authenticated;
revoke all on function public.finish_production_job_adjusted(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid, p_adjustments jsonb, p_packaging jsonb) from public, anon, authenticated, service_role;
grant execute on function public.finish_production_job_adjusted(p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid, p_adjustments jsonb, p_packaging jsonb) to authenticated;
revoke all on function public.get_item_detail(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_item_detail(p_company uuid, p_item uuid) to authenticated;
revoke all on function public.import_items(p_company uuid, p_rows jsonb) from public, anon, authenticated, service_role;
grant execute on function public.import_items(p_company uuid, p_rows jsonb) to authenticated;
revoke all on function public.import_price_list_items(p_company uuid, p_list uuid, p_rows jsonb, p_apply boolean, p_reason text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.import_price_list_items(p_company uuid, p_list uuid, p_rows jsonb, p_apply boolean, p_reason text, p_request_id uuid) to authenticated;
revoke all on function public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) from public, anon, authenticated, service_role;
grant execute on function public.issue_delivery_note(p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) to authenticated;
revoke all on function public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.issue_production_material(p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid) to authenticated;
revoke all on function public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) from public, anon, authenticated, service_role;
grant execute on function public.issue_sale_delivery_note(p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid) to authenticated;
revoke all on function public.item_cost_context(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.item_cost_context(p_company uuid, p_item uuid) to authenticated;
revoke all on function public.list_production_items(p_company uuid, p_include_inactive boolean) from public, anon, authenticated, service_role;
grant execute on function public.list_production_items(p_company uuid, p_include_inactive boolean) to authenticated;
revoke all on function public.list_production_jobs(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.list_production_jobs(p_company uuid) to authenticated;
revoke all on function public.list_production_plans(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.list_production_plans(p_company uuid) to authenticated;
revoke all on function public.list_production_runs(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.list_production_runs(p_company uuid) to authenticated;
revoke all on function public.my_company_access() from public, anon, authenticated, service_role;
grant execute on function public.my_company_access() to authenticated;
revoke all on function public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb) from public, anon, authenticated, service_role;
grant execute on function public.post_production_run(p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb) to authenticated;
revoke all on function public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.post_sale(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid) to authenticated;
revoke all on function public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.post_sale_payment(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid) to authenticated;
revoke all on function public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid) from public, anon, authenticated, service_role;
grant execute on function public.post_sale_payment_to_account(p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid) to authenticated;
revoke all on function public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid) from public, anon, authenticated, service_role;
grant execute on function public.post_sale_with_payment(p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid) to authenticated;
revoke all on function public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) from public, anon, authenticated, service_role;
grant execute on function public.post_stock_operation(p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date) to authenticated;
revoke all on function public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid) from public, anon, authenticated, service_role;
grant execute on function public.post_treasury_entry(p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid) to authenticated;
revoke all on function public.preview_item_import(p_company uuid, p_rows jsonb) from public, anon, authenticated, service_role;
grant execute on function public.preview_item_import(p_company uuid, p_rows jsonb) to authenticated;
revoke all on function public.production_formula_cost(p_company uuid, p_product uuid) from public, anon, authenticated, service_role;
grant execute on function public.production_formula_cost(p_company uuid, p_product uuid) to authenticated;
revoke all on function public.production_output_by_product(p_company uuid, p_from date, p_to date, p_search text, p_limit integer, p_offset integer, p_tz text) from public, anon, authenticated, service_role;
grant execute on function public.production_output_by_product(p_company uuid, p_from date, p_to date, p_search text, p_limit integer, p_offset integer, p_tz text) to authenticated;
revoke all on function public.production_output_summary(p_company uuid, p_from date, p_to date, p_bucket text, p_product uuid, p_tz text) from public, anon, authenticated, service_role;
grant execute on function public.production_output_summary(p_company uuid, p_from date, p_to date, p_bucket text, p_product uuid, p_tz text) to authenticated;
revoke all on function public.purchase_item_options(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.purchase_item_options(p_company uuid, p_search text) to authenticated;
revoke all on function public.purchase_material_options(p_company uuid, p_search text, p_supplier uuid) from public, anon, authenticated, service_role;
grant execute on function public.purchase_material_options(p_company uuid, p_search text, p_supplier uuid) to authenticated;
revoke all on function public.purchase_receivable_lines(p_company uuid, p_order uuid) from public, anon, authenticated, service_role;
grant execute on function public.purchase_receivable_lines(p_company uuid, p_order uuid) to authenticated;
revoke all on function public.purchase_request_item_options(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.purchase_request_item_options(p_company uuid, p_search text) to authenticated;
revoke all on function public.purchase_supplier_quotes(p_company uuid, p_supplier uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.purchase_supplier_quotes(p_company uuid, p_supplier uuid, p_item uuid) to authenticated;
revoke all on function public.purchase_suppliers_for_items(p_company uuid, p_items uuid[]) from public, anon, authenticated, service_role;
grant execute on function public.purchase_suppliers_for_items(p_company uuid, p_items uuid[]) to authenticated;
revoke all on function public.recalculate_production_reservations(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.recalculate_production_reservations(p_company uuid) to authenticated;
revoke all on function public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb) from public, anon, authenticated, service_role;
grant execute on function public.receive_purchase_order(p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb) to authenticated;
revoke all on function public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.refund_sale_credit(p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid) to authenticated;
revoke all on function public.reject_purchase_request(p_company uuid, p_request uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.reject_purchase_request(p_company uuid, p_request uuid, p_reason text) to authenticated;
revoke all on function public.remove_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.remove_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_reason text) to authenticated;
revoke all on function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.restore_archived_record(p_company uuid, p_resource text, p_id uuid) to authenticated;
revoke all on function public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid) from public, anon, authenticated, service_role;
grant execute on function public.return_production_material(p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid) to authenticated;
revoke all on function public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.reverse_sale_payment(p_company uuid, p_payment uuid, p_reason text) to authenticated;
revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role;
grant execute on function public.rls_auto_enable() to public;
revoke all on function public.sale_credit_balance(p_company uuid, p_sale uuid) from public, anon, authenticated, service_role;
grant execute on function public.sale_credit_balance(p_company uuid, p_sale uuid) to authenticated;
revoke all on function public.sale_receivables(p_company uuid, p_page integer, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.sale_receivables(p_company uuid, p_page integer, p_search text) to authenticated;
revoke all on function public.save_company_profile(p_company uuid, p_legal_name text, p_tax_id text, p_tax_condition text, p_address text, p_phone text, p_email text, p_website text, p_logo text) from public, anon, authenticated, service_role;
grant execute on function public.save_company_profile(p_company uuid, p_legal_name text, p_tax_id text, p_tax_condition text, p_address text, p_phone text, p_email text, p_website text, p_logo text) to authenticated;
revoke all on function public.save_item_sale_settings(p_company uuid, p_item uuid, p_tax numeric, p_content numeric, p_content_unit uuid) from public, anon, authenticated, service_role;
grant execute on function public.save_item_sale_settings(p_company uuid, p_item uuid, p_tax numeric, p_content numeric, p_content_unit uuid) to authenticated;
revoke all on function public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean) from public, anon, authenticated, service_role;
grant execute on function public.save_item_with_cost(p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean) to authenticated;
revoke all on function public.save_price_list(p_company uuid, p_id uuid, p_name text, p_currency text, p_valid_from date, p_valid_to date, p_is_default boolean, p_base_list uuid, p_base_discount numeric, p_rounding_step numeric, p_note text, p_archived boolean) from public, anon, authenticated, service_role;
grant execute on function public.save_price_list(p_company uuid, p_id uuid, p_name text, p_currency text, p_valid_from date, p_valid_to date, p_is_default boolean, p_base_list uuid, p_base_discount numeric, p_rounding_step numeric, p_note text, p_archived boolean) to authenticated;
revoke all on function public.save_price_settings(p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric, p_max_discount numeric) from public, anon, authenticated, service_role;
grant execute on function public.save_price_settings(p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric, p_max_discount numeric) to authenticated;
revoke all on function public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb) from public, anon, authenticated, service_role;
grant execute on function public.save_production_document_settings(p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb) to authenticated;
revoke all on function public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb) from public, anon, authenticated, service_role;
grant execute on function public.save_production_formula(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb) to authenticated;
revoke all on function public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric) from public, anon, authenticated, service_role;
grant execute on function public.save_production_formula_v2(p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric) to authenticated;
revoke all on function public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean) from public, anon, authenticated, service_role;
grant execute on function public.save_production_packaging_type(p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean) to authenticated;
revoke all on function public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone) from public, anon, authenticated, service_role;
grant execute on function public.save_production_work_details(p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone) to authenticated;
revoke all on function public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone, p_create_only boolean) from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_quote(p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone, p_create_only boolean) to authenticated;
revoke all on function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean) from public, anon, authenticated, service_role;
grant execute on function public.set_company_member(p_company uuid, p_user uuid, p_role uuid, p_active boolean) to authenticated;
revoke all on function public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid) from public, anon, authenticated, service_role;
grant execute on function public.set_preferred_supplier(p_company uuid, p_item uuid, p_supplier uuid) to authenticated;
revoke all on function public.set_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_method text, p_value numeric, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.set_price_list_item(p_company uuid, p_list uuid, p_item uuid, p_method text, p_value numeric, p_reason text) to authenticated;
revoke all on function public.set_quote_status(p_company uuid, p_quote uuid, p_status text) from public, anon, authenticated, service_role;
grant execute on function public.set_quote_status(p_company uuid, p_quote uuid, p_status text) to authenticated;
revoke all on function public.start_production_job(p_company uuid, p_job uuid) from public, anon, authenticated, service_role;
grant execute on function public.start_production_job(p_company uuid, p_job uuid) to authenticated;
revoke all on function public.stock_item_options(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.stock_item_options(p_company uuid, p_search text) to authenticated;
revoke all on function public.stock_lot_breakdown(p_company uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.stock_lot_breakdown(p_company uuid, p_item uuid) to authenticated;
revoke all on function public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid) from public, anon, authenticated, service_role;
grant execute on function public.stock_lot_options(p_company uuid, p_item uuid, p_warehouse uuid) to authenticated;
revoke all on function public.stock_summary(p_company uuid, p_page integer, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.stock_summary(p_company uuid, p_page integer, p_search text) to authenticated;
revoke all on function public.stock_warehouse_options(p_company uuid, p_search text) from public, anon, authenticated, service_role;
grant execute on function public.stock_warehouse_options(p_company uuid, p_search text) to authenticated;
revoke all on function public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.supplier_account(p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer) to authenticated;
revoke all on function public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric) from public, anon, authenticated, service_role;
grant execute on function public.supplier_adjustment_preview(p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric) to authenticated;
revoke all on function public.supplier_cost_comparison(p_company uuid, p_supplier uuid, p_item uuid) from public, anon, authenticated, service_role;
grant execute on function public.supplier_cost_comparison(p_company uuid, p_supplier uuid, p_item uuid) to authenticated;
revoke all on function public.supplier_directory(p_company uuid, p_search text, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.supplier_directory(p_company uuid, p_search text, p_page integer) to authenticated;
revoke all on function public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.supplier_payable_orders(p_company uuid, p_supplier uuid, p_page integer) to authenticated;
revoke all on function public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date) from public, anon, authenticated, service_role;
grant execute on function public.supplier_purchase_statistics(p_company uuid, p_from date, p_to date) to authenticated;
revoke all on function public.supplier_quote_catalog(p_company uuid, p_supplier uuid, p_item uuid, p_search text, p_page integer) from public, anon, authenticated, service_role;
grant execute on function public.supplier_quote_catalog(p_company uuid, p_supplier uuid, p_item uuid, p_search text, p_page integer) to authenticated;
revoke all on function public.treasury_activity(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.treasury_activity(p_company uuid) to authenticated;
revoke all on function public.treasury_balances(p_company uuid) from public, anon, authenticated, service_role;
grant execute on function public.treasury_balances(p_company uuid) to authenticated;
revoke all on function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb) from public, anon, authenticated, service_role;
grant execute on function public.update_company_role(p_company uuid, p_role uuid, p_name text, p_permissions jsonb) to authenticated;
revoke all on function public.void_delivery_note(p_company uuid, p_note uuid, p_reason text) from public, anon, authenticated, service_role;
grant execute on function public.void_delivery_note(p_company uuid, p_note uuid, p_reason text) to authenticated;
revoke all on function private.module_enabled(p_company uuid, p_resource text) from public, anon, authenticated, service_role;

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant truncate, references, trigger, maintain on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role;

insert into public.ajustes_permisos_catalogo (recurso, modulo, padre, etiqueta, ayuda, orden, acciones, es_grupo, solo_admin, exigido) values
  ('stock', 'stock', null, 'Stock (todas las pantallas)', 'Agrupa existencias, movimientos y remitos.', 120, array['ver', 'crear', 'editar', 'eliminar']::text[], true, false, true),
  ('produccion', 'produccion', null, 'Producción (todas las pantallas)', 'Agrupa todas las pantallas de producción.', 200, array['ver', 'crear', 'editar', 'eliminar']::text[], true, false, true),
  ('compras', 'compras', null, 'Compras (todas las pantallas)', 'Agrupa todas las pantallas de compras.', 400, array['ver', 'crear', 'editar', 'eliminar']::text[], true, false, true),
  ('inicio', 'inicio', null, 'Inicio', 'Panel principal con las decisiones del día.', 10, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, false),
  ('inventario', 'stock', null, 'Resumen de stock', 'Panel general de existencias y alertas.', 100, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('items', 'stock', null, 'Ítems', 'Fichas de materiales y productos, altas e importación.', 110, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('stock_saldos', 'stock', 'stock', 'Stock por depósito', 'Existencias por depósito e ingresos o egresos manuales.', 121, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('stock_movimientos', 'stock', 'stock', 'Movimientos', 'Historial de entradas y salidas.', 122, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('stock_remitos', 'stock', 'stock', 'Remitos de entrega', 'Remitos de entrega de materiales y productos.', 123, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_resumen', 'produccion', 'produccion', 'Resumen de producción', 'Qué se fabrica, qué falta y qué decidir hoy.', 201, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_ordenes', 'produccion', 'produccion', 'Órdenes de fabricación', 'Crear, iniciar, entregar insumos, devolver y terminar órdenes.', 202, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_formulas', 'produccion', 'produccion', 'Fórmulas', 'Fórmulas o recetas de los productos.', 203, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_planificacion', 'produccion', 'produccion', 'Planificación', 'Planes de producción.', 204, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_disponibilidad', 'produccion', 'produccion', '¿Alcanza el stock para fabricar?', 'Simulador de faltantes.', 205, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_reposicion', 'produccion', 'produccion', 'Pronóstico y reposición', 'Qué reponer y cuándo.', 206, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_envasado', 'produccion', 'produccion', 'Envases y presentaciones', 'Tipos de envase y presentaciones.', 207, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_estadistica', 'produccion', 'produccion', 'Estadística de producción', 'Cuánto se produjo por mes, semana o rango.', 208, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('produccion_documentos', 'produccion', 'produccion', 'Formato de documentos de producción', 'Logo, código y campos de la hoja de fabricación.', 209, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('ventas', 'ventas', null, 'Ventas (todas las pantallas)', 'Resumen, presupuestos, clientes, listas de precios y registro de ventas.', 300, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, false),
  ('compras_resumen', 'compras', 'compras', 'Resumen de compras', 'Panel general de compras.', 401, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('compras_pedidos', 'compras', 'compras', 'Pedidos internos', 'Pedir materiales que faltan; Compras los revisa.', 402, array['ver', 'crear', 'editar', 'eliminar', 'gestionar']::text[], false, false, true),
  ('compras_ordenes', 'compras', 'compras', 'Órdenes de compra', 'Órdenes de compra y recepción de mercadería.', 403, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('compras_proveedores', 'compras', 'compras', 'Proveedores', 'Proveedores y catálogo de precios.', 404, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('compras_cuentas', 'compras', 'compras', 'Compras y cuentas', 'Deuda con proveedores, órdenes de pago y estadísticas.', 405, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('finanzas', 'finanzas', null, 'Finanzas (todas las pantallas)', 'Cuentas por cobrar, tesorería y rentabilidad.', 500, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, false),
  ('reportes', 'reportes', null, 'Reportes', 'Resumen por período y exportaciones.', 600, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, false),
  ('ajustes', 'ajustes', null, 'Datos de la empresa', 'Nombre y datos generales de la empresa.', 700, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, false),
  ('unidades', 'ajustes', null, 'Unidades', 'Unidades de medida.', 710, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('categorias', 'ajustes', null, 'Categorías', 'Categorías de ítems.', 720, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('depositos', 'ajustes', null, 'Depósitos', 'Depósitos y ubicaciones.', 730, array['ver', 'crear', 'editar', 'eliminar']::text[], false, false, true),
  ('usuarios', 'ajustes', null, 'Usuarios', 'Alta, cambio de rol y suspensión. Solo el administrador.', 740, array['ver', 'crear', 'editar', 'eliminar']::text[], false, true, false),
  ('roles', 'ajustes', null, 'Roles y permisos', 'Crear roles y definir accesos. Solo el administrador.', 750, array['ver', 'crear', 'editar', 'eliminar']::text[], false, true, false),
  ('costos_materiales', 'sensible', null, 'Ver costos de materiales', 'Costo de referencia de materias primas y semielaborados.', 800, array['ver']::text[], false, false, true),
  ('costos_produccion', 'sensible', null, 'Ver costos y márgenes de producción', 'Costos de fórmulas y órdenes, márgenes y listas con costos.', 810, array['ver']::text[], false, false, true);

commit;
