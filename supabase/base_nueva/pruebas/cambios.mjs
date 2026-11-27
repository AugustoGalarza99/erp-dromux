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

/* ---------- 004: documentos de más de 40 ítems ---------- */

const leerCambio = (ruta) => readFileSync(fileURLToPath(new URL(`../cambios/${ruta}`, import.meta.url)), 'utf8');
const largo = '004_lineas_de_documentos_largos.sql';
// Deshacer y rehacer va antes de crear documentos largos: con ellos, deshacer se niega a propósito.
await db.exec(leerCambio(`deshacer/${largo}`));
await db.exec(leerCambio(largo));
espera((await db.query(leerCambio(`comprobaciones/${largo}`))).rows.length === 2, `comprobación ${largo}`);

await db.query(`update public.empresas
  set modulos = jsonb_set(jsonb_set(modulos,'{compras}','true'),'{produccion}','true') where id=$1`, [empresa]);
await como(jefa);
const muchos = [];
for (let n = 1; n <= 45; n++) {
  const item = await nuevoItem(`L${n}`, 'materia_prima', '10');
  await bien(...mover(item, 'ingreso', 5), `004: ingreso ${n}`);
  muchos.push(item);
}
const lineasRemito = J(muchos.map((item_id) => ({ item_id, warehouse_id: deposito, quantity: 1 })));
const remitoLargo = await bien("select public.issue_delivery_note($1,'materiales',null,'sector','remito largo',$2::jsonb,$3)",
  [empresa, lineasRemito, randomUUID()], '004: remito de 45 ítems');
espera(Number(await valor('select count(*) from public.stock_remitos_lineas where remito_id=$1', [remitoLargo])) === 45, '004: guarda las 45 líneas');
espera(await saldo(muchos[44]) === 4, '004: descuenta una sola vez el ítem 45');

await db.exec('reset role');
const proveedor = await valor("insert into public.compras_proveedores(empresa_id,nombre) values ($1,'Proveedor largo') returning id", [empresa]);
for (const item_id of muchos) {
  await db.query('insert into public.compras_proveedores_items(empresa_id,proveedor_id,item_id,precio_unitario) values ($1,$2,$3,3.5)',
    [empresa, proveedor, item_id]);
}
await como(jefa);
const compra = await bien('select public.create_purchase_order_once($1,$2,$3,$4::jsonb,$5)',
  [empresa, proveedor, 'compra larga', J(muchos.map((item_id) => ({ item_id, quantity: '2', unit_price: '3.50' }))), randomUUID()],
  '004: orden de compra de 45 ítems');
espera(Number(await valor('select count(*) from public.compras_ordenes_lineas where orden_compra_id=$1', [compra])) === 45, '004: guarda las 45 líneas de compra');

await db.exec('reset role');
let seNego = false;
try { await db.exec(leerCambio(`deshacer/${largo}`)); } catch { seNego = true; await db.exec('rollback'); }
espera(seNego, '004: deshacer se niega si hay documentos largos');

/* ---------- 005: recalcular reservas solo del material movido ---------- */

const rapido = '005_reservas_por_componente.sql';
// Las pruebas de deshacer de arriba reaplican el 003: se vuelve a poner el 005 encima.
await db.exec('reset role');
await db.exec(leerCambio(rapido));
await como(jefa);
const deposito2 = await valor(
  "insert into public.stock_depositos(empresa_id,codigo,nombre) values ($1,'planta2','Planta 2') returning id", [empresa]);
const itemEspecial = (codigo, tipo, extras) => bien(
  'select public.save_item_with_cost($1,null,$2::jsonb,null,false)',
  [empresa, J({ codigo, nombre: `Ítem ${codigo}`, tipo, unit_id: unidad, category_id: null, codigo_barras: '', descripcion: '', stock_minimo: '0', seguir_lotes: 'false', stock_infinito: 'false', costo_referencia_ars: '10', precio_venta_ars: '', activo: 'true', ...extras })],
  `005: ítem ${codigo}`);
