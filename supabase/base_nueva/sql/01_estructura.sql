-- 01. Extensiones, esquemas, tablas, claves, restricciones e índices.
begin;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists plpgsql_check with schema extensions;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table private.produccion_solicitudes_eliminadas (
  empresa_id uuid not null,
  recurso text not null,
  solicitud_id uuid not null,
  autor_id uuid not null,
  eliminado_en timestamp with time zone not null default clock_timestamp()
);
alter table private.produccion_solicitudes_eliminadas enable row level security;

create table private.soporte_accesos (
  id bigint generated always as identity not null,
  usuario_id uuid not null,
  empresa_id uuid not null,
  motivo text not null,
  iniciado_en timestamp with time zone not null default clock_timestamp(),
  vence_en timestamp with time zone not null
);
alter table private.soporte_accesos enable row level security;

create table private.soporte_operadores (
  usuario_id uuid not null,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table private.soporte_operadores enable row level security;

create table private.soporte_sesiones (
  usuario_id uuid not null,
  empresa_id uuid not null,
  vence_en timestamp with time zone not null
);
alter table private.soporte_sesiones enable row level security;

create table public.ajustes_auditoria_accesos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  autor_id uuid not null,
  accion text not null,
  usuario_destino_id uuid,
  rol_destino_id uuid,
  detalle jsonb not null default '{}'::jsonb,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ajustes_auditoria_accesos enable row level security;

create table public.empresas (
  id uuid not null default gen_random_uuid(),
  nombre text not null,
  identificador text not null,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now(),
  activo boolean not null default true,
  moneda text not null default 'ARS' check (moneda ~ '^[A-Z]{3}$'),
  zona_horaria text not null default 'America/Argentina/Cordoba',
  modulos jsonb not null default '{"stock": true, "produccion": true, "compras": false, "ventas": false, "finanzas": false, "reportes": false}'::jsonb check (jsonb_typeof(modulos) = 'object')
);
alter table public.empresas enable row level security;

create table public.empresas_perfil (
  empresa_id uuid not null,
  razon_social text not null default ''::text,
  identificacion_fiscal text not null default ''::text,
  condicion_fiscal text not null default ''::text,
  direccion text not null default ''::text,
  telefono text not null default ''::text,
  email text not null default ''::text,
  sitio_web text not null default ''::text,
  logo text not null default ''::text,
  actualizado_en timestamp with time zone not null default clock_timestamp(),
  actualizado_por uuid
);
alter table public.empresas_perfil enable row level security;

create table public.empresas_usuarios (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  usuario_id uuid not null,
  rol_id uuid not null,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table public.empresas_usuarios enable row level security;

create table public.ventas_clientes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  identificacion_fiscal text not null default ''::text,
  email text not null default ''::text,
  telefono text not null default ''::text,
  direccion text not null default ''::text,
  nota text not null default ''::text,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now(),
  lista_precio_id uuid
);
alter table public.ventas_clientes enable row level security;

create table public.stock_remitos_lineas (
  empresa_id uuid not null,
  remito_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  item_codigo text not null,
  item_nombre text not null,
  unidad_simbolo text not null,
  deposito_id uuid not null,
  deposito_nombre text not null,
  lote_codigo text,
  cantidad numeric(18,6) not null,
  operacion_stock_id uuid not null,
  evento_produccion_id uuid,
  venta_id uuid,
  venta_linea smallint
);
alter table public.stock_remitos_lineas enable row level security;

create table public.stock_remitos_reversiones (
  empresa_id uuid not null,
  remito_id uuid not null,
  linea smallint not null,
  operacion_stock_id uuid not null,
  evento_produccion_id uuid,
  venta_id uuid,
  venta_linea smallint
);
alter table public.stock_remitos_reversiones enable row level security;

create table public.stock_remitos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  tipo text not null,
  orden_id uuid,
  venta_id uuid,
  destinatario text not null,
  nota text not null,
  estado text not null default 'emitido'::text,
  motivo_anulacion text,
  anulado_en timestamp with time zone,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  archivado boolean not null default false
);
alter table public.stock_remitos enable row level security;

create table public.finanzas_tipos_cambio (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  activo boolean not null default true,
  archivado boolean not null default false,
  activo_antes_de_archivar boolean
);
alter table public.finanzas_tipos_cambio enable row level security;

create table public.finanzas_cotizaciones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  tipo_cambio_id uuid not null,
  ars_por_usd numeric(18,6) not null,
  vigente_desde date not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.finanzas_cotizaciones enable row level security;

create table public.stock_categorias (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  codigo text not null,
  nombre text not null,
  descripcion text not null default ''::text,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table public.stock_categorias enable row level security;

create table public.ventas_items_config (
  empresa_id uuid not null,
  item_id uuid not null,
  impuesto_porcentaje numeric(5,2),
  contenido_cantidad numeric(18,6),
  contenido_unidad_id uuid,
  actualizado_en timestamp with time zone not null default clock_timestamp(),
  actualizado_por uuid
);
alter table public.ventas_items_config enable row level security;

create table public.stock_items (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  codigo text not null,
  nombre text not null,
  tipo_item text not null,
  categoria_id uuid,
  unidad_id uuid not null,
  codigo_barras text,
  descripcion text not null default ''::text,
  stock_minimo numeric(18,6) not null default 0,
  usa_lotes boolean not null default false,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now(),
  costo_unitario_referencia numeric(18,2),
  precio_venta_unitario numeric(18,2),
  stock_infinito boolean not null default false,
  costo_referencia_usd numeric(14,2),
  tipo_cambio_referencia_id uuid,
  usa_rendimiento boolean not null default false,
  factor_rendimiento numeric(12,6) not null default 1,
  archivado boolean not null default false,
  activo_antes_de_archivar boolean
);
alter table public.stock_items enable row level security;

create table public.inicio_alertas_leidas (
  empresa_id uuid not null,
  usuario_id uuid not null,
  alerta_clave text not null,
  huella text not null,
  leido_en timestamp with time zone not null default now()
);
alter table public.inicio_alertas_leidas enable row level security;

create table public.ajustes_permisos_catalogo (
  recurso text not null,
  modulo text not null,
  padre text,
  etiqueta text not null,
  ayuda text not null default ''::text,
  orden integer not null,
  acciones text[] not null default ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text],
  es_grupo boolean not null default false,
  solo_admin boolean not null default false,
  exigido boolean not null default false
);
alter table public.ajustes_permisos_catalogo enable row level security;

create table public.ventas_precios_antiduplicado (
  empresa_id uuid not null,
  solicitud_id uuid not null,
  lista_precio_id uuid not null,
  tipo text not null,
  resultado jsonb not null,
  creado_por uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_precios_antiduplicado enable row level security;

create table public.ventas_listas_items_historial (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  lista_precio_id uuid not null,
  item_id uuid not null,
  precio_neto_anterior numeric(18,2),
  precio_neto_nuevo numeric(18,2),
  metodo text,
  metodo_valor numeric(18,4),
  costo_copia numeric(18,2),
  origen text not null,
  motivo text not null default ''::text,
  cambiado_por uuid not null,
  cambiado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_listas_items_historial enable row level security;

create table public.ventas_listas_items_metodo (
  empresa_id uuid not null,
  lista_precio_id uuid not null,
  item_id uuid not null,
  metodo text not null,
  metodo_valor numeric(18,4) not null,
  costo_copia numeric(18,2),
  actualizado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_listas_items_metodo enable row level security;

create table public.ventas_listas_items (
  empresa_id uuid not null,
  lista_precio_id uuid not null,
  item_id uuid not null,
  precio_neto numeric(18,2) not null,
  actualizado_en timestamp with time zone not null default clock_timestamp(),
  actualizado_por uuid
);
alter table public.ventas_listas_items enable row level security;

create table public.ventas_listas_precios (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  moneda text not null default 'ARS'::text,
  lista_base_id uuid,
  descuento_base_porcentaje numeric(6,3) not null default 0,
  redondeo numeric(12,2) not null default 0,
  vigente_desde date,
  vigente_hasta date,
  es_predeterminada boolean not null default false,
  archivado boolean not null default false,
  nota text not null default ''::text,
  creado_en timestamp with time zone not null default clock_timestamp(),
  creado_por uuid
);
alter table public.ventas_listas_precios enable row level security;

create table public.ventas_precios_config (
  empresa_id uuid not null,
  impuesto_porcentaje_predeterminado numeric(5,2) not null default 21,
  margen_minimo_porcentaje numeric(5,2) not null default 0,
  comision_porcentaje numeric(5,2) not null default 0,
  estructura_porcentaje numeric(5,2) not null default 0,
  actualizado_en timestamp with time zone not null default clock_timestamp(),
  actualizado_por uuid,
  descuento_maximo_porcentaje numeric(5,2) not null default 0
);
alter table public.ventas_precios_config enable row level security;

create table public.produccion_documentos_config (
  empresa_id uuid not null,
  logo text not null default ''::text,
  documento_codigo text not null default 'OP'::text,
  revision text not null default '01'::text,
  observaciones_etiquetas jsonb not null default '[]'::jsonb,
  actualizado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.produccion_documentos_config enable row level security;

create table public.produccion_formulas_lineas (
  empresa_id uuid not null,
  producto_id uuid not null,
  componente_id uuid not null,
  cantidad numeric(18,6) not null
);
alter table public.produccion_formulas_lineas enable row level security;

create table public.produccion_formulas (
  empresa_id uuid not null,
  producto_id uuid not null,
  cantidad_base numeric(18,6) not null,
  version integer not null default 1,
  actualizado_en timestamp with time zone not null default now(),
  archivado boolean not null default false
);
alter table public.produccion_formulas enable row level security;

create table public.produccion_ordenes_eventos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  orden_id uuid not null,
  solicitud_id uuid not null,
  tipo text not null,
  entrega_id uuid,
  componente_id uuid not null,
  deposito_id uuid not null,
  lote_codigo text,
  cantidad numeric(18,6) not null,
  costo_unitario numeric(18,2) not null,
  operacion_stock_id uuid not null,
  nota text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.produccion_ordenes_eventos enable row level security;

create table public.produccion_ordenes_reservas (
  empresa_id uuid not null,
  orden_id uuid not null,
  componente_id uuid not null,
  cantidad_requerida numeric(18,6) not null,
  cantidad_reservada numeric(18,6) not null default 0,
  actualizado_en timestamp with time zone not null default now()
);
alter table public.produccion_ordenes_reservas enable row level security;

create table public.produccion_ordenes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  producto_id uuid not null,
  plan_id uuid,
  cantidad_planificada numeric(18,6) not null,
  cantidad_real numeric(18,6),
  deposito_id uuid not null,
  fecha_limite date,
  formula_version integer not null,
  formula_copia jsonb not null,
  estado text not null default 'pendiente'::text,
  nota text not null,
  motivo_cancelacion text,
  nota_diferencia text,
  producto_lote text,
  producto_vencimiento date,
  fabricacion_id uuid,
  solicitud_cierre_id uuid,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  iniciado_en timestamp with time zone,
  terminado_en timestamp with time zone,
  cancelado_en timestamp with time zone,
  numero bigint not null,
  factor_rendimiento numeric(12,6) not null default 1,
  cantidad_esperada numeric(18,6) not null,
  documento_copia jsonb not null default '{}'::jsonb,
  opciones_trabajo jsonb not null default '{}'::jsonb,
  opciones_trabajo_solicitadas jsonb not null default '{}'::jsonb,
  detalles_actualizado_en timestamp with time zone not null default clock_timestamp(),
  archivado boolean not null default false
);
alter table public.produccion_ordenes enable row level security;

create table public.produccion_fabricaciones_antiduplicado (
  empresa_id uuid not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  orden_id uuid not null,
  fabricacion_id uuid not null,
  autor_id uuid not null
);
alter table public.produccion_fabricaciones_antiduplicado enable row level security;

create table public.produccion_tipos_envase (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  capacidad numeric(18,6) not null,
  unidad_id uuid not null,
  activo boolean not null default true
);
alter table public.produccion_tipos_envase enable row level security;

create table public.produccion_planes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  solicitud_id uuid not null,
  producto_id uuid not null,
  deposito_id uuid not null,
  cantidad numeric(18,6) not null,
  formula_version integer not null,
  costo_estimado numeric(18,2) not null,
  componentes_copia jsonb not null,
  fecha_limite date,
  nota text not null,
  estado text not null default 'planificado'::text,
  fabricacion_id uuid,
  solicitud_cierre_id uuid,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default now(),
  terminado_en timestamp with time zone,
  cancelado_en timestamp with time zone,
  archivado boolean not null default false
);
alter table public.produccion_planes enable row level security;

create table public.produccion_reservas_ubicaciones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  orden_id uuid not null,
  componente_id uuid not null,
  deposito_id uuid not null,
  lote_id uuid,
  lote_codigo text,
  cantidad numeric(18,6) not null
);
alter table public.produccion_reservas_ubicaciones enable row level security;

create table public.produccion_fabricaciones_lineas (
  empresa_id uuid not null,
  fabricacion_id uuid not null,
  componente_id uuid not null,
  deposito_id uuid not null,
  cantidad numeric(18,6) not null,
  lote_codigo text,
  costo_unitario numeric(18,2) not null,
  operacion_stock_id uuid not null
);
alter table public.produccion_fabricaciones_lineas enable row level security;

create table public.produccion_fabricaciones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  producto_id uuid not null,
  formula_version integer not null,
  cantidad numeric(18,6) not null,
  deposito_id uuid not null,
  operacion_producto_id uuid not null,
  costo_estimado numeric(18,2) not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  nota text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  archivado boolean not null default false
);
alter table public.produccion_fabricaciones enable row level security;

