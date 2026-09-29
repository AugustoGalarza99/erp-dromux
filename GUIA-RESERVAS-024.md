# Dromux Producción · reservas y disponibilidad (versión 024)

## Instalar en el proyecto local

1. Guardá una copia de tu proyecto y de la base de prueba.
2. Descomprimí `erp-dromux-reservas-024.zip`. Copiá el contenido de `erp-dromux/` a la raíz de tu proyecto local sin borrar `.env.local`.
3. Ejecutá **una sola vez** `supabase/024_reservas_disponibilidad.sql` en Supabase SQL Editor, después de las migraciones 001–023. La instalación crea reservas para las órdenes existentes, asignadas por fecha; las cerradas quedan con reserva cero.
4. Ejecutá `npm install`, `npm run dev`; también podés verificar con `npm run build`.

## Cómo funciona

- **Producción → ¿Tengo stock para fabricar?** Seleccioná producto con fórmula y cantidad. El sistema compara por componente el **físico**, lo **reservado** para órdenes activas y lo **libre** (`máximo entre cero y físico menos reservado`). «Faltante» es lo requerido menos lo libre. La simulación no crea ni cambia órdenes.
- **Crear orden en cola:** se crea una reserva por componente tomando lo libre, primero para las órdenes con fecha prevista más próxima; sin fecha quedan al final. Podés crear una orden con faltantes: su asignación será parcial. Las reservas no descuentan stock físico ni sustituyen la entrega con remito.
- **Entregar/consumir insumos:** el stock físico disminuye y las reservas de componentes todavía pendientes se reasignan en la misma operación. Al devolver o cerrar/cancelar la orden, se recalculan las reservas. La anulación de una orden sigue exigiendo devolver los insumos consumidos.
- **Tras compras y otros movimientos:** pulsá **Recalcular** en Disponibilidad para distribuir el nuevo stock libre entre órdenes abiertas. El orden de prioridad es la fecha prevista y luego la fecha de alta.
- **Planificación:** la vista de necesidades muestra el saldo libre y reservado, en lugar de dar por disponible el mismo material en varias órdenes. Guardar un *plan* todavía no reserva; la reserva se crea al convertirlo en orden.

## Prueba sugerida

1. Cargá 12 unidades de un insumo. Creá la fórmula A que usa 8; simulá fabricar A y comprobá que indica 12 libres.
2. Creá una orden A. Simulá otra orden que necesita 8: debe indicar 8 reservadas, 4 libres y 4 faltantes. Creá igualmente la segunda orden: recibirá reserva parcial de 4; ninguna unidad quedará reservada dos veces.
3. Entregá 3 unidades de la primera orden y verificá que el físico baja a 9, su pendiente disminuye y el reparto sigue siendo coherente. Repetí con remito vinculado a producción.
4. Ingresá más stock y pulsá Recalcular. Comprobá que se cubre primero la orden prioritaria. Cancelá una orden sin consumos y comprobá que libera reservas.
5. Probá con un usuario sin permisos de lectura de stock: la pantalla no debe mostrar saldos. Cambiá de empresa y verificá que no aparecen compromisos de la anterior.

## Límites de esta fase

La asignación se hace **por ítem a nivel de empresa**, sumando depósitos. No reserva un lote, depósito, máquina, turno ni fecha de recepción. Los semielaborados se consideran existencias independientes: la receta de ese semielaborado se consulta por separado. La consulta es una fotografía del momento; ventas, remitos independientes u otras salidas pueden reducir el físico después de reservar y causar un faltante operativo. Por eso esta versión informa la reserva y las brechas, pero **todavía no bloquea todas las salidas ajenas a la orden**. El bloqueo transversal y la disponibilidad por depósito/lote pertenecen a la siguiente fase. La previsión «en cuántos días se agota» requiere consumo histórico y plazos de reposición confiables.

## Archivos destacados

| Ruta | Función |
| --- | --- |
| `supabase/024_reservas_disponibilidad.sql` | Ledger y asignación transaccional de reservas, funciones de simulación |
| `src/modules/production/ManufacturingAvailabilityPage.jsx` | Simulación y compromisos activos |
| `src/modules/production/availability.css` | Diseño adaptable de la pantalla |
| `src/modules/production/ProductionPlanningPage.jsx` | Saldos libres y reservados al planificar |
| `src/services/production.js` | Nuevas consultas de producción |
| `src/app/App.jsx`, `src/components/AdminLayout.jsx`, `src/modules/dashboard/Dashboard.jsx` | Rutas y accesos directos |

La interfaz compiló localmente. Esta entrega no aplicó el SQL en tu instancia: probá movimientos, reservas y permisos con datos de prueba antes de usarla con tu cliente.