const conLotes = await itemEspecial('R-LOTE', 'materia_prima', { seguir_lotes: 'true' });
const sinLimite = await itemEspecial('R-INF', 'materia_prima', { stock_infinito: 'true' });
const comunA = await itemEspecial('R-A', 'materia_prima', {});
const comunB = await itemEspecial('R-B', 'insumo', {});
const producto = await itemEspecial('R-PT', 'producto_terminado', {});
const operar = (item, dep, tipo, cantidad, lote = null, vence = null, destino = null) => [
  'select public.post_stock_operation($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::date)',
  [empresa, item, dep, destino, tipo, cantidad, 'movimiento de prueba', randomUUID(), lote, vence]];
await bien(...operar(conLotes, deposito, 'ingreso', 30, 'VENCIDO', '2020-01-01'), '005: lote vencido');
await bien(...operar(conLotes, deposito, 'ingreso', 12, 'VIGENTE', '2099-01-01'), '005: lote vigente');
await bien(...operar(conLotes, deposito2, 'ingreso', 8, 'OTRO', null), '005: lote sin vencimiento');
await bien(...operar(comunA, deposito, 'ingreso', 25), '005: ingreso A central');
await bien(...operar(comunA, deposito2, 'ingreso', 10), '005: ingreso A planta');
await bien(...operar(comunB, deposito, 'ingreso', 6), '005: ingreso B');
await bien('select public.save_production_formula_v2($1,$2,10,$3::jsonb,false,1)',
  [empresa, producto, J([conLotes, sinLimite, comunA, comunB].map((component_id) => ({ component_id, quantity: 10 })))], '005: fórmula');
const ordenDe = (item, vence) => bien(
  "select public.create_production_work_order($1,$2,10,$3,$4::date,'orden de prueba',$5,null,'{}'::jsonb)",
  [empresa, item, deposito, vence, randomUUID()], '005: orden');
const urgente = await ordenDe(producto, hoy);
const media = await ordenDe(producto, '2098-01-01');
const lejana = await ordenDe(producto, '2099-01-01');

async function foto() {
  await db.exec('reset role');
  const reservas = await filas(`select orden_id, componente_id, cantidad_reservada::text c
    from public.produccion_ordenes_reservas where empresa_id=$1 order by 1,2`, [empresa]);
  const lugares = await filas(`select orden_id, componente_id, deposito_id, lote_id, cantidad::text c
    from public.produccion_reservas_ubicaciones where empresa_id=$1 order by 1,2,3,4`, [empresa]);
  return J([reservas, lugares]);
}
// Lo que dejó el recálculo por material debe ser igual a recalcular todo de nuevo.
async function igualAlCompleto(texto) {
  const parcial = await foto();
  await db.query('select private.rebalance_production_reservations($1)', [empresa]);
  espera(parcial === await foto(), `005: equivalencia tras ${texto}`);
  await como(jefa);
}
await igualAlCompleto('crear órdenes');
const dada = await bien(...entregar(media, comunA, 4), '005: entrega');
await igualAlCompleto('entregar');
await bien('select public.return_production_material($1,$2,$3,2,$4,$5)',
  [empresa, media, dada, 'sobrante de prueba', randomUUID()], '005: devolución');
await igualAlCompleto('devolver');
await bien('select public.issue_production_material($1,$2,$3,$4,$5,5,$6,$7)',
  [empresa, urgente, conLotes, deposito, 'VIGENTE', 'entrega de lote', randomUUID()], '005: entrega con lote');
await igualAlCompleto('entregar un lote');
await bien(...operar(comunB, deposito, 'ingreso', 40), '005: nuevo ingreso');
await igualAlCompleto('ingresar');
await bien(...operar(comunB, deposito, 'transferencia', 7, null, null, deposito2), '005: transferencia');
await igualAlCompleto('transferir');
await bien(...operar(comunB, deposito, 'egreso', 3), '005: egreso libre');
await igualAlCompleto('retirar');
await falla(...operar(comunA, deposito, 'egreso', 20), '005: no se retira lo reservado', null);
await falla(...operar(conLotes, deposito, 'egreso', 1, 'VENCIDO'), '005: no sale un lote vencido', null);
await bien("select public.issue_delivery_note($1,'produccion',$2,'sector',$3,$4::jsonb,$5)",
  [empresa, lejana, 'remito de prueba', J([{ item_id: comunB, warehouse_id: deposito, quantity: 2 },
    { item_id: sinLimite, warehouse_id: deposito, quantity: 5 }]), randomUUID()], '005: remito mixto');