create table public.ajustes_perfiles (
  id uuid not null,
  nombre text,
  creado_en timestamp with time zone not null default now(),
  actualizado_en timestamp with time zone not null default now()
);
alter table public.ajustes_perfiles enable row level security;

create table public.compras_ordenes_lineas (
  empresa_id uuid not null,
  orden_compra_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  item_codigo text not null,
  unidad_simbolo text not null,
  cantidad numeric(18,6) not null,
  precio_unitario numeric(18,2) not null,
  item_nombre text,
  cantidad_recibida numeric(18,6) not null default 0
);
alter table public.compras_ordenes_lineas enable row level security;

create table public.compras_ordenes_antiduplicado (
  empresa_id uuid not null,
  solicitud_id uuid not null,
  orden_compra_id uuid not null,
  solicitud_datos jsonb not null,
  autor_id uuid not null
);
alter table public.compras_ordenes_antiduplicado enable row level security;

create table public.compras_ordenes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  proveedor_id uuid not null,
  proveedor_nombre text not null,
  estado text not null default 'abierta'::text,
  nota text not null default ''::text,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  cancelado_en timestamp with time zone
);
alter table public.compras_ordenes enable row level security;

create table public.compras_recepciones_lineas (
  empresa_id uuid not null,
  recepcion_id uuid not null,
  orden_compra_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  deposito_id uuid not null,
  deposito_codigo text not null,
  cantidad numeric(18,6) not null,
  precio_unitario numeric(18,2) not null,
  lote_codigo text,
  vencimiento date,
  operacion_stock_id uuid not null
);
alter table public.compras_recepciones_lineas enable row level security;

create table public.compras_recepciones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  orden_compra_id uuid not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  nota text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.compras_recepciones enable row level security;

create table public.compras_pedidos_lineas (
  empresa_id uuid not null,
  pedido_id uuid not null,
  linea smallint not null,
  item_id uuid,
  item_codigo text,
  item_nombre text not null,
  unidad_simbolo text not null default ''::text,
  cantidad numeric not null,
  nota text not null default ''::text
);
alter table public.compras_pedidos_lineas enable row level security;

create table public.compras_pedidos_antiduplicado (
  empresa_id uuid not null,
  solicitud_id uuid not null,
  pedido_id uuid not null,
  solicitud_datos jsonb not null,
  autor_id uuid not null
);
alter table public.compras_pedidos_antiduplicado enable row level security;

create table public.compras_pedidos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  solicitado_por uuid not null,
  solicitante_nombre text not null,
  estado text not null default 'pendiente'::text,
  prioridad text not null default 'normal'::text,
  fecha_necesaria date,
  nota text not null default ''::text,
  nota_resolucion text not null default ''::text,
  orden_compra_id uuid,
  resuelto_por uuid,
  resuelto_en timestamp with time zone,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.compras_pedidos enable row level security;

create table public.ventas_presupuestos_lineas (
  empresa_id uuid not null,
  presupuesto_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  item_codigo text not null,
  item_nombre text not null,
  unidad_simbolo text not null,
  cantidad numeric(18,6) not null,
  lista_precio_id uuid,
  precio_unitario_lista numeric(18,2) not null,
  descuento_porcentaje numeric(5,2) not null default 0,
  descuento_motivo text,
  precio_unitario numeric(18,2) not null,
  total_linea numeric(18,2) not null,
  impuesto_porcentaje numeric(5,2) not null
);
alter table public.ventas_presupuestos_lineas enable row level security;

create table public.ventas_presupuestos_estados (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  presupuesto_id uuid not null,
  estado_anterior text,
  estado_nuevo text not null,
  cambiado_por uuid not null,
  cambiado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_presupuestos_estados enable row level security;

create table public.ventas_presupuestos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  cliente_id uuid,
  cliente_nombre text not null,
  cliente_identificacion_fiscal text not null default ''::text,
  cliente_email text not null default ''::text,
  cliente_telefono text not null default ''::text,
  cliente_direccion text not null default ''::text,
  estado text not null default 'abierto'::text,
  vigente_hasta date not null,
  nota text not null default ''::text,
  mostrar_impuesto boolean not null default true,
  total_neto numeric(18,2) not null,
  total_impuesto numeric(18,2) not null,
  total_bruto numeric(18,2) not null,
  impuestos_detalle jsonb not null default '[]'::jsonb,
  creado_por uuid not null,
  creado_por_nombre text not null default ''::text,
  creado_en timestamp with time zone not null default clock_timestamp(),
  estado_cambiado_en timestamp with time zone,
  estado_cambiado_por uuid,
  impuesto_incluido boolean not null default false
);
alter table public.ventas_presupuestos enable row level security;

create table public.ajustes_roles_permisos (
  empresa_id uuid not null,
  rol_id uuid not null,
  recurso text not null,
  accion text not null
);
alter table public.ajustes_roles_permisos enable row level security;

create table public.ajustes_roles (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  codigo text not null,
  nombre text not null,
  creado_en timestamp with time zone not null default now()
);
alter table public.ajustes_roles enable row level security;

create table public.ventas_ajustes_lineas (
  empresa_id uuid not null,
  ajuste_id uuid not null,
  venta_id uuid not null,
  venta_linea smallint not null,
  cantidad numeric(18,6) not null,
  credito_importe numeric(18,2) not null,
  reingresado boolean not null,
  operacion_stock_id uuid
);
alter table public.ventas_ajustes_lineas enable row level security;

create table public.ventas_ajustes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  venta_id uuid not null,
  solicitud_id uuid not null,
  tipo text not null,
  motivo text not null,
  credito_total numeric(18,2) not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_ajustes enable row level security;

create table public.ventas_cobros_antiduplicado (
  empresa_id uuid not null,
  solicitud_id uuid not null,
  venta_id uuid not null,
  solicitud_cobro_id uuid,
  modo_pago text not null,
  importe numeric(18,2),
  medio_pago text,
  cuenta_id uuid,
  autor_id uuid not null
);
alter table public.ventas_cobros_antiduplicado enable row level security;

create table public.ventas_lineas (
  empresa_id uuid not null,
  venta_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  item_codigo text not null,
  item_nombre text not null,
  unidad_simbolo text not null,
  deposito_id uuid not null,
  deposito_codigo text not null,
  lote_codigo text,
  cantidad numeric(18,6) not null,
  precio_unitario numeric(18,2) not null,
  total_linea numeric(18,2) not null,
  costo_unitario_estimado numeric(18,2),
  operacion_stock_id uuid not null,
  lista_precio_id uuid,
  precio_unitario_lista numeric(18,2),
  descuento_porcentaje numeric(5,2) not null default 0,
  descuento_motivo text,
  impuesto_porcentaje numeric(5,2)
);
alter table public.ventas_lineas enable row level security;

create table public.ventas_cobros_reversiones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  venta_id uuid not null,
  cobro_id uuid not null,
  motivo text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_cobros_reversiones enable row level security;

