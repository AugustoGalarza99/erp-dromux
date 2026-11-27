// Carga el SQL y revalida las funciones SQL con la comprobación de cuerpos activada.
import { crearBase } from './base.mjs';

let fallas = 0;
try {
  const db = await crearBase();
  const funciones = await db.query(`
    select p.oid::regprocedure::text as firma, pg_get_functiondef(p.oid) as def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace join pg_language l on l.oid = p.prolang
    where n.nspname in ('public', 'private') and l.lanname = 'sql'`);
  for (const f of funciones.rows) {
    try {
      await db.exec(`set check_function_bodies = on; ${f.def};`);
    } catch (error) {
      fallas += 1;
      console.log('FUNCION', f.firma, '->', error.message);
    }
  }
  console.log('funciones sql revisadas', funciones.rows.length, 'con falla', fallas);
  const cuentas = await db.query(`select
    (select count(*) from pg_tables where schemaname in ('public','private')) tablas,
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private')) funciones,
    (select count(*) from pg_policies where schemaname in ('public','private')) politicas,
    (select count(*) from pg_trigger where not tgisinternal) disparadores,
    (select count(*) from public.ajustes_permisos_catalogo) permisos,
    (select count(*) from pg_tables where schemaname='public' and not rowsecurity) sin_rls`);
  console.log(cuentas.rows[0]);
  if (fallas) process.exit(1);
} catch {
  process.exit(1);
}
process.exit(0);
