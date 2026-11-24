# Evidencia — L3a Producción (estructura, resumen y tema), 23/11/2026

Método: arnés local temporal (ya eliminado) con autenticación y `supabase` simulados; datos inventados de un taller metalúrgico (para comprobar que no hay textos de un solo rubro). `npm run build` OK.

Verificado en el navegador integrado:
- Las 7 pantallas de Producción (Resumen, Órdenes, Fórmulas, Planificación, ¿Alcanza el stock?, Reposición, Envases) comparten cabecera y pestañas; pestaña y miga activas correctas; sin desborde horizontal a 360 px; 1440 y 1024 revisados visualmente en Resumen, Órdenes y Fórmulas.
- Resumen de producción (`/production`): 4 indicadores, "Para decidir hoy" (fuera de plazo, materiales que se agotan, cola sin fabricación, planes sin lanzar), próximas entregas y materiales por reponer, accesos rápidos.
- Órdenes: tarjetas con estado en texto + color (en cola, en proceso, completada, cancelada, plan), borde lateral por estado, acciones destructivas al final; `?new=1` abre "Nueva orden" (también desde el Resumen) y el diálogo cabe en 360 px.
- Multirrubro (D-006): "Tipos de envasado" pasó a "Envases y presentaciones" con ejemplos genéricos; `rg` de términos de un rubro sin resultados en `src`.

No verificado: guardado real de fórmulas, órdenes, planes y envases; iniciar/terminar/cancelar órdenes y devolver insumos (el arnés no ejecuta RPC); diálogos internos de la tarjeta de orden (entrega, devolución, finalización); PDF de la orden; roles reales; zoom 200 %; iPad; lector de pantalla.
