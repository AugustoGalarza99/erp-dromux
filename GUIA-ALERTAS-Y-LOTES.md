# Activación de lotes y notificaciones · ERP Dromux

## Instalación

1. Aplicá **una sola vez** `supabase/migrations/202609240007_lots_activation.sql` en el SQL Editor del proyecto ERP. La migración `006` de lotes debe estar aplicada antes. Si usás Supabase CLI para todas las migraciones, utilizá `npx supabase db push` en su lugar.
2. Copiá los archivos `src/`, `package.json` y `package-lock.json` del ZIP a las rutas equivalentes de tu proyecto. **Conservá tu `.env.local`**.
3. En la raíz del proyecto ejecutá `npm install` y luego `npm run dev`. Se instala Sonner y se reinicia Vite.

## Por qué fallaba al marcar «Seguir por lotes»

La migración `005` había creado una regla que impedía activar lotes si el ítem tenía **cualquier** movimiento anterior. Eso puede causar el PATCH 400 que viste: Supabase rechaza la operación. La migración `007` permite comenzar a seguir lotes aunque el ítem tenga historial. Los movimientos pasados se conservan sin lote.

Si el ítem todavía tiene stock, al guardar se crea **un lote inicial por depósito**, con el saldo actual y el usuario que hizo la apertura. El total de stock no cambia. Ese lote representa existencias previas a la trazabilidad: no afirma que conocemos los lotes reales de la mercadería anterior. Si necesitás separarlos por lote real, primero completá la identificación física y planificá un ajuste documentado. El registro de apertura puede consultarse en `stock_lot_openings`.

## Prueba rápida

1. Abrí un ítem que nunca tuvo stock, activá **Seguir por lotes** y guardá. Debe aparecer la notificación «Ítem actualizado».
2. Probá con uno que **tuvo movimientos** pero cuyo saldo actual es cero: también debe guardarse.
3. En otro ítem con saldo positivo en dos depósitos, activá lotes y guardá. Deben aparecer dos lotes iniciales, uno por depósito, y **el stock total debe conservarse**. Las salidas posteriores deberán elegir el lote correspondiente.
4. Creá o editá una categoría y registrá un movimiento: deben aparecer notificaciones de éxito. Provocá un error de cantidad insuficiente: debe verse una notificación de error.
5. En **Usuarios → Invitaciones**, tocá **Revocar**. Debe aparecer «¿Seguro que quieres eliminar?». **Cancelar** conserva la invitación; confirmar la revoca y muestra la notificación.
6. Ejecutá `supabase/tests/20260924_stock_lots_integrity.sql`. Sus tres consultas deben devolver **cero filas**; la segunda cuenta los lotes iniciales auditados.

No se habilitan eliminaciones físicas nuevas. Ítems, depósitos, categorías y unidades se activan o desactivan según los permisos existentes. La confirmación se aplica a la revocación de invitaciones; el componente de confirmación queda listo para futuras acciones de eliminación.