await igualAlCompleto('emitir remito');
await bien('select public.return_production_material($1,$2,$3,2,$4,$5)',
  [empresa, media, dada, 'devuelve el resto', randomUUID()], '005: devolución total');
await bien('select public.cancel_production_job($1,$2,$3)', [empresa, media, 'cancela el administrador'], '005: cancelar');
await igualAlCompleto('cancelar');

// Reconstruir material por material, en cualquier orden, da lo mismo que recalcular todo.
await db.exec('reset role');
await db.query('select private.rebalance_production_reservations($1)', [empresa]);
const completo = await foto();
await db.query('delete from public.produccion_reservas_ubicaciones where empresa_id=$1', [empresa]);
await db.query('update public.produccion_ordenes_reservas set cantidad_reservada=0 where empresa_id=$1', [empresa]);
const componentes = await filas(`select componente_id from public.produccion_ordenes_reservas
  where empresa_id=$1 group by componente_id order by random()`, [empresa]);
for (const { componente_id } of componentes) {
  await db.query('select private.rebalance_production_reservations_item($1,$2)', [empresa, componente_id]);
}
espera(completo === await foto(), '005: reconstrucción material por material');
await como(operario);
await falla('select private.rebalance_production_reservations_item($1,$2)', [empresa, comunA], '005: nadie la llama directo');

// Escala: remito grande y comparación de tiempos con y sin el cambio.
await como(jefa);
const grandes = [];
for (let n = 1; n <= 200; n++) {
  const item = await itemEspecial(`G${n}`, 'materia_prima', {});
  await bien(...operar(item, deposito, 'ingreso', 100), `005: ingreso G${n}`);
  grandes.push(item);
}
const productoGrande = await itemEspecial('G-PT', 'producto_terminado', {});
await bien('select public.save_production_formula_v2($1,$2,10,$3::jsonb,false,1)',
  [empresa, productoGrande, J(grandes.map((component_id) => ({ component_id, quantity: 3 })))], '005: fórmula grande');
const ordenesGrandes = [await ordenDe(productoGrande, hoy), await ordenDe(productoGrande, '2099-01-01')];
async function remitoDe(orden, cuantos) {
  // La base en memoria no actualiza estadísticas sola y conserva planes armados con tablas casi
  // vacías: se renuevan para que la medición sea comparable.
  await db.exec('reset role; analyze; discard plans');
  await como(jefa);
  const inicio = performance.now();
  await bien("select public.issue_delivery_note($1,'produccion',$2,'sector',$3,$4::jsonb,$5)",
    [empresa, orden, 'remito grande', J(grandes.slice(0, cuantos).map((item_id) => ({ item_id, warehouse_id: deposito, quantity: 1 }))), randomUUID()],
    `005: remito de ${cuantos}`);
  return Math.round(performance.now() - inicio);
}
const conCambio = await remitoDe(ordenesGrandes[0], 40);
await db.exec('reset role');
await db.exec(leerCambio(`deshacer/${rapido}`));
const sinCambio = await remitoDe(ordenesGrandes[1], 40);
await db.exec('reset role');
await db.exec(leerCambio(rapido));
const verificado = await db.query(leerCambio(`comprobaciones/${rapido}`));
espera(verificado.rows.length === 4 && verificado.rows.every((r) => r.correcto === true), `comprobación ${rapido}`);
const completoGrande = await remitoDe(ordenesGrandes[1], 200);
await igualAlCompleto('un remito de 200 ítems');
espera(conCambio * 4 < sinCambio, '005: al menos 4 veces más rápido');
console.log(`remito de 40 ítems: con el cambio ${conCambio} ms, sin él ${sinCambio} ms; 200 ítems con el cambio ${completoGrande} ms`);

