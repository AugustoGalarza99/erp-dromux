// Comprobación estática de funciones plpgsql: prepara cada consulta embebida
// contra la base nueva, reemplazando las variables por NULL.
import { crearBase } from './base.mjs';
import { tokenizar } from '../generador/sql.mjs';

const db = await crearBase({ mostrar: false });
const columnas = new Map();
for (const f of (await db.query(`select table_schema||'.'||table_name t, column_name c from information_schema.columns where table_schema in ('public','private')`)).rows) {
  if (!columnas.has(f.t)) columnas.set(f.t, new Set());
  columnas.get(f.t).add(f.c);
}
const funciones = (await db.query(`
  select p.oid, n.nspname||'.'||p.proname nombre, p.prosrc, coalesce(p.proargnames, '{}') nombres,
    (select array_agg(format_type(t, null) order by o) from unnest(coalesce(p.proallargtypes, p.proargtypes::oid[])) with ordinality x(t, o)) tipos,
    (select array_agg(tn.nspname||'.'||c.relname) from pg_trigger g join pg_class c on c.oid=g.tgrelid join pg_namespace tn on tn.oid=c.relnamespace where g.tgfoid=p.oid) disparadores
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
  where n.nspname in ('public','private') and l.lanname='plpgsql' order by 2`)).rows;

await db.exec(`set search_path = ''`);
let preparadas = 0;
const fallas = [];

for (const f of funciones) {
  const s = tokenizar(f.prosrc).filter((t) => t.tipo !== 'espacio' && t.tipo !== 'comentario');
  const bajo = (i) => (s[i]?.tipo === 'palabra' ? s[i].texto.toLowerCase() : s[i]?.texto);
  const variables = new Map();
  f.nombres.forEach((n, i) => n && variables.set(n, { tipo: f.tipos?.[i] }));
  let inicioCuerpo = 0;
  for (let i = 0; i < s.length; i += 1) {
    if (bajo(i) !== 'declare') continue;
    let j = i + 1;
    while (j < s.length && bajo(j) !== 'begin') {
      let k = j;
      while (s[k] && s[k].texto !== ';') k += 1;
      const resto = s.slice(j + 1, k);
      const corte = resto.findIndex((t) => t.texto === ':=' || t.texto.toLowerCase() === 'default');
      const tipo = (corte < 0 ? resto : resto.slice(0, corte)).map((t) => t.texto).join('');
      const fila = tipo.match(/^(\w+\.\w+)%rowtype$/i);
      variables.set(bajo(j), fila ? { fila: fila[1] } : { tipo: tipo === 'record' || tipo.includes('%') ? null : tipo });
      j = k + 1;
    }
    inicioCuerpo = j;
  }
  for (let i = 0; i < s.length; i += 1) {
    if (bajo(i) === 'for' && bajo(i + 2) === 'in' && !variables.has(bajo(i + 1))) variables.set(bajo(i + 1), { tipo: 'integer' });
  }

  const profundidad = [];
  let nivel = 0;
  const pareja = new Map();
  const pila = [];
  s.forEach((t, i) => {
    if (t.texto === ')') { nivel -= 1; pareja.set(pila.pop(), i); }
    profundidad[i] = nivel;
    if (t.texto === '(') { nivel += 1; pila.push(i); }
  });

  const rangos = [];
  const ARRANQUE = ['select', 'insert', 'update', 'delete', 'with', 'perform'];
  for (let i = inicioCuerpo; i < s.length; i += 1) {
    if (profundidad[i] !== 0 || !ARRANQUE.includes(bajo(i))) continue;
    const previo = bajo(i - 1);
    if (!(i === 0 || [';', 'then', 'loop', 'begin', 'else', 'query', 'in'].includes(previo))) continue;
    if (previo === 'in' && bajo(i - 3) !== 'for') continue;
    // "then"/"else" dentro de una expresión CASE no inicia sentencia.
    if (rangos.length && i < rangos[rangos.length - 1][1]) continue;
    let fin = i;
    while (fin < s.length && !(profundidad[fin] === 0 && (s[fin].texto === ';' || (previo === 'in' && bajo(fin) === 'loop')))) fin += 1;
    rangos.push([i, fin]);
  }
  for (let i = inicioCuerpo; i < s.length; i += 1) {
    if (s[i].texto !== '(' || !['select', 'with'].includes(bajo(i + 1))) continue;
    if (rangos.some(([a, b]) => i >= a && i < b)) continue;
    rangos.push([i + 1, pareja.get(i)]);
  }

  for (let i = 0; i < s.length; i += 1) {
    const v = variables.get(bajo(i));
    if (v?.fila && s[i + 1]?.texto === '.' && !columnas.get(v.fila)?.has(bajo(i + 2))) {
      fallas.push([f.nombre, `campo inexistente ${s[i].texto}.${s[i + 2].texto} (${v.fila})`]);
    }
    if (['new', 'old'].includes(bajo(i)) && s[i + 1]?.texto === '.' && f.disparadores) {
      if (!f.disparadores.some((t) => columnas.get(t)?.has(bajo(i + 2)))) {
        fallas.push([f.nombre, `campo inexistente ${s[i].texto}.${s[i + 2].texto} en ${f.disparadores}`]);
      }
    }
  }

  for (const [a, b] of rangos) {
    const piezas = [];
    for (let i = a; i < b; i += 1) {
      const palabra = bajo(i);
      if (palabra === 'perform') { piezas.push('select'); continue; }
      if (palabra === 'into' && bajo(i - 1) !== 'insert') {
        if (bajo(i + 1) === 'strict') i += 1;
        i += 1;
        while (s[i + 1]?.texto === ',' || s[i + 1]?.texto === '.') i += 2;
        continue;
      }
      const previo = s[i - 1]?.texto;
      if (['new', 'old'].includes(palabra) && s[i + 1]?.texto === '.' && f.disparadores) { piezas.push('null'); i += 2; continue; }
      const v = s[i].tipo === 'palabra' && previo !== '.' && bajo(i - 1) !== 'as' ? variables.get(palabra) : null;
      if (v && s[i + 1]?.texto === '.') { piezas.push('null'); i += 2; continue; }
      if (v && s[i + 1]?.texto !== '(') {
        // En listas de columnas de INSERT/ON CONFLICT el nombre es una columna.
        const enLista = ['(', ','].includes(previo) && [',', ')'].includes(s[i + 1]?.texto) && !v.tipo;
        if (!enLista) { piezas.push(v.tipo ? `(null::${v.tipo})` : 'null'); continue; }
      }
      piezas.push(s[i].texto);
    }
    const consulta = piezas.join(' ');
    try {
      await db.exec(`prepare revisa as ${consulta}`);
      await db.exec('deallocate revisa');
      preparadas += 1;
    } catch (error) {
      fallas.push([f.nombre, error.message, consulta.slice(0, 170)]);
    }
  }
}
console.log('funciones', funciones.length, 'consultas correctas', preparadas, 'avisos', fallas.length);
for (const x of fallas) console.log(x.join(' | '));
process.exit(0);
