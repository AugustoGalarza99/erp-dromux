// Levanta una base Postgres en memoria con lo mínimo de Supabase y carga el SQL generado.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';

const sql = fileURLToPath(new URL('../sql', import.meta.url));

export async function crearBase({ mostrar = true } = {}) {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(`
    create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
    create schema auth; create schema extensions;
    create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    create function auth.role() returns text language sql stable as $$ select current_user::text $$;
    create function auth.jwt() returns jsonb language sql stable as
      $$ select jsonb_build_object('sub', current_setting('request.jwt.claim.sub', true)) $$;
    grant usage on schema auth, extensions to anon, authenticated, service_role;
    grant usage on schema public to anon, authenticated, service_role;
  `);
  // Línea base y, después, los cambios posteriores en orden de número.
  const inicial = ['01_estructura.sql', '02a_funciones.sql', '02b_funciones.sql', '03_permisos_y_datos.sql', '04_proteccion_rls.sql']
    .map((nombre) => [nombre, `${sql}/${nombre}`]);
  const cambios = fileURLToPath(new URL('../cambios', import.meta.url));
  const posteriores = existsSync(cambios)
    ? readdirSync(cambios).filter((n) => /^\d{3}_.*\.sql$/.test(n)).sort().map((n) => [n, `${cambios}/${n}`])
    : [];
  for (const [archivo, ruta] of [...inicial, ...posteriores]) {
    const texto = readFileSync(ruta, 'utf8')
      .replace('create extension if not exists plpgsql_check with schema extensions;', '');
    try {
      await db.exec(texto);
      if (mostrar) console.log('OK', archivo);
    } catch (error) {
      console.log('FALLA', archivo, error.message, error.detail ?? '', error.hint ?? '');
      if (error.position) {
        const p = Number(error.position);
        console.log('--- cerca de:', texto.slice(Math.max(0, p - 300), p + 160));
      }
      console.log('where:', (error.where ?? '').slice(0, 400));
      throw error;
    }
  }
  return db;
}
