# Plan — soporte completo y alta de empresa única

27/11/2026. Diseño revisado con Opus por lectura de código (no ejecutado). Decisiones: D-010 y D-011.
Estado: **006 a 010 aplicados y verificados el 27/11**; falta cargar el operador de soporte y probarlo por pantalla. Numeración final: 006 empresa única, 007 envasado, 008 soporte (incluye `end_support_session` y rechazo de cuentas que figuren como usuario), 009 nombre visible, 010 funciones cerradas (cada función nueva de la aplicación necesita `grant execute ... to authenticated`). Cada cambio con deshacer, comprobaciones y pruebas en `supabase/base_nueva/pruebas/cambios.mjs`; se aplican por separado.

## 006 — Una cuenta, una empresa
- `create_company`: bloqueo por usuario (`pg_advisory_xact_lock`) y rechazo si la cuenta tiene cualquier fila en `empresas_usuarios` (activa o no, empresa suspendida o no). Deshacer: versión del 002.
- Pruebas: segunda alta, membresía inactiva y empresa suspendida fallan. La carrera real no se puede probar en PGlite.

## 007 — Datos de envasado
- `save_production_work_details`: mezclar con `opciones_trabajo` existente en lugar de reemplazar, para no perder `unpackaged_quantity`.

## 008 — Soporte completo
- `get_user_role`: con sesión de soporte activa devolver `administrador`. `has_permission`: sesión activa = todo el catálogo y acciones, manteniendo `module_enabled`.
- `begin_support_session`: 4 horas, motivo obligatorio, rechazar empresas donde la cuenta es miembro activo.
- Frontend: `core.js` (`getPermissions`), textos de «solo lectura» en `AdminLayout.jsx` y `App.jsx`, permitir «ver como rol», borrar caché al vencer o cambiar de empresa (`AuthContext.jsx`).
- Cargar el operador en `private.soporte_operadores` a mano (sin correos en el repositorio).
- Pruebas: con sesión crea/edita/cancela y ve costos; sin sesión o vencida, 42501; no figura en `company_members`; un usuario común no puede abrir sesión.
- Segundo factor: descartado por ahora (decisión del propietario). Miembro inactivo de una empresa: hoy entraría como soporte.

## 009 — La empresa ve «Soporte Dromux»
- `private.nombre_autor_visible(empresa, usuario)`: «Soporte Dromux» si tuvo acceso de soporte a esa empresa y no es miembro. El `autor_id` real no cambia.
- Aplicar en `access_audit_events_list` (correos), `create_purchase_request`, `create_quote` y `erp_price_list_history`. Revisar PDF de presupuesto.

## 010 — Margen del operario: DESCARTADO
Decisión del propietario (27/11): sin tope. El número 010 queda libre; al escribir, numerar correlativo según lo que se aplique.

## 011 — Funciones nuevas cerradas por defecto
- `alter default privileges for role postgres revoke execute on functions from public;` (sin `in schema`). En `public` ya están revocados `anon` y `authenticated` (verificado en la base real).
- Vigilar extensiones nuevas creadas por `postgres`. Comprobación con una función de prueba.

## Protección de la cuenta de soporte
Abre todas las empresas: contraseña única y fuerte, corte inmediato con `activo=false`. Segundo factor: pendiente para más adelante.

## Sin revisar
Storage y Realtime (la aplicación no usa Realtime); alta de miembros (hoy manual).
