# Dromux Producción · reservas por depósito y lote (versión 026)

## Instalación

1. Guardá una copia del proyecto y de la base de pruebas. Descomprimí `erp-dromux-ubicaciones-026.zip` y copiá el contenido de `erp-dromux/` a tu proyecto local. Conservá tu `.env.local` con `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`; el paquete no contiene credenciales.
2. En el SQL Editor de la **base de pruebas**, ejecutá una sola vez `supabase/026_reservas_por_ubicacion.sql`. Requiere las migraciones 024 y 025 ya aplicadas. El script crea la tabla de ubicaciones y asigna las reservas de las órdenes existentes. No borra movimientos históricos.
3. Desde la raíz local ejecutá `npm install`, `npm run build` y `npm run dev`. Si todo funciona en pruebas, repetí la migración en la base que corresponda siguiendo tu proceso de publicación.

## Cómo trabaja

- Al crear una orden, el sistema asigna el stock utilizable por depósito y, cuando corresponde, por lote. Prioriza la fecha prevista de la orden y luego el lote con vencimiento más cercano. Los lotes vencidos quedan fuera de la asignación.
- «¿Tengo stock para fabricar?» muestra físico, utilizable, reservado y libre; desplegá un componente para ver sus ubicaciones. Es una simulación y no aparta stock.
- En cada orden aparece lo asignado a cada insumo. El remito para fabricación propone un renglón por ubicación asignada; podés entregar solo parte y luego emitir otro remito.
- Una salida independiente o transferencia no puede retirar lo asignado en ese depósito y lote. Una entrega a la orden puede consumir su propia asignación. Entradas, salidas y transferencias vuelven a distribuir las reservas.
- La asignación refleja el stock actual, no es una promesa de inmovilidad de un lote. Si cambia la disponibilidad antes del retiro, consultá de nuevo la orden; el movimiento se valida al confirmar.

## Prueba de punta a punta

1. En pruebas, cargá un material con lotes: lote A con 6 unidades y vencimiento futuro cercano en depósito Norte, lote B con 5 unidades y vencimiento posterior en depósito Sur. Fórmula con 8 unidades de ese material.
2. Simulá una orden por 8. Debe verse 11 utilizable y 11 libre, con A y B en el detalle. Creá la orden: deberá asignar 6 de A y 2 de B. Reabrí disponibilidad: 8 reservado y 3 libre.
3. Intentá una salida manual de 1 desde A: debe rechazarse. Una salida de 3 desde B debe ser posible; 4 desde B debe rechazarse. También probá una transferencia desde A: debe respetar su reserva.
4. Abrí la orden, emití un remito parcial de 4 del lote A y verificá que se descontó una vez. El saldo asignado a A debe ser 2, y el de B 2. Emití otro remito para completar y verificá insumos entregados y stock.
5. Repetí con un lote vencido: debe aparecer en stock físico, pero no en utilizable ni en la propuesta. Probá dos órdenes con fechas diferentes para confirmar prioridad y cancelá una sin consumos para liberar su reserva.

## Alcance y siguiente etapa

La compilación local pasó con `npm run build`. El SQL y los flujos con datos reales deben validarse en tu base de pruebas; aquí no hay acceso a tu instancia. El siguiente bloque recomendado es pronóstico de agotamiento y sugerencias de compra basadas en consumo real, pedidos y plazos del proveedor. Para una puesta en producción, además conviene hacer una prueba guiada con el cliente y revisar permisos, copias de seguridad y restauración.
