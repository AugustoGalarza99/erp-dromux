# Producto y reglas de negocio — requisitos, no certificado de implementación

## Identidad y alcance
Dromux ERP industrial para pymes de Argentina/LATAM. Fuerte en fabricación, semielaborados, órdenes de trabajo, stock, reservas, lotes, remitos y alertas. Compras, proveedores, ventas básicas y tesorería integradas. Producto multirrubro (D-006): debe servir a cualquier pyme que fabrique (metalúrgica, jabones, alimentos, textil, pinturería…). Sin campos, textos ni ejemplos exclusivos de una industria; lo específico de cada empresa es configurable (unidades, categorías, envasados, campos opcionales).

## Catálogo y proveedores
- Materias primas, semielaborados, terminados e insumos con ID estable, código, nombre, unidad, mínimo decimal y stock infinito opcional.
- Mismo material con varios proveedores: catálogo por proveedor, nota descriptiva, costos por unidad, comparación y ajustes individuales/masivos.
- Costos ARS/USD, tipo de dólar existente, fecha de cotización y conversión reproducible; proveedor/dólar opcionales si no aplican.
- Importación Excel con vista previa, validación por fila y formatos argentinos ($16.500,50). Resolver separadores ambiguos según formato/columna; no adivinar silenciosamente.
- Duplicados: actualizar solo con confirmación y preservar IDs/vínculos. No renumerar materiales por tamaño ni reemplazar otro material por compartir código.

## Producción y stock
- Fórmulas/BOM con materias primas y semielaborados; unidades compatibles, costo teórico y versionado/snapshot de la orden.
- Planificar no fabrica. Orden en cola/en proceso/completada/cancelada; verificar disponibilidad y reservas por depósito/lote.
- Consumos parciales, adicionales, devoluciones y resultado real distinto del previsto. No consumir dos veces el mismo remito al finalizar.
- Costo real incluye consumo neto y criterio contable documentado; comparación teórico/real. Proteger trabajos simultáneos y reintentos.
- Lote de salida obligatorio cuando corresponda; entradas/devoluciones conservan trazabilidad.
- Densidad y rendimiento no son intercambiables: verificar dimensionalmente kg, litros y kg/L. Un factor de rendimiento multiplica una base; una densidad convierte volumen/masa. No cambiar cálculos históricos sin migración explícita y pruebas.
- Envasados configurables y observaciones por empresa. Revisar si envases consumen stock/costo según la configuración real.
- Remitos de materiales o productos, entregas parciales y reversión controlada. Archivar no devuelve stock. PDF operativo con logo, proceso, cantidades y observaciones, sin costos.
- Alertas por mínimos, disponibilidad para fabricar y pronóstico de agotamiento: explicar horizonte, demanda utilizada y limitaciones; no precisión ficticia.

## Compras, ventas y tesorería
- OC imprimible, filtro bidireccional proveedor/ítem y buscador junto a cada línea; recepción parcial/total sin doble ingreso.
- Cuenta corriente de proveedor, órdenes de pago y estadísticas por fecha/top proveedores/productos sin sumar unidades incompatibles.
- Venta con salida de stock, cobro total/parcial en efectivo o cuenta y registro único en tesorería. Anulación/devolución con reversión trazable.
- Lista de precios consultable por vendedor; admin define precio, ve costo real y margen. Distinguir margen sobre venta de recargo sobre costo.
- Ganancia consistente con método de valuación de inventario y costo real de fabricación; no recalcular ventas históricas con cotizaciones actuales.

## Multiempresa y experiencia
- Empresa suspendida no puede operar por API ni sesiones antiguas. Roles y permisos validados en servidor; perfil y contraseña acorde a política documentada.
- Soporte autorizado y auditado, sin backdoor. Ocultar un usuario en un listado no equivale a seguridad ni habilita acceso secreto.
- Español, etiquetas humanas y numeración de documentos; no UUIDs ni detalles de infraestructura en pantallas de cliente.
- Fondo blanco y paleta sobria con acentos existentes, textos legibles, Sonner, confirmaciones destructivas, acciones visibles en iPad/móvil y sidebar desplazable.
- Inicio con datos y accesos útiles. Ayuda contextual con pasos cortos; estados vacíos con siguiente acción y errores accionables.
- `meta.json` y novedades deben actualizarse de forma compatible con despliegue/cache; no forzar recarga durante una edición sin tratar cambios sin guardar.