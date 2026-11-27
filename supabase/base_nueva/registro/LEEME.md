# Registro de la base de datos

_Generado por `documentar.mjs`; no editar a mano._

76 tablas, 202 funciones, 81 reglas de acceso por fila, 60 automatismos.

Detalle por módulo en cada archivo; funciones en [funciones.md](funciones.md); historial en [BITACORA.md](BITACORA.md).
Solo describe la estructura: los datos de las empresas no se guardan en el proyecto.

| Tabla | Para qué sirve |
|---|---|
| [empresas](empresas.md) | Cada empresa: nombre, si está activa y qué módulos tiene habilitados. |
| [empresas_numeradores](empresas.md) | Próximo número de cada tipo de documento por empresa. |
| [empresas_perfil](empresas.md) | Datos fiscales, contacto y logo de la empresa. |
| [empresas_usuarios](empresas.md) | Qué usuarios pertenecen a cada empresa y con qué rol. |
| [ajustes_auditoria_accesos](ajustes.md) | Historial de cambios de roles y usuarios. |
| [ajustes_perfiles](ajustes.md) | Nombre visible de cada usuario. |
| [ajustes_permisos_catalogo](ajustes.md) | Lista fija de permisos que existen en el sistema. |
| [ajustes_roles](ajustes.md) | Roles definidos por cada empresa. |
| [ajustes_roles_permisos](ajustes.md) | Qué puede ver o hacer cada rol. |
| [inicio_alertas_leidas](inicio.md) | Avisos que cada usuario ya marcó como leídos. |
| [stock_categorias](stock.md) | Categorías de ítems. |
| [stock_depositos](stock.md) | Depósitos. |
| [stock_items](stock.md) | Materias primas, insumos, semielaborados y productos. |
| [stock_lotes](stock.md) | Lotes y vencimientos de ítems que los usan. |
| [stock_lotes_aperturas](stock.md) | Registro de cuando un ítem con stock empezó a usar lotes. |
| [stock_lotes_saldos](stock.md) | Existencia actual por lote y depósito. |
| [stock_movimientos](stock.md) | Renglones de historial de stock con saldo resultante. |
| [stock_operaciones](stock.md) | Cada ingreso, egreso o transferencia registrada. |
| [stock_remitos](stock.md) | Remitos de entrega. |
| [stock_remitos_lineas](stock.md) | Ítems de cada remito. |
| [stock_remitos_reversiones](stock.md) | Movimientos que revierten un remito anulado. |
| [stock_saldos](stock.md) | Existencia actual por ítem y depósito. |
| [stock_unidades](stock.md) | Unidades de medida. |
| [produccion_documentos_config](produccion.md) | Logo y datos de los documentos de producción. |
| [produccion_fabricaciones](produccion.md) | Fabricaciones registradas. |
| [produccion_fabricaciones_antiduplicado](produccion.md) | Evita registrar dos veces una fabricación en un paso. |
| [produccion_fabricaciones_lineas](produccion.md) | Materiales consumidos en cada fabricación. |
| [produccion_formulas](produccion.md) | Fórmula o receta de cada producto. |
| [produccion_formulas_lineas](produccion.md) | Componentes y cantidades de cada fórmula. |
| [produccion_ordenes](produccion.md) | Órdenes de fabricación. |
| [produccion_ordenes_eventos](produccion.md) | Entregas y devoluciones de material de cada orden. |
| [produccion_ordenes_reservas](produccion.md) | Cantidad que cada orden tiene reservada por componente. |
| [produccion_planes](produccion.md) | Planificación de fabricación. |
| [produccion_reservas_ubicaciones](produccion.md) | De qué depósito y lote sale cada reserva. |
| [produccion_tipos_envase](produccion.md) | Envases y presentaciones. |
| [compras_ordenes](compras.md) | Órdenes de compra. |
| [compras_ordenes_antiduplicado](compras.md) | Evita crear dos veces una orden de compra. |
| [compras_ordenes_lineas](compras.md) | Ítems de cada orden de compra. |
| [compras_pagos](compras.md) | Órdenes de pago a proveedores. |
| [compras_pagos_lineas](compras.md) | Compras que cubre cada pago. |
| [compras_pedidos](compras.md) | Pedidos internos de compra. |
| [compras_pedidos_antiduplicado](compras.md) | Evita crear dos veces un pedido interno. |
| [compras_pedidos_lineas](compras.md) | Ítems de cada pedido interno. |
| [compras_proveedores](compras.md) | Proveedores. |
| [compras_proveedores_ajustes_precio](compras.md) | Historial de aumentos o rebajas de precios de proveedor. |
| [compras_proveedores_items](compras.md) | Precio de cada ítem según cada proveedor. |
| [compras_recepciones](compras.md) | Recepciones de mercadería. |
| [compras_recepciones_lineas](compras.md) | Ítems recibidos en cada recepción. |
| [ventas](ventas.md) | Ventas registradas. |
| [ventas_ajustes](ventas.md) | Anulaciones y devoluciones de ventas. |
| [ventas_ajustes_lineas](ventas.md) | Productos de cada anulación o devolución. |
| [ventas_clientes](ventas.md) | Clientes, con su lista de precios. |
| [ventas_cobros](ventas.md) | Cobros de ventas. |
| [ventas_cobros_antiduplicado](ventas.md) | Evita registrar dos veces una venta con cobro. |
| [ventas_cobros_reversiones](ventas.md) | Cobros anulados. |
| [ventas_items_config](ventas.md) | Impuesto y contenido de venta por producto. |
| [ventas_lineas](ventas.md) | Productos de cada venta. |
| [ventas_listas_items](ventas.md) | Precio de cada producto en cada lista. |
| [ventas_listas_items_historial](ventas.md) | Historial de cambios de precios. |
| [ventas_listas_items_metodo](ventas.md) | Cómo se calculó cada precio. |
| [ventas_listas_precios](ventas.md) | Listas de precios. |
| [ventas_precios_antiduplicado](ventas.md) | Evita aplicar dos veces un cambio masivo de precios. |
| [ventas_precios_config](ventas.md) | Impuesto, márgenes y descuentos por defecto. |
| [ventas_presupuestos](ventas.md) | Presupuestos. |
| [ventas_presupuestos_estados](ventas.md) | Historial de estados de cada presupuesto. |
| [ventas_presupuestos_lineas](ventas.md) | Productos de cada presupuesto. |
| [ventas_reintegros](ventas.md) | Dinero devuelto a clientes. |
| [finanzas_cobros_cuentas](finanzas.md) | En qué cuenta entró cada cobro. |
| [finanzas_cotizaciones](finanzas.md) | Valor de cada tipo de dólar por fecha. |
| [finanzas_cuentas](finanzas.md) | Cajas y cuentas bancarias. |
| [finanzas_movimientos](finanzas.md) | Ingresos, egresos y transferencias de dinero. |
| [finanzas_tipos_cambio](finanzas.md) | Tipos de dólar definidos por la empresa. |
| [private.produccion_solicitudes_eliminadas](interno.md) | Evita que un reintento recree una orden o plan eliminado. |
| [private.soporte_accesos](interno.md) | Historial de accesos de soporte. |
| [private.soporte_operadores](interno.md) | Usuarios habilitados como soporte. |
| [private.soporte_sesiones](interno.md) | Sesiones de soporte abiertas. |
