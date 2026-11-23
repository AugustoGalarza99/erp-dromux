---
name: erp-diseno
description: Mejorar UX/UI industrial responsive, accesibilidad y ayuda contextual en un módulo de Dromux.
---

Alcance: $ARGUMENTS. Usar Sonnet y revisar el flujo existente antes de CSS.
1. Identificar usuario (admin, operario, compras, vendedor), objetivo frecuente y pasos actuales. Reducir doble carga y clics conservando controles de negocio.
2. Reutilizar tokens/componentes; fondo blanco, acentos sobrios existentes, texto oscuro legible, escala tipográfica/espaciado consistente. Botones, inputs, selects, buscadores, tablas, badges y modales con estados hover/focus/disabled/loading/error.
3. Una acción principal clara; acciones destructivas secundarias con confirmación, Sonner y protección contra doble envío. Etiquetas visibles, mensajes españoles accionables y numeración humana; no UUIDs ni infraestructura técnica al cliente.
4. Tabla con búsqueda/filtros próximos al trabajo, paginación y acciones accesibles. En móvil usar tarjetas o scroll dentro de tabla; no esconder editar/eliminar. Sidebar con scroll independiente. Modales con alto máximo, scroll, foco inicial/retorno, Escape, teclado y etiquetas accesibles.
5. Probar a 360, 768, 1024 y 1440 px, iPad apaisado y zoom 200%. Objetivos: sin desborde global, contraste WCAG AA, controles táctiles cómodos, navegación por teclado, estados vacíos/loading/error y nombres largos reales.
6. Ayuda contextual: qué hace, qué necesitás y próximo paso en 2–4 frases. No recargar cada pantalla de tutoriales. Operario/PDF sin costos; comprobar también API.
7. Cambios por módulo, sin !important globales ni duplicar hojas. No instalar librerías de UI para ocultar problemas de layout. Separar cambio visual de lógica crítica para revisar.
Verificar visualmente en navegador si está disponible y guardar evidencia sanitizada. Si no lo está, indicar qué pruebas visuales quedan pendientes; un build no verifica UX.