/* ---------- 006 a 010: alta única, envasado, soporte y funciones cerradas ---------- */

const posteriores = ['006_ajustes_una_empresa_por_cuenta.sql', '007_produccion_conservar_envasado.sql',
  '008_soporte_acceso_completo.sql', '009_soporte_nombre_visible.sql', '010_ajustes_funciones_cerradas.sql'];
// Las pruebas de deshacer de arriba reaplican cambios anteriores: se vuelven a poner estos encima.
await db.exec('reset role');
for (const nombre of posteriores) await db.exec(leerCambio(nombre));
for (const nombre of [...posteriores].reverse()) await db.exec(leerCambio(`deshacer/${nombre}`));
for (const nombre of posteriores) {
  await db.exec(leerCambio(nombre));
  const resultado = await db.query(leerCambio(`comprobaciones/${nombre}`));
  espera(resultado.rows.length > 0 && resultado.rows.every((r) => r.correcto === true), `comprobación ${nombre}`);
}

const [soporte, nueva, comun] = [randomUUID(), randomUUID(), randomUUID()];
await db.query(`insert into auth.users(id,email,raw_user_meta_data) values
  ($1,'dueno@ejemplo.test','{"full_name":"Dueño Real"}'), ($2,'nueva@ejemplo.test','{}'), ($3,'comun@ejemplo.test','{}')`,
  [soporte, nueva, comun]);

// 006
await como(jefa);
await falla("select public.create_company('Otra de la jefa')", [], '006: quien ya tiene empresa no crea otra', 'P0001');
await como(planta);
await falla("select public.create_company('Del operario')", [], '006: un miembro no crea empresas', 'P0001');
await db.exec('reset role');
await db.query('update public.empresas_usuarios set activo=false where usuario_id=$1', [sinSaldos]);
await como(sinSaldos);
await falla("select public.create_company('Inactivo')", [], '006: un vínculo inactivo tampoco permite crear', 'P0001');
await como(nueva);
const empresaNueva = await bien("select public.create_company('Cuenta nueva')", [], '006: una cuenta sin empresa crea la suya');
await db.exec('reset role');
await db.query('update public.empresas set activo=false where id=$1', [empresaNueva]);
await como(nueva);
await falla("select public.create_company('Segunda')", [], '006: con la empresa suspendida no crea otra', 'P0001');

// 007
await db.exec('reset role');
await db.query(`update public.produccion_ordenes
  set opciones_trabajo='{"packaging":[],"observations":{},"unpackaged_quantity":3}' where id=$1`, [ordenA]);
await como(jefa);
const antesDe = (await valor('select public.list_production_jobs($1)', [empresa]))
  .find((o) => o.id === ordenA)?.details_updated_at;
await bien("select public.save_production_work_details($1,$2,'{}'::jsonb,'{}'::jsonb,$3)",
  [empresa, ordenA, antesDe], '007: guardar controles en una orden terminada');
await db.exec('reset role');
espera(await valor("select opciones_trabajo->>'unpackaged_quantity' from public.produccion_ordenes where id=$1", [ordenA]) === '3',
  '007: se conserva lo que quedó sin envasar');

// 008
await como(soporte);
await bien("select public.create_company('Empresa propia de soporte')", [], '008: soporte tiene su empresa');
await db.exec('reset role');
const propia = await valor('select empresa_id from public.empresas_usuarios where usuario_id=$1', [soporte]);
await db.query(`update public.empresas set modulos='{"stock":true,"produccion":true,"compras":true,"ventas":true,"finanzas":true,"reportes":true}'
  where id=$1`, [empresa]);
