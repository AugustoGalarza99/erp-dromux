// Une la estructura exportada (origen.csv) con el mapa de nombres (mapa.json).
import { readFileSync } from 'node:fs';

const leer = (ruta) => readFileSync(ruta, 'utf8');

export function cargarOrigen(ruta) {
  const texto = leer(ruta).replace(/^﻿/, '');
  let celda = texto.slice(texto.indexOf('\n') + 1).trim();
  if (celda.startsWith('"')) celda = celda.slice(1, -1).replace(/""/g, '"');
  return JSON.parse(celda);
}

export function crearModelo(origen, rutaMapa) {
  const mapa = JSON.parse(leer(rutaMapa));
  const tablas = new Map();

  for (const tabla of origen.tablas) {
    const clave = tabla.esquema === 'public' ? tabla.nombre : `${tabla.esquema}.${tabla.nombre}`;
    const regla = mapa.tablas[clave];
    if (!regla) throw new Error(`Tabla sin mapa: ${clave}`);
    const columnas = new Map();
    for (const columna of tabla.columnas) {
      const nuevo = regla.columnas?.[columna.nombre] ?? mapa.columnas[columna.nombre];
      if (!nuevo) throw new Error(`Columna sin mapa: ${clave}.${columna.nombre}`);
      columnas.set(columna.nombre, nuevo);
    }
    // Columnas que se suman a la tabla (nombre "viejo" interno -> nombre nuevo).
    for (const [columna, nombre] of Object.entries(regla.agregar ?? {})) columnas.set(columna, nombre);
    const esquema = tabla.esquema;
    const nuevo = regla.nuevo ? regla.nuevo.replace(/^private\./, '') : null;
    tablas.set(`${tabla.esquema}.${tabla.nombre}`, {
      clave,
      esquema,
      viejo: tabla.nombre,
      nuevo,
      accion: regla.accion ?? 'renombrar',
      en: regla.en ?? null,
      columnas,
      origen: tabla,
    });
  }

  // Tablas que no existían: se declaran para poder escribir SQL con nombres internos.
  for (const [viejo, regla] of Object.entries(mapa.tablas_virtuales ?? {})) {
    tablas.set(`public.${viejo}`, {
      clave: viejo,
      esquema: 'public',
      viejo,
      nuevo: regla.nuevo,
      columnas: new Map(Object.entries(regla.columnas)),
      origen: null,
    });
  }

  const resolverDominio = (clave) => {
    let valor = mapa.valores[clave];
    while (typeof valor === 'string') valor = mapa.valores[valor.slice(1)];
    return valor ?? null;
  };

  return {
    mapa,
    tablas,
    dominio: resolverDominio,
    columnaNueva(tabla, columna) {
      return tabla.columnas.get(columna) ?? mapa.columnas[columna] ?? null;
    },
  };
}
