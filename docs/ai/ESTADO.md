# Estado — cierre 27/11/2026 (cambio de PC): cambios 001–010 aplicados; falta cargar soporte, probarlo y publicar

## Resumen en una frase
La base nueva está al día y coincide con el proyecto; órdenes, volumen, concurrencia, tablet y PDF probados. NO está publicada ni lista para producción. El cliente NO usa el sistema hasta el visto bueno del propietario.

## Retomar en otra PC
Ver `CAMBIO_DE_PC.md`. Prompt: `PROMPT_PROXIMA_SESION.md`.

## Evidencia y entorno
- Git: base de la sesión `9c738b1` («1.0.5.0»). Cierre previsto «DromuxERP 1.0.5.1»: comprobar con `git log` al retomar.
- Base NUEVA `nummzswhycklmzbgacnl` (`.env.nueva.local`; conector Supabase de solo lectura). Base VIEJA `drcexqsewiwfhiowrgtv` intacta (`.env.local`); el código ya no funciona contra ella.
- `cambios/001`–`010` aplicados por el propietario; 27/11 `base:registro` y 9 huellas iguales (205 funciones, 81 políticas).
- Local (27/11): `base:probar` flujo 66/66 y cambios 661/661; `base:frontend` sin errores; `build:nueva` correcto.
- **Publicar con `npm run build:nueva`** (`npm run build` arma contra la base vieja). El propietario sube `dist/` a mano a `erp.dromux.com` (provisorio).
- Usuarios de prueba: `demo@dromuxerp.com` (administrador) y `operario@dromuxerp.com` en «Empresa de prueba». «Empresa de prueba B» la administra la cuenta personal del propietario. Dos sesiones a la vez: `localhost:5174` y `127.0.0.1:5174`.

## Pendiente inmediato (en orden)
1. **Cargar el operador de soporte**: el 27/11 había 0 en `private.soporte_operadores` (la cuenta existe en la base). Lo ejecuta el propietario:
   `insert into private.soporte_operadores(usuario_id) select id from auth.users where lower(email) = lower('CORREO_DE_SOPORTE') on conflict (usuario_id) do update set activo = true;`
2. **Probar soporte por pantalla** con esa cuenta: elegir «Empresa de prueba», motivo, acceso completo y costos; no figurar en Usuarios; presupuesto/pedido firmados «Soporte Dromux»; volver a la empresa propia y cerrar sesión (la sesión debe quedar vencida en `private.soporte_sesiones`). Probar también que administrador y operario siguen igual (incluido cerrar sesión).
3. Supabase (propietario): Authentication → URL Configuration: Site URL `https://erp.dromux.com`, Redirect `https://erp.dromux.com/**`. Estado no verificado.
4. Hosting: confirmar que al recargar una ruta interna (ej. `/production/orders`) no dé 404; no hay archivo de redirección en `public/` y no se sabe qué servidor usa.
5. Publicar solo con confirmación (lista en `LANZAMIENTO.md`). Respaldos: plan gratuito sin copias automáticas; pasa a Pro al estar en producción.
6. Después: baja completa de empresa (`PLAN_REORGANIZACION.md`), ordenamiento (nombres en español, importaciones Excel, botones de eliminar).

## Hecho el 27/11
- Órdenes (crear, remito, entrega, devolución, cierre, cancelación), doble clic, dos usuarios a la vez: correcto.
- Volumen: fórmula/orden de 220, remito de 110 ítems 1,3 s, cierre con 110 devoluciones 0,9 s.
- Tablet 768/1024 simulada y texto de 5 PDF.
- Correcciones de pantalla: remito paginado y con sugerencias, horas 24 h, orden cerrada sin «Falta», número OF en remito, fechas y tildes en PDF, frase de IVA del presupuesto, desbordes en tablet.
- 004 topes de líneas (40 → 500/200). 005 reservas por material (evita el límite de 8 s). 006 una cuenta, una empresa. 007 envasado no se pierde. 008 soporte completo 4 h. 009 «Soporte Dromux». 010 funciones nuevas cerradas.
- Dos revisiones de seguridad y dos diseños con Opus; sin P0.

## Cuidados
- 005: un lote que vence no refresca reservas de OTROS materiales hasta que se muevan, se cree/cierre/cancele una orden o «Recalcular».
- 010: toda función nueva que use la aplicación necesita `grant execute ... to authenticated`.
- Soporte: una sola sesión por cuenta; con dos pestañas la primera sigue diciendo «acceso completo» aunque el servidor ya la cortó. La empresa no ve el historial de ingresos. Sin segundo factor.
- Deshacer 004 se niega si hay documentos largos.

## No probado
Corte de internet en un cierre; roles vendedor y compras; documentos de compras/ventas con cientos de ítems; 500 líneas; «ya fabricada» con 500 insumos; muchas órdenes abiertas; aspecto visual de PDF; tablet física; restaurar respaldo; volver a la versión anterior.

## Datos de prueba
OF 7–11 cerradas, remito Nº 6; materiales `VOL-001`–`VOL-220` y producto `VOL-PT` (generan muchos avisos de mínimo; archivar o borrar con la baja de empresa).

## Observaciones abiertas (no bloquean)
- Devolver de más se avisa después de confirmar. Componentes de fórmula sin orden fijo.
- «Depósito Depósito central» en el cierre; decimales con punto («10.000000 kg»); «Disponible» sin unidad.
- Cuentas por cobrar avisa «cobros anteriores a la devolución» aun reintegrado. Inicio puede tardar ~1 min.
- Grilla de permisos no marca módulos no contratados. Plantilla Excel de un solo rubro (D-006). Zona horaria fija.
- Operario ve precios de venta (no costos) y permisos de otros roles.
- Pendiente anterior: H-UX4 y Roles en 360 px; `post_stock_operation` a fondo; H-011b; H-008, H-010, H-012, H-003, H-002; P2 de la 047 y 048; `docs/cliente`; revisión crítica de Ventas.

## Decisiones vigentes
- D-008/D-009: español en tablas, columnas y valores; funciones en inglés. Cambios de base solo como archivo en `cambios/`. Opus analiza y planifica; Sonnet ejecuta.
- D-010: operario entrega y termina desde la orden; cancelar exige «Gestionar».
- D-011: una cuenta, una empresa; soporte completo y visto como «Soporte Dromux»; sin tope para el operario; sin segundo factor.
- El propietario aplica los SQL y hace o confirma los commits. Altas de usuarios y empresas manuales. Empresa nueva: `stock` y `produccion`.
- Ventas y órdenes de pago siguen limitadas a 40 ítems a propósito. IVA: precios sin IVA, informativo en la venta.
- D-005 paleta, D-006 multirrubro, D-007 volumen.

## Datos de sesión
- Nunca pedir ni recibir contraseñas: el propietario inicia sesión en el panel del navegador. Usa VS Code (Commit sin mensaje abre `COMMIT_EDITMSG` y queda a medias).
- Explicar en lenguaje simple. En el shell NO usar heredocs, `cat >` sin entrada, `awk` con `exit` ni `node -e` largos con comillas anidadas.

## Regla de mantenimiento
Reemplazar este resumen al avanzar; máximo 100 líneas. No marcar algo resuelto sin evidencia.
