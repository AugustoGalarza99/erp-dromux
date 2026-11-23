---
name: erp-auditar
description: Auditar seguridad multiempresa, RLS, permisos y lógica crítica de Dromux con evidencia.
---

Alcance: $ARGUMENTS. Leer cobertura del área; usar Opus para amenazas complejas, Sonnet para seguimiento acotado. No declarar seguridad total.
1. Trazar UI → servicio → API/RPC → tablas/policies/triggers/Storage/Realtime. Separar inspección estática de prueba real.
2. Verificar anon, autenticado, rol sin permiso, empresa A/B, empresa suspendida y soporte. Probar lectura/escritura/exportación y costos con identidades reales de prueba, sin usar service_role como sustituto de RLS.
3. Inventariar grants públicos, RLS habilitada y policies por comando; comprobar WITH CHECK, company_id falsificado, FKs compuestas multiempresa, vistas/security_invoker y objetos expuestos. Comprobar propietario/roles que omiten RLS.
4. Por cada RPC/firma y trigger: autenticación, permiso de acción y empresa activa; SECURITY DEFINER, search_path, nombres calificados, EXECUTE PUBLIC/anon, SQL dinámico parametrizado, validación de entradas y tamaño. No convertir indiscriminadamente todo a SECURITY DEFINER.
5. Revisar Auth, recuperación de contraseña, Storage de logos/PDF, buckets/policies, secretos frontend/VITE, logs, XSS, importación/exportación y enlaces. Distinguir claves publicables de secretos privilegiados.
6. Stock/dinero: transacción, locks y orden de bloqueo, idempotencia persistente y reintentos, reservas, redondeos, devoluciones y reversión. Probar dos sesiones concurrentes cuando el caso lo exija.
7. Realtime: acceso a publicación/canal/evento por empresa, payload mínimo y reconexión; un filtro del frontend no es autorización. Cache/logout/cambio de empresa sin datos residuales.
8. Dependencias: identificar vulnerabilidad aplicable y ruta de explotación antes de actualizar; no ejecutar correcciones mayores automáticas.
Registrar hallazgos con ruta/objeto, actor, reproducción, impacto y evidencia. Corregir localmente un lote pequeño cuando esté autorizado y crear prueba negativa. Remoto: solo lectura autorizada, sin leer PII innecesaria. Si no se puede ejecutar una prueba, marcarla pendiente.