create table public.ventas_cobros (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  venta_id uuid not null,
  solicitud_id uuid not null,
  importe numeric(18,2) not null,
  medio_pago text not null,
  fecha_pago date not null,
  referencia text not null default ''::text,
  nota text not null default ''::text,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_cobros enable row level security;

create table public.ventas_reintegros (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  venta_id uuid not null,
  solicitud_id uuid not null,
  cuenta_id uuid not null,
  movimiento_finanzas_id uuid not null,
  importe numeric(18,2) not null,
  motivo text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas_reintegros enable row level security;

create table public.ventas (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  cliente_id uuid not null,
  cliente_nombre text not null,
  cliente_identificacion_fiscal text not null,
  nota text not null,
  total numeric(18,2) not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.ventas enable row level security;

create table public.stock_saldos (
  empresa_id uuid not null,
  item_id uuid not null,
  deposito_id uuid not null,
  cantidad numeric(18,6) not null default 0,
  version bigint not null default 0,
  actualizado_en timestamp with time zone not null default now()
);
alter table public.stock_saldos enable row level security;

create table public.stock_lotes_saldos (
  empresa_id uuid not null,
  item_id uuid not null,
  deposito_id uuid not null,
  lote_id uuid not null,
  cantidad numeric(18,6) not null default 0
);
alter table public.stock_lotes_saldos enable row level security;

create table public.stock_lotes_aperturas (
  empresa_id uuid not null,
  item_id uuid not null,
  deposito_id uuid not null,
  lote_id uuid not null,
  cantidad numeric(18,6) not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.stock_lotes_aperturas enable row level security;

create table public.stock_lotes (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  item_id uuid not null,
  codigo text not null,
  vencimiento date,
  creado_en timestamp with time zone not null default now()
);
alter table public.stock_lotes enable row level security;

create table public.stock_movimientos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  operacion_id uuid not null,
  linea smallint not null,
  item_id uuid not null,
  deposito_id uuid not null,
  tipo text not null,
  variacion numeric(18,6) not null,
  saldo_posterior numeric(18,6) not null,
  saldo_version bigint not null,
  item_codigo text not null,
  deposito_codigo text not null,
  unidad_simbolo text not null,
  nota text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  lote_id uuid,
  lote_codigo text,
  lote_vencimiento date
);
alter table public.stock_movimientos enable row level security;

create table public.stock_operaciones (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  solicitud_id uuid not null,
  item_id uuid not null,
  deposito_id uuid not null,
  deposito_destino_id uuid,
  tipo text not null,
  cantidad numeric(18,6) not null,
  nota text not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  lote_id uuid,
  lote_codigo text,
  lote_vencimiento date
);
alter table public.stock_operaciones enable row level security;

create table public.compras_proveedores_items (
  empresa_id uuid not null,
  proveedor_id uuid not null,
  item_id uuid not null,
  precio_unitario numeric(18,2) not null,
  proveedor_codigo text not null default ''::text,
  actualizado_en timestamp with time zone not null default now(),
  moneda text not null default 'ARS'::text,
  tipo_cambio_id uuid,
  ajuste_porcentaje numeric(8,2) not null default 0,
  preferido boolean not null default false
);
alter table public.compras_proveedores_items enable row level security;

create table public.compras_pagos_lineas (
  empresa_id uuid not null,
  pago_id uuid not null,
  orden_compra_id uuid not null,
  importe numeric(18,2) not null,
  solicitud_finanzas_id uuid not null default gen_random_uuid(),
  movimiento_finanzas_id uuid
);
alter table public.compras_pagos_lineas enable row level security;

create table public.compras_pagos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  numero bigint not null,
  proveedor_id uuid not null,
  cuenta_id uuid not null,
  solicitud_id uuid not null,
  solicitud_datos jsonb not null,
  importe numeric(18,2) not null,
  fecha_pago date not null,
  nota text not null,
  referencia text not null default ''::text,
  estado text not null default 'borrador'::text,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp(),
  confirmado_en timestamp with time zone
);
alter table public.compras_pagos enable row level security;

create table public.compras_proveedores_ajustes_precio (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  solicitud_id uuid not null,
  proveedor_id uuid,
  item_id uuid,
  porcentaje numeric(8,2) not null,
  cantidad_cambiados integer not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default now()
);
alter table public.compras_proveedores_ajustes_precio enable row level security;

create table public.compras_proveedores (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  identificacion_fiscal text not null default ''::text,
  email text not null default ''::text,
  telefono text not null default ''::text,
  nota text not null default ''::text,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now(),
  demora_dias integer not null default 7,
  provee_descripcion text not null default ''::text
);
alter table public.compras_proveedores enable row level security;

create table public.finanzas_cuentas (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  nombre text not null,
  tipo text not null,
  saldo_inicial numeric(18,2) not null default 0,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table public.finanzas_cuentas enable row level security;

create table public.finanzas_movimientos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  cuenta_id uuid not null,
  solicitud_id uuid not null,
  tipo text not null,
  importe numeric(18,2) not null,
  orden_compra_id uuid,
  nota text not null,
  fecha date not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.finanzas_movimientos enable row level security;

create table public.finanzas_cobros_cuentas (
  empresa_id uuid not null,
  cobro_id uuid not null,
  cuenta_id uuid not null,
  autor_id uuid not null,
  creado_en timestamp with time zone not null default clock_timestamp()
);
alter table public.finanzas_cobros_cuentas enable row level security;

create table public.stock_unidades (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  codigo text not null,
  nombre text not null,
  simbolo text not null,
  magnitud text not null,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table public.stock_unidades enable row level security;

create table public.stock_depositos (
  id uuid not null default gen_random_uuid(),
  empresa_id uuid not null,
  codigo text not null,
  nombre text not null,
  ubicacion text not null default ''::text,
  activo boolean not null default true,
  creado_en timestamp with time zone not null default now()
);
alter table public.stock_depositos enable row level security;

create table public.empresas_numeradores (
  empresa_id uuid not null,
  documento text not null,
  proximo_numero bigint not null default 1 check (proximo_numero > 0),
  constraint empresas_numeradores_pkey primary key (empresa_id, documento)
);
alter table public.empresas_numeradores enable row level security;

alter table private.produccion_solicitudes_eliminadas add constraint produccion_solicitudes_eliminadas_pkey PRIMARY KEY (empresa_id, recurso, solicitud_id);
alter table private.soporte_accesos add constraint soporte_accesos_motivo_check CHECK (((length(btrim(motivo)) >= 8) AND (length(btrim(motivo)) <= 300)));
alter table private.soporte_accesos add constraint soporte_accesos_pkey PRIMARY KEY (id);
alter table private.soporte_operadores add constraint soporte_operadores_pkey PRIMARY KEY (usuario_id);
alter table private.soporte_sesiones add constraint soporte_sesiones_pkey PRIMARY KEY (usuario_id);
alter table public.ajustes_auditoria_accesos add constraint ajustes_auditoria_accesos_accion_check CHECK ((accion = ANY (ARRAY['rol_creado'::text, 'rol_editado'::text, 'miembro_editado'::text])));
alter table public.ajustes_auditoria_accesos add constraint ajustes_auditoria_accesos_pkey PRIMARY KEY (id);
alter table public.empresas add constraint empresas_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)));
alter table public.empresas add constraint empresas_pkey PRIMARY KEY (id);
alter table public.empresas add constraint empresas_identificador_key UNIQUE (identificador);
alter table public.empresas_perfil add constraint empresas_perfil_direccion_check CHECK ((length(direccion) <= 240));
alter table public.empresas_perfil add constraint empresas_perfil_email_check CHECK ((length(email) <= 160));
alter table public.empresas_perfil add constraint empresas_perfil_razon_social_check CHECK ((length(razon_social) <= 160));
alter table public.empresas_perfil add constraint empresas_perfil_logo_check CHECK ((length(logo) <= 3000000));
alter table public.empresas_perfil add constraint empresas_perfil_telefono_check CHECK ((length(telefono) <= 40));
alter table public.empresas_perfil add constraint empresas_perfil_condicion_fiscal_check CHECK ((length(condicion_fiscal) <= 60));
alter table public.empresas_perfil add constraint empresas_perfil_identificacion_fiscal_check CHECK ((length(identificacion_fiscal) <= 30));
alter table public.empresas_perfil add constraint empresas_perfil_sitio_web_check CHECK ((length(sitio_web) <= 160));
alter table public.empresas_perfil add constraint empresas_perfil_pkey PRIMARY KEY (empresa_id);
alter table public.empresas_usuarios add constraint empresas_usuarios_pkey PRIMARY KEY (id);
alter table public.empresas_usuarios add constraint empresas_usuarios_empresa_id_usuario_id_key UNIQUE (empresa_id, usuario_id);
alter table public.ventas_clientes add constraint ventas_clientes_direccion_check CHECK ((length(direccion) <= 240));
alter table public.ventas_clientes add constraint ventas_clientes_email_check CHECK ((length(email) <= 160));
alter table public.ventas_clientes add constraint ventas_clientes_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)));
alter table public.ventas_clientes add constraint ventas_clientes_nota_check CHECK ((length(nota) <= 500));
alter table public.ventas_clientes add constraint ventas_clientes_telefono_check CHECK ((length(telefono) <= 40));
alter table public.ventas_clientes add constraint ventas_clientes_identificacion_fiscal_check CHECK ((length(identificacion_fiscal) <= 30));
alter table public.ventas_clientes add constraint ventas_clientes_pkey PRIMARY KEY (id);
alter table public.ventas_clientes add constraint ventas_clientes_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_check CHECK (((venta_id IS NULL) = (venta_linea IS NULL)));
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_linea_check CHECK (((linea >= 1) AND (linea <= 40)));
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_pkey PRIMARY KEY (empresa_id, remito_id, linea);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_evento_produccion_id_key UNIQUE (empresa_id, evento_produccion_id);
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_check CHECK (((venta_id IS NULL) = (venta_linea IS NULL)));
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_pkey PRIMARY KEY (empresa_id, remito_id, linea);
alter table public.stock_remitos add constraint stock_remitos_check CHECK (((tipo = 'produccion'::text) = (orden_id IS NOT NULL)));
alter table public.stock_remitos add constraint stock_remitos_check1 CHECK (((tipo = 'venta'::text) = (venta_id IS NOT NULL)));
alter table public.stock_remitos add constraint stock_remitos_check2 CHECK (((estado = 'anulado'::text) = ((anulado_en IS NOT NULL) AND (motivo_anulacion IS NOT NULL))));
alter table public.stock_remitos add constraint stock_remitos_tipo_check CHECK ((tipo = ANY (ARRAY['produccion'::text, 'materiales'::text, 'productos'::text, 'venta'::text])));
alter table public.stock_remitos add constraint stock_remitos_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 300)));
alter table public.stock_remitos add constraint stock_remitos_numero_check CHECK ((numero > 0));
alter table public.stock_remitos add constraint stock_remitos_destinatario_check CHECK (((length(btrim(destinatario)) >= 3) AND (length(btrim(destinatario)) <= 120)));
alter table public.stock_remitos add constraint stock_remitos_estado_check CHECK ((estado = ANY (ARRAY['emitido'::text, 'anulado'::text])));
alter table public.stock_remitos add constraint stock_remitos_pkey PRIMARY KEY (id);
alter table public.stock_remitos add constraint stock_remitos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.stock_remitos add constraint stock_remitos_empresa_id_numero_key UNIQUE (empresa_id, numero);
alter table public.stock_remitos add constraint stock_remitos_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.finanzas_tipos_cambio add constraint finanzas_tipos_cambio_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 60)));
alter table public.finanzas_tipos_cambio add constraint finanzas_tipos_cambio_pkey PRIMARY KEY (id);
alter table public.finanzas_tipos_cambio add constraint finanzas_tipos_cambio_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.finanzas_tipos_cambio add constraint finanzas_tipos_cambio_empresa_id_nombre_key UNIQUE (empresa_id, nombre);
alter table public.finanzas_cotizaciones add constraint finanzas_cotizaciones_ars_por_usd_check CHECK ((ars_por_usd > (0)::numeric));
alter table public.finanzas_cotizaciones add constraint finanzas_cotizaciones_pkey PRIMARY KEY (id);
alter table public.finanzas_cotizaciones add constraint finanzas_cotizaciones_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.stock_categorias add constraint stock_categorias_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,39}$'::text));
alter table public.stock_categorias add constraint stock_categorias_descripcion_check CHECK ((length(descripcion) <= 500));
alter table public.stock_categorias add constraint stock_categorias_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)));
alter table public.stock_categorias add constraint stock_categorias_pkey PRIMARY KEY (id);
alter table public.stock_categorias add constraint stock_categorias_empresa_id_codigo_key UNIQUE (empresa_id, codigo);
alter table public.stock_categorias add constraint stock_categorias_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_items_config add constraint ventas_items_config_check CHECK (((contenido_cantidad IS NULL) = (contenido_unidad_id IS NULL)));
alter table public.ventas_items_config add constraint ventas_items_config_contenido_cantidad_check CHECK (((contenido_cantidad IS NULL) OR (contenido_cantidad > (0)::numeric)));
alter table public.ventas_items_config add constraint ventas_items_config_impuesto_porcentaje_check CHECK (((impuesto_porcentaje IS NULL) OR ((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric))));
alter table public.ventas_items_config add constraint ventas_items_config_pkey PRIMARY KEY (empresa_id, item_id);
alter table public.stock_items add constraint stock_items_codigo_barras_check CHECK (((codigo_barras IS NULL) OR ((length(btrim(codigo_barras)) >= 4) AND (length(btrim(codigo_barras)) <= 80))));
alter table public.stock_items add constraint stock_items_codigo_check CHECK ((codigo ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,49}$'::text));
alter table public.stock_items add constraint stock_items_descripcion_check CHECK ((length(descripcion) <= 1500));
alter table public.stock_items add constraint stock_items_infinite_rules CHECK (((NOT stock_infinito) OR ((NOT usa_lotes) AND (stock_minimo = (0)::numeric))));
alter table public.stock_items add constraint stock_items_tipo_item_check CHECK ((tipo_item = ANY (ARRAY['materia_prima'::text, 'semielaborado'::text, 'producto_terminado'::text, 'insumo'::text])));
alter table public.stock_items add constraint stock_items_stock_minimo_check CHECK ((stock_minimo >= (0)::numeric));
alter table public.stock_items add constraint stock_items_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)));
alter table public.stock_items add constraint stock_items_costo_unitario_referencia_check CHECK (((costo_unitario_referencia IS NULL) OR (costo_unitario_referencia >= (0)::numeric)));
alter table public.stock_items add constraint stock_items_reference_usd_pair CHECK ((((costo_referencia_usd IS NULL) AND (tipo_cambio_referencia_id IS NULL)) OR ((costo_referencia_usd IS NOT NULL) AND (costo_referencia_usd >= (0)::numeric) AND (tipo_cambio_referencia_id IS NOT NULL))));
alter table public.stock_items add constraint stock_items_precio_venta_unitario_check CHECK (((precio_venta_unitario IS NULL) OR (precio_venta_unitario >= (0)::numeric)));
alter table public.stock_items add constraint stock_items_factor_rendimiento_check CHECK (((factor_rendimiento > (0)::numeric) AND (factor_rendimiento <= (1000)::numeric)));
alter table public.stock_items add constraint stock_items_pkey PRIMARY KEY (id);
alter table public.stock_items add constraint stock_items_company_codigo_unique UNIQUE (empresa_id, codigo);
alter table public.stock_items add constraint stock_items_empresa_id_unique UNIQUE (empresa_id, id);
alter table public.inicio_alertas_leidas add constraint inicio_alertas_leidas_alerta_clave_check CHECK (((length(alerta_clave) >= 5) AND (length(alerta_clave) <= 120)));
alter table public.inicio_alertas_leidas add constraint inicio_alertas_leidas_huella_check CHECK (((length(huella) >= 1) AND (length(huella) <= 150)));
alter table public.inicio_alertas_leidas add constraint inicio_alertas_leidas_pkey PRIMARY KEY (empresa_id, usuario_id, alerta_clave);
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_acciones_check CHECK (((acciones <@ ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text]) AND (cardinality(acciones) > 0)));
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_check CHECK (((padre IS NULL) OR (padre <> recurso)));
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_etiqueta_check CHECK (((length(btrim(etiqueta)) >= 2) AND (length(btrim(etiqueta)) <= 80)));
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_recurso_check CHECK ((recurso ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_pkey PRIMARY KEY (recurso);
alter table public.ventas_precios_antiduplicado add constraint ventas_precios_antiduplicado_tipo_check CHECK ((tipo = ANY (ARRAY['porcentaje'::text, 'recalculo'::text, 'importacion'::text])));
alter table public.ventas_precios_antiduplicado add constraint ventas_precios_antiduplicado_pkey PRIMARY KEY (empresa_id, solicitud_id);
alter table public.ventas_listas_items_historial add constraint ventas_listas_items_historial_motivo_check CHECK ((length(motivo) <= 200));
alter table public.ventas_listas_items_historial add constraint ventas_listas_items_historial_origen_check CHECK ((origen = ANY (ARRAY['manual'::text, 'masivo'::text, 'recalculo'::text, 'importacion'::text, 'quitado'::text])));
alter table public.ventas_listas_items_historial add constraint ventas_listas_items_historial_pkey PRIMARY KEY (id);
alter table public.ventas_listas_items_metodo add constraint ventas_listas_items_metodo_metodo_check CHECK ((metodo = ANY (ARRAY['margen'::text, 'recargo'::text, 'fijo'::text])));
alter table public.ventas_listas_items_metodo add constraint ventas_listas_items_metodo_metodo_valor_check CHECK ((metodo_valor >= (0)::numeric));
alter table public.ventas_listas_items_metodo add constraint ventas_listas_items_metodo_pkey PRIMARY KEY (empresa_id, lista_precio_id, item_id);
alter table public.ventas_listas_items add constraint ventas_listas_items_precio_neto_check CHECK (((precio_neto >= (0)::numeric) AND (precio_neto < ('10000000000000000'::bigint)::numeric)));
alter table public.ventas_listas_items add constraint ventas_listas_items_pkey PRIMARY KEY (empresa_id, lista_precio_id, item_id);
alter table public.ventas_listas_precios add constraint ventas_listas_precios_descuento_base_porcentaje_check CHECK (((descuento_base_porcentaje > ('-1000'::integer)::numeric) AND (descuento_base_porcentaje < (100)::numeric)));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_check CHECK (((lista_base_id IS NULL) OR (lista_base_id <> id)));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_check1 CHECK (((vigente_hasta IS NULL) OR (vigente_desde IS NULL) OR (vigente_hasta >= vigente_desde)));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_check2 CHECK (((lista_base_id IS NOT NULL) OR (descuento_base_porcentaje = (0)::numeric)));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_moneda_check CHECK ((moneda = ANY (ARRAY['ARS'::text, 'USD'::text])));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_nombre_check CHECK (((length(btrim(nombre)) >= 1) AND (length(btrim(nombre)) <= 80)));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_nota_check CHECK ((length(nota) <= 300));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_redondeo_check CHECK ((redondeo >= (0)::numeric));
alter table public.ventas_listas_precios add constraint ventas_listas_precios_pkey PRIMARY KEY (id);
alter table public.ventas_listas_precios add constraint ventas_listas_precios_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_precios_config add constraint ventas_precios_config_comision_porcentaje_check CHECK (((comision_porcentaje >= (0)::numeric) AND (comision_porcentaje <= (100)::numeric)));
alter table public.ventas_precios_config add constraint ventas_precios_config_impuesto_porcentaje_predeterminado_check CHECK (((impuesto_porcentaje_predeterminado >= (0)::numeric) AND (impuesto_porcentaje_predeterminado <= (100)::numeric)));
alter table public.ventas_precios_config add constraint ventas_precios_config_descuento_maximo_porcentaje_check CHECK (((descuento_maximo_porcentaje >= (0)::numeric) AND (descuento_maximo_porcentaje < (100)::numeric)));
alter table public.ventas_precios_config add constraint ventas_precios_config_margen_minimo_porcentaje_check CHECK (((margen_minimo_porcentaje >= (0)::numeric) AND (margen_minimo_porcentaje < (100)::numeric)));
alter table public.ventas_precios_config add constraint ventas_precios_config_estructura_porcentaje_check CHECK (((estructura_porcentaje >= (0)::numeric) AND (estructura_porcentaje <= (100)::numeric)));
alter table public.ventas_precios_config add constraint ventas_precios_config_pkey PRIMARY KEY (empresa_id);
alter table public.produccion_documentos_config add constraint produccion_documentos_config_pkey PRIMARY KEY (empresa_id);
alter table public.produccion_formulas_lineas add constraint produccion_formulas_lineas_check CHECK ((producto_id <> componente_id));
alter table public.produccion_formulas_lineas add constraint produccion_formulas_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_formulas_lineas add constraint produccion_formulas_lineas_pkey PRIMARY KEY (empresa_id, producto_id, componente_id);
alter table public.produccion_formulas add constraint produccion_formulas_cantidad_base_check CHECK ((cantidad_base > (0)::numeric));
alter table public.produccion_formulas add constraint produccion_formulas_pkey PRIMARY KEY (empresa_id, producto_id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_check CHECK (((tipo = 'devolucion'::text) = (entrega_id IS NOT NULL)));
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_tipo_check CHECK ((tipo = ANY (ARRAY['entrega'::text, 'devolucion'::text])));
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 300)));
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_costo_unitario_check CHECK ((costo_unitario >= (0)::numeric));
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_pkey PRIMARY KEY (id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.produccion_ordenes_reservas add constraint produccion_ordenes_reservas_cantidad_requerida_check CHECK ((cantidad_requerida > (0)::numeric));
alter table public.produccion_ordenes_reservas add constraint produccion_ordenes_reservas_cantidad_reservada_check CHECK ((cantidad_reservada >= (0)::numeric));
alter table public.produccion_ordenes_reservas add constraint produccion_ordenes_reservas_pkey PRIMARY KEY (empresa_id, orden_id, componente_id);
alter table public.produccion_ordenes add constraint produccion_ordenes_cantidad_real_check CHECK ((cantidad_real > (0)::numeric));
alter table public.produccion_ordenes add constraint produccion_ordenes_check CHECK (((estado = 'terminada'::text) = ((fabricacion_id IS NOT NULL) AND (terminado_en IS NOT NULL) AND (cantidad_real IS NOT NULL) AND (solicitud_cierre_id IS NOT NULL))));
alter table public.produccion_ordenes add constraint produccion_ordenes_check1 CHECK (((estado = 'cancelada'::text) = (cancelado_en IS NOT NULL)));
alter table public.produccion_ordenes add constraint produccion_ordenes_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 400)));
alter table public.produccion_ordenes add constraint produccion_ordenes_cantidad_planificada_check CHECK ((cantidad_planificada > (0)::numeric));
alter table public.produccion_ordenes add constraint produccion_ordenes_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'en_proceso'::text, 'terminada'::text, 'cancelada'::text])));
alter table public.produccion_ordenes add constraint produccion_ordenes_pkey PRIMARY KEY (id);
alter table public.produccion_ordenes add constraint produccion_ordenes_production_job_numero_unique UNIQUE (empresa_id, numero);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_plan_id_key UNIQUE (empresa_id, plan_id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.produccion_fabricaciones_antiduplicado add constraint produccion_fabricaciones_antiduplicado_pkey PRIMARY KEY (empresa_id, solicitud_id);
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_capacidad_check CHECK ((capacidad > (0)::numeric));
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)));
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_pkey PRIMARY KEY (id);
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.produccion_planes add constraint produccion_planes_check CHECK ((((estado = 'terminado'::text) AND (fabricacion_id IS NOT NULL) AND (terminado_en IS NOT NULL) AND (solicitud_cierre_id IS NOT NULL)) OR ((estado <> 'terminado'::text) AND (fabricacion_id IS NULL) AND (terminado_en IS NULL) AND (solicitud_cierre_id IS NULL))));
alter table public.produccion_planes add constraint produccion_planes_check1 CHECK (((estado = 'cancelado'::text) = (cancelado_en IS NOT NULL)));
alter table public.produccion_planes add constraint produccion_planes_costo_estimado_check CHECK ((costo_estimado >= (0)::numeric));
alter table public.produccion_planes add constraint produccion_planes_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 400)));
alter table public.produccion_planes add constraint produccion_planes_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_planes add constraint produccion_planes_estado_check CHECK ((estado = ANY (ARRAY['planificado'::text, 'terminado'::text, 'cancelado'::text])));
alter table public.produccion_planes add constraint produccion_planes_pkey PRIMARY KEY (id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_fabricacion_id_key UNIQUE (empresa_id, fabricacion_id);
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_check CHECK (((lote_id IS NULL) = (lote_codigo IS NULL)));
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_pkey PRIMARY KEY (id);
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_pkey PRIMARY KEY (empresa_id, fabricacion_id, componente_id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_pkey PRIMARY KEY (id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.ajustes_perfiles add constraint ajustes_perfiles_pkey PRIMARY KEY (id);
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_check CHECK (((cantidad_recibida >= (0)::numeric) AND (cantidad_recibida <= cantidad)));
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_linea_check CHECK (((linea >= 1) AND (linea <= 40)));
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric));
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_pkey PRIMARY KEY (empresa_id, orden_compra_id, linea);
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_purchase_lines_item_unique UNIQUE (empresa_id, orden_compra_id, item_id);
alter table public.compras_ordenes_antiduplicado add constraint compras_ordenes_antiduplicado_pkey PRIMARY KEY (empresa_id, solicitud_id);
alter table public.compras_ordenes_antiduplicado add constraint compras_ordenes_antiduplicado_empresa_id_orden_compra_id_key UNIQUE (empresa_id, orden_compra_id);
alter table public.compras_ordenes add constraint compras_ordenes_nota_check CHECK ((length(nota) <= 500));
alter table public.compras_ordenes add constraint compras_ordenes_numero_check CHECK ((numero > 0));
alter table public.compras_ordenes add constraint compras_ordenes_estado_check CHECK ((estado = ANY (ARRAY['abierta'::text, 'parcial'::text, 'recibida'::text, 'cancelada'::text])));
alter table public.compras_ordenes add constraint compras_ordenes_pkey PRIMARY KEY (id);
alter table public.compras_ordenes add constraint compras_ordenes_empresa_id_unique UNIQUE (empresa_id, id);
alter table public.compras_ordenes add constraint compras_ordenes_company_numero_unique UNIQUE (empresa_id, numero);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric));
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_pkey PRIMARY KEY (empresa_id, recepcion_id, linea);
alter table public.compras_recepciones add constraint compras_recepciones_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 430)));
alter table public.compras_recepciones add constraint compras_recepciones_pkey PRIMARY KEY (id);
alter table public.compras_recepciones add constraint compras_recepciones_empresa_id_unique UNIQUE (empresa_id, id);
alter table public.compras_recepciones add constraint compras_recepciones_request_unique UNIQUE (empresa_id, solicitud_id);
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_check CHECK (((item_id IS NOT NULL) OR (item_codigo IS NULL)));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_item_nombre_check CHECK (((length(btrim(item_nombre)) >= 2) AND (length(btrim(item_nombre)) <= 160)));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_linea_check CHECK (((linea >= 1) AND (linea <= 200)));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_nota_check CHECK ((length(nota) <= 200));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_cantidad_check CHECK (((cantidad > (0)::numeric) AND (cantidad < ('1000000000000'::bigint)::numeric)));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_unidad_simbolo_check CHECK ((length(unidad_simbolo) <= 20));
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_pkey PRIMARY KEY (pedido_id, linea);
alter table public.compras_pedidos_antiduplicado add constraint compras_pedidos_antiduplicado_pkey PRIMARY KEY (empresa_id, solicitud_id);
alter table public.compras_pedidos add constraint compras_pedidos_check CHECK (((estado = 'pendiente'::text) = (resuelto_en IS NULL)));
alter table public.compras_pedidos add constraint compras_pedidos_check1 CHECK (((estado <> 'ordenado'::text) OR (orden_compra_id IS NOT NULL)));
alter table public.compras_pedidos add constraint compras_pedidos_nota_check CHECK ((length(nota) <= 500));
alter table public.compras_pedidos add constraint compras_pedidos_prioridad_check CHECK ((prioridad = ANY (ARRAY['normal'::text, 'urgente'::text])));
alter table public.compras_pedidos add constraint compras_pedidos_solicitante_nombre_check CHECK (((length(solicitante_nombre) >= 1) AND (length(solicitante_nombre) <= 200)));
alter table public.compras_pedidos add constraint compras_pedidos_nota_resolucion_check CHECK ((length(nota_resolucion) <= 500));
alter table public.compras_pedidos add constraint compras_pedidos_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'ordenado'::text, 'rechazado'::text, 'cancelado'::text])));
alter table public.compras_pedidos add constraint compras_pedidos_pkey PRIMARY KEY (id);
alter table public.compras_pedidos add constraint compras_pedidos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.compras_pedidos add constraint compras_pedidos_empresa_id_numero_key UNIQUE (empresa_id, numero);
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_descuento_porcentaje_check CHECK (((descuento_porcentaje >= (0)::numeric) AND (descuento_porcentaje < (100)::numeric)));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_descuento_motivo_check CHECK (((descuento_motivo IS NULL) OR (length(descuento_motivo) <= 200)));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_linea_check CHECK (((linea >= 1) AND (linea <= 200)));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_total_linea_check CHECK ((total_linea >= (0)::numeric));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_precio_unitario_lista_check CHECK ((precio_unitario_lista >= (0)::numeric));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_impuesto_porcentaje_check CHECK (((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric)));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric));
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_pkey PRIMARY KEY (empresa_id, presupuesto_id, linea);
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_empresa_id_presupuesto_id_i_5d0cc6a8 UNIQUE (empresa_id, presupuesto_id, item_id);
alter table public.ventas_presupuestos_estados add constraint ventas_presupuestos_estados_pkey PRIMARY KEY (id);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_check CHECK ((total_bruto = (total_neto + total_impuesto)));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_cliente_direccion_check CHECK ((length(cliente_direccion) <= 240));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_cliente_email_check CHECK ((length(cliente_email) <= 160));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_cliente_nombre_check CHECK (((length(btrim(cliente_nombre)) >= 1) AND (length(btrim(cliente_nombre)) <= 160)));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_cliente_telefono_check CHECK ((length(cliente_telefono) <= 40));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_cliente_identificacion_fiscal_check CHECK ((length(cliente_identificacion_fiscal) <= 30));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_total_bruto_check CHECK ((total_bruto >= (0)::numeric));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_total_neto_check CHECK (((total_neto >= (0)::numeric) AND (total_neto < ('10000000000000000'::bigint)::numeric)));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_nota_check CHECK ((length(nota) <= 1000));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_estado_check CHECK ((estado = ANY (ARRAY['abierto'::text, 'aceptado'::text, 'rechazado'::text, 'cancelado'::text])));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_tax_mode_check CHECK ((NOT (mostrar_impuesto AND impuesto_incluido)));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_total_impuesto_check CHECK ((total_impuesto >= (0)::numeric));
alter table public.ventas_presupuestos add constraint ventas_presupuestos_pkey PRIMARY KEY (id);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_empresa_id_numero_key UNIQUE (empresa_id, numero);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.ajustes_roles_permisos add constraint ajustes_roles_permisos_accion_check CHECK ((accion = ANY (ARRAY['ver'::text, 'crear'::text, 'editar'::text, 'eliminar'::text, 'gestionar'::text])));
alter table public.ajustes_roles_permisos add constraint ajustes_roles_permisos_recurso_check CHECK ((recurso ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.ajustes_roles_permisos add constraint ajustes_roles_permisos_pkey PRIMARY KEY (rol_id, recurso, accion);
alter table public.ajustes_roles add constraint ajustes_roles_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]*$'::text));
alter table public.ajustes_roles add constraint ajustes_roles_pkey PRIMARY KEY (id);
alter table public.ajustes_roles add constraint ajustes_roles_empresa_id_codigo_key UNIQUE (empresa_id, codigo);
alter table public.ajustes_roles add constraint ajustes_roles_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_check CHECK ((reingresado = (operacion_stock_id IS NOT NULL)));
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_credito_importe_check CHECK ((credito_importe >= (0)::numeric));
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_pkey PRIMARY KEY (empresa_id, ajuste_id, venta_linea);
alter table public.ventas_ajustes add constraint ventas_ajustes_credito_total_check CHECK ((credito_total >= (0)::numeric));
alter table public.ventas_ajustes add constraint ventas_ajustes_tipo_check CHECK ((tipo = ANY (ARRAY['anulacion'::text, 'devolucion'::text])));
alter table public.ventas_ajustes add constraint ventas_ajustes_motivo_check CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 300)));
alter table public.ventas_ajustes add constraint ventas_ajustes_pkey PRIMARY KEY (id);
alter table public.ventas_ajustes add constraint ventas_ajustes_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_ajustes add constraint ventas_ajustes_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_modo_pago_check CHECK ((modo_pago = ANY (ARRAY['pendiente'::text, 'parcial'::text, 'pagado'::text])));
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_pkey PRIMARY KEY (empresa_id, solicitud_id);
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_empresa_id_venta_id_key UNIQUE (empresa_id, venta_id);
alter table public.ventas_lineas add constraint ventas_lineas_descuento_porcentaje_check CHECK (((descuento_porcentaje >= (0)::numeric) AND (descuento_porcentaje < (100)::numeric)));
alter table public.ventas_lineas add constraint ventas_lineas_descuento_motivo_check CHECK (((descuento_motivo IS NULL) OR (length(descuento_motivo) <= 200)));
alter table public.ventas_lineas add constraint ventas_lineas_linea_check CHECK (((linea >= 1) AND (linea <= 40)));
alter table public.ventas_lineas add constraint ventas_lineas_total_linea_check CHECK ((total_linea >= (0)::numeric));
alter table public.ventas_lineas add constraint ventas_lineas_precio_unitario_lista_check CHECK (((precio_unitario_lista IS NULL) OR (precio_unitario_lista >= (0)::numeric)));
alter table public.ventas_lineas add constraint ventas_lineas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.ventas_lineas add constraint ventas_lineas_impuesto_porcentaje_check CHECK (((impuesto_porcentaje IS NULL) OR ((impuesto_porcentaje >= (0)::numeric) AND (impuesto_porcentaje <= (100)::numeric))));
alter table public.ventas_lineas add constraint ventas_lineas_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric));
alter table public.ventas_lineas add constraint ventas_lineas_pkey PRIMARY KEY (empresa_id, venta_id, linea);
alter table public.ventas_lineas add constraint ventas_lineas_empresa_id_venta_id_item_id_key UNIQUE (empresa_id, venta_id, item_id);
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_motivo_check CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 300)));
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_pkey PRIMARY KEY (id);
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_empresa_id_cobro_id_key UNIQUE (empresa_id, cobro_id);
alter table public.ventas_cobros add constraint ventas_cobros_importe_check CHECK ((importe > (0)::numeric));
alter table public.ventas_cobros add constraint ventas_cobros_medio_pago_check CHECK ((medio_pago = ANY (ARRAY['efectivo'::text, 'transferencia'::text, 'tarjeta'::text, 'cheque'::text, 'otro'::text])));
alter table public.ventas_cobros add constraint ventas_cobros_nota_check CHECK ((length(nota) <= 500));
alter table public.ventas_cobros add constraint ventas_cobros_referencia_check CHECK ((length(referencia) <= 100));
alter table public.ventas_cobros add constraint ventas_cobros_pkey PRIMARY KEY (id);
alter table public.ventas_cobros add constraint ventas_cobros_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas_cobros add constraint ventas_cobros_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.ventas_reintegros add constraint ventas_reintegros_importe_check CHECK ((importe > (0)::numeric));
alter table public.ventas_reintegros add constraint ventas_reintegros_motivo_check CHECK (((length(btrim(motivo)) >= 5) AND (length(btrim(motivo)) <= 240)));
alter table public.ventas_reintegros add constraint ventas_reintegros_pkey PRIMARY KEY (id);
alter table public.ventas_reintegros add constraint ventas_reintegros_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.ventas_reintegros add constraint ventas_reintegros_empresa_id_movimiento_finanzas_id_key UNIQUE (empresa_id, movimiento_finanzas_id);
alter table public.ventas add constraint ventas_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 500)));
alter table public.ventas add constraint ventas_numero_check CHECK ((numero > 0));
alter table public.ventas add constraint ventas_total_check CHECK ((total >= (0)::numeric));
alter table public.ventas add constraint ventas_pkey PRIMARY KEY (id);
alter table public.ventas add constraint ventas_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.ventas add constraint ventas_empresa_id_numero_key UNIQUE (empresa_id, numero);
alter table public.ventas add constraint ventas_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.stock_saldos add constraint stock_saldos_cantidad_check CHECK ((cantidad >= (0)::numeric));
alter table public.stock_saldos add constraint stock_saldos_version_check CHECK ((version >= 0));
alter table public.stock_saldos add constraint stock_saldos_pkey PRIMARY KEY (empresa_id, item_id, deposito_id);
alter table public.stock_lotes_saldos add constraint stock_lotes_saldos_cantidad_check CHECK ((cantidad >= (0)::numeric));
alter table public.stock_lotes_saldos add constraint stock_lotes_saldos_pkey PRIMARY KEY (empresa_id, item_id, deposito_id, lote_id);
alter table public.stock_lotes_aperturas add constraint stock_lotes_aperturas_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.stock_lotes_aperturas add constraint stock_lotes_aperturas_pkey PRIMARY KEY (empresa_id, item_id, deposito_id);
alter table public.stock_lotes add constraint stock_lotes_codigo_check CHECK ((((length(btrim(codigo)) >= 1) AND (length(btrim(codigo)) <= 80)) AND (codigo = btrim(codigo))));
alter table public.stock_lotes add constraint stock_lotes_pkey PRIMARY KEY (id);
alter table public.stock_lotes add constraint stock_lotes_company_item_id_unique UNIQUE (empresa_id, item_id, id);
alter table public.stock_movimientos add constraint stock_movimientos_saldo_posterior_check CHECK ((saldo_posterior >= (0)::numeric));
alter table public.stock_movimientos add constraint stock_movimientos_saldo_version_check CHECK ((saldo_version > 0));
alter table public.stock_movimientos add constraint stock_movimientos_variacion_check CHECK ((variacion <> (0)::numeric));
alter table public.stock_movimientos add constraint stock_movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'transferencia_salida'::text, 'transferencia_entrada'::text])));
alter table public.stock_movimientos add constraint stock_movimientos_linea_check CHECK ((linea = ANY (ARRAY[1, 2])));
alter table public.stock_movimientos add constraint stock_movimientos_sign_check CHECK ((((tipo = ANY (ARRAY['ingreso'::text, 'transferencia_entrada'::text])) AND (variacion > (0)::numeric)) OR ((tipo = ANY (ARRAY['egreso'::text, 'transferencia_salida'::text])) AND (variacion < (0)::numeric))));
alter table public.stock_movimientos add constraint stock_movimientos_pkey PRIMARY KEY (id);
alter table public.stock_movimientos add constraint stock_movimientos_operacion_id_linea_key UNIQUE (operacion_id, linea);
alter table public.stock_operaciones add constraint stock_operaciones_destination_check CHECK ((((tipo = 'transferencia'::text) AND (deposito_destino_id IS NOT NULL) AND (deposito_destino_id <> deposito_id)) OR ((tipo <> 'transferencia'::text) AND (deposito_destino_id IS NULL))));
alter table public.stock_operaciones add constraint stock_operaciones_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'transferencia'::text])));
alter table public.stock_operaciones add constraint stock_operaciones_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 500)));
alter table public.stock_operaciones add constraint stock_operaciones_cantidad_check CHECK ((cantidad > (0)::numeric));
alter table public.stock_operaciones add constraint stock_operaciones_pkey PRIMARY KEY (id);
alter table public.stock_operaciones add constraint stock_operaciones_empresa_id_unique UNIQUE (empresa_id, id);
alter table public.stock_operaciones add constraint stock_operaciones_request_unique UNIQUE (empresa_id, solicitud_id);
alter table public.compras_proveedores_items add constraint compras_proveedores_items_ajuste_porcentaje_check CHECK (((ajuste_porcentaje >= '-99.99'::numeric) AND (ajuste_porcentaje <= (1000)::numeric)));
alter table public.compras_proveedores_items add constraint compras_proveedores_items_currency_check CHECK ((((moneda = 'ARS'::text) AND (tipo_cambio_id IS NULL)) OR ((moneda = 'USD'::text) AND (tipo_cambio_id IS NOT NULL))));
alter table public.compras_proveedores_items add constraint compras_proveedores_items_moneda_check CHECK ((moneda = ANY (ARRAY['ARS'::text, 'USD'::text])));
alter table public.compras_proveedores_items add constraint compras_proveedores_items_proveedor_codigo_check CHECK ((length(proveedor_codigo) <= 80));
alter table public.compras_proveedores_items add constraint compras_proveedores_items_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric));
alter table public.compras_proveedores_items add constraint compras_proveedores_items_pkey PRIMARY KEY (empresa_id, proveedor_id, item_id);
alter table public.compras_pagos_lineas add constraint compras_pagos_lineas_importe_check CHECK ((importe > (0)::numeric));
alter table public.compras_pagos_lineas add constraint compras_pagos_lineas_pkey PRIMARY KEY (empresa_id, pago_id, orden_compra_id);
alter table public.compras_pagos add constraint compras_pagos_importe_check CHECK ((importe > (0)::numeric));
alter table public.compras_pagos add constraint compras_pagos_check CHECK (((estado = 'pagado'::text) = (confirmado_en IS NOT NULL)));
alter table public.compras_pagos add constraint compras_pagos_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 240)));
alter table public.compras_pagos add constraint compras_pagos_numero_check CHECK ((numero > 0));
alter table public.compras_pagos add constraint compras_pagos_referencia_check CHECK ((length(referencia) <= 120));
alter table public.compras_pagos add constraint compras_pagos_estado_check CHECK ((estado = ANY (ARRAY['borrador'::text, 'pagado'::text, 'cancelado'::text])));
alter table public.compras_pagos add constraint compras_pagos_pkey PRIMARY KEY (id);
alter table public.compras_pagos add constraint compras_pagos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.compras_pagos add constraint compras_pagos_empresa_id_numero_key UNIQUE (empresa_id, numero);
alter table public.compras_pagos add constraint compras_pagos_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.compras_proveedores_ajustes_precio add constraint compras_proveedores_ajustes_precio_porcentaje_check CHECK (((porcentaje >= '-99.99'::numeric) AND (porcentaje <= (1000)::numeric)));
alter table public.compras_proveedores_ajustes_precio add constraint compras_proveedores_ajustes_precio_pkey PRIMARY KEY (id);
alter table public.compras_proveedores_ajustes_precio add constraint compras_proveedores_ajustes_precio_empresa_id_solicitud_id_key UNIQUE (empresa_id, solicitud_id);
alter table public.compras_proveedores add constraint compras_proveedores_email_check CHECK ((length(email) <= 160));
alter table public.compras_proveedores add constraint compras_proveedores_demora_dias_check CHECK (((demora_dias >= 0) AND (demora_dias <= 365)));
alter table public.compras_proveedores add constraint compras_proveedores_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 160)));
alter table public.compras_proveedores add constraint compras_proveedores_nota_check CHECK ((length(nota) <= 500));
alter table public.compras_proveedores add constraint compras_proveedores_telefono_check CHECK ((length(telefono) <= 40));
alter table public.compras_proveedores add constraint compras_proveedores_provee_descripcion_check CHECK ((length(provee_descripcion) <= 200));
alter table public.compras_proveedores add constraint compras_proveedores_identificacion_fiscal_check CHECK ((length(identificacion_fiscal) <= 30));
alter table public.compras_proveedores add constraint compras_proveedores_pkey PRIMARY KEY (id);
alter table public.compras_proveedores add constraint compras_proveedores_empresa_id_unique UNIQUE (empresa_id, id);
alter table public.finanzas_cuentas add constraint finanzas_cuentas_tipo_check CHECK ((tipo = ANY (ARRAY['caja'::text, 'banco'::text, 'otra'::text])));
alter table public.finanzas_cuentas add constraint finanzas_cuentas_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)));
alter table public.finanzas_cuentas add constraint finanzas_cuentas_pkey PRIMARY KEY (id);
alter table public.finanzas_cuentas add constraint finanzas_cuentas_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.finanzas_movimientos add constraint finanzas_movimientos_importe_check CHECK ((importe > (0)::numeric));
alter table public.finanzas_movimientos add constraint finanzas_movimientos_check CHECK (((tipo = 'pago_proveedor'::text) = (orden_compra_id IS NOT NULL)));
alter table public.finanzas_movimientos add constraint finanzas_movimientos_tipo_check CHECK ((tipo = ANY (ARRAY['ingreso'::text, 'egreso'::text, 'pago_proveedor'::text, 'transferencia_entrada'::text, 'transferencia_salida'::text])));
alter table public.finanzas_movimientos add constraint finanzas_movimientos_nota_check CHECK (((length(btrim(nota)) >= 3) AND (length(btrim(nota)) <= 240)));
alter table public.finanzas_movimientos add constraint finanzas_movimientos_pkey PRIMARY KEY (id);
alter table public.finanzas_movimientos add constraint finanzas_movimientos_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.finanzas_movimientos add constraint finanzas_movimientos_empresa_id_solicitud_id_tipo_key UNIQUE (empresa_id, solicitud_id, tipo);
alter table public.finanzas_cobros_cuentas add constraint finanzas_cobros_cuentas_pkey PRIMARY KEY (empresa_id, cobro_id);
alter table public.stock_unidades add constraint stock_unidades_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,19}$'::text));
alter table public.stock_unidades add constraint stock_unidades_magnitud_check CHECK ((magnitud = ANY (ARRAY['cantidad'::text, 'masa'::text, 'volumen'::text, 'longitud'::text, 'superficie'::text, 'tiempo'::text])));
alter table public.stock_unidades add constraint stock_unidades_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 80)));
alter table public.stock_unidades add constraint stock_unidades_simbolo_check CHECK (((length(btrim(simbolo)) >= 1) AND (length(btrim(simbolo)) <= 12)));
alter table public.stock_unidades add constraint stock_unidades_pkey PRIMARY KEY (id);
alter table public.stock_unidades add constraint stock_unidades_empresa_id_codigo_key UNIQUE (empresa_id, codigo);
alter table public.stock_unidades add constraint stock_unidades_empresa_id_id_key UNIQUE (empresa_id, id);
alter table public.stock_depositos add constraint stock_depositos_codigo_check CHECK ((codigo ~ '^[a-z][a-z0-9_]{0,39}$'::text));
alter table public.stock_depositos add constraint stock_depositos_ubicacion_check CHECK ((length(ubicacion) <= 250));
alter table public.stock_depositos add constraint stock_depositos_nombre_check CHECK (((length(btrim(nombre)) >= 2) AND (length(btrim(nombre)) <= 100)));
alter table public.stock_depositos add constraint stock_depositos_pkey PRIMARY KEY (id);
alter table public.stock_depositos add constraint stock_depositos_empresa_id_codigo_key UNIQUE (empresa_id, codigo);
alter table public.stock_depositos add constraint stock_depositos_empresa_id_id_key UNIQUE (empresa_id, id);


