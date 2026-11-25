# Estado — cierre de sesión 24/11/2026: permisos por pantalla de Compras y Producción aplicados; Fase 1 recorrida por Claude

## Resumen en una frase
Foco: dejar PRODUCCIÓN, costos, stock y Ajustes listos para que el primer cliente empiece a probar (sin registrar ventas ni clientes). Migraciones 035–047 + 046b + 046c APLICADAS por el propietario y verificadas con catálogo y con `supabase/verificaciones/pruebas_roles_empresas.sql` (0 FALLA tras 046c; la 047 se aplicó y su comprobación 8 dio 0 filas; falta pegar el resto de `047_comprobaciones.sql` y re-correr el script con el grupo 12). Seguimiento: `docs/ai/AVANCE_FASES.md` (leer primero) y `PROMPT_PROXIMA_SESION.md`.

## Evidencia y entorno
- Repo `main`, HEAD de partida `f639070`; trabajo de la sesión SIN commit (el propietario lo sube). Base: proyecto `drcexqsewiwfhiowrgtv` (conector de solo lectura). Empresas de prueba: Dromux ERP, Espacio Demo, Metalurgica Cerquatti (ids en AVANCE_FASES).
- VERIFICADO: build OK; Fase 1 recorrida por Claude en Espacio Demo con la sesión admin del propietario (evidencia/2026-11-24_flujo_completo_fase1.md): catálogos, ítems, stock manual, fórmula (costo = cálculo a mano), ¿alcanza?, orden, entrega por remito, cierre con diferencias, estadística, devolución, cancelación, archivar/recuperar, envasado con 2 presentaciones. H-E1 (entrega del lote 100 % reservado por la propia orden) cerrado con 046c.
- NO probado: PDF de la orden (descarga), usuarios operario/vendedor reales, corte de red, cierre con stock insuficiente, orden con 200 insumos, concurrencia (HI-001), rendimiento con datos grandes, interfaz rediseñada de Ajustes y Producción por pantalla a 360/768/1024/1440 (solo arnés simulado de Ajustes en 1440/360).

## Hecho en esta línea
- 045 catálogo; 046 Compras por pantalla; 046b precio de proveedor = costo (`costs_materials`); 046c reserva propia en entregas; 047 Producción por pantalla (36 funciones, 14 políticas) + `costs_production` (admin o permiso explícito). Ver evidencias `compras_046_preparada` y `produccion_047_preparada`.
- Interfaz: "ver como rol", candados en menú/Ctrl+K/Inicio; Ajustes rediseñado (Roles con plantillas y barra de guardado, Usuarios con filtros, Archivados, Documentos de producción con vista previa); correcciones D1–D9 de la Fase 1.
- Decisión: alta de empleados, cuentas y empresas MANUAL hasta el lanzamiento comercial (web + Stripe); HI-002/HI-003 diferidos (DECISIONES.md).

## Incompleto o sin hacer
- 048 Stock y Ajustes por pantalla (stock_levels, stock_movements, stock_delivery_notes, unidades/categorías/depósitos) y `private.cleanup_target` (Archivados) por pantalla; lote de Ventas (precios y márgenes con `costs_production`, `price_require_*`, `erp_admin_*`); P2 de la 047 (production_formula_cost sin pantalla, recalculate_production_reservations escritura con permiso de lectura, erp_company_profile).
- H-008 (rutas sin puerta), H-010, H-012, HI-005 (esquema `private` expuesto: confirmar en el panel), H-002 (esquema no reproducible), H-003 (índices con datos), HI-001 (concurrencia), C-013 (PDF/exportaciones sin costos), lectura a fondo de `post_stock_operation`.
- Ventas L5, Finanzas L6, Reportes L7: después de cerrar producción.

## Riesgos
- Sin recorrido con usuarios no admin reales ni PDF verificado: cerrar antes de abrir al cliente. El cierre de órdenes con muchos ajustes toma el bloqueo de reservas de la empresa (tope 300 ajustes): medir con volumen.
- Ventas toca dinero: no tocar `post_sale` ni cobros sin revisión crítica.

## Decisiones vigentes
- Costos: `costs_materials` (referencia y precios de proveedor) y `costs_production` (costos de fórmulas, órdenes, planes, corridas) = admin o permiso explícito por rol; el Vendedor no los tiene. Márgenes/listas de Ventas: aún admin + finanzas hasta su lote.
- Roles y usuarios solo del administrador; módulos y pantallas sin permiso se ven bloqueados (candado); "Gestionar" solo existe en Pedidos internos.
- Pruebas en el MISMO proyecto con 3 empresas de prueba, sin datos reales; Claude opera por pantalla solo en Espacio Demo con la sesión del propietario; los scripts con suplantación los corre el propietario.
- D-005 paleta por módulo, D-006 multirrubro, D-007 volumen. IVA: precios sin IVA, informativo en la venta. Nunca tocar base ni aplicar migraciones sin autorización.

## Próximo paso concreto (prompt en `docs/ai/PROMPT_PROXIMA_SESION.md`)
1. Propietario: commit de esta sesión; pegar `047_comprobaciones.sql` completo y el script con grupo 12 (copia nueva).
2. Claude: cerrar Fase 1 con intervención humana (PDF, operario/vendedor, red, stock insuficiente, 200 insumos), verificar visualmente, 048 y Fase 2a, lista de lanzamiento.

## Datos de sesión
- Arnés: la app local en `localhost:5173` con la sesión del propietario en el panel del navegador; con la ventana emulada a 1440 px los clics por coordenadas fallan: usar referencias o eventos de entrada. El arnés simulado (mock de Supabase) se borra siempre al terminar.
- El conector de la base es de solo lectura. En el shell, evitar heredocs largos con caracteres especiales: usar la herramienta de archivos.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. Preservar decisiones vigentes y próximo paso. No marcar algo resuelto sin evidencia.
