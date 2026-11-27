/*
 * Valores que se guardan en la base y sus textos en pantalla.
 * Salen de las restricciones de supabase/base_nueva/sql/01_estructura.sql;
 * `npm run base:frontend` comprueba que sigan coincidiendo.
 */

export const ROL = {
  administrador: "administrador",
  soporte: "soporte",
};

/* ---------- Acceso y permisos ---------- */

export const ACCION_ETIQUETA = {
  ver: "Ver",
  crear: "Crear",
  editar: "Editar",
  eliminar: "Eliminar",
  gestionar: "Gestionar",
};

export const GRUPO_PERMISOS_ETIQUETA = {
  inicio: "Inicio",
  stock: "Stock",
  produccion: "Producción",
  ventas: "Ventas",
  compras: "Compras",
  finanzas: "Finanzas",
  reportes: "Reportes",
  ajustes: "Ajustes",
  sensible: "Datos sensibles",
};

/* Módulos que se contratan por empresa (empresas.modulos). */
export const MODULOS_DEL_PLAN = [
  "stock",
  "produccion",
  "compras",
  "ventas",
  "finanzas",
  "reportes",
];

/* Datos base: no dependen de ningún módulo. */
const RECURSOS_SIN_MODULO = ["items", "unidades", "categorias", "depositos"];

/* Espejo de private.module_enabled: qué módulo contratado necesita cada recurso. */
export function moduloDeRecurso(recurso) {
  if (RECURSOS_SIN_MODULO.includes(recurso)) return null;
  if (recurso === "inventario") return "stock";
  const [prefijo] = String(recurso).split("_");
  return MODULOS_DEL_PLAN.includes(prefijo) ? prefijo : null;
}

export function moduloHabilitado(recurso, modulos) {
  const modulo = moduloDeRecurso(recurso);
  return !modulo || modulos?.[modulo] === true;
}

export const AUDITORIA_ETIQUETA = {
  rol_creado: "Creó un rol",
  rol_editado: "Modificó un rol",
  miembro_editado: "Cambió un usuario",
};

/* ---------- Stock ---------- */

export const TIPOS_ITEM = [
  "materia_prima",
  "semielaborado",
  "producto_terminado",
  "insumo",
];

export const TIPO_ITEM_ETIQUETA = {
  materia_prima: "Materia prima",
  semielaborado: "Semielaborado",
  producto_terminado: "Producto terminado",
  insumo: "Insumo",
};

export const MAGNITUD_ETIQUETA = {
  cantidad: "Cantidad",
  masa: "Masa",
  volumen: "Volumen",
  longitud: "Longitud",
  superficie: "Superficie",
  tiempo: "Tiempo",
};

export const OPERACIONES_STOCK = ["ingreso", "egreso", "transferencia"];

export const MOVIMIENTOS_STOCK = [
  "ingreso",
  "egreso",
  "transferencia_salida",
  "transferencia_entrada",
];

export const TIPOS_REMITO = ["produccion", "materiales", "productos", "venta"];

export const ESTADOS_REMITO = ["emitido", "anulado"];

/* ---------- Producción ---------- */

export const ESTADOS_ORDEN = ["pendiente", "en_proceso", "terminada", "cancelada"];

export const ESTADOS_PLAN = ["planificado", "terminado", "cancelado"];

export const EVENTOS_ORDEN = ["entrega", "devolucion"];

/* ---------- Compras ---------- */

export const ESTADOS_ORDEN_COMPRA = ["abierta", "parcial", "recibida", "cancelada"];

export const ESTADOS_PEDIDO = ["pendiente", "ordenado", "rechazado", "cancelado"];

export const PRIORIDADES_PEDIDO = ["normal", "urgente"];

export const ESTADOS_PAGO_PROVEEDOR = ["borrador", "pagado", "cancelado"];

/* ---------- Ventas ---------- */

export const MEDIO_PAGO_ETIQUETA = {
  efectivo: "Efectivo",
  transferencia: "Transferencia",
  tarjeta: "Tarjeta",
  cheque: "Cheque",
  otro: "Otro",
};

export const MODOS_PAGO = ["pendiente", "parcial", "pagado"];

export const AJUSTES_VENTA = ["anulacion", "devolucion"];

export const METODOS_PRECIO = ["margen", "recargo", "fijo"];

/* "vencido" no se elige: lo calcula el servidor por la fecha. */
export const ESTADOS_PRESUPUESTO = [
  "abierto",
  "aceptado",
  "rechazado",
  "cancelado",
  "vencido",
];

/* ---------- Finanzas ---------- */

export const TIPOS_CUENTA = ["caja", "banco", "otra"];

export const TIPOS_MOVIMIENTO_FINANZAS = [
  "ingreso",
  "egreso",
  "pago_proveedor",
  "transferencia_entrada",
  "transferencia_salida",
];

/* Para el control automático: columna de la base -> valores que usa la aplicación. */
export const VALORES_GUARDADOS = {
  "stock_items.tipo_item": TIPOS_ITEM,
  "stock_unidades.magnitud": Object.keys(MAGNITUD_ETIQUETA),
  "stock_operaciones.tipo": OPERACIONES_STOCK,
  "stock_movimientos.tipo": MOVIMIENTOS_STOCK,
  "stock_remitos.tipo": TIPOS_REMITO,
  "stock_remitos.estado": ESTADOS_REMITO,
  "produccion_ordenes.estado": ESTADOS_ORDEN,
  "produccion_planes.estado": ESTADOS_PLAN,
  "produccion_ordenes_eventos.tipo": EVENTOS_ORDEN,
  "compras_ordenes.estado": ESTADOS_ORDEN_COMPRA,
  "compras_pedidos.estado": ESTADOS_PEDIDO,
  "compras_pedidos.prioridad": PRIORIDADES_PEDIDO,
  "compras_pagos.estado": ESTADOS_PAGO_PROVEEDOR,
  "ventas_cobros.medio_pago": Object.keys(MEDIO_PAGO_ETIQUETA),
  "ventas_cobros_antiduplicado.modo_pago": MODOS_PAGO,
  "ventas_ajustes.tipo": AJUSTES_VENTA,
  "ventas_listas_items_metodo.metodo": METODOS_PRECIO,
  "finanzas_cuentas.tipo": TIPOS_CUENTA,
  "finanzas_movimientos.tipo": TIPOS_MOVIMIENTO_FINANZAS,
};
