# Bitácora de la base de datos

Un renglón por cada cambio aplicado a la base real, del más nuevo al más antiguo. La completa quien prepara el cambio; la fecha de aplicación y la comprobación se agregan al verificarlo.

| Aplicado | Archivo | Qué cambió | Comprobación |
|---|---|---|---|
| 27/11/2026 | `cambios/010_ajustes_funciones_cerradas.sql` | Las funciones nuevas no quedan ejecutables por cualquiera (la base real no tenía regla global previa). | Comprobación correcta en la base real; local 661/661; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/009_soporte_nombre_visible.sql` | Lo que hace soporte se muestra como «Soporte Dromux»; el autor real no cambia. 1 función nueva. | Comprobación correcta en la base real; local 661/661; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/008_soporte_acceso_completo.sql` | Soporte con acceso completo 4 horas, con motivo y registro; se cierra al salir. 1 función nueva. | Comprobación correcta en la base real; local 661/661; huellas iguales (9 de 9). Operador de soporte sin cargar al verificar. |
| 27/11/2026 | `cambios/007_produccion_conservar_envasado.sql` | Guardar controles no borra lo que quedó sin envasar. | Comprobación correcta en la base real; local 661/661; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/006_ajustes_una_empresa_por_cuenta.sql` | Crear empresa solo si la cuenta no está vinculada a ninguna. | Comprobación correcta en la base real; local 661/661; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/005_reservas_por_componente.sql` | Cada movimiento recalcula solo las reservas del material movido (antes, las de toda la empresa); índice para entregas por material. 1 función nueva (203 en total). | 4 comprobaciones correctas; local 605/605 (equivalencia con el recálculo completo); en la base real, remito de 110 ítems 1,3 s y cierre con 110 devoluciones 0,9 s, saldos exactos; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/004_lineas_de_documentos_largos.sql` | Tope de ítems: remitos de 40 a 500 y órdenes de compra de 40 a 200 (igual que las funciones). | 2 reglas con tope nuevo; local 158/158; huellas iguales (9 de 9). El remito de 110 ítems pasa el tope pero excede el tiempo máximo de la base (ver 005). |
| 27/11/2026 | `cambios/003_produccion_permisos_operario.sql` | Quien opera órdenes entrega, devuelve y termina desde la orden sin permiso general de stock; cancelar exige «Gestionar» (administradores y roles que crean y editan órdenes). 2 funciones nuevas (202 en total; `05_comprobaciones` esperaba 200). | Comprobaciones correctas (1 rol sin cancelar: operario); local 61/61 y deshacer con huellas iguales; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/002_ajustes_nombre_de_perfil.sql` | Una empresa nueva guarda el nombre de la persona (o su correo sin dominio) como perfil; corrige los que tenían el código interno. | 0 perfiles con código; anónimo sin permiso; huellas iguales (9 de 9). |
| 27/11/2026 | `cambios/001_stock_lectura_depositos_unidades.sql` | Quien trabaja con stock u órdenes puede leer nombres de depósitos y unidades (2 reglas de acceso; 81 en total). | 2 reglas presentes; local 14/14; huellas iguales (9 de 9). |
| 26/11/2026 | `sql/01` a `sql/04` | Línea base: 76 tablas en español, 200 funciones, 79 reglas de acceso, 60 automatismos, 34 permisos, módulos por empresa. | `plpgsql_check` 0 errores (14 avisos); 9 huellas iguales entre base real y proyecto. |

## Ajustes hechos a mano en el panel de Supabase (no están en los SQL)
| Fecha | Ajuste | Estado comprobado |
|---|---|---|
| 26/11/2026 | Registro público de usuarios desactivado | Sí (`disable_signup: true`) |
