# Funciones

_Generado por `documentar.mjs`; no editar a mano._

«Aplicación» = la puede llamar un usuario con sesión (cada una controla sus permisos). El resto son internas.

| Función | Uso | Parámetros | Tablas que menciona |
|---|---|---|---|
| access_audit_events_list | Aplicación | p_company uuid, p_page integer | ajustes_auditoria_accesos, ajustes_roles |
| activate_item_lots | Aplicación | p_company uuid, p_item uuid | empresas, stock_depositos, stock_items, stock_lotes, stock_lotes_aperturas, stock_lotes_saldos, stock_saldos |
| add_exchange_rate | Aplicación | p_company uuid, p_type uuid, p_rate numeric, p_date date | empresas, finanzas_cotizaciones, finanzas_tipos_cambio |
| add_exchange_rate_type | Aplicación | p_company uuid, p_name text | finanzas_tipos_cambio |
| adjust_sale | Aplicación | p_company uuid, p_sale uuid, p_kind text, p_reason text, p_lines jsonb, p_request_id uuid | stock_lotes, ventas, ventas_ajustes, ventas_ajustes_lineas, ventas_lineas |
| adjust_supplier_prices | Aplicación | p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric, p_request_id uuid | compras_proveedores, compras_proveedores_ajustes_precio, compras_proveedores_items, empresas, stock_items |
| archived_records | Aplicación | p_company uuid, p_resource text, p_search text, p_page integer | finanzas_cotizaciones, stock_items |
| assign_customer_price_list | Aplicación | p_company uuid, p_customer uuid, p_list uuid | ventas_clientes, ventas_listas_precios |
| assign_sale_payment_account | Aplicación | p_company uuid, p_payment uuid, p_account uuid | finanzas_cobros_cuentas, finanzas_cuentas, ventas_cobros |
| begin_support_session | Aplicación | p_company uuid, p_reason text | empresas, empresas_usuarios, private.soporte_accesos, private.soporte_operadores, private.soporte_sesiones |
| bulk_price_change | Aplicación | p_company uuid, p_list uuid, p_mode text, p_percent numeric, p_item_ids uuid[], p_apply boolean, p_reason text, p_request_id uuid | stock_items, ventas_listas_items, ventas_listas_items_metodo, ventas_listas_precios, ventas_precios_antiduplicado |
| cancel_production_job | Aplicación | p_company uuid, p_job uuid, p_reason text | produccion_ordenes, produccion_ordenes_eventos, produccion_planes |
| cancel_production_plan | Aplicación | p_company uuid, p_plan uuid | produccion_ordenes, produccion_planes |
| cancel_purchase_order | Aplicación | p_company uuid, p_order uuid | compras_ordenes, empresas |
| cancel_purchase_request | Aplicación | p_company uuid, p_request uuid | compras_pedidos |
| cancel_supplier_payment_order | Aplicación | p_company uuid, p_payment uuid | compras_pagos, empresas |
| cleanup_preview | Aplicación | p_company uuid, p_resource text, p_id uuid | compras_ordenes, compras_ordenes_lineas, compras_proveedores, compras_proveedores_items, produccion_formulas, produccion_formulas_lineas, produccion_ordenes, produccion_ordenes_eventos, produccion_planes, stock_items, stock_saldos |
| cleanup_record | Aplicación | p_company uuid, p_resource text, p_id uuid, p_action text | compras_proveedores_items, empresas, produccion_formulas_lineas, produccion_ordenes_reservas, produccion_reservas_ubicaciones, stock_items, private.produccion_solicitudes_eliminadas |
| company_members | Aplicación | p_company uuid | ajustes_perfiles, ajustes_roles, empresas_usuarios |
| complete_production_now | Aplicación | p_company uuid, p_product uuid, p_planned_quantity numeric, p_actual_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_variance_note text, p_inputs jsonb, p_request_id uuid, p_finish_request_id uuid, p_plan uuid | produccion_fabricaciones_antiduplicado |
| complete_production_plan | Interna | p_company uuid, p_plan uuid, p_request_id uuid, p_inputs jsonb, p_output_lot text, p_expires_on date | produccion_formulas, produccion_planes |
| confirm_supplier_payment_order | Aplicación | p_company uuid, p_payment uuid | compras_pagos, compras_pagos_lineas, empresas |
| convert_purchase_request | Aplicación | p_company uuid, p_request uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid | compras_ordenes_antiduplicado, compras_pedidos |
| create_company | Aplicación | p_name text | ajustes_perfiles, ajustes_permisos_catalogo, ajustes_roles, ajustes_roles_permisos, empresas, empresas_usuarios |
| create_company_role | Aplicación | p_company uuid, p_name text, p_code text, p_permissions jsonb | ajustes_roles, ajustes_roles_permisos |
| create_production_job | Aplicación | p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid, p_plan uuid | produccion_formulas, produccion_formulas_lineas, produccion_ordenes, produccion_planes, stock_depositos, stock_items |
| create_production_plan | Aplicación | p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due_on date, p_note text, p_request_id uuid | produccion_formulas, produccion_formulas_lineas, produccion_planes, stock_depositos, stock_items |
| create_production_work_order | Aplicación | p_company uuid, p_product uuid, p_quantity numeric, p_warehouse uuid, p_due date, p_note text, p_request uuid, p_plan uuid, p_options jsonb, p_finish jsonb | empresas, produccion_ordenes |
| create_purchase_order | Interna | p_company uuid, p_supplier uuid, p_note text, p_lines jsonb | compras_ordenes, compras_ordenes_lineas, compras_proveedores, empresas, empresas_numeradores, stock_items, stock_unidades |
| create_purchase_order_once | Aplicación | p_company uuid, p_supplier uuid, p_note text, p_lines jsonb, p_request_id uuid | compras_ordenes_antiduplicado |
| create_purchase_request | Aplicación | p_company uuid, p_note text, p_needed_by date, p_priority text, p_lines jsonb, p_request_id uuid | compras_pedidos, compras_pedidos_antiduplicado, compras_pedidos_lineas, empresas, empresas_numeradores, stock_items, stock_unidades |
| create_quote | Aplicación | p_company uuid, p_customer uuid, p_name text, p_tax_id text, p_email text, p_phone text, p_address text, p_valid_until date, p_note text, p_show_tax boolean, p_lines jsonb, p_request_id uuid, p_tax_included boolean | ajustes_perfiles, empresas, empresas_numeradores, stock_items, stock_unidades, ventas_clientes, ventas_precios_config, ventas_presupuestos, ventas_presupuestos_lineas |
| create_supplier_payment_order | Aplicación | p_company uuid, p_supplier uuid, p_account uuid, p_on date, p_note text, p_reference text, p_lines jsonb, p_request uuid | compras_ordenes, compras_ordenes_lineas, compras_pagos, compras_pagos_lineas, compras_proveedores, empresas, empresas_numeradores, finanzas_cuentas, finanzas_movimientos |
| create_treasury_account | Aplicación | p_company uuid, p_name text, p_kind text, p_opening numeric | finanzas_cuentas |
| end_support_session | Aplicación |  | private.soporte_sesiones |
| erp_admin_price_list_rows | Aplicación | p_company uuid, p_list uuid, p_search text, p_filter text, p_page integer, p_page_size integer | ventas_listas_precios, ventas_precios_config |
| erp_admin_product_costs | Aplicación | p_company uuid, p_search text |  |
| erp_admin_sales_profit_detail | Aplicación | p_company uuid, p_from date, p_to date, p_search text, p_page integer | ventas, ventas_ajustes, ventas_ajustes_lineas, ventas_lineas |
| erp_admin_sales_profit_summary | Aplicación | p_company uuid | ventas_ajustes_lineas, ventas_lineas |
| erp_can_manufacture | Aplicación | p_company uuid, p_product uuid, p_quantity numeric | produccion_formulas, produccion_formulas_lineas, produccion_ordenes, produccion_reservas_ubicaciones, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_saldos, stock_unidades |
| erp_company_profile | Aplicación | p_company uuid | empresas, empresas_perfil |
| erp_dashboard | Aplicación | p_company uuid | compras_ordenes, produccion_formulas, stock_items, ventas, ventas_cobros, ventas_cobros_reversiones |
| erp_operational_dashboard | Aplicación | p_company uuid | compras_ordenes, produccion_planes, stock_items, stock_saldos, ventas, ventas_ajustes, ventas_ajustes_lineas, ventas_cobros, ventas_cobros_reversiones, ventas_lineas |
| erp_operational_report | Aplicación | p_company uuid, p_from date, p_to date | compras_ordenes, produccion_fabricaciones, produccion_ordenes, ventas, ventas_ajustes, ventas_ajustes_lineas, ventas_lineas |
| erp_price_list_history | Aplicación | p_company uuid, p_list uuid, p_item uuid, p_page integer | ajustes_perfiles, stock_items, ventas_listas_items_historial |
| erp_price_list_rows | Aplicación | p_company uuid, p_list uuid, p_search text, p_only_missing boolean, p_page integer, p_page_size integer | stock_unidades, ventas_items_config, ventas_listas_precios, ventas_precios_config |
| erp_price_settings | Aplicación | p_company uuid | ventas_precios_config |
| erp_product_costs | Interna | p_company uuid, p_search text | produccion_formulas, stock_items, stock_unidades |
| erp_production_alerts | Aplicación | p_company uuid | produccion_ordenes, produccion_ordenes_eventos, produccion_ordenes_reservas, stock_items, stock_unidades |
| erp_production_dashboard | Aplicación | p_company uuid | produccion_ordenes, stock_items |
| erp_public_price_list | Aplicación | p_company uuid, p_search text | stock_items, stock_unidades |
| erp_quote_detail | Aplicación | p_company uuid, p_quote uuid | ventas_presupuestos, ventas_presupuestos_lineas |
| erp_quotes_page | Aplicación | p_company uuid, p_search text, p_status text, p_page integer, p_size integer | ventas_presupuestos, ventas_presupuestos_lineas |
| erp_replenishment_forecast | Aplicación | p_company uuid | compras_ordenes, compras_ordenes_lineas, compras_proveedores, compras_proveedores_items, produccion_ordenes, produccion_reservas_ubicaciones, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_movimientos, stock_saldos, stock_unidades |
| erp_resolve_sale_price | Aplicación | p_company uuid, p_customer uuid, p_item uuid |  |
| erp_sale_discount_policy | Aplicación | p_company uuid | ventas_precios_config |
| erp_sale_prices | Aplicación | p_company uuid, p_customer uuid, p_items uuid[] | stock_items, ventas_listas_precios |
| erp_sales_profit_summary | Interna | p_company uuid | ventas_ajustes_lineas, ventas_lineas |
| erp_set_finished_product_price | Aplicación | p_company uuid, p_item uuid, p_price numeric | stock_items |
| exchange_rate_overview | Aplicación | p_company uuid | finanzas_cotizaciones, finanzas_tipos_cambio |
| finish_production_job | Aplicación | p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid | produccion_fabricaciones, produccion_ordenes, produccion_ordenes_eventos, produccion_planes, stock_items |
| finish_production_job_adjusted | Aplicación | p_company uuid, p_job uuid, p_actual_quantity numeric, p_output_lot text, p_expires_on date, p_variance_note text, p_request_id uuid, p_adjustments jsonb, p_packaging jsonb | produccion_ordenes, produccion_ordenes_eventos, stock_items, stock_unidades |
| get_item_detail | Aplicación | p_company uuid, p_item uuid | stock_categorias, stock_items, stock_unidades |
| import_items | Aplicación | p_company uuid, p_rows jsonb |  |
| import_price_list_items | Aplicación | p_company uuid, p_list uuid, p_rows jsonb, p_apply boolean, p_reason text, p_request_id uuid | stock_items, ventas_listas_items, ventas_listas_precios, ventas_precios_antiduplicado |
| issue_delivery_note | Aplicación | p_company uuid, p_kind text, p_job uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid | empresas, empresas_numeradores, produccion_ordenes, produccion_ordenes_eventos, stock_depositos, stock_items, stock_remitos, stock_remitos_lineas, stock_unidades |
| issue_production_material | Aplicación | p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid | produccion_fabricaciones, produccion_ordenes, produccion_ordenes_eventos, stock_items |
| issue_sale_delivery_note | Aplicación | p_company uuid, p_sale uuid, p_recipient text, p_note text, p_lines jsonb, p_request uuid | empresas, empresas_numeradores, stock_remitos, stock_remitos_lineas, ventas, ventas_ajustes, ventas_ajustes_lineas, ventas_lineas |
| item_cost_context | Aplicación | p_company uuid, p_item uuid | compras_proveedores, compras_proveedores_items |
| list_production_items | Aplicación | p_company uuid, p_include_inactive boolean | stock_items, stock_unidades |
| list_production_jobs | Aplicación | p_company uuid | produccion_ordenes, produccion_ordenes_eventos |
| list_production_plans | Aplicación | p_company uuid | produccion_planes |
| list_production_runs | Aplicación | p_company uuid | produccion_fabricaciones, produccion_fabricaciones_lineas |
| my_company_access | Aplicación |  | ajustes_roles, empresas, empresas_usuarios, private.soporte_operadores |
| post_production_run | Aplicación | p_company uuid, p_product uuid, p_request_id uuid, p_quantity numeric, p_warehouse uuid, p_output_lot text, p_expires_on date, p_note text, p_inputs jsonb | produccion_fabricaciones, produccion_fabricaciones_lineas, produccion_formulas, produccion_formulas_lineas, stock_items |
| post_sale | Aplicación | p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid | empresas, empresas_numeradores, produccion_fabricaciones, stock_depositos, stock_items, stock_unidades, ventas, ventas_clientes, ventas_lineas, ventas_precios_config |
| post_sale_payment | Aplicación | p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid | ventas, ventas_cobros, ventas_cobros_reversiones |
| post_sale_payment_to_account | Aplicación | p_company uuid, p_sale uuid, p_amount numeric, p_method text, p_paid_on date, p_reference text, p_note text, p_request_id uuid, p_account uuid | finanzas_cobros_cuentas, finanzas_cuentas |
| post_sale_with_payment | Aplicación | p_company uuid, p_customer uuid, p_note text, p_lines jsonb, p_request_id uuid, p_payment_request_id uuid, p_payment_mode text, p_amount numeric, p_method text, p_account uuid | finanzas_cuentas, ventas, ventas_cobros_antiduplicado |
| post_stock_operation | Aplicación | p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date | empresas, produccion_ordenes, produccion_reservas_ubicaciones, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_operaciones, stock_saldos |
| post_treasury_entry | Aplicación | p_company uuid, p_account uuid, p_kind text, p_amount numeric, p_order uuid, p_note text, p_on date, p_request uuid, p_target uuid | compras_ordenes, compras_ordenes_lineas, empresas, finanzas_cuentas, finanzas_movimientos |
| preview_item_import | Aplicación | p_company uuid, p_rows jsonb |  |
| production_formula_cost | Aplicación | p_company uuid, p_product uuid |  |
| production_output_by_product | Aplicación | p_company uuid, p_from date, p_to date, p_search text, p_limit integer, p_offset integer, p_tz text | produccion_ordenes, stock_items, stock_unidades |
| production_output_summary | Aplicación | p_company uuid, p_from date, p_to date, p_bucket text, p_product uuid, p_tz text | produccion_ordenes, stock_items, stock_unidades |
| purchase_item_options | Aplicación | p_company uuid, p_search text | stock_items, stock_unidades |
| purchase_material_options | Aplicación | p_company uuid, p_search text, p_supplier uuid | compras_proveedores_items, stock_items, stock_unidades |
| purchase_receivable_lines | Aplicación | p_company uuid, p_order uuid | compras_ordenes_lineas, stock_items |
| purchase_request_item_options | Aplicación | p_company uuid, p_search text | stock_items, stock_unidades |
| purchase_supplier_quotes | Aplicación | p_company uuid, p_supplier uuid, p_item uuid | compras_proveedores, compras_proveedores_items, stock_items, stock_unidades |
| purchase_suppliers_for_items | Aplicación | p_company uuid, p_items uuid[] | compras_proveedores, compras_proveedores_items, stock_items |
| recalculate_production_reservations | Aplicación | p_company uuid |  |
| receive_purchase_order | Aplicación | p_company uuid, p_order uuid, p_request_id uuid, p_note text, p_lines jsonb | compras_ordenes, compras_ordenes_lineas, compras_recepciones, compras_recepciones_lineas, empresas, stock_depositos, stock_operaciones |
| refund_sale_credit | Aplicación | p_company uuid, p_sale uuid, p_account uuid, p_amount numeric, p_reason text, p_request_id uuid | ventas_reintegros |
| reject_purchase_request | Aplicación | p_company uuid, p_request uuid, p_reason text | compras_pedidos |
| remove_price_list_item | Aplicación | p_company uuid, p_list uuid, p_item uuid, p_reason text | ventas_listas_items, ventas_listas_items_historial, ventas_listas_items_metodo, ventas_listas_precios |
| restore_archived_record | Aplicación | p_company uuid, p_resource text, p_id uuid | compras_proveedores_items, finanzas_tipos_cambio, produccion_formulas_lineas, stock_items |
| return_production_material | Aplicación | p_company uuid, p_job uuid, p_issue uuid, p_quantity numeric, p_note text, p_request_id uuid | produccion_ordenes, produccion_ordenes_eventos, stock_lotes |
| reverse_sale_payment | Aplicación | p_company uuid, p_payment uuid, p_reason text | ventas_cobros, ventas_cobros_reversiones |
| rls_auto_enable | Aplicación |  |  |
| sale_credit_balance | Aplicación | p_company uuid, p_sale uuid | ventas, ventas_ajustes, ventas_cobros, ventas_cobros_reversiones, ventas_reintegros |
| sale_receivables | Aplicación | p_company uuid, p_page integer, p_search text | ventas, ventas_ajustes, ventas_cobros, ventas_cobros_reversiones |
| save_company_profile | Aplicación | p_company uuid, p_legal_name text, p_tax_id text, p_tax_condition text, p_address text, p_phone text, p_email text, p_website text, p_logo text | empresas_perfil |
| save_item_sale_settings | Aplicación | p_company uuid, p_item uuid, p_tax numeric, p_content numeric, p_content_unit uuid | stock_items, ventas_items_config |
| save_item_with_cost | Aplicación | p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean |  |
| save_price_list | Aplicación | p_company uuid, p_id uuid, p_name text, p_currency text, p_valid_from date, p_valid_to date, p_is_default boolean, p_base_list uuid, p_base_discount numeric, p_rounding_step numeric, p_note text, p_archived boolean | ventas_listas_precios |
| save_price_settings | Aplicación | p_company uuid, p_default_tax numeric, p_min_margin numeric, p_commission numeric, p_structure numeric, p_max_discount numeric | ventas_precios_config |
| save_production_document_settings | Aplicación | p_company uuid, p_logo text, p_code text, p_revision text, p_labels jsonb | empresas, produccion_documentos_config |
| save_production_formula | Aplicación | p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb | produccion_formulas, produccion_formulas_lineas, stock_items |
| save_production_formula_v2 | Aplicación | p_company uuid, p_product uuid, p_batch_quantity numeric, p_lines jsonb, p_yield_enabled boolean, p_yield_factor numeric | stock_items |
| save_production_packaging_type | Aplicación | p_company uuid, p_id uuid, p_name text, p_capacity numeric, p_unit uuid, p_active boolean | empresas, produccion_tipos_envase, stock_unidades |
| save_production_work_details | Aplicación | p_company uuid, p_job uuid, p_counts jsonb, p_observations jsonb, p_expected timestamp with time zone | empresas, produccion_ordenes |
| save_supplier_quote | Aplicación | p_company uuid, p_supplier uuid, p_item uuid, p_price numeric, p_sku text, p_currency text, p_exchange_type uuid, p_adjustment numeric, p_expected_updated_at timestamp with time zone, p_create_only boolean | compras_proveedores_items, empresas |
| set_company_member | Aplicación | p_company uuid, p_user uuid, p_role uuid, p_active boolean | ajustes_roles, empresas, empresas_usuarios |
| set_preferred_supplier | Aplicación | p_company uuid, p_item uuid, p_supplier uuid | compras_proveedores, compras_proveedores_items |
| set_price_list_item | Aplicación | p_company uuid, p_list uuid, p_item uuid, p_method text, p_value numeric, p_reason text | stock_items, ventas_listas_precios |
| set_quote_status | Aplicación | p_company uuid, p_quote uuid, p_status text | ventas_presupuestos, ventas_presupuestos_estados |
| start_production_job | Aplicación | p_company uuid, p_job uuid | produccion_ordenes |
| stock_item_options | Aplicación | p_company uuid, p_search text | stock_items, stock_unidades |
| stock_lot_breakdown | Aplicación | p_company uuid, p_item uuid | stock_depositos, stock_lotes, stock_lotes_saldos |
| stock_lot_options | Aplicación | p_company uuid, p_item uuid, p_warehouse uuid | stock_lotes, stock_lotes_saldos |
| stock_summary | Aplicación | p_company uuid, p_page integer, p_search text | stock_items, stock_saldos, stock_unidades |
| stock_warehouse_options | Aplicación | p_company uuid, p_search text | stock_depositos |
| supplier_account | Aplicación | p_company uuid, p_supplier uuid, p_from date, p_to date, p_page integer | compras_ordenes, compras_recepciones, compras_recepciones_lineas, finanzas_movimientos |
| supplier_adjustment_preview | Aplicación | p_company uuid, p_supplier uuid, p_item uuid, p_percent numeric | compras_proveedores, compras_proveedores_items, stock_items |
| supplier_cost_comparison | Aplicación | p_company uuid, p_supplier uuid, p_item uuid | compras_proveedores, compras_proveedores_items, finanzas_tipos_cambio, stock_items, stock_unidades |
| supplier_directory | Aplicación | p_company uuid, p_search text, p_page integer | compras_proveedores, compras_proveedores_items |
| supplier_payable_orders | Aplicación | p_company uuid, p_supplier uuid, p_page integer | compras_ordenes, compras_ordenes_lineas, finanzas_movimientos |
| supplier_purchase_statistics | Aplicación | p_company uuid, p_from date, p_to date | compras_ordenes, compras_ordenes_lineas, compras_recepciones, compras_recepciones_lineas |
| supplier_quote_catalog | Aplicación | p_company uuid, p_supplier uuid, p_item uuid, p_search text, p_page integer | compras_proveedores, compras_proveedores_items, finanzas_tipos_cambio, stock_items, stock_unidades |
| treasury_activity | Aplicación | p_company uuid | finanzas_cobros_cuentas, finanzas_movimientos, ventas, ventas_cobros, ventas_cobros_reversiones |
| treasury_balances | Aplicación | p_company uuid | finanzas_cobros_cuentas, finanzas_cuentas, finanzas_movimientos, ventas_cobros, ventas_cobros_reversiones |
| update_company_role | Aplicación | p_company uuid, p_role uuid, p_name text, p_permissions jsonb | ajustes_roles, ajustes_roles_permisos |
| void_delivery_note | Aplicación | p_company uuid, p_note uuid, p_reason text | produccion_ordenes, produccion_ordenes_eventos, stock_lotes, stock_remitos, stock_remitos_lineas, stock_remitos_reversiones |
| private.access_audit_immutable | Interna |  |  |
| private.can_operate_production | Interna | p_company uuid |  |
| private.can_post_stock | Interna | p_company uuid | produccion_ordenes |
| private.can_see_production_costs | Interna | p_company uuid |  |
| private.can_see_reference_cost | Interna | p_company uuid |  |
| private.check_infinite_stock_change | Interna |  | produccion_ordenes, produccion_ordenes_reservas, stock_saldos |
| private.check_item_catalogs | Interna |  | stock_categorias, stock_unidades |
| private.check_reference_fx_cost | Interna |  | finanzas_tipos_cambio |
| private.check_stock_catalog_deactivation | Interna |  | stock_saldos |
| private.check_supplier_item | Interna |  | compras_proveedores, finanzas_tipos_cambio, stock_items |
| private.cleanup_has_references | Interna | p_company uuid, p_resource text, p_id uuid | produccion_fabricaciones, produccion_formulas_lineas, produccion_ordenes, produccion_planes |
| private.cleanup_target | Interna | p_resource text |  |
| private.current_fx_rate | Interna | p_company uuid, p_type uuid | finanzas_cotizaciones |
| private.erp_production_alerts | Interna | p_company uuid | produccion_ordenes, stock_items, stock_saldos, stock_unidades |
| private.etiqueta_soporte | Interna | p_company uuid, p_user uuid | empresas_usuarios, private.soporte_accesos |
| private.get_user_role | Interna | p_company uuid | ajustes_roles, empresas, empresas_usuarios |
| private.guard_archived_formula_edit | Interna |  |  |
| private.guard_archived_recipe | Interna |  | produccion_formulas, private.produccion_solicitudes_eliminadas |
| private.guard_purchase_supplier_item | Interna |  | compras_ordenes, compras_proveedores_items, stock_items |
| private.guard_reversal_after_refund | Interna |  | ventas, ventas_ajustes, ventas_cobros, ventas_cobros_reversiones, ventas_reintegros |
| private.guard_sale_payment_net | Interna |  | ventas, ventas_ajustes, ventas_cobros, ventas_cobros_reversiones |
| private.has_permission | Interna | p_company uuid, p_resource text, p_action text | ajustes_permisos_catalogo, ajustes_roles_permisos, empresas, empresas_usuarios |
| private.import_items | Interna | p_company uuid, p_rows jsonb | stock_items |
| private.is_company_member | Interna | p_company uuid | empresas, empresas_usuarios |
| private.issue_production_material | Interna | p_company uuid, p_job uuid, p_component uuid, p_warehouse uuid, p_lot text, p_quantity numeric, p_note text, p_request_id uuid | produccion_fabricaciones, produccion_ordenes, produccion_ordenes_eventos, stock_items |
| private.log_access_event | Interna | p_company uuid, p_action text, p_user uuid, p_role uuid, p_detail jsonb | ajustes_auditoria_accesos |
| private.module_enabled | Interna | p_company uuid, p_resource text | ajustes_permisos_catalogo, empresas |
| private.post_stock_operation | Interna | p_company uuid, p_item uuid, p_warehouse uuid, p_to_warehouse uuid, p_kind text, p_quantity numeric, p_note text, p_request_id uuid, p_lot_code text, p_expires_on date | empresas, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_movimientos, stock_operaciones, stock_saldos, stock_unidades |
| private.prepare_item_import | Interna | p_company uuid, p_rows jsonb, p_existing uuid | compras_proveedores, compras_proveedores_items, empresas, finanzas_tipos_cambio, stock_categorias, stock_items, stock_unidades |
| private.prepare_production_document | Interna |  | empresas_numeradores, produccion_documentos_config, stock_items |
| private.prevent_infinite_physical_movement | Interna |  | stock_items |
| private.prevent_late_lot_tracking | Interna |  | stock_lotes, stock_lotes_saldos, stock_saldos |
| private.prevent_preferred_quote_deletion | Interna |  |  |
| private.prevent_stock_unit_change | Interna |  | stock_movimientos |
| private.prevent_supplier_price_unit_mismatch | Interna |  | compras_proveedores_items |
| private.price_compute | Interna | p_method text, p_value numeric, p_cost numeric, p_step numeric |  |
| private.price_costs | Interna | p_company uuid, p_items uuid[] | produccion_formulas, stock_items |
| private.price_effective | Interna | p_company uuid, p_list uuid, p_term text | stock_items, stock_unidades, ventas_listas_items, ventas_listas_items_metodo, ventas_listas_precios |
| private.price_history_immutable | Interna |  |  |
| private.price_item_cost | Interna | p_company uuid, p_item uuid |  |
| private.price_lists_guard | Interna |  | ventas_listas_items, ventas_listas_precios |
| private.price_require_admin | Interna | p_company uuid, p_cost boolean |  |
| private.price_require_cost_view | Interna | p_company uuid |  |
| private.price_round | Interna | p numeric, p_step numeric |  |
| private.price_write | Interna | p_company uuid, p_list uuid, p_item uuid, p_new numeric, p_method text, p_value numeric, p_cost numeric, p_keep_cost boolean, p_source text, p_reason text | ventas_listas_items, ventas_listas_items_historial, ventas_listas_items_metodo |
| private.production_unit_cost | Interna | p_company uuid, p_item uuid, p_path uuid[] | produccion_formulas, produccion_formulas_lineas, stock_items |
| private.protect_archived_activity | Interna |  |  |
| private.protect_preferred_material_cost | Interna |  | compras_proveedores_items |
| private.purchase_request_lines_immutable | Interna |  |  |
| private.purchase_requests_guard | Interna |  |  |
| private.quote_lines_immutable | Interna |  |  |
| private.quotes_guard | Interna |  |  |
| private.rebalance_production_on_event | Interna |  |  |
| private.rebalance_production_reservations | Interna | p_company uuid | produccion_ordenes, produccion_ordenes_eventos, produccion_ordenes_reservas, produccion_reservas_ubicaciones, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_saldos |
| private.rebalance_production_reservations_item | Interna | p_company uuid, p_item uuid | produccion_ordenes, produccion_ordenes_eventos, produccion_ordenes_reservas, produccion_reservas_ubicaciones, stock_depositos, stock_items, stock_lotes, stock_lotes_saldos, stock_saldos |
| private.refresh_fx_costs | Interna |  | compras_proveedores_items, stock_items |
| private.refresh_quote_cost | Interna |  |  |
| private.reject_stock_history_mutation | Interna |  |  |
| private.reject_stock_operation_mutation | Interna |  |  |
| private.release_closed_production_job | Interna |  |  |
| private.reserve_new_production_job | Interna |  | produccion_ordenes_reservas |
| private.row_has_cost | Interna | p_row jsonb |  |
| private.sale_resolve_price | Interna | p_company uuid, p_customer uuid, p_item uuid | stock_items, ventas_clientes, ventas_items_config, ventas_listas_items, ventas_listas_precios, ventas_precios_config |
| private.save_item_with_cost | Interna | p_company uuid, p_item uuid, p_row jsonb, p_expected_updated_at timestamp with time zone, p_preserve_cost boolean | compras_proveedores, compras_proveedores_items, finanzas_tipos_cambio, stock_categorias, stock_items, stock_unidades |
| private.save_role_permissions | Interna | p_company uuid, p_role uuid, p_permissions jsonb | ajustes_permisos_catalogo, ajustes_roles, ajustes_roles_permisos |
| private.snapshot_purchase_item_name | Interna |  | stock_items |
| private.snapshot_work_options | Interna | p_company uuid, p_options jsonb | produccion_documentos_config, produccion_tipos_envase, stock_unidades |
| private.strip_snapshot_cost | Interna | p_snapshot jsonb |  |
| private.support_session_active | Interna | p_company uuid | empresas, private.soporte_operadores, private.soporte_sesiones |
| private.sync_preferred_material_cost | Interna | p_company uuid, p_item uuid | compras_proveedores_items, stock_items |
| private.touch_item_updated_at | Interna |  |  |
