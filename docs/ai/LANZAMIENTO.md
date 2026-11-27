# Lista de lanzamiento — actualizada 27/11/2026

Estado: **todavía no publicar**. «No probado» nunca significa «funciona».

## Antes de publicar (obligatorio)
- [x] Cambios 001–010 aplicados en la base nueva y verificados (9 huellas iguales).
- [x] Decisiones de seguridad (tabla de abajo).
- [ ] Cargar la cuenta de soporte y probar soporte por pantalla; repetir ingreso y salida de administrador y operario.
- [ ] Supabase: Site URL `https://erp.dromux.com` y Redirect `https://erp.dromux.com/**`.
- [ ] Copia de respaldo (plan gratuito: manual; Pro al estar en producción).
- [ ] Confirmar que el servidor del sitio no da error al recargar una ruta interna.
- [ ] Commit al día y subido a GitHub.
- [ ] Armar con `npm run build:nueva`. **No usar `npm run build`**: apunta a la base vieja.
- [ ] Subir `dist/` a mano, guardando una copia del sitio anterior para poder volver.

## Seguridad (revisión con Opus)
Sin fugas entre empresas, sin costos expuestos al operario ni claves secretas en el sitio. Esquema `private` no expuesto; registro público y anónimo desactivados.

| N.º | Tema | Resultado (27/11) |
|---|---|---|
| S1 | El operario declara cualquier cantidad fabricada | Aceptado: sin tope (queda el autor) |
| S2 | Cualquiera podía crear empresas | Corregido (006) |
| S3 | Editar controles de una orden terminada perdía «sin envasar» | Corregido (007); se sigue pudiendo editar |
| S4 | Funciones futuras nacían abiertas | Corregido (010) |
| S5 | Soporte | Acceso completo con motivo, 4 horas y registro (008); visto como «Soporte Dromux» (009). Sin segundo factor |
| S6 | Sin tope al entregar material | Aceptado |
| S7 | Operario ve precios de venta y permisos de otros roles | Sigue igual |

Riesgos aceptados a revisar con clientes reales: la empresa no ve el historial de ingresos de soporte; conviene mencionar el acceso de soporte en las condiciones del servicio; la cuenta de soporte abre todas las empresas (contraseña única y fuerte).

Sin revisar: gran parte de las funciones de ventas, compras y finanzas; archivos adjuntos (Storage); disparadores y vistas.

## Probado el 27/11 en la base nueva (empresa de prueba)
- Orden: crear, iniciar, remito parcial, entrega sin remito, devolver, terminar con ajustes, cancelar. Saldos exactos.
- Rechazos correctos: devolver de más, cancelar con materiales entregados, anular remito de orden terminada.
- Doble clic al emitir y al terminar: una sola operación.
- Dos usuarios a la vez: por el último stock entra uno; cerrar la misma orden, uno; 3 reintentos iguales, un movimiento.
- 220 materiales y fórmula de 220 componentes: fórmula, orden, remito de 110 ítems, cierre y PDF.
- Tablet 768 y 1024 de ancho (simulada): sin desbordes tras las correcciones.
- PDF (texto): remito, orden de fabricación sin costos, presupuesto, orden de compra, orden de pago.

## No probado
- Soporte en la base real; corte de internet durante un cierre; roles vendedor y compras reales.
- Órdenes de compra, recepciones, ventas y presupuestos con cientos de ítems en pantalla; 500 líneas.
- Aspecto visual de los PDF (se revisó el texto) y tablet física.
- Restaurar un respaldo, volver a la versión anterior, vigilancia de errores y responsable del piloto.
