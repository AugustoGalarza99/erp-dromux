-- 04. Activa la seguridad por filas en cualquier tabla nueva (aparte por si pide otro permiso).
drop event trigger if exists ensure_rls;
create event trigger ensure_rls on ddl_command_end when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO') execute function public.rls_auto_enable();
