# Dromux ERP · pronóstico y reposición (versión 027)

## Instalación

1. Conservá una copia de tu proyecto y de la base de pruebas. Copiá el contenido de `erp-dromux/` del paquete sobre tu proyecto local, sin reemplazar `.env.local`.
2. En el SQL Editor de tu **base de pruebas**, ejecutá una vez `supabase/027_pronostico_reposicion.sql`. Deben estar aplicadas las versiones hasta la 026. La migración agrega `lead_time_days` a proveedores y una consulta de pronóstico; no cambia movimientos de stock ni compras históricas.
3. En la raíz local ejecutá `npm install`, `npm run build` y `npm run dev`. Entrá en Producción → Pronóstico y reposición. Para ver datos necesitás lectura de producción, stock y compras. Para preparar una orden necesitás además permiso de creación de compras.

## Qué calcula

- **Utilizable:** existencias de depósitos activos; para ítems con lote no incluye lotes vencidos.
- **Libre:** utilizable menos reservas activas de fabricación por ubicación.
- **Pedido pendiente:** cantidad aún no recibida en órdenes de compra abiertas o parciales. Se descuenta de la propuesta para evitar volver a pedirla.
- **Consumo diario:** salidas registradas en los últimos 60 días, divididas por días observados. Se muestra una estimación de cobertura cuando hay al menos 14 días entre la primera salida observada y hoy. Las devoluciones no se descuentan del consumo histórico: el pronóstico es conservador.
- **Compra sugerida:** cantidad necesaria para recuperar el mayor valor entre stock mínimo y consumo esperado durante el plazo habitual del proveedor más siete días, menos stock libre y pedidos pendientes. Se redondea hacia arriba a la unidad. El proveedor sugerido es el marcado como principal; si no hay principal se presenta otro proveedor activo asociado. Su plazo inicial es siete días y se puede editar en su ficha.

La pantalla no crea compras ni reserva entregas futuras automáticamente. El botón «Preparar orden» abre el formulario de compras con el material, proveedor y cantidad propuestos. Revisá cotización en pesos, fecha de llegada y cantidad antes de confirmar.

## Prueba guiada

1. En Proveedores, cargá el plazo habitual (por ejemplo, diez días) y confirmá que persiste al volver a abrir la ficha.
2. Configurá el stock mínimo de una materia prima y registrá consumos durante un período de al menos 14 días en la **base de pruebas**. La vista debe mostrar consumo por día y cobertura aproximada. Si no hay suficiente historial, debe indicarlo expresamente.
3. Creá una orden de fabricación para ese material. Al recalcular, el libre debe reducirse por lo asignado. Cargá también un lote vencido: se ve en físico, pero no suma a utilizable.
4. Pulsá «Preparar orden», revisá el borrador y creá la compra. Al regresar al pronóstico, la cantidad pendiente debe aumentar y la sugerencia reducirse. Una recepción parcial debe disminuir pendiente y aumentar stock sin duplicar cantidades.
5. Comprobá una segunda empresa y un usuario sin permisos de compras. No deben verse los datos de la primera empresa ni poder prepararse la compra.

## Lo que aún queda antes del lanzamiento

Validar SQL y pruebas completas con datos de cliente en una base de ensayo; revisar simultaneidad en movimientos y remitos; confirmar políticas de acceso por rol; restaurar una copia de seguridad de prueba; configurar monitoreo y soporte; y documentar los procedimientos del cliente. El pronóstico todavía no conoce fechas prometidas de proveedores ni ventas futuras: su cobertura es una estimación, no una fecha garantizada.

La interfaz pasó `npm run build`. La migración no se ejecutó en tu Supabase desde este entorno.
