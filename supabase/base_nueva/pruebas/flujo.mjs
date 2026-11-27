// Prueba de punta a punta sobre la base generada, con datos ficticios y permisos reales.
import { randomUUID } from 'node:crypto';
import { crearBase } from './base.mjs';

const db = await crearBase({ mostrar: false });
const admin = randomUUID();
const operario = randomUUID();
await db.query(`insert into auth.users(id,email) values ($1,'admin@ejemplo.test'),($2,'operario@ejemplo.test')`, [admin, operario]);

let ok = 0;
const fallas = [];
const como = async (usuario) => {
  await db.exec(`reset role; set request.jwt.claim.sub = '${usuario}'; set role authenticated;`);
};
const valor = async (sql, p = []) => Object.values((await db.query(sql, p)).rows[0] ?? {})[0];
const filas = async (sql, p = []) => (await db.query(sql, p)).rows;
async function paso(nombre, fn) {
  try {
    const r = await fn();
    ok += 1;
    return r;
  } catch (error) {
    fallas.push(`${nombre}: ${error.message}${error.where ? ' @ ' + error.where.split('\n')[0] : ''}`);
    return null;
  }
}
const espera = (condicion, texto) => { if (!condicion) throw new Error(`esperado: ${texto}`); };
const hoy = new Date().toISOString().slice(0, 10);
const J = JSON.stringify;

await como(admin);
const emp = await paso('crear empresa', () => valor(`select public.create_company('Fábrica de Prueba')`));
await paso('acceso', async () => {
  const [a] = await filas('select * from public.my_company_access()');
  espera(a.role_code === 'administrador' && a.company_modules.produccion === true, 'administrador con producción');
});
await db.exec('reset role');
await db.query(`update public.empresas set modulos = '{"stock":true,"produccion":true,"compras":true,"ventas":true,"finanzas":true,"reportes":true}' where id=$1`, [emp]);
await como(admin);

const unidad = await paso('unidad', () => valor(`insert into public.stock_unidades(empresa_id,codigo,nombre,simbolo,magnitud) values ($1,'kg','Kilo','kg','masa') returning id`, [emp]));
const categoria = await paso('categoría', () => valor(`insert into public.stock_categorias(empresa_id,codigo,nombre) values ($1,'gen','General') returning id`, [emp]));
const dep = await paso('depósito', () => valor(`insert into public.stock_depositos(empresa_id,codigo,nombre) values ($1,'cen','Central') returning id`, [emp]));
const dep2 = await paso('depósito 2', () => valor(`insert into public.stock_depositos(empresa_id,codigo,nombre) values ($1,'sec','Secundario') returning id`, [emp]));

const item = (codigo, tipo, costo) => paso(`ítem ${codigo}`, () => valor(
  `select public.save_item_with_cost($1,null,$2::jsonb,null,false)`,
  [emp, J({ codigo, nombre: `Ítem ${codigo}`, tipo, unit_id: unidad, category_id: categoria, codigo_barras: '', descripcion: '', stock_minimo: '1', seguir_lotes: 'false', stock_infinito: 'false', costo_referencia_ars: costo, precio_venta_ars: '', activo: 'true' })]));
const materia = await item('MP1', 'materia_prima', '100');
const insumo = await item('IN1', 'insumo', '10');
const producto = await item('PT1', 'producto_terminado', '');
const sinUso = await item('SU1', 'insumo', '5');

const mover = (it, tipo, cant, destino = null) => valor(
  `select public.post_stock_operation($1,$2,$3,$4,$5,$6,'movimiento de prueba',$7,null,null)`,
  [emp, it, dep, destino, tipo, cant, randomUUID()]);
await paso('ingreso materia', () => mover(materia, 'ingreso', 100));
await paso('ingreso insumo', () => mover(insumo, 'ingreso', 50));
await paso('transferencia', () => mover(insumo, 'transferencia', 5, dep2));
await paso('egreso', () => mover(insumo, 'egreso', 1));
await paso('detalle de ítem', () => valor('select public.get_item_detail($1,$2)', [emp, materia]));
await paso('resumen stock', async () => espera((await filas('select * from public.stock_summary($1)', [emp])).length > 0, 'filas'));

await paso('fórmula', () => valor('select public.save_production_formula_v2($1,$2,10,$3::jsonb,false,1)', [emp, producto, J([{ component_id: materia, quantity: 5 }, { component_id: insumo, quantity: 2 }])]));
await paso('costo de fórmula', () => valor('select public.production_formula_cost($1,$2)', [emp, producto]));
await paso('envase', () => valor(`select public.save_production_packaging_type($1,null,'Caja',5,$2,true)`, [emp, unidad]));
await paso('alcanza', () => valor('select public.erp_can_manufacture($1,$2,10)', [emp, producto]));
const orden = await paso('crear orden', () => valor(
  `select public.create_production_work_order($1,$2,10,$3,$4::date,'orden de prueba',$5,null,'{}'::jsonb)`,
  [emp, producto, dep, hoy, randomUUID()]));