await como(soporte);
await falla(...mover(mp1, 'ingreso', 1), '008: sin ser operador ni sesión no mueve stock');
await falla('select public.begin_support_session($1,$2)', [empresa, 'motivo de prueba largo'], '008: no operador no abre sesión');
await db.exec('reset role');
await db.query('insert into private.soporte_operadores(usuario_id) values ($1)', [soporte]);
await como(soporte);
await falla(...mover(mp1, 'ingreso', 1), '008: operador sin sesión no mueve stock');
await falla('select public.production_formula_cost($1,$2)', [empresa, pt1], '008: operador sin sesión no ve costos', null);
await falla('select public.begin_support_session($1,$2)', [empresa, 'corto'], '008: exige motivo');
await falla('select public.begin_support_session($1,$2)', [propia, 'motivo de prueba largo'], '008: no abre sesión en su propia empresa');
await bien('select public.begin_support_session($1,$2)', [empresa, 'ayuda pedida por el cliente'], '008: abre sesión');
await db.exec('reset role');
const horas = Number(await valor('select extract(epoch from vence_en - now())/3600 from private.soporte_sesiones where usuario_id=$1', [soporte]));
espera(horas > 3.9 && horas <= 4, '008: la sesión dura 4 horas');
await como(soporte);
await bien(...mover(mp1, 'ingreso', 7), '008: con sesión mueve stock');
const deSoporte = await nuevaOrden();
await bien(...entregar(deSoporte, mp1, 1), '008: con sesión entrega');
await bien('select public.production_formula_cost($1,$2)', [empresa, pt1], '008: con sesión ve costos');
await bien('select public.create_company_role($1,$2,$3,$4::jsonb)',
  [empresa, 'Por soporte', 'porsoporte', J([{ resource: 'inicio', action: 'ver' }])], '008: con sesión administra roles');
const miembros = J(await filas('select * from public.company_members($1)', [empresa]));
espera(!miembros.includes(soporte) && !miembros.includes('dueno@ejemplo.test'), '008: soporte no figura entre los usuarios');
await db.exec('reset role');
espera(await valor('select autor_id from public.produccion_ordenes where id=$1', [deSoporte]) === soporte, '008: la base guarda el autor real');
await db.query("update public.empresas set modulos = jsonb_set(modulos,'{stock}','false') where id=$1", [empresa]);
await como(soporte);
await falla(...mover(mp1, 'ingreso', 1), '008: respeta los módulos de la empresa');
await db.exec('reset role');
await db.query("update public.empresas set modulos = jsonb_set(modulos,'{stock}','true') where id=$1", [empresa]);
await como(comun);
await falla('select public.begin_support_session($1,$2)', [empresa, 'quiero entrar igual'], '008: un usuario común no abre sesión');
await falla(...mover(mp1, 'ingreso', 1), '008: un usuario común no mueve stock ajeno');
await falla('insert into private.soporte_operadores(usuario_id) values ($1)', [comun], '008: nadie se agrega como soporte', null);

// 009
await como(soporte);
const pedido = await bien("select public.create_purchase_request($1,'pedido de soporte',null,'normal',$2::jsonb,$3)",
  [empresa, J([{ item_id: mp1, quantity: '1', note: '' }]), randomUUID()], '009: pedido de soporte');
const vendible = await bien('select public.save_item_with_cost($1,null,$2::jsonb,null,false)',
  [empresa, J({ codigo: 'PV1', nombre: 'Producto para vender', tipo: 'producto_terminado', unit_id: unidad, category_id: null, codigo_barras: '', descripcion: '', stock_minimo: '0', seguir_lotes: 'false', stock_infinito: 'false', costo_referencia_ars: '10', precio_venta_ars: '100', activo: 'true' })],
  '009: producto con precio');
const presupuesto = await bien(`select public.create_quote($1,null,'Interesado de prueba','','','','',current_date + 5,'',true,$2::jsonb,$3)`,
  [empresa, J([{ item_id: vendible, quantity: 1 }]), randomUUID()], '009: presupuesto de soporte');
const lista = await bien(`select public.save_price_list($1,null,'Lista de prueba','ARS',null,null,false,null,0,0,'',false)`,
  [empresa], '009: lista de precios');
await bien("select public.set_price_list_item($1,$2,$3,'fijo',120,'precio de prueba')",
  [empresa, lista, vendible], '009: precio de soporte');
