// Comprueba en la base local los cambios posteriores a la línea base (carpeta cambios/).
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { crearBase } from './base.mjs';

const db = await crearBase({ mostrar: false });
const [jefa, operario, ajeno, sinPermiso] = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values
  ($1,'jefa@ejemplo.test','{"full_name":"Jefa de Prueba"}'), ($2,'operario@ejemplo.test','{}'),
  ($3,'ajeno@ejemplo.test','{}'), ($4,'sinpermiso@ejemplo.test','{}')`, [jefa, operario, ajeno, sinPermiso]);

let ok = 0;
const fallas = [];
const como = async (usuario) => {
  await db.exec(`reset role; set request.jwt.claim.sub = '${usuario}'; set role authenticated;`);
};
const filas = async (sql, p = []) => (await db.query(sql, p)).rows;
const valor = async (sql, p = []) => Object.values((await filas(sql, p))[0] ?? {})[0];
function espera(condicion, texto) {
  if (condicion) ok += 1;
  else fallas.push(texto);
}

await como(jefa);
const empresa = await valor("select public.create_company('Empresa A')");
await db.query("insert into public.stock_depositos(empresa_id,codigo,nombre) values ($1,'central','Central')", [empresa]);
await db.query(`insert into public.stock_unidades(empresa_id,codigo,nombre,simbolo,magnitud)
  values ($1,'kg','Kilo','kg','masa')`, [empresa]);
await como(ajeno);
const otra = await valor("select public.create_company('Empresa B')");

await db.exec('reset role');
espera(await valor('select nombre from public.ajustes_perfiles where id=$1', [jefa]) === 'Jefa de Prueba', '002: nombre completo');
espera(await valor('select nombre from public.ajustes_perfiles where id=$1', [ajeno]) === 'ajeno', '002: nombre desde el correo');

async function miembro(usuario, codigo, recursos) {
  const rol = await valor('insert into public.ajustes_roles(empresa_id,codigo,nombre) values ($1,$2,$2) returning id', [empresa, codigo]);
  for (const recurso of recursos) {
    await db.query("insert into public.ajustes_roles_permisos(empresa_id,rol_id,recurso,accion) values ($1,$2,$3,'ver')", [empresa, rol, recurso]);
  }
  await db.query('insert into public.empresas_usuarios(empresa_id,usuario_id,rol_id) values ($1,$2,$3)', [empresa, usuario, rol]);
}
await miembro(operario, 'operario', ['inicio', 'produccion_ordenes']);
await miembro(sinPermiso, 'mirador', ['inicio']);

const cuenta = async (tabla) => Number(await valor(`select count(*) from public.${tabla} where empresa_id=$1`, [empresa]));

await como(operario);
espera(await cuenta('stock_depositos') === 1, '001: el operario de producción lee depósitos');
espera(await cuenta('stock_unidades') === 1, '001: el operario de producción lee unidades');
try {
  await db.query("insert into public.stock_depositos(empresa_id,codigo,nombre) values ($1,'x1','X')", [empresa]);
  espera(false, '001: el operario no debe crear depósitos');
} catch { espera(true, ''); }
const cambiados = await filas('update public.stock_depositos set nombre=$2 where empresa_id=$1 returning id', [empresa, 'Otro']);
espera(cambiados.length === 0, '001: el operario no debe editar depósitos');

await como(sinPermiso);
espera(await cuenta('stock_depositos') === 0, '001: sin permiso operativo no lee depósitos');
espera(await cuenta('stock_unidades') === 0, '001: sin permiso operativo no lee unidades');

await como(ajeno);
espera(await cuenta('stock_depositos') === 0, '001: otra empresa no lee depósitos');
espera(await cuenta('stock_unidades') === 0, '001: otra empresa no lee unidades');
espera(Boolean(otra), 'empresa B creada');

/* ---------- 003: el operario avanza órdenes sin permiso general de stock ---------- */

const J = JSON.stringify;
const hoy = new Date().toISOString().slice(0, 10);
async function bien(sql, p, texto) {
  try {
    const resultado = await valor(sql, p);
    ok += 1;
    return resultado;
  } catch (error) {
    fallas.push(`${texto}: ${error.message}`);
    return null;
  }
}
// codigo null: alcanza con que falle.
async function falla(sql, p, texto, codigo = '42501') {
  try {
    await valor(sql, p);
    fallas.push(`${texto}: se permitió`);
  } catch (error) {
    if (codigo && error.code !== codigo) fallas.push(`${texto}: ${error.code} ${error.message}`);
    else ok += 1;
  }
}

const [planta, superv, sinSaldos] = [randomUUID(), randomUUID(), randomUUID()];
await db.exec('reset role');
await db.query(`insert into auth.users(id,email) values ($1,'planta@ejemplo.test'),
  ($2,'superv@ejemplo.test'), ($3,'sinsaldos@ejemplo.test')`, [planta, superv, sinSaldos]);
await como(jefa);
const deposito = await valor("select id from public.stock_depositos where empresa_id=$1", [empresa]);
const unidad = await valor("select id from public.stock_unidades where empresa_id=$1", [empresa]);
const nuevoItem = (codigo, tipo, costo) => bien(
  'select public.save_item_with_cost($1,null,$2::jsonb,null,false)',
  [empresa, J({ codigo, nombre: `Ítem ${codigo}`, tipo, unit_id: unidad, category_id: null, codigo_barras: '', descripcion: '', stock_minimo: '0', seguir_lotes: 'false', stock_infinito: 'false', costo_referencia_ars: costo, precio_venta_ars: '', activo: 'true' })],
  `ítem ${codigo}`);
const mp1 = await nuevoItem('MP1', 'materia_prima', '100');
const mp2 = await nuevoItem('MP2', 'materia_prima', '50');
const in1 = await nuevoItem('IN1', 'insumo', '10');
const pt1 = await nuevoItem('PT1', 'producto_terminado', '');
const mover = (item, tipo, cantidad) => ['select public.post_stock_operation($1,$2,$3,null,$4,$5,$6,$7,null,null)',
  [empresa, item, deposito, tipo, cantidad, 'movimiento de prueba', randomUUID()]];
for (const [item, cantidad] of [[mp1, 100], [mp2, 20], [in1, 50]]) await bien(...mover(item, 'ingreso', cantidad), 'ingreso');
await bien('select public.save_production_formula_v2($1,$2,10,$3::jsonb,false,1)',
  [empresa, pt1, J([{ component_id: mp1, quantity: 5 }, { component_id: in1, quantity: 2 }])], 'fórmula');
const nuevaOrden = () => bien(
  "select public.create_production_work_order($1,$2,10,$3,$4::date,'orden de prueba',$5,null,'{}'::jsonb)",
  [empresa, pt1, deposito, hoy, randomUUID()], 'crear orden');
const ordenA = await nuevaOrden();
const ordenB = await nuevaOrden();

async function conRol(usuario, codigo, permisos) {
  await como(jefa);
  const lista = Object.entries(permisos).flatMap(([resource, acciones]) => acciones.map((action) => ({ resource, action })));
  const rol = await bien('select public.create_company_role($1,$2,$3,$4::jsonb)', [empresa, codigo, codigo, J(lista)], `rol ${codigo}`);
  await db.exec('reset role');
  await db.query('insert into public.empresas_usuarios(empresa_id,usuario_id,rol_id) values ($1,$2,$3)', [empresa, usuario, rol]);
  return rol;
}
await conRol(planta, 'planta', { inicio: ['ver'], items: ['ver'], stock_saldos: ['ver'], produccion_ordenes: ['ver', 'editar'] });
await conRol(superv, 'superv', { inicio: ['ver'], items: ['ver'], stock_saldos: ['ver'], produccion_ordenes: ['ver', 'crear', 'editar', 'gestionar'] });
await conRol(sinSaldos, 'sinsaldos', { inicio: ['ver'], items: ['ver'], produccion_ordenes: ['ver', 'editar'] });

const saldo = async (item) => Number(await valor(
  'select coalesce(sum(cantidad),0) from public.stock_saldos where empresa_id=$1 and item_id=$2', [empresa, item]));
const entregar = (orden, item, cantidad, emp = empresa) => [
  'select public.issue_production_material($1,$2,$3,$4,null,$5,$6,$7)',
  [emp, orden, item, deposito, cantidad, 'entrega de prueba', randomUUID()]];

await como(planta);
await bien('select public.start_production_job($1,$2)', [empresa, ordenA], '003: el operario inicia');
const entrega = await bien(...entregar(ordenA, mp1, 5), '003: el operario entrega');
espera(await saldo(mp1) === 95, '003: la entrega descuenta stock');
await bien('select public.return_production_material($1,$2,$3,1,$4,$5)',
  [empresa, ordenA, entrega, 'sobrante de prueba', randomUUID()], '003: el operario devuelve');
espera(await saldo(mp1) === 96, '003: la devolución suma stock');
const cambiadaEn = (await valor('select public.list_production_jobs($1)', [empresa]))
  .find((o) => o.id === ordenA)?.details_updated_at ?? null;
await bien("select public.save_production_work_details($1,$2,'{}'::jsonb,'{}'::jsonb,$3)",
  [empresa, ordenA, cambiadaEn], '003: el operario carga controles');
await falla('select public.cancel_production_job($1,$2,$3)', [empresa, ordenB, 'motivo de prueba'], '003: el operario no cancela');
await falla(...entregar(ordenB, mp2, 1), '003: no entrega un insumo fuera de la fórmula');
await falla(...entregar(ordenB, mp1, 1000), '003: no entrega sin stock', null);
await falla(...mover(mp1, 'ingreso', 1), '003: el operario no ingresa stock a mano');
await falla(...mover(mp1, 'egreso', 1), '003: el operario no retira stock a mano');
await falla("select public.issue_delivery_note($1,'produccion',$2,'sector',$3,$4::jsonb,$5)",
  [empresa, ordenB, 'remito de prueba', J([{ item_id: mp1, warehouse_id: deposito, quantity: 1 }]), randomUUID()], '003: el operario no emite remitos');
await falla("select public.create_production_work_order($1,$2,10,$3,$4::date,'intento',$5,null,'{}'::jsonb)",
  [empresa, pt1, deposito, hoy, randomUUID()], '003: el operario no crea órdenes');
await falla("select public.post_production_run($1,$2,$3,1,$4,null,null,'intento','[]'::jsonb)",
  [empresa, pt1, randomUUID(), deposito], '003: el operario no registra fabricaciones sueltas');
const cierre = randomUUID();
const terminar = [
  'select public.finish_production_job_adjusted($1,$2,10,null,null,$3,$4,$5::jsonb,$6::jsonb)',
  [empresa, ordenA, 'cierre de prueba', cierre, J([
    { kind: 'entrega', component_id: mp1, warehouse_id: deposito, lot_code: null, quantity: 1, note: 'ajuste de prueba' },
    { kind: 'entrega', component_id: in1, warehouse_id: deposito, lot_code: null, quantity: 2, note: 'ajuste de prueba' },
  ]), '{}']];
const hecho = await bien(...terminar, '003: el operario termina con ajustes');
espera(await bien(...terminar, '003: repetir el cierre') === hecho, '003: repetir el cierre no duplica');
espera(await saldo(pt1) === 10, '003: ingresa lo fabricado una sola vez');
const vistas = await valor('select public.list_production_jobs($1)', [empresa]);
espera(vistas.every((o) => (o.production_job_events ?? []).every((e) => e.unit_cost === null)), '003: sin costos en las órdenes');
await falla('select costo_unitario from public.produccion_ordenes_eventos limit 1', [], '003: sin lectura directa de costos');
await falla(...entregar(ordenA, mp1, 1), '003: una orden terminada no admite insumos', null);

await como(sinSaldos);
await falla(...entregar(ordenB, mp1, 1), '003: sin ver saldos no entrega');
await como(ajeno);
await falla(...entregar(ordenB, mp1, 1), '003: otra empresa no entrega');
await como(planta);
await falla(...entregar(ordenB, mp1, 1, otra), '003: el operario no opera en otra empresa');

for (const modulo of ['stock', 'produccion']) {
  await db.exec('reset role');
  await db.query("update public.empresas set modulos = jsonb_set(modulos, array[$2::text], 'false') where id=$1", [empresa, modulo]);
  await como(planta);
  await falla(...entregar(ordenB, mp1, 1), `003: con ${modulo} apagado no entrega`);
  await db.exec('reset role');
  await db.query("update public.empresas set modulos = jsonb_set(modulos, array[$2::text], 'true') where id=$1", [empresa, modulo]);
}

await como(superv);
await bien('select public.cancel_production_job($1,$2,$3)', [empresa, ordenB, 'cancela el supervisor'], '003: el supervisor cancela');
await como(jefa);
const ordenC = await nuevaOrden();
const remito = await bien("select public.issue_delivery_note($1,'produccion',$2,'sector',$3,$4::jsonb,$5)",
  [empresa, ordenC, 'remito de prueba', J([{ item_id: mp1, warehouse_id: deposito, quantity: 1 }]), randomUUID()], '003: el remito de producción sigue funcionando');
await bien('select public.void_delivery_note($1,$2,$3)', [empresa, remito, 'anulación de prueba'], '003: anular el remito sigue funcionando');
await bien('select public.cancel_production_job($1,$2,$3)', [empresa, ordenC, 'cancela el administrador'], '003: el administrador cancela');
await falla('select public.create_company_role($1,$2,$3,$4::jsonb)',
  [empresa, 'raro', 'raro', J([{ resource: 'produccion_formulas', action: 'gestionar' }])], '003: gestionar no existe en otras pantallas', null);
await db.exec('reset role');
espera(Number(await valor('select count(*) from public.stock_saldos where cantidad < 0')) === 0, '003: sin stock negativo');

/* ---------- 001 con el módulo apagado ---------- */

await db.query("update public.empresas set modulos = jsonb_set(modulos,'{produccion}','false') where id=$1", [empresa]);
await como(operario);
espera(await cuenta('stock_depositos') === 0, '001: con el módulo apagado no lee depósitos');

// Cada cambio se puede deshacer y volver a aplicar.
await db.exec('reset role');
for (const nombre of ['001_stock_lectura_depositos_unidades.sql', '002_ajustes_nombre_de_perfil.sql', '003_produccion_permisos_operario.sql']) {
  const leer = (ruta) => readFileSync(fileURLToPath(new URL(`../cambios/${ruta}`, import.meta.url)), 'utf8');
  await db.exec(leer(`deshacer/${nombre}`));
  await db.exec(leer(nombre));
  espera((await db.query(leer(`comprobaciones/${nombre}`))).rows.length > 0, `comprobación ${nombre}`);
}

console.log(`comprobaciones correctas ${ok}, con falla ${fallas.length}`);
console.log(fallas.join('\n'));
await db.close();
process.exit(fallas.length ? 1 : 0);
