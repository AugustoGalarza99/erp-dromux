-- Deshacer 047: restaura las 36 funciones y 14 políticas de Producción y el catálogo (acciones y "exigido") desde las copias private.*_pre047.
-- No toca role_permissions. Después de deshacer, el servidor vuelve a exigir el módulo "production" completo (un rol con acceso parcial a Producción
-- queda SIN esas pantallas) y los costos de producción vuelven a ser administrador + finanzas.
-- Si 048 o posterior ya está aplicada, NO usar este archivo: primero deshacer esas migraciones en orden inverso.
begin;
do $$
declare r record;
begin
  if (select count(*) from private.function_defs_pre047) <> 36 or (select count(*) from private.policy_defs_pre047) <> 14 then
    raise exception 'Las copias de la 047 no están completas: no se deshizo nada.';
  end if;
  -- Guarda: solo se deshace si las funciones siguen siendo las de 047 (nadie las cambió después).
  if exists (select 1 from private.function_defs_pre047 f
    where pg_get_functiondef(f.signature::regprocedure) ~ 'has_permission\(\s*[a-z_]+\s*,\s*''production''\s*,'
      and f.signature <> 'public.erp_replenishment_forecast(uuid)') then
    raise exception 'Una función ya tiene el permiso viejo o fue cambiada: no se deshizo nada.';
  end if;
  for r in select definition from private.function_defs_pre047 order by signature loop execute r.definition; end loop;
  for r in select tbl, policy, qual from private.policy_defs_pre047 order by tbl, policy loop
    execute format('alter policy %I on public.%I using (%s)', r.policy, r.tbl, r.qual);
  end loop;
end $$;
update public.permission_catalog c set enforced = b.enforced from private.permission_catalog_pre047 b where b.resource = c.resource;
drop table private.function_defs_pre047;
drop table private.policy_defs_pre047;
drop table private.permission_catalog_pre047;
commit;
