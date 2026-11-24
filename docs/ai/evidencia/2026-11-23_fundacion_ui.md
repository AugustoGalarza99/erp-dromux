# Evidencia — fundación UI (L0), 23/11/2026

Método: arnés local temporal (autenticación simulada, sin base ni datos reales; ya eliminado) que montó `AdminLayout` real con rutas de prueba. Navegador integrado, `npm run build` OK (solo el aviso previo de chunks > 500 kB).

| Ancho | Sin desborde horizontal | Resultado observado |
| --- | --- | --- |
| 1440 | Sí | Sidebar agrupado, migas "Operación / Producción / Órdenes…", borde superior color del módulo (naranja → azul al pasar a Stock), Ctrl+K abre con foco en el buscador y filtra ("remito" → Remitos de entrega; Enter navega y cierra) |
| 1024 | Sí | Atajo `g` + `v` abre Ventas (clase `mod-sales`, acento verde); guía "Cómo usar ventas" con 3 pasos; la guía cerrada queda recordada (`dromux.guide.<usuario>.<módulo>`) |
| 768 | Sí | Sidebar fijo con scroll propio; indicador "Sistema activo" oculto bajo 900 px para no truncar las migas |
| 360 | Sí | Menú lateral deslizable (abre en 0 px, Escape lo cierra), migas reducidas a la página, búsqueda a pantalla completa (332 px), botones táctiles ≥ 40 px tras el ajuste |

Contraste (texto del acento sobre blanco): índigo 7,9; azul 6,7; naranja 5,0; violeta 7,1; verde 5,0; verde azulado 5,5; gris azulado 6,5; pizarra 10,4. Todos ≥ 4,5:1. Sobre el tono suave de fondo el mínimo es 4,6.

No verificado: zoom 200 % real, iPad apaisado físico, lector de pantalla, retorno de foco con clic real tras cerrar Ctrl+K (con clic simulado vuelve a `body`), módulos con datos reales, roles reales (el arnés da todos los permisos), pantallas internas de cada módulo con los nuevos colores.
