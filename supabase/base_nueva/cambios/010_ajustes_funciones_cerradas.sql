-- 010 · Las funciones que se creen en adelante no quedan ejecutables para cualquiera.
-- No cambia ninguna función existente. Cada función nueva que use la aplicación debe dar el
-- permiso de forma explícita (grant execute ... to authenticated).
begin;

alter default privileges for role postgres revoke execute on functions from public;

commit;