await como(jefa);
const auditoria = J(await filas('select * from public.access_audit_events_list($1)', [empresa]));
espera(auditoria.includes('Soporte Dromux') && !auditoria.includes('dueno@ejemplo.test'), '009: auditoría sin correo de soporte');
espera(auditoria.includes('jefa@ejemplo.test') || !auditoria.includes('null'), '009: la auditoría sigue mostrando a la empresa');
const historial = J(await filas('select * from public.erp_price_list_history($1,$2,null)', [empresa, lista]));
espera(historial.includes('Soporte Dromux') && !historial.includes('Dueño Real'), '009: historial de precios sin nombre real');
await db.exec('reset role');
espera(await valor('select solicitante_nombre from public.compras_pedidos where id=$1', [pedido]) === 'Soporte Dromux', '009: pedido firmado como soporte');
espera(await valor('select creado_por_nombre from public.ventas_presupuestos where id=$1', [presupuesto]) === 'Soporte Dromux', '009: presupuesto firmado como soporte');
espera(await valor('select creado_por from public.ventas_presupuestos where id=$1', [presupuesto]) === soporte, '009: autor real guardado');
await como(jefa);
const propio = await bien("select public.create_purchase_request($1,'pedido de la jefa',null,'normal',$2::jsonb,$3)",
  [empresa, J([{ item_id: mp1, quantity: '1', note: '' }]), randomUUID()], '009: pedido de la empresa');
await db.exec('reset role');
espera(await valor('select solicitante_nombre from public.compras_pedidos where id=$1', [propio]) === 'Jefa de Prueba', '009: los demás conservan su nombre');

// Cerrar la sesión corta el acceso sin esperar al vencimiento.
await como(soporte);
await bien('select public.end_support_session()', [], '008: cierra la sesión');
await falla(...mover(mp1, 'ingreso', 1), '008: tras cerrar la sesión no mueve stock');
await bien('select public.begin_support_session($1,$2)', [empresa, 'vuelve a entrar'], '008: vuelve a abrir');
await como(comun);
await bien('select public.end_support_session()', [], '008: cerrar no afecta a otros');
await como(soporte);
await bien(...mover(mp1, 'ingreso', 1), '008: la sesión de soporte sigue abierta');
await db.exec('reset role');
espera(await valor("select has_function_privilege('anon','public.end_support_session()','execute')") === false,
  '008: sin sesión no se puede llamar');
// Quien figura como usuario (aunque esté suspendido) no entra como soporte.
const rolSuspendido = await valor('select id from public.ajustes_roles where empresa_id=$1 limit 1', [empresaNueva]);
await db.query('update public.empresas set activo=true where id=$1', [empresaNueva]);
await db.query('insert into public.empresas_usuarios(empresa_id,usuario_id,rol_id,activo) values ($1,$2,$3,false)',
  [empresaNueva, soporte, rolSuspendido]);
await como(soporte);
await falla('select public.begin_support_session($1,$2)', [empresaNueva, 'intento suspendido'], '008: un usuario suspendido no entra como soporte');

// Vencimiento y corte del acceso.
await db.exec('reset role');
await db.query("update private.soporte_sesiones set vence_en = now() - interval '1 minute' where usuario_id=$1", [soporte]);
await como(soporte);
await falla(...mover(mp1, 'ingreso', 1), '008: la sesión vencida no sirve');
await bien('select public.begin_support_session($1,$2)', [empresa, 'segunda ayuda pedida'], '008: abre otra sesión');
await db.exec('reset role');
await db.query('update private.soporte_operadores set activo=false where usuario_id=$1', [soporte]);
await como(soporte);
await falla(...mover(mp1, 'ingreso', 1), '008: cortar al operador corta el acceso');

// 010
await db.exec('reset role');
await db.exec("create function public.prueba_cerrada() returns int language sql as 'select 1'");
espera(await valor("select has_function_privilege('anon','public.prueba_cerrada()','execute') or has_function_privilege('authenticated','public.prueba_cerrada()','execute')") === false,
  '010: una función nueva no queda abierta');
await db.exec('drop function public.prueba_cerrada()');

console.log(`comprobaciones correctas ${ok}, con falla ${fallas.length}`);
console.log(fallas.join('\n'));
await db.close();
process.exit(fallas.length ? 1 : 0);
