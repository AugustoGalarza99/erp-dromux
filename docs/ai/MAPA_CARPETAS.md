# Dónde está cada cosa (desde el 26/11/2026)

Las carpetas siguen el menú del sistema. Si falla una pantalla, entrá a la carpeta de su módulo y después a la de su submódulo.

## Estructura
```
src/
  main.jsx                 arranque de la aplicación
  aplicacion/              rutas (App.jsx)
  compartido/              lo que usan varios módulos
    componentes/  contextos/  hooks/  utilidades/  servicios/  estilos/
  modulos/
    acceso/                inicio de sesión
    inicio/                tablero  ·  avisos/
    stock/                 resumen/ items/ (items/importacion/) existencias/ movimientos/ remitos/
    produccion/            resumen/ ordenes-fabricacion/ formulas/ planificacion/ disponibilidad/
                           reposicion/ envases/ estadistica/
    compras/               resumen/ pedidos-internos/ ordenes-compra/ proveedores/ cuentas-proveedores/
    ventas/                resumen/ presupuestos/ clientes/ listas-precios/ registrar-venta/
    finanzas/              cuentas-por-cobrar/ tesoreria/ rentabilidad/
    reportes/
    ajustes/               usuarios/ roles/ catalogos/ (unidades, categorías, depósitos)
                           documentos-produccion/ archivados/ perfil/
    ayuda/
```

## Reglas
- `compartido/` dentro de un módulo: lo que usan varios de sus submódulos (servicio principal, marco y estilos del módulo).
- Un servicio vive en el módulo dueño del dato; otros módulos lo importan desde ahí.
- Los nombres de ARCHIVOS y del código siguen en inglés: se traducen en la etapa 1 (ver `PLAN_REORGANIZACION.md`).
- La documentación anterior al 26/11 cita rutas viejas (`src/modules/inventory` = `src/modulos/stock`, `production` = `produccion`, `purchases` = `compras`, `sales` = `ventas`, `finance` = `finanzas`, `settings` y `catalogs` = `ajustes`, `src/components` = `src/compartido/componentes`, `src/services` = dentro de cada módulo o `src/compartido/servicios`).
