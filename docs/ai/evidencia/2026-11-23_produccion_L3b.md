# Evidencia — L3b Producción para volumen (D-007), 23/11/2026

Método: arnés local temporal (ya eliminado) con autenticación y `supabase` simulados; 260 ítems, 240 filas de reposición (70 urgentes, 100 a planificar), una orden con 200 insumos y 60 movimientos, una fórmula de 40 componentes (el tope vigente del servidor), 30 presentaciones. `npm run build` OK.

Verificado en el navegador integrado:
- Reposición: 170 materiales que requieren atención se muestran de a 25 (urgentes primero, luego por días de cobertura), filtros por estado con contadores, búsqueda, filtro por proveedor, detalle plegable por fila, compra sugerida con acceso directo; en 360 px cada fila pasa a tarjeta. Método de cálculo plegado.
- Orden con 200 insumos: la tarjeta mide ~430 px con los insumos plegados y ~1150 px abierta (antes, un bloque por insumo); barra de avance "9 de 200 cubiertos", pendientes primero, filtros (Pendientes/Cubiertos/Todos), búsqueda, tabla paginada de a 15 con encabezado fijo, asignaciones plegadas por fila; historial de movimientos paginado de a 10.
- Fórmulas: editor con buscador para agregar (no un renglón por componente), tabla paginada, resaltado de nuevo/modificado/quitado con "Antes X", recuperación de quitados, indicador de límite "n de 40", barra de guardado con "cambios sin guardar" y aviso al abrir otra fórmula; lista de fórmulas buscable y paginada. Se corrigió un `<form>` anidado.
- Envases y presentaciones: tabla con estado, búsqueda con espera, paginación, estado vacío con acción y diálogo de alta/edición de dos columnas; sin desborde a 360 px (el diálogo cabe).
- Sin desborde horizontal del documento a 360 px en las cuatro pantallas.

Hallazgo: H-006 (la base limita a 40 líneas fórmulas y remitos; ver `HALLAZGOS.md`).

No verificado: guardado real de fórmulas/presentaciones, creación de órdenes "ya fabricadas" con cientos de insumos (se paginó pero no se probó con datos), simulador "¿Alcanza el stock?" y planificación con muchos componentes, diálogos de entrega/devolución/finalización, PDF con 200 líneas, roles reales, zoom 200 %, iPad.
