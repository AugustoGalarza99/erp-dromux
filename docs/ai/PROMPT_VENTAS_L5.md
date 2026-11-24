# Prompt para arrancar la próxima sesión (copiar y pegar)

```
/erp-retomar Seguimos con el módulo VENTAS (L5), con la misma forma de trabajo de las sesiones anteriores.

Contexto: leé docs/ai/ESTADO.md y docs/ai/VENTAS_PLAN.md. Reglas permanentes: CLAUDE.md (multirrubro D-006, volumen D-007), costos y márgenes solo para admin con finance:read (D-004) y nada de tocar base, permisos ni dinero sin mi autorización. Las migraciones 035 a 042 ya están aplicadas y verificadas por catálogo (listas de precios, venta con lista y descuento, presupuestos, IVA sumado sin discriminar). El commit de todo el trabajo de Ventas ya lo subí a GitHub.

Paso 0 — Verificación con datos reales: te cuento qué probé (presupuesto de consumidor final impreso, vendedor sin costos, venta con lista y descuento). Si te pego un error, arreglalo primero.

Paso 1 — Presupuesto aceptado → venta: diseñá la conversión con un clic (carga los productos y precios del presupuesto en Registrar venta o crea la venta directamente). Toca stock y dinero: preparame la migración 043 con deshacer y comprobaciones, pasala por el subagente erp-revisor-critico y NO la apliques; yo la aplico después de revisarla. Preguntame antes de decidir si reserva precios, qué pasa con un presupuesto vencido y qué pasa si falta stock.

Paso 2 — Ofertas por cantidad y kits (están en mi Excel de costos, docs/ai/referencias/, fuera de Git): "10 + 2 bonificadas", medio pallet / pallet, kit con costo, ganancia y margen de la oferta, alerta si la ganancia es negativa. Primero proponeme el diseño y preguntame lo que haga falta; solo después la migración.

Paso 3 — Pendientes de Ventas que hayan quedado: lista imprimible para clientes (PDF/Excel sin costos), duplicar presupuesto, presupuestos por vencer en el Resumen, importar .xlsx nativo, costo compuesto con comisión y estructura, dólar "ayer vs hoy". Decime cuáles conviene hacer primero.

Probá la interfaz con el arnés local (360/768/1024/1440, con 200+ filas, borrarlo al terminar) y npm run build. Al cerrar: guardá evidencia en docs/ai/evidencia, actualizá ESTADO.md, PLAN.md y la memoria. Pedime confirmación antes de cualquier commit.
```

## Antes de empezar (checklist del propietario)
1. Haber subido el commit a GitHub (lista de archivos en ESTADO.md, sección "Commit").
2. Tener a mano lo que probaste: ¿el presupuesto de consumidor final salió bien impreso? ¿el vendedor no vio costos? ¿la venta con lista y descuento salió al precio esperado?
3. Corregir los 3 perfiles cuyo nombre es un identificador (aparecen como "Usuario" en presupuestos).
4. Levantar el servidor de desarrollo; si falla con "Outdated Optimize Dep", reiniciar Vite.
5. Tener a mano el Excel en `docs/ai/referencias/` (no se sube a Git).

## Si una migración da error
Pegar el mensaje exacto. Las migraciones van en una transacción: si fallan, no queda nada a medias. Las que parchean `post_sale` ignoran saltos de línea de Windows (CRLF) desde el 24/11.
