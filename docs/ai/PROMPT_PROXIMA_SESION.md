# Prompt para arrancar la próxima sesión (copiar y pegar)

El prompt anterior (Ventas L5) quedó guardado en `docs/ai/PROMPT_VENTAS_L5.md`.

```
/erp-retomar Seguimos con la salida a producción del primer cliente (parte de producción), por fases, con la misma forma de trabajo: prolijo, guardando avances y próxima tarea en docs/ai/AVANCE_FASES.md y docs/ai/ESTADO.md.

Contexto: leé docs/ai/AVANCE_FASES.md, docs/ai/ESTADO.md y docs/ai/DISENO_045_PERMISOS_FINOS.md. Reglas permanentes: CLAUDE.md (multirrubro D-006, volumen D-007), costos y márgenes solo para quien el administrador autorice, y nada de tocar base, permisos ni dinero sin mi autorización (las migraciones las preparás con deshacer, verificaciones y revisión crítica con el subagente erp-revisor-critico, y las aplico yo). Las migraciones 035 a 045 ya están aplicadas y verificadas (043 cierre de producción con ajustes + estadística + índices; 044 usuarios y roles solo admin + historial de accesos; 045 catálogo de permisos por pantalla). El script supabase/verificaciones/pruebas_roles_empresas.sql (204 casos) pasó completo. Pruebo en el mismo proyecto de Supabase con las empresas Dromux ERP, Espacio Demo y Metalurgica Cerquatti y los usuarios admin, vendedor y demo (ids en AVANCE_FASES.md); vos no recibís contraseñas: los scripts con suplantación los corro yo en el editor SQL y te pego el resultado. El commit de lo hecho hasta la 045 ya lo subí a GitHub.

Paso 0 — Lo que probé yo desde la última sesión (te lo cuento al empezar): recorrido de la guía docs/ai/FASE1_GUIA_RECORRIDO.md (pasos que salieron OK y errores con el mensaje exacto) y si el frontend ya está publicado. Si te pego un error, arreglalo primero.

Paso 1 — Migración 046 (Compras por pantalla, ver diseño §5): re-apuntar funciones y políticas de Compras a sus pantallas (Resumen de compras, Pedidos internos, Órdenes de compra, Proveedores, Compras y cuentas) con el método de 037 (leer la definición vigente con pg_get_functiondef, mapa explícito función→recurso, abortar si el conteo de apariciones no coincide); que can_see_reference_cost use costs_materials (cierra H-011: el vendedor no debe ver costos de materiales salvo que el administrador se lo dé); marcar enforced=true en el catálogo para Compras; rutas y menú por pantalla (el menú muestra las pantallas sin permiso bloqueadas, con candado). Prueba clave: un rol con solo Pedidos internos entra a esa pantalla y todo lo demás da 42501 en el servidor; un rol Encargado de compras con costs_materials ve costos y el Vendedor no. Preparame 046 + deshacer + verificaciones + casos nuevos en pruebas_roles_empresas.sql (grupo 11) y pasala por erp-revisor-critico; NO la apliques. Preguntame antes de decidir lo que sea ambiguo (por ejemplo funciones compartidas como tableros y reposición).

Paso 2 — Vista "ver como rol" (solo interfaz): el administrador elige un rol y ve menú, pantallas bloqueadas y botones como los vería ese rol (usando role_permissions del rol elegido), con barra fija "Estás viendo como: <rol> · Salir de esta vista"; no cambia la sesión ni escribe nada y avisa que el servidor sigue respondiendo con los permisos reales del administrador. También: la búsqueda Ctrl+K y las tarjetas del Inicio muestran lo bloqueado con candado.

Paso 3 — Si queda tiempo: 047 Producción por pantalla (production_* + costs_production en can_see_production_costs y márgenes) con el mismo método, y lectura a fondo de post_stock_operation y de los PDF/exportaciones sin costos (C-013).

Probá la interfaz con el arnés local (360/768/1024/1440, con 200+ filas, borrarlo al terminar) y npm run build. Al cerrar: guardá evidencia en docs/ai/evidencia, actualizá AVANCE_FASES.md, ESTADO.md, COBERTURA.md, HALLAZGOS.md y la memoria, y dejame el prompt de la sesión siguiente. Pedime confirmación antes de cualquier commit.
```

## Antes de empezar (checklist del propietario)
1. Haber subido el commit de la sesión anterior (migraciones 043–045, frontend y docs).
2. Haber publicado el frontend (sin eso, Usuarios/Roles, el historial de accesos, la Estadística y el cierre con ajustes no se ven).
3. Haber recorrido al menos los pasos A–F de `FASE1_GUIA_RECORRIDO.md` y tener a mano los resultados (OK/FALLA y mensajes exactos).
4. Decidir (si ya lo sabés): ¿la estadística incluye órdenes archivadas?, ¿cómo se da de alta un empleado (invitación por email o alta manual)?, ¿cuota para crear empresas?
5. Tener a mano el editor SQL de Supabase para correr las verificaciones y el script de pruebas.

## Si una migración da error
Pegar el mensaje exacto. Las migraciones van en una transacción: si fallan, no queda nada a medias. Cada una trae su deshacer en `supabase/reparacion/0_deshacer_NNN.sql` (leer la advertencia al inicio del archivo antes de usarlo).