CREATE INDEX soporte_accesos_company_time ON private.soporte_accesos USING btree (empresa_id, iniciado_en DESC);
CREATE INDEX ajustes_auditoria_accesos_company_idx ON public.ajustes_auditoria_accesos USING btree (empresa_id, creado_en DESC, id);
CREATE INDEX empresas_activo_idx ON public.empresas USING btree (id) WHERE activo;
CREATE INDEX empresas_usuarios_user_idx ON public.empresas_usuarios USING btree (usuario_id, empresa_id) WHERE activo;
CREATE INDEX ventas_clientes_listing ON public.ventas_clientes USING btree (empresa_id, activo, nombre);
CREATE UNIQUE INDEX ventas_clientes_tax_unique ON public.ventas_clientes USING btree (empresa_id, lower(identificacion_fiscal)) WHERE (btrim(identificacion_fiscal) <> ''::text);
CREATE INDEX stock_remitos_job ON public.stock_remitos USING btree (empresa_id, orden_id, creado_en) WHERE (orden_id IS NOT NULL);
CREATE INDEX stock_remitos_recent ON public.stock_remitos USING btree (empresa_id, creado_en DESC);
CREATE UNIQUE INDEX finanzas_tipos_cambio_unique_nombre ON public.finanzas_tipos_cambio USING btree (empresa_id, lower(nombre));
CREATE INDEX finanzas_cotizaciones_current ON public.finanzas_cotizaciones USING btree (empresa_id, tipo_cambio_id, vigente_desde DESC, creado_en DESC);
CREATE INDEX stock_categorias_categories_listing_idx ON public.stock_categorias USING btree (empresa_id, activo, nombre);
CREATE INDEX stock_items_category_idx ON public.stock_items USING btree (empresa_id, categoria_id);
CREATE UNIQUE INDEX stock_items_company_codigo_barras_unique ON public.stock_items USING btree (empresa_id, codigo_barras) WHERE (codigo_barras IS NOT NULL);
CREATE UNIQUE INDEX stock_items_company_codigo_casefold_unique ON public.stock_items USING btree (empresa_id, lower(codigo));
CREATE INDEX stock_items_company_nombre_idx ON public.stock_items USING btree (empresa_id, nombre, id);
CREATE INDEX stock_items_company_type_nombre_idx ON public.stock_items USING btree (empresa_id, tipo_item, activo, nombre, id);
CREATE INDEX ajustes_permisos_catalogo_padre_idx ON public.ajustes_permisos_catalogo USING btree (padre);
CREATE INDEX ventas_listas_items_historial_idx ON public.ventas_listas_items_historial USING btree (empresa_id, lista_precio_id, item_id, cambiado_en DESC);
CREATE INDEX ventas_listas_items_historial_list_idx ON public.ventas_listas_items_historial USING btree (empresa_id, lista_precio_id, cambiado_en DESC);
CREATE INDEX ventas_listas_items_item_idx ON public.ventas_listas_items USING btree (empresa_id, item_id);
CREATE UNIQUE INDEX ventas_listas_precios_nombre_unique ON public.ventas_listas_precios USING btree (empresa_id, lower(btrim(nombre))) WHERE (NOT archivado);
CREATE UNIQUE INDEX ventas_listas_precios_one_default ON public.ventas_listas_precios USING btree (empresa_id) WHERE (es_predeterminada AND (NOT archivado));
CREATE INDEX produccion_formulas_lineas_component_idx ON public.produccion_formulas_lineas USING btree (empresa_id, componente_id);
CREATE INDEX produccion_ordenes_eventos_component_idx ON public.produccion_ordenes_eventos USING btree (empresa_id, componente_id, creado_en DESC);
CREATE INDEX produccion_ordenes_eventos_issue_idx ON public.produccion_ordenes_eventos USING btree (empresa_id, entrega_id) WHERE (entrega_id IS NOT NULL);
CREATE INDEX produccion_ordenes_eventos_list ON public.produccion_ordenes_eventos USING btree (empresa_id, orden_id, creado_en, id);
CREATE INDEX produccion_ordenes_reservas_production_reservation_component ON public.produccion_ordenes_reservas USING btree (empresa_id, componente_id);
CREATE INDEX produccion_ordenes_done_idx ON public.produccion_ordenes USING btree (empresa_id, terminado_en DESC) WHERE (estado = 'terminada'::text);
CREATE INDEX produccion_ordenes_product_idx ON public.produccion_ordenes USING btree (empresa_id, producto_id, estado);
CREATE INDEX produccion_ordenes_queue ON public.produccion_ordenes USING btree (empresa_id, estado, fecha_limite, creado_en);
CREATE UNIQUE INDEX produccion_tipos_envase_packaging_names ON public.produccion_tipos_envase USING btree (empresa_id, lower(nombre));
CREATE INDEX produccion_planes_queue ON public.produccion_planes USING btree (empresa_id, estado, fecha_limite, creado_en);
CREATE INDEX produccion_reservas_ubicaciones_production_reservation_a23ed7e4 ON public.produccion_reservas_ubicaciones USING btree (empresa_id, orden_id);
CREATE INDEX produccion_reservas_ubicaciones_production_reservation_d9afa509 ON public.produccion_reservas_ubicaciones USING btree (empresa_id, componente_id, deposito_id, lote_id);
CREATE INDEX produccion_fabricaciones_lineas_component_idx ON public.produccion_fabricaciones_lineas USING btree (empresa_id, componente_id);
CREATE INDEX produccion_fabricaciones_product_idx ON public.produccion_fabricaciones USING btree (empresa_id, producto_id, creado_en DESC);
CREATE INDEX produccion_fabricaciones_recent ON public.produccion_fabricaciones USING btree (empresa_id, creado_en DESC);
CREATE INDEX compras_ordenes_company_date_idx ON public.compras_ordenes USING btree (empresa_id, creado_en DESC);
CREATE INDEX compras_recepciones_order_date_idx ON public.compras_recepciones USING btree (empresa_id, orden_compra_id, creado_en DESC);
CREATE INDEX compras_recepciones_statistics ON public.compras_recepciones USING btree (empresa_id, creado_en);
CREATE INDEX compras_pedidos_company_estado_idx ON public.compras_pedidos USING btree (empresa_id, estado, creado_en DESC);
CREATE INDEX compras_pedidos_requester_idx ON public.compras_pedidos USING btree (empresa_id, solicitado_por, creado_en DESC);
CREATE INDEX ventas_presupuestos_estados_idx ON public.ventas_presupuestos_estados USING btree (empresa_id, presupuesto_id, cambiado_en);
CREATE INDEX ventas_presupuestos_company_created_idx ON public.ventas_presupuestos USING btree (empresa_id, creado_en DESC);
CREATE INDEX ventas_presupuestos_company_estado_idx ON public.ventas_presupuestos USING btree (empresa_id, estado, vigente_hasta);
CREATE INDEX ajustes_roles_permisos_company_idx ON public.ajustes_roles_permisos USING btree (empresa_id, rol_id);
CREATE INDEX ventas_ajustes_sale ON public.ventas_ajustes USING btree (empresa_id, venta_id);
CREATE UNIQUE INDEX ventas_ajustes_sale_one_cancellation ON public.ventas_ajustes USING btree (empresa_id, venta_id) WHERE (tipo = 'anulacion'::text);
CREATE INDEX ventas_cobros_sale_date ON public.ventas_cobros USING btree (empresa_id, venta_id, creado_en DESC);
CREATE INDEX ventas_recent ON public.ventas USING btree (empresa_id, creado_en DESC);
CREATE INDEX stock_saldos_warehouse_idx ON public.stock_saldos USING btree (empresa_id, deposito_id, item_id);
CREATE INDEX stock_lotes_saldos_available_idx ON public.stock_lotes_saldos USING btree (empresa_id, item_id, deposito_id) WHERE (cantidad > (0)::numeric);
CREATE UNIQUE INDEX stock_lotes_codigo_unique ON public.stock_lotes USING btree (empresa_id, item_id, lower(codigo));
CREATE INDEX stock_lotes_expiry_idx ON public.stock_lotes USING btree (empresa_id, vencimiento) WHERE (vencimiento IS NOT NULL);
CREATE UNIQUE INDEX stock_movimientos_saldo_version_unique ON public.stock_movimientos USING btree (empresa_id, item_id, deposito_id, saldo_version);
CREATE INDEX stock_movimientos_company_date_idx ON public.stock_movimientos USING btree (empresa_id, creado_en DESC, id DESC);
CREATE INDEX stock_movimientos_item_date_idx ON public.stock_movimientos USING btree (empresa_id, item_id, creado_en DESC);
CREATE INDEX stock_movimientos_warehouse_date_idx ON public.stock_movimientos USING btree (empresa_id, deposito_id, creado_en DESC);
CREATE INDEX stock_operaciones_company_date_idx ON public.stock_operaciones USING btree (empresa_id, creado_en DESC);
CREATE INDEX compras_proveedores_items_item_price_idx ON public.compras_proveedores_items USING btree (empresa_id, item_id, precio_unitario, proveedor_id);
CREATE UNIQUE INDEX compras_proveedores_items_one_preferido ON public.compras_proveedores_items USING btree (empresa_id, item_id) WHERE preferido;
CREATE INDEX compras_pagos_recent ON public.compras_pagos USING btree (empresa_id, creado_en DESC, id);
CREATE INDEX compras_proveedores_company_activo_idx ON public.compras_proveedores USING btree (empresa_id, activo, nombre);
CREATE UNIQUE INDEX compras_proveedores_company_nombre_unique ON public.compras_proveedores USING btree (empresa_id, lower(nombre));
CREATE UNIQUE INDEX finanzas_cuentas_unique_nombre ON public.finanzas_cuentas USING btree (empresa_id, lower(nombre));
CREATE INDEX finanzas_movimientos_recent ON public.finanzas_movimientos USING btree (empresa_id, fecha DESC, creado_en DESC);
CREATE INDEX finanzas_movimientos_treasury_supplier_order ON public.finanzas_movimientos USING btree (empresa_id, orden_compra_id, fecha);
CREATE INDEX stock_unidades_listing_idx ON public.stock_unidades USING btree (empresa_id, activo, nombre);
CREATE INDEX stock_depositos_listing_idx ON public.stock_depositos USING btree (empresa_id, activo, nombre);

