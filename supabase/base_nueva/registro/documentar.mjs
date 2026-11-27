// Escribe el registro legible de la base a partir de los SQL del proyecto
// (sql/ y cambios/). No se edita a mano. Necesita la base de prueba (ver LEEME).
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { crearBase } from '../pruebas/base.mjs';

const carpeta = (nombre) => fileURLToPath(new URL(nombre, import.meta.url));
const descripciones = JSON.parse(readFileSync(carpeta('descripciones.json'), 'utf8'));
const db = await crearBase({ mostrar: false });
const filas = async (sql) => (await db.query(sql)).rows;

const columnas = await filas(`
  select n.nspname esquema, c.relname tabla, a.attname columna, format_type(a.atttypid, a.atttypmod) tipo,
    a.attnotnull obligatoria, coalesce(pg_get_expr(d.adbin, d.adrelid), case when a.attidentity <> '' then 'automático' end) defecto,
    has_column_privilege('authenticated', c.oid, a.attnum, 'select') ver,
    has_column_privilege('authenticated', c.oid, a.attnum, 'insert') crear,
    has_column_privilege('authenticated', c.oid, a.attnum, 'update') editar
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where n.nspname in ('public', 'private') and c.relkind = 'r'
  order by n.nspname desc, c.relname, a.attnum`);
const restricciones = await filas(`
  select n.nspname esquema, c.relname tabla, k.contype tipo, pg_get_constraintdef(k.oid) definicion,
    (select array_agg(a.attname::text order by x.o) from unnest(k.conkey) with ordinality x(num, o)
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = x.num) columnas,
    (select t.relname from pg_class t where t.oid = k.confrelid) destino
  from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'private') and k.contype <> 'n' order by k.conname`);
const politicas = await filas(`select schemaname esquema, tablename tabla, policyname nombre, cmd from pg_policies
  where schemaname in ('public', 'private') order by 2, 3`);
const disparadores = await filas(`
  select n.nspname esquema, c.relname tabla, g.tgname nombre, p.proname funcion
  from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace
  join pg_proc p on p.oid = g.tgfoid where not g.tgisinternal order by 2, 3`);
const funciones = await filas(`
  select n.nspname esquema, p.proname nombre, pg_get_function_identity_arguments(p.oid) argumentos, p.prosrc cuerpo,
    has_function_privilege('authenticated', p.oid, 'execute') and n.nspname = 'public' aplicacion
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') order by 1 desc, 2`);

const MODULOS = [
  ['empresas', 'Empresas'], ['ajustes', 'Ajustes y permisos'], ['inicio', 'Inicio'], ['stock', 'Stock'],
  ['produccion', 'Producción'], ['compras', 'Compras'], ['ventas', 'Ventas'], ['finanzas', 'Finanzas'],
  ['interno', 'Tablas internas (esquema private)'],
];
const moduloDe = (esquema, tabla) => (esquema === 'private' ? 'interno' : tabla.split('_')[0]);
const nombreDe = (esquema, tabla) => (esquema === 'private' ? `private.${tabla}` : tabla);
const celda = (texto) => String(texto ?? '').replaceAll('|', '\\|').replace(/\s+/g, ' ');
const AVISO = '_Generado por `documentar.mjs`; no editar a mano._';

const indice = [];
const tablas = [...new Set(columnas.map((c) => `${c.esquema}.${c.tabla}`))];
for (const [modulo, titulo] of MODULOS) {
  const propias = tablas.filter((t) => moduloDe(...t.split('.')) === modulo);
  const salida = [`# ${titulo}`, '', AVISO, ''];
  for (const completa of propias) {
    const [esquema, tabla] = completa.split('.');
    const de = (lista) => lista.filter((x) => x.esquema === esquema && x.tabla === tabla);
    const nombre = nombreDe(esquema, tabla);
    const descripcion = descripciones[nombre] ?? '(sin descripción: agregarla en descripciones.json)';
    indice.push(`| [${nombre}](${modulo}.md) | ${descripcion} |`);
    salida.push(`## ${nombre}`, '', descripcion, '', '| Columna | Tipo | Obligatoria | Por defecto | Relación | La aplicación puede |', '|---|---|---|---|---|---|');
    const reglas = de(restricciones);
    for (const c of de(columnas)) {
      const relaciones = reglas
        .filter((r) => r.tipo === 'f' && r.columnas.at(-1) === c.columna)
        .map((r) => `→ ${r.destino}`);
      if (reglas.some((r) => r.tipo === 'p' && r.columnas.includes(c.columna))) relaciones.unshift('clave');
      const accesos = [c.ver && 'ver', c.crear && 'crear', c.editar && 'editar'].filter(Boolean).join(', ');
      salida.push(`| ${c.columna} | ${c.tipo} | ${c.obligatoria ? 'sí' : 'no'} | ${celda(c.defecto)} | ${relaciones.join(' ')} | ${accesos || '—'} |`);
    }
    const controles = reglas.filter((r) => r.tipo === 'c' || r.tipo === 'u');
    if (controles.length) salida.push('', 'Reglas:', ...controles.map((r) => `- \`${celda(r.definicion)}\``));
    const reglasFila = de(politicas);
    if (reglasFila.length) salida.push('', `Seguridad por filas: ${reglasFila.map((p) => `${p.nombre} (${p.cmd})`).join(', ')}.`);
    const automatismos = de(disparadores);
    if (automatismos.length) salida.push('', `Automatismos: ${automatismos.map((d) => `${d.nombre} → ${d.funcion}`).join(', ')}.`);
    salida.push('');
  }
  writeFileSync(carpeta(`${modulo}.md`), `${salida.join('\n').trimEnd()}\n`);
}

const nombres = tablas.map((t) => nombreDe(...t.split('.')));
const listaFunciones = [
  '# Funciones', '', AVISO, '',
  '«Aplicación» = la puede llamar un usuario con sesión (cada una controla sus permisos). El resto son internas.', '',
  '| Función | Uso | Parámetros | Tablas que menciona |', '|---|---|---|---|',
  ...funciones.map((f) => {
    const usa = nombres.filter((t) => new RegExp(`\\b${t.includes('.') ? t.replace('.', '\\.') : `public\\.${t}`}\\b`).test(f.cuerpo));
    const nombre = f.esquema === 'private' ? `private.${f.nombre}` : f.nombre;
    return `| ${nombre} | ${f.aplicacion ? 'Aplicación' : 'Interna'} | ${celda(f.argumentos)} | ${usa.join(', ')} |`;
  }),
];
writeFileSync(carpeta('funciones.md'), `${listaFunciones.join('\n')}\n`);

const huella = await filas(readFileSync(carpeta('huella.sql'), 'utf8'));
writeFileSync(carpeta('huella.json'), `${JSON.stringify(huella.map((h) => ({ ...h, cantidad: Number(h.cantidad) })), null, 2)}\n`);

writeFileSync(carpeta('LEEME.md'), `${[
  '# Registro de la base de datos', '', AVISO, '',
  `${tablas.length} tablas, ${funciones.length} funciones, ${politicas.length} reglas de acceso por fila, ${disparadores.length} automatismos.`, '',
  'Detalle por módulo en cada archivo; funciones en [funciones.md](funciones.md); historial en [BITACORA.md](BITACORA.md).',
  'Solo describe la estructura: los datos de las empresas no se guardan en el proyecto.', '',
  '| Tabla | Para qué sirve |', '|---|---|', ...indice,
].join('\n')}\n`);

console.log('tablas', tablas.length, 'funciones', funciones.length);
console.table(huella);
process.exit(0);
