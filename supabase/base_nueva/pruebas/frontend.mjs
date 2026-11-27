// Comprueba que la aplicación (src/) coincida con la base nueva, usando la base local en memoria.
// Ejecuta cada función de servicio con un cliente de Supabase falso que anota las consultas y
// luego verifica tablas, columnas, relaciones, permisos por columna, funciones RPC y permisos.
// Límite: no prueba PostgREST ni los datos; eso se confirma recorriendo la aplicación.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { build, transform } from 'esbuild';
import { parseAst } from 'rollup/parseAst';
import { crearBase } from './base.mjs';

const raiz = fileURLToPath(new URL('../../..', import.meta.url));
const src = join(raiz, 'src');
const errores = [];
const avisos = [];

function archivos(dir, patron) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const ruta = join(dir, e.name);
    if (e.isDirectory()) return archivos(ruta, patron);
    return patron.test(e.name) ? [ruta] : [];
  });
}
const corto = (ruta) => ruta.slice(raiz.length).replaceAll('\\', '/').replace(/^\//, '');

/* ---------- 1. Cliente falso y ejecución de los servicios ---------- */

const STUB = `
export const supabase = {
  from: (tabla) => globalThis.__consulta({ tabla, pasos: [] }),
  rpc: (funcion, args) => globalThis.__consulta({ funcion, args: args ?? {}, pasos: [] }),
  auth: new Proxy({}, { get: () => async () => ({ data: {}, error: null }) }),
};
export const isConfigured = true;
`;

const consultas = [];
let archivoActual = '';
let modo = { texto: 'x', existe: true };

// Valor comodín: sirve de texto, número, objeto o lista para recorrer las funciones.
function comodin() {
  return new Proxy(function comodinFn() {}, {
    get(_t, clave) {
      if (clave === Symbol.toPrimitive) return () => '2026-01-01';
      if (clave === Symbol.iterator) return function* vacio() {};
      if (clave === 'then') return undefined;
      if (clave === 'trim') return () => modo.texto;
      if (clave === 'toLowerCase') return () => 'x';
      if (clave === 'length') return 1;
      if (['map', 'filter', 'flatMap'].includes(clave)) return (fn) => [comodin()].map(fn);
      if (clave === 'slice') return () => [comodin()];
      if (clave === 'split') return () => [];
      if (clave === 'toJSON') return () => 'x';
      return comodin();
    },
  });
}

globalThis.__consulta = (consulta) => {
  consulta.archivo = archivoActual;
  consultas.push(consulta);
  let unico = false;
  const constructor = new Proxy({}, {
    get(_t, metodo) {
      if (metodo === 'then') {
        return (resolver) => resolver({
          data: unico ? (modo.existe ? comodin() : null) : [], error: null, count: 1,
        });
      }
      return (...args) => {
        if (metodo === 'single' || metodo === 'maybeSingle') unico = true;
        consulta.pasos.push({ metodo, args });
        return constructor;
      };
    },
  });
  return constructor;
};

const falso = {
  name: 'supabase-falso',
  setup(b) {
    b.onResolve({ filter: /utilidades\/supabase$/ }, () => ({ path: 'stub', namespace: 'stub' }));
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: STUB, loader: 'js' }));
  },
};