alter table private.produccion_solicitudes_eliminadas add constraint produccion_solicitudes_eliminadas_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table private.produccion_solicitudes_eliminadas add constraint produccion_solicitudes_eliminadas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table private.soporte_accesos add constraint soporte_accesos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table private.soporte_accesos add constraint soporte_accesos_usuario_id_fkey foreign key (usuario_id) references auth.users(id);
alter table private.soporte_operadores add constraint soporte_operadores_usuario_id_fkey foreign key (usuario_id) references auth.users(id) ON DELETE CASCADE;
alter table private.soporte_sesiones add constraint soporte_sesiones_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table private.soporte_sesiones add constraint soporte_sesiones_usuario_id_fkey foreign key (usuario_id) references auth.users(id) ON DELETE CASCADE;
alter table public.ajustes_auditoria_accesos add constraint ajustes_auditoria_accesos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.empresas_perfil add constraint empresas_perfil_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.empresas_usuarios add constraint empresas_usuarios_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.empresas_usuarios add constraint empresas_usuarios_empresa_id_rol_id_fkey foreign key (empresa_id, rol_id) references public.ajustes_roles(empresa_id, id);
alter table public.empresas_usuarios add constraint empresas_usuarios_usuario_id_fkey foreign key (usuario_id) references auth.users(id) ON DELETE CASCADE;
alter table public.ventas_clientes add constraint ventas_clientes_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_remito_id_fkey foreign key (empresa_id, remito_id) references public.stock_remitos(empresa_id, id);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_evento_produccion_id_fkey foreign key (empresa_id, evento_produccion_id) references public.produccion_ordenes_eventos(empresa_id, id);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_venta_id_venta_linea_fkey foreign key (empresa_id, venta_id, venta_linea) references public.ventas_lineas(empresa_id, venta_id, linea);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_operacion_stock_id_fkey foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.stock_remitos_lineas add constraint stock_remitos_lineas_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_empresa_id_remito_id_linea_fkey foreign key (empresa_id, remito_id, linea) references public.stock_remitos_lineas(empresa_id, remito_id, linea);
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_empresa_id_evento_produccion_id_fkey foreign key (empresa_id, evento_produccion_id) references public.produccion_ordenes_eventos(empresa_id, id);
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_empresa_id_venta_id_venta_linea_fkey foreign key (empresa_id, venta_id, venta_linea) references public.ventas_lineas(empresa_id, venta_id, linea);
alter table public.stock_remitos_reversiones add constraint stock_remitos_reversiones_empresa_id_operacion_stock_id_fkey foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.stock_remitos add constraint stock_remitos_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.stock_remitos add constraint stock_remitos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_remitos add constraint stock_remitos_empresa_id_orden_id_fkey foreign key (empresa_id, orden_id) references public.produccion_ordenes(empresa_id, id);
alter table public.stock_remitos add constraint stock_remitos_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.finanzas_tipos_cambio add constraint finanzas_tipos_cambio_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.finanzas_cotizaciones add constraint finanzas_cotizaciones_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.finanzas_cotizaciones add constraint finanzas_cotizaciones_empresa_id_tipo_cambio_id_fkey foreign key (empresa_id, tipo_cambio_id) references public.finanzas_tipos_cambio(empresa_id, id);
alter table public.stock_categorias add constraint stock_categorias_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.ventas_items_config add constraint ventas_items_config_empresa_id_contenido_unidad_id_fkey foreign key (empresa_id, contenido_unidad_id) references public.stock_unidades(empresa_id, id);
alter table public.ventas_items_config add constraint ventas_items_config_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_items add constraint stock_items_category_company_fk foreign key (empresa_id, categoria_id) references public.stock_categorias(empresa_id, id);
alter table public.stock_items add constraint stock_items_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_items add constraint stock_items_reference_fx_company_fk foreign key (empresa_id, tipo_cambio_referencia_id) references public.finanzas_tipos_cambio(empresa_id, id);
alter table public.stock_items add constraint stock_items_unit_company_fk foreign key (empresa_id, unidad_id) references public.stock_unidades(empresa_id, id);
alter table public.inicio_alertas_leidas add constraint inicio_alertas_leidas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.inicio_alertas_leidas add constraint inicio_alertas_leidas_usuario_id_fkey foreign key (usuario_id) references auth.users(id) ON DELETE CASCADE;
alter table public.ajustes_permisos_catalogo add constraint ajustes_permisos_catalogo_padre_fkey foreign key (padre) references public.ajustes_permisos_catalogo(recurso);
alter table public.ventas_precios_antiduplicado add constraint ventas_precios_antiduplicado_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.ventas_listas_items_historial add constraint ventas_listas_items_historial_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.ventas_listas_items_historial add constraint ventas_listas_items_historial_empresa_id_lista_precio_id_fkey foreign key (empresa_id, lista_precio_id) references public.ventas_listas_precios(empresa_id, id);
alter table public.ventas_listas_items_metodo add constraint ventas_listas_items_metodo_empresa_id_lista_precio_id__5e62a702 foreign key (empresa_id, lista_precio_id, item_id) references public.ventas_listas_items(empresa_id, lista_precio_id, item_id);
alter table public.ventas_listas_items add constraint ventas_listas_items_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.ventas_listas_items add constraint ventas_listas_items_empresa_id_lista_precio_id_fkey foreign key (empresa_id, lista_precio_id) references public.ventas_listas_precios(empresa_id, id);
alter table public.ventas_listas_precios add constraint ventas_listas_precios_empresa_id_lista_base_id_fkey foreign key (empresa_id, lista_base_id) references public.ventas_listas_precios(empresa_id, id);
alter table public.ventas_listas_precios add constraint ventas_listas_precios_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.ventas_precios_config add constraint ventas_precios_config_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.produccion_documentos_config add constraint produccion_documentos_config_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.produccion_formulas_lineas add constraint produccion_formulas_lineas_empresa_id_componente_id_fkey foreign key (empresa_id, componente_id) references public.stock_items(empresa_id, id);
alter table public.produccion_formulas_lineas add constraint produccion_formulas_lineas_empresa_id_producto_id_fkey foreign key (empresa_id, producto_id) references public.produccion_formulas(empresa_id, producto_id);
alter table public.produccion_formulas add constraint produccion_formulas_empresa_id_producto_id_fkey foreign key (empresa_id, producto_id) references public.stock_items(empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_componente_id_fkey foreign key (empresa_id, componente_id) references public.stock_items(empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_entrega_id_fkey foreign key (empresa_id, entrega_id) references public.produccion_ordenes_eventos(empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_orden_id_fkey foreign key (empresa_id, orden_id) references public.produccion_ordenes(empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_operacion_stock_id_fkey foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.produccion_ordenes_eventos add constraint produccion_ordenes_eventos_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.produccion_ordenes_reservas add constraint produccion_ordenes_reservas_empresa_id_componente_id_fkey foreign key (empresa_id, componente_id) references public.stock_items(empresa_id, id);
alter table public.produccion_ordenes_reservas add constraint produccion_ordenes_reservas_empresa_id_orden_id_fkey foreign key (empresa_id, orden_id) references public.produccion_ordenes(empresa_id, id);
alter table public.produccion_ordenes add constraint produccion_ordenes_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_plan_id_fkey foreign key (empresa_id, plan_id) references public.produccion_planes(empresa_id, id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_producto_id_fkey foreign key (empresa_id, producto_id) references public.stock_items(empresa_id, id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_fabricacion_id_fkey foreign key (empresa_id, fabricacion_id) references public.produccion_fabricaciones(empresa_id, id);
alter table public.produccion_ordenes add constraint produccion_ordenes_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.produccion_fabricaciones_antiduplicado add constraint produccion_fabricaciones_antiduplicado_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.produccion_fabricaciones_antiduplicado add constraint produccion_fabricaciones_antiduplicado_empresa_id_orden_id_fkey foreign key (empresa_id, orden_id) references public.produccion_ordenes(empresa_id, id);
alter table public.produccion_fabricaciones_antiduplicado add constraint produccion_fabricaciones_antiduplicado_empresa_id_fabr_5ee891ef foreign key (empresa_id, fabricacion_id) references public.produccion_fabricaciones(empresa_id, id);
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.produccion_tipos_envase add constraint produccion_tipos_envase_empresa_id_unidad_id_fkey foreign key (empresa_id, unidad_id) references public.stock_unidades(empresa_id, id);
alter table public.produccion_planes add constraint produccion_planes_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_producto_id_fkey foreign key (empresa_id, producto_id) references public.stock_items(empresa_id, id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_fabricacion_id_fkey foreign key (empresa_id, fabricacion_id) references public.produccion_fabricaciones(empresa_id, id);
alter table public.produccion_planes add constraint produccion_planes_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_production_reservation_0994351b foreign key (empresa_id, orden_id, componente_id) references public.produccion_ordenes_reservas(empresa_id, orden_id, componente_id);
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.produccion_reservas_ubicaciones add constraint produccion_reservas_ubicaciones_lote_id_fkey foreign key (lote_id) references public.stock_lotes(id);
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_empresa_id_componente_id_fkey foreign key (empresa_id, componente_id) references public.stock_items(empresa_id, id);
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_empresa_id_fabricacion_id_fkey foreign key (empresa_id, fabricacion_id) references public.produccion_fabricaciones(empresa_id, id);
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_empresa_id_operacion_s_01757d32 foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.produccion_fabricaciones_lineas add constraint produccion_fabricaciones_lineas_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_empresa_id_operacion_producto_id_fkey foreign key (empresa_id, operacion_producto_id) references public.stock_operaciones(empresa_id, id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_empresa_id_producto_id_fkey foreign key (empresa_id, producto_id) references public.stock_items(empresa_id, id);
alter table public.produccion_fabricaciones add constraint produccion_fabricaciones_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.ajustes_perfiles add constraint ajustes_perfiles_id_fkey foreign key (id) references auth.users(id) ON DELETE CASCADE;
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_purchase_lines_item_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.compras_ordenes_lineas add constraint compras_ordenes_lineas_purchase_lines_order_fk foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.compras_ordenes_antiduplicado add constraint compras_ordenes_antiduplicado_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.compras_ordenes_antiduplicado add constraint compras_ordenes_antiduplicado_empresa_id_orden_compra_id_fkey foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.compras_ordenes add constraint compras_ordenes_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.compras_ordenes add constraint compras_ordenes_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.compras_ordenes add constraint compras_ordenes_supplier_fk foreign key (empresa_id, proveedor_id) references public.compras_proveedores(empresa_id, id);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_receipt_lines_item_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_receipt_lines_order_fk foreign key (empresa_id, orden_compra_id, linea) references public.compras_ordenes_lineas(empresa_id, orden_compra_id, linea);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_receipt_lines_receipt_fk foreign key (empresa_id, recepcion_id) references public.compras_recepciones(empresa_id, id);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_receipt_lines_stock_fk foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.compras_recepciones_lineas add constraint compras_recepciones_lineas_receipt_lines_warehouse_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.compras_recepciones add constraint compras_recepciones_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.compras_recepciones add constraint compras_recepciones_order_fk foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.compras_pedidos_lineas add constraint compras_pedidos_lineas_empresa_id_pedido_id_fkey foreign key (empresa_id, pedido_id) references public.compras_pedidos(empresa_id, id);
alter table public.compras_pedidos_antiduplicado add constraint compras_pedidos_antiduplicado_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.compras_pedidos_antiduplicado add constraint compras_pedidos_antiduplicado_pedido_id_fkey foreign key (pedido_id) references public.compras_pedidos(id);
alter table public.compras_pedidos add constraint compras_pedidos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.compras_pedidos add constraint compras_pedidos_empresa_id_orden_compra_id_fkey foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_empresa_id_lista_precio_id_fkey foreign key (empresa_id, lista_precio_id) references public.ventas_listas_precios(empresa_id, id);
alter table public.ventas_presupuestos_lineas add constraint ventas_presupuestos_lineas_empresa_id_presupuesto_id_fkey foreign key (empresa_id, presupuesto_id) references public.ventas_presupuestos(empresa_id, id);
alter table public.ventas_presupuestos_estados add constraint ventas_presupuestos_estados_empresa_id_presupuesto_id_fkey foreign key (empresa_id, presupuesto_id) references public.ventas_presupuestos(empresa_id, id);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_empresa_id_cliente_id_fkey foreign key (empresa_id, cliente_id) references public.ventas_clientes(empresa_id, id);
alter table public.ventas_presupuestos add constraint ventas_presupuestos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.ajustes_roles_permisos add constraint ajustes_roles_permisos_empresa_id_rol_id_fkey foreign key (empresa_id, rol_id) references public.ajustes_roles(empresa_id, id) ON DELETE CASCADE;
alter table public.ajustes_roles add constraint ajustes_roles_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_empresa_id_ajuste_id_fkey foreign key (empresa_id, ajuste_id) references public.ventas_ajustes(empresa_id, id);
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_empresa_id_venta_id_venta_linea_fkey foreign key (empresa_id, venta_id, venta_linea) references public.ventas_lineas(empresa_id, venta_id, linea);
alter table public.ventas_ajustes_lineas add constraint ventas_ajustes_lineas_empresa_id_operacion_stock_id_fkey foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.ventas_ajustes add constraint ventas_ajustes_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas_ajustes add constraint ventas_ajustes_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_empresa_id_cuenta_id_fkey foreign key (empresa_id, cuenta_id) references public.finanzas_cuentas(empresa_id, id);
alter table public.ventas_cobros_antiduplicado add constraint ventas_cobros_antiduplicado_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_lineas add constraint ventas_lineas_empresa_id_item_id_fkey foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.ventas_lineas add constraint ventas_lineas_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_lineas add constraint ventas_lineas_empresa_id_operacion_stock_id_fkey foreign key (empresa_id, operacion_stock_id) references public.stock_operaciones(empresa_id, id);
alter table public.ventas_lineas add constraint ventas_lineas_empresa_id_deposito_id_fkey foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.ventas_lineas add constraint ventas_lineas_price_list_fkey foreign key (empresa_id, lista_precio_id) references public.ventas_listas_precios(empresa_id, id);
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_empresa_id_cobro_id_fkey foreign key (empresa_id, cobro_id) references public.ventas_cobros(empresa_id, id);
alter table public.ventas_cobros_reversiones add constraint ventas_cobros_reversiones_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_cobros add constraint ventas_cobros_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas_cobros add constraint ventas_cobros_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_reintegros add constraint ventas_reintegros_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas_reintegros add constraint ventas_reintegros_empresa_id_cuenta_id_fkey foreign key (empresa_id, cuenta_id) references public.finanzas_cuentas(empresa_id, id);
alter table public.ventas_reintegros add constraint ventas_reintegros_empresa_id_venta_id_fkey foreign key (empresa_id, venta_id) references public.ventas(empresa_id, id);
alter table public.ventas_reintegros add constraint ventas_reintegros_empresa_id_movimiento_finanzas_id_fkey foreign key (empresa_id, movimiento_finanzas_id) references public.finanzas_movimientos(empresa_id, id);
alter table public.ventas add constraint ventas_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.ventas add constraint ventas_empresa_id_cliente_id_fkey foreign key (empresa_id, cliente_id) references public.ventas_clientes(empresa_id, id);
alter table public.stock_saldos add constraint stock_saldos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_saldos add constraint stock_saldos_item_company_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_saldos add constraint stock_saldos_warehouse_company_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_lotes_saldos add constraint stock_lotes_saldos_lot_fk foreign key (empresa_id, item_id, lote_id) references public.stock_lotes(empresa_id, item_id, id);
alter table public.stock_lotes_saldos add constraint stock_lotes_saldos_warehouse_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_lotes_aperturas add constraint stock_lotes_aperturas_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.stock_lotes_aperturas add constraint stock_lotes_aperturas_lot_fk foreign key (empresa_id, item_id, lote_id) references public.stock_lotes(empresa_id, item_id, id);
alter table public.stock_lotes_aperturas add constraint stock_lotes_aperturas_warehouse_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_lotes add constraint stock_lotes_item_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_movimientos add constraint stock_movimientos_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.stock_movimientos add constraint stock_movimientos_item_company_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_movimientos add constraint stock_movimientos_lot_fk foreign key (empresa_id, item_id, lote_id) references public.stock_lotes(empresa_id, item_id, id);
alter table public.stock_movimientos add constraint stock_movimientos_operation_company_fk foreign key (empresa_id, operacion_id) references public.stock_operaciones(empresa_id, id);
alter table public.stock_movimientos add constraint stock_movimientos_warehouse_company_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_operaciones add constraint stock_operaciones_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.stock_operaciones add constraint stock_operaciones_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_operaciones add constraint stock_operaciones_item_company_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.stock_operaciones add constraint stock_operaciones_lot_fk foreign key (empresa_id, item_id, lote_id) references public.stock_lotes(empresa_id, item_id, id);
alter table public.stock_operaciones add constraint stock_operaciones_target_company_fk foreign key (empresa_id, deposito_destino_id) references public.stock_depositos(empresa_id, id);
alter table public.stock_operaciones add constraint stock_operaciones_warehouse_company_fk foreign key (empresa_id, deposito_id) references public.stock_depositos(empresa_id, id);
alter table public.compras_proveedores_items add constraint compras_proveedores_items_fx_fk foreign key (empresa_id, tipo_cambio_id) references public.finanzas_tipos_cambio(empresa_id, id);
alter table public.compras_proveedores_items add constraint compras_proveedores_items_item_fk foreign key (empresa_id, item_id) references public.stock_items(empresa_id, id);
alter table public.compras_proveedores_items add constraint compras_proveedores_items_supplier_fk foreign key (empresa_id, proveedor_id) references public.compras_proveedores(empresa_id, id);
alter table public.compras_pagos_lineas add constraint compras_pagos_lineas_empresa_id_orden_compra_id_fkey foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.compras_pagos_lineas add constraint compras_pagos_lineas_empresa_id_pago_id_fkey foreign key (empresa_id, pago_id) references public.compras_pagos(empresa_id, id) ON DELETE CASCADE;
alter table public.compras_pagos_lineas add constraint compras_pagos_lineas_empresa_id_movimiento_finanzas_id_fkey foreign key (empresa_id, movimiento_finanzas_id) references public.finanzas_movimientos(empresa_id, id);
alter table public.compras_pagos add constraint compras_pagos_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.compras_pagos add constraint compras_pagos_empresa_id_cuenta_id_fkey foreign key (empresa_id, cuenta_id) references public.finanzas_cuentas(empresa_id, id);
alter table public.compras_pagos add constraint compras_pagos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.compras_pagos add constraint compras_pagos_empresa_id_proveedor_id_fkey foreign key (empresa_id, proveedor_id) references public.compras_proveedores(empresa_id, id);
alter table public.compras_proveedores_ajustes_precio add constraint compras_proveedores_ajustes_precio_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.compras_proveedores_ajustes_precio add constraint compras_proveedores_ajustes_precio_empresa_id_fkey foreign key (empresa_id) references public.empresas(id);
alter table public.compras_proveedores add constraint compras_proveedores_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.finanzas_cuentas add constraint finanzas_cuentas_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.finanzas_movimientos add constraint finanzas_movimientos_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.finanzas_movimientos add constraint finanzas_movimientos_empresa_id_cuenta_id_fkey foreign key (empresa_id, cuenta_id) references public.finanzas_cuentas(empresa_id, id);
alter table public.finanzas_movimientos add constraint finanzas_movimientos_empresa_id_orden_compra_id_fkey foreign key (empresa_id, orden_compra_id) references public.compras_ordenes(empresa_id, id);
alter table public.finanzas_cobros_cuentas add constraint finanzas_cobros_cuentas_autor_id_fkey foreign key (autor_id) references auth.users(id);
alter table public.finanzas_cobros_cuentas add constraint finanzas_cobros_cuentas_empresa_id_cuenta_id_fkey foreign key (empresa_id, cuenta_id) references public.finanzas_cuentas(empresa_id, id);
alter table public.finanzas_cobros_cuentas add constraint finanzas_cobros_cuentas_empresa_id_cobro_id_fkey foreign key (empresa_id, cobro_id) references public.ventas_cobros(empresa_id, id);
alter table public.stock_unidades add constraint stock_unidades_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.stock_depositos add constraint stock_depositos_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) ON DELETE CASCADE;
alter table public.empresas_numeradores add constraint empresas_numeradores_empresa_id_fkey foreign key (empresa_id) references public.empresas(id) on delete cascade;
alter table public.ventas_clientes add constraint ventas_clientes_lista_precio_fkey foreign key (empresa_id, lista_precio_id) references public.ventas_listas_precios(empresa_id, id);
commit;