await paso('listar órdenes', async () => {
  const lista = await valor('select public.list_production_jobs($1)', [emp]);
  espera(lista[0].status === 'pendiente' && lista[0].number === 1, 'orden 1 pendiente');
});
await paso('reservas', async () => espera((await filas('select * from public.produccion_ordenes_reservas where empresa_id=$1', [emp])).length === 2, 'dos reservas'));
await paso('iniciar orden', () => valor('select public.start_production_job($1,$2)', [emp, orden]));
const entrega = await paso('entregar material', () => valor(
  `select public.issue_production_material($1,$2,$3,$4,null,5,'entrega de prueba',$5)`, [emp, orden, materia, dep, randomUUID()]));
await paso('devolver material', () => valor(`select public.return_production_material($1,$2,$3,1,'devolución de prueba',$4)`, [emp, orden, entrega, randomUUID()]));
await paso('avisos de producción', () => filas('select * from public.erp_production_alerts($1)', [emp]));
await paso('tablero producción', () => valor('select public.erp_production_dashboard($1)', [emp]));
await paso('tablero general', () => valor('select public.erp_operational_dashboard($1)', [emp]));
await paso('terminar orden', () => valor(
  `select public.finish_production_job_adjusted($1,$2,10,null,null,'',$3,$4::jsonb,'{}'::jsonb)`,
  [emp, orden, randomUUID(), J([
    { kind: 'entrega', component_id: materia, warehouse_id: dep, lot_code: null, quantity: 1, note: 'ajuste' },
    { kind: 'entrega', component_id: insumo, warehouse_id: dep, lot_code: null, quantity: 2, note: 'ajuste' },
  ])]));
await paso('estadística', async () => espera((await filas('select * from public.production_output_summary($1,$2::date,$2::date)', [emp, hoy])).length === 1, 'una fila'));
await paso('fabricaciones', () => valor('select public.list_production_runs($1)', [emp]));
const plan = await paso('plan', () => valor(`select public.create_production_plan($1,$2,5,$3,$4::date,'plan',$5)`, [emp, producto, dep, hoy, randomUUID()]));
await paso('listar planes', () => valor('select public.list_production_plans($1)', [emp]));
await paso('reposición', () => filas('select * from public.erp_replenishment_forecast($1)', [emp]));
await paso('ítems de producción', () => valor('select public.list_production_items($1)', [emp]));

const remito = await paso('remito', () => valor(
  `select public.issue_delivery_note($1,'productos',null,'Depósito externo','remito de prueba',$2::jsonb,$3)`,
  [emp, J([{ item_id: producto, warehouse_id: dep, lot_code: null, quantity: 1 }]), randomUUID()]));
await paso('anular remito', () => valor(`select public.void_delivery_note($1,$2,'anulación de prueba')`, [emp, remito]));

await paso('vista de borrado (sin uso)', async () => {
  const v = await valor(`select public.cleanup_preview($1,'items',$2)`, [emp, sinUso]);
  espera(v.action === 'delete', `eliminar (${v.action})`);
  await valor(`select public.cleanup_record($1,'items',$2,'delete')`, [emp, sinUso]);
});
await paso('archivar y recuperar remito', async () => {
  await valor(`select public.cleanup_record($1,'remitos',$2,'archive')`, [emp, remito]);
  const lista = await valor(`select public.archived_records($1,'remitos')`, [emp]);
  espera(lista.count === 1, 'un archivado');
  await valor(`select public.restore_archived_record($1,'remitos',$2)`, [emp, remito]);
});
await paso('cancelar plan y borrarlo', async () => {
  await valor('select public.cancel_production_plan($1,$2)', [emp, plan]);
  const v = await valor(`select public.cleanup_preview($1,'planes',$2)`, [emp, plan]);
  await valor(`select public.cleanup_record($1,'planes',$2,$3)`, [emp, plan, v.action]);
});