const servicios = archivos(src, /\.js$/)
  .filter((ruta) => /utilidades\/supabase['"]/.test(readFileSync(ruta, 'utf8')));
let ejecutadas = 0;

for (const ruta of servicios) {
  const salida = await build({
    entryPoints: [ruta], bundle: true, write: false, format: 'esm', platform: 'neutral',
    plugins: [falso], logLevel: 'silent', loader: { '.css': 'empty' }, mainFields: ['module', 'main'],
  });
  const modulo = await import(`data:text/javascript;base64,${Buffer.from(salida.outputFiles[0].text).toString('base64')}`);
  for (const [nombre, valor] of Object.entries(modulo)) {
    if (typeof valor !== 'function') continue;
    const claves = nombre.includes('Catalog') && /catalogs\.js$/.test(ruta)
      ? ['unidades', 'categorias', 'depositos']
      : nombre === 'searchItemOptions' ? ['category', 'unit'] : [null];
    for (const clave of claves) {
      for (const variante of [{ texto: 'x', existe: true }, { texto: '5', existe: false }]) {
        modo = variante;
        archivoActual = `${corto(ruta)} ${nombre}`;
        const args = Array.from({ length: 8 }, comodin);
        if (clave && nombre === 'searchItemOptions') args[1] = clave;
        else if (clave) args[0] = clave;
        // Segunda vuelta de saveRole: sin rol existente, para recorrer la creación.
        if (nombre === 'saveRole' && !variante.existe) args[1] = null;
        try {
          await valor(...args);
          ejecutadas += 1;
        } catch (error) {
          avisos.push(`No terminó ${archivoActual}: ${error.message.slice(0, 90)}`);
        }
      }
    }
  }
}

/* ---------- 2. Verificación contra la base local ---------- */

const db = await crearBase({ mostrar: false });
const filas = async (sql, params = []) => (await db.query(sql, params)).rows;
const uno = async (sql, params) => (await filas(sql, params))[0];

const tablas = new Set((await filas(
  "select tablename from pg_tables where schemaname = 'public'",
)).map((f) => f.tablename));

const columnas = new Map();
for (const f of await filas(
  "select table_name, column_name from information_schema.columns where table_schema = 'public'",
)) {
  if (!columnas.has(f.table_name)) columnas.set(f.table_name, new Set());
  columnas.get(f.table_name).add(f.column_name);
}

const relaciones = await filas(`
  select conname, conrelid::regclass::text as desde, confrelid::regclass::text as hacia
  from pg_constraint where contype = 'f' and connamespace = 'public'::regnamespace`);
const sinEsquema = (t) => t.replace(/^public\./, '');

async function columna(tabla, nombre, permiso, donde) {
  if (!columnas.get(tabla)?.has(nombre)) {
    errores.push(`${donde}: no existe la columna ${tabla}.${nombre}`);
    return;
  }
  const f = await uno("select has_column_privilege('authenticated', $1, $2, $3) as ok",
    [`public.${tabla}`, nombre, permiso]);
  if (!f.ok) errores.push(`${donde}: sin permiso ${permiso} sobre ${tabla}.${nombre}`);
}

function partir(texto) {
  const partes = [];
  let nivel = 0;
  let actual = '';
  for (const c of texto) {
    if (c === '(') nivel += 1;
    if (c === ')') nivel -= 1;
    if (c === ',' && nivel === 0) {
      partes.push(actual);
      actual = '';
    } else actual += c;
  }
  partes.push(actual);
  return partes.map((p) => p.trim()).filter(Boolean);
}

async function seleccion(tabla, texto, donde) {
  for (const parte of partir(texto)) {
    const abre = parte.indexOf('(');
    if (abre < 0) {
      if (parte === '*') {
        errores.push(`${donde}: select * devuelve las claves en español`);
        continue;
      }
      const pedazos = parte.split(':').map((p) => p.trim());
      await columna(tabla, pedazos.at(-1), 'SELECT', donde);
      continue;
    }
    const cabeza = parte.slice(0, abre).split(':').at(-1).trim();
    const [hija, pista] = cabeza.split('!').map((p) => p.trim());
    if (!tablas.has(hija)) {
      errores.push(`${donde}: no existe la tabla relacionada ${hija}`);
      continue;
    }
    const entre = relaciones.filter((r) => {
      const a = sinEsquema(r.desde);
      const b = sinEsquema(r.hacia);
      return (a === tabla && b === hija) || (a === hija && b === tabla);
    });
    if (!entre.length) errores.push(`${donde}: no hay relación entre ${tabla} y ${hija}`);
    else if (pista && !entre.some((r) => r.conname === pista)) {
      errores.push(`${donde}: la relación ${pista} no existe entre ${tabla} y ${hija}`);
    } else if (!pista && entre.length > 1) {
      errores.push(`${donde}: relación ambigua entre ${tabla} y ${hija} (${entre.map((r) => r.conname).join(', ')})`);
    }
    await seleccion(hija, parte.slice(abre + 1, parte.lastIndexOf(')')), donde);
  }
}

const FILTROS = new Set(['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'in', 'is', 'not', 'order', 'contains']);
const vistas = new Set();

for (const c of consultas.filter((x) => x.tabla !== undefined)) {
  const donde = c.archivo;
  if (!tablas.has(c.tabla)) {
    errores.push(`${donde}: no existe la tabla ${c.tabla}`);
    continue;
  }
  vistas.add(c.tabla);
  for (const { metodo, args } of c.pasos) {
    if (metodo === 'select' && typeof args[0] === 'string') await seleccion(c.tabla, args[0], donde);
    else if (FILTROS.has(metodo)) await columna(c.tabla, String(args[0]), 'SELECT', donde);
    else if (['insert', 'update', 'upsert'].includes(metodo)) {
      const permisos = metodo === 'upsert' ? ['INSERT', 'UPDATE'] : [metodo.toUpperCase()];
      for (const clave of Object.keys(args[0])) {
        for (const permiso of permisos) await columna(c.tabla, clave, permiso, donde);
      }
      const conflicto = args[1]?.onConflict;
      if (conflicto) {
        const pedido = conflicto.split(',').map((x) => x.trim()).sort().join(',');
        const unicos = await filas(`
          select (select string_agg(a.attname::text, ',' order by a.attname::text) from pg_attribute a
                  where a.attrelid = i.indrelid and a.attnum = any(i.indkey::int2[])) as cols
          from pg_index i where i.indrelid = $1::regclass and i.indisunique`, [`public.${c.tabla}`]);
        if (!unicos.some((u) => u.cols === pedido)) errores.push(`${donde}: onConflict ${conflicto} no es único`);
      }
    } else if (metodo === 'delete') {
      const f = await uno("select has_table_privilege('authenticated', $1, 'DELETE') as ok", [`public.${c.tabla}`]);
      if (!f.ok) errores.push(`${donde}: sin permiso para borrar en ${c.tabla}`);
    }
  }
}

const funciones = await filas(`
  select p.proname as nombre, p.pronargs as total, p.pronargdefaults as opcionales,
         p.proargnames as nombres, p.proargmodes::text[] as modos,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') as puede
  from pg_proc p where p.pronamespace = 'public'::regnamespace`);

const rpcVistas = new Set();
function comprobarRpc(c) {
  const donde = c.archivo;
  rpcVistas.add(c.funcion);
  const candidatas = funciones.filter((f) => f.nombre === c.funcion);
  if (!candidatas.length) {
    errores.push(`${donde}: no existe la función ${c.funcion}`);
    return;
  }
  const enviados = Object.keys(c.args);
  const sirve = candidatas.some((f) => {
    const entradas = (f.nombres ?? []).filter((_n, i) => !f.modos || ['i', 'b', 'v'].includes(f.modos[i]));
    const obligatorias = entradas.slice(0, f.total - f.opcionales);
    return f.puede && enviados.every((k) => entradas.includes(k)) && obligatorias.every((k) => enviados.includes(k));
  });
  if (!sirve) errores.push(`${donde}: los parámetros de ${c.funcion} no coinciden o no hay permiso (${enviados.join(', ')})`);
}

consultas.filter((x) => x.funcion !== undefined).forEach(comprobarRpc);

// Llamadas hechas desde las pantallas: se comprueban los nombres de parámetro escritos.
for (const ruta of archivos(src, /\.jsx$/)) {
  const texto = readFileSync(ruta, 'utf8');
  for (const m of texto.matchAll(/\.rpc\(\s*['"]([a-z0-9_]+)['"]\s*(?:,\s*\{([^{}]*)\})?/g)) {
    const args = Object.fromEntries([...(m[2] ?? '').matchAll(/\bp_[a-z_]+/g)].map((x) => [x[0], 1]));
    comprobarRpc({ funcion: m[1], args, archivo: corto(ruta) });
  }
}

// Funciones llamadas en el código que ningún recorrido ejecutó.
for (const ruta of archivos(src, /\.(js|jsx)$/)) {
  const texto = readFileSync(ruta, 'utf8');
  for (const m of texto.matchAll(/(?:\.rpc|\brpc|\bcall)\(\s*['"]([a-z0-9_]+)['"]/g)) {
    if (!funciones.some((f) => f.nombre === m[1])) errores.push(`${corto(ruta)}: no existe la función ${m[1]}`);
    else if (!rpcVistas.has(m[1])) avisos.push(`Parámetros sin comprobar: ${m[1]} (${corto(ruta)})`);
  }
  if (ruta.endsWith('.jsx') && /supabase\s*\.\s*from\(/.test(texto)) {
    errores.push(`${corto(ruta)}: consulta directa a una tabla desde una pantalla; no se comprueba`);
  }
}

/* ---------- 3. Permisos y valores ---------- */

const catalogo = new Map((await filas(
  'select recurso, acciones from public.ajustes_permisos_catalogo',
)).map((f) => [f.recurso, f.acciones]));
// has_permission admite además recursos generales que no figuran como pantalla.
const generales = new Set(['inicio', 'inventario', 'items', 'stock', 'depositos', 'unidades', 'categorias',
  'produccion', 'compras', 'ventas', 'finanzas', 'reportes', 'ajustes', 'usuarios', 'roles']);
const acciones = new Set([...catalogo.values()].flat());
let permisosVistos = 0;

function recurso(nombre, donde) {
  permisosVistos += 1;
  if (!catalogo.has(nombre) && !generales.has(nombre)) errores.push(`${donde}: permiso desconocido «${nombre}»`);
}

for (const ruta of archivos(src, /\.(js|jsx)$/)) {
  const texto = readFileSync(ruta, 'utf8');
  const donde = corto(ruta);
  for (const m of texto.matchAll(/\bcan\(([^()]*)\)/g)) {
    const [primero, ...resto] = m[1].split(',');
    const literal = primero.trim().match(/^['"]([a-z_]+)['"]$/);
    if (literal) recurso(literal[1], donde);
    for (const a of resto.join(',').matchAll(/['"]([a-z_]+)['"]/g)) {
      if (!acciones.has(a[1])) errores.push(`${donde}: acción desconocida «${a[1]}»`);
    }
  }
  for (const m of texto.matchAll(/\b(?:permission|needs|screen)\s*[:=]\s*['"]([a-z_]+)['"]/g)) recurso(m[1], donde);
  if (/Shell\.jsx$|App\.jsx$|guideContent|roleTemplates|Dashboard|ReportsPage/.test(ruta)) {
    for (const m of texto.matchAll(/\bresource\s*[:=]\s*['"]([a-z_]+)['"]/g)) recurso(m[1], donde);
    for (const m of texto.matchAll(/\bany(?:Of)?\s*[:=]\s*\{?\[([^\]]*)\]/g)) {
      for (const r of m[1].matchAll(/['"]([a-z_]+)['"]/g)) recurso(r[1], donde);
    }
  }
}

const valores = await import(pathToFileURL(join(src, 'compartido/valores.js')).href);
for (const [clave, lista] of Object.entries(valores.VALORES_GUARDADOS)) {
  const [tabla, col] = clave.split('.');
  const checks = await filas(`
    select pg_get_constraintdef(c.oid) as def from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
    where c.contype = 'c' and c.conrelid = $1::regclass and a.attname = $2
      and array_length(c.conkey, 1) = 1`, [`public.${tabla}`, col]);
  const conLista = checks.map((f) => f.def).find((d) => d.includes('ARRAY['));
  if (!conLista) {
    avisos.push(`valores.js: ${clave} no tiene una lista fija en la base`);
    continue;
  }
  const base = [...new Set([...conLista.matchAll(/'([a-z_]+)'::text/g)].map((m) => m[1]))];
  // "vencido" lo calcula el servidor: está en la pantalla pero no se guarda.
  const sobran = lista.filter((v) => !base.includes(v) && v !== 'vencido');
  const faltan = base.filter((v) => !lista.includes(v));
  if (sobran.length || faltan.length) {
    errores.push(`valores.js ${clave}: sobran [${sobran}] faltan [${faltan}]`);
  }
}

const empresa = (await uno(`insert into public.empresas(nombre, identificador, modulos)
  values ('Control', 'control', '{}'::jsonb) returning id`)).id;
for (const nombre of [...catalogo.keys(), 'inventario']) {
  const f = await uno('select private.module_enabled($1, $2) as ok', [empresa, nombre]);
  if (f.ok !== valores.moduloHabilitado(nombre, {})) {
    errores.push(`valores.js: el módulo de «${nombre}» no coincide con private.module_enabled`);
  }
}

/* ---------- 4. Nombres usados que no existen ---------- */
// La compilación no avisa si una pantalla usa un nombre que ya no está: la pantalla se cae al abrirla.
// Control simple: todo nombre usado en un archivo debe declararse o importarse en ese archivo.

const GLOBALES = new Set([...Object.getOwnPropertyNames(globalThis), '__jsx', '__fragmento', 'window',
  'document', 'localStorage', 'sessionStorage', 'navigator', 'location', 'history', 'requestAnimationFrame',
  'cancelAnimationFrame', 'FileReader', 'Image', 'createImageBitmap', 'DOMParser', 'XMLSerializer',
  'HTMLElement', 'HTMLInputElement', 'ResizeObserver', 'IntersectionObserver', 'matchMedia',
  'getComputedStyle', 'alert', 'confirm', 'DecompressionStream']);

function nombresDe(patron, destino) {
  if (!patron) return;
  if (patron.type === 'Identifier') destino.add(patron.name);
  else if (patron.type === 'ObjectPattern') patron.properties.forEach((p) => nombresDe(p.value ?? p.argument, destino));
  else if (patron.type === 'ArrayPattern') patron.elements.forEach((e) => nombresDe(e, destino));
  else if (patron.type === 'AssignmentPattern') nombresDe(patron.left, destino);
  else if (patron.type === 'RestElement') nombresDe(patron.argument, destino);
}

for (const ruta of archivos(src, /\.(js|jsx)$/)) {
  const { code } = await transform(readFileSync(ruta, 'utf8'), {
    loader: 'jsx', jsx: 'transform', jsxFactory: '__jsx', jsxFragment: '__fragmento',
  });
  const declarados = new Set();
  const usados = new Set();
  const recorrer = (nodo) => {
    if (Array.isArray(nodo)) return nodo.forEach(recorrer);
    if (!nodo || typeof nodo.type !== 'string') return undefined;
    if (/^Import.*Specifier$/.test(nodo.type)) {
      declarados.add(nodo.local.name);
      return undefined;
    }
    if (nodo.type === 'VariableDeclarator') nombresDe(nodo.id, declarados);
    if (/Function/.test(nodo.type)) {
      nombresDe(nodo.id, declarados);
      nodo.params?.forEach((p) => nombresDe(p, declarados));
    }
    if (nodo.type === 'ClassDeclaration') nombresDe(nodo.id, declarados);
    if (nodo.type === 'CatchClause') nombresDe(nodo.param, declarados);
    if (nodo.type === 'Identifier') {
      usados.add(nodo.name);
      return undefined;
    }
    for (const [clave, hijo] of Object.entries(nodo)) {
      const esNombrePropio = (clave === 'key' && !nodo.computed)
        || (clave === 'property' && nodo.type === 'MemberExpression' && !nodo.computed)
        || ['label', 'meta', 'exported', 'imported'].includes(clave)
        || (nodo.type === 'MetaProperty' && clave === 'property');
      if (!esNombrePropio && hijo && typeof hijo === 'object') recorrer(hijo);
    }
    return undefined;
  };
  recorrer(parseAst(code));
  for (const nombre of usados) {
    if (!declarados.has(nombre) && !GLOBALES.has(nombre)) {
      errores.push(`${corto(ruta)}: se usa «${nombre}» pero no está declarado ni importado`);
    }
  }
}

console.log(`Servicios: ${servicios.length} archivos, ${ejecutadas} recorridos, ${consultas.length} consultas`);
console.log(`Tablas usadas: ${vistas.size} · funciones RPC comprobadas: ${rpcVistas.size} · permisos revisados: ${permisosVistos}`);
for (const a of [...new Set(avisos)]) console.log('AVISO', a);
const unicos = [...new Set(errores)];
for (const e of unicos) console.log('ERROR', e);
console.log(unicos.length ? `${unicos.length} errores` : 'Sin errores');
await db.close();
process.exitCode = unicos.length ? 1 : 0;