const proveedor = await paso('proveedor', () => valor(`insert into public.compras_proveedores(empresa_id,nombre) values ($1,'Proveedor Uno') returning id`, [emp]));
await paso('cotización proveedor', () => valor(`select public.save_supplier_quote($1,$2,$3,120,'','ARS',null,0,null,true)`, [emp, proveedor, materia]));
await paso('catálogo proveedor', () => filas('select * from public.supplier_quote_catalog($1)', [emp]));
await paso('directorio proveedores', () => filas('select * from public.supplier_directory($1)', [emp]));
const pedido = await paso('pedido interno', () => valor(`select public.create_purchase_request($1,'pedido de prueba',null,'urgente',$2::jsonb,$3)`, [emp, J([{ item_id: materia, quantity: 3, note: '' }]), randomUUID()]));
const oc = await paso('orden de compra', () => valor(`select public.create_purchase_order_once($1,$2,'compra',$3::jsonb,$4)`, [emp, proveedor, J([{ item_id: materia, quantity: 10, unit_price: 120 }]), randomUUID()]));
await paso('recibir compra', () => valor(`select public.receive_purchase_order($1,$2,$3,'recepción',$4::jsonb)`, [emp, oc, randomUUID(), J([{ line_no: 1, quantity: 4, warehouse_id: dep, lot_code: null, expires_on: null }])]));
await paso('estado compra', async () => espera(await valor('select estado from public.compras_ordenes where id=$1', [oc]) === 'parcial', 'parcial'));
await paso('cuenta proveedor', () => valor('select public.supplier_account($1,$2,$3::date,$3::date)', [emp, proveedor, hoy]));
await paso('estadística compras', () => valor('select public.supplier_purchase_statistics($1,$2::date,$2::date)', [emp, hoy]));
await paso('pedidos a pagar', () => valor('select public.supplier_payable_orders($1,$2)', [emp, proveedor]));

const caja = await paso('cuenta de caja', () => valor(`select public.create_treasury_account($1,'Caja','caja',0)`, [emp]));
const cliente = await paso('cliente', () => valor(`insert into public.ventas_clientes(empresa_id,nombre) values ($1,'Cliente Uno') returning id`, [emp]));
const lista = await paso('lista de precios', () => valor(`select public.save_price_list($1,null,'General','ARS',null,null,true,null,null,0.01,'',false)`, [emp]));
await paso('precio en lista', () => valor(`select public.set_price_list_item($1,$2,$3,'fijo',500,'alta')`, [emp, lista, producto]));
await paso('lista del cliente', () => valor('select public.assign_customer_price_list($1,$2,$3)', [emp, cliente, lista]));
await paso('venta con cobro', () => valor(
  `select public.post_sale_with_payment($1,$2,'venta',$3::jsonb,$4,$5,'pagado',500,'efectivo',$6)`,
  [emp, cliente, J([{ item_id: producto, warehouse_id: dep, lot_code: null, quantity: 1, expected_unit_price: 500 }]), randomUUID(), randomUUID(), caja]));
await paso('saldos de tesorería', async () => espera((await filas('select * from public.treasury_balances($1)', [emp]))[0].kind === 'caja', 'caja'));
await paso('presupuesto', () => valor(
  `select public.create_quote($1,$2,'Cliente Uno','','','','',($3::date+10),'',false,$4::jsonb,$5)`,
  [emp, cliente, hoy, J([{ item_id: producto, quantity: 1, expected_unit_price: 500, discount_percent: 0, discount_reason: '' }]), randomUUID()]));
await paso('listar presupuestos', async () => espera((await filas('select * from public.erp_quotes_page($1)', [emp])).length === 1, 'uno'));

// Permisos: un rol que solo ve órdenes, sin costos.
const rol = await paso('rol operario', () => valor(`select public.create_company_role($1,'Operario','operario',$2::jsonb)`, [emp, J([
  { resource: 'produccion_ordenes', action: 'ver' }, { resource: 'items', action: 'ver' }])]));
await db.exec('reset role');
await db.query('insert into public.empresas_usuarios(empresa_id,usuario_id,rol_id) values ($1,$2,$3)', [emp, operario, rol]);
await como(operario);
await paso('operario ve órdenes sin costos', async () => {
  const l = await valor('select public.list_production_jobs($1)', [emp]);
  espera(l.length === 1, 'una orden');
  espera(l[0].production_job_events.every((e) => e.unit_cost === null), 'sin costos');
});
await paso('operario no crea ítems', async () => {
  try { await mover(materia, 'ingreso', 1); } catch { return; }
  throw new Error('pudo mover stock sin permiso');
});
await db.exec('reset role');
await db.query(`update public.empresas set modulos = jsonb_set(modulos,'{produccion}','false') where id=$1`, [emp]);
await como(admin);
await paso('módulo apagado bloquea', async () => {
  const l = await valor('select public.list_production_jobs($1)', [emp]);
  espera(l.length === 0, 'sin órdenes');
  espera((await filas('select id, codigo, nombre from public.stock_items where empresa_id=$1', [emp])).length > 0, 'stock sigue');
});
await paso('el administrador no puede activar módulos', async () => {
  try { await db.query(`update public.empresas set modulos='{}' where id=$1`, [emp]); } catch { return; }
  throw new Error('pudo modificar empresas');
});

console.log(`pasos correctos ${ok}, con falla ${fallas.length}`);
console.log(fallas.join('\n'));
process.exit(fallas.length ? 1 : 0);
