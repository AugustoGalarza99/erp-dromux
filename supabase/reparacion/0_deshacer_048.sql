-- Deshacer 048: restaura las 12 funciones y 11 políticas de lectura de Stock, private.cleanup_target y el catálogo desde las copias private.*_pre048.
-- No toca role_permissions. Después de deshacer, el servidor vuelve a exigir el módulo 'stock' completo para ver saldos/lotes/movimientos/remitos
-- (un rol con acceso parcial a Stock queda SIN esas lecturas) y Archivados vuelve a pedir el módulo completo.
-- Si una migración posterior (048b o Ventas) ya está aplicada, NO usar este archivo: primero deshacer esas migraciones en orden inverso.
begin;
do $$
declare r record;
begin
  if (select count(*) from private.function_defs_pre048) <> 12 or (select count(*) from private.policy_defs_pre048) <> 11 then
    raise exception 'Las copias de la 048 no están completas: no se deshizo nada.';
  end if;
  -- Guarda: solo se deshace si las funciones siguen siendo las de 048 (nadie las cambió después).
  if exists (select 1 from private.function_defs_pre048 f
    where f.signature <> 'private.cleanup_target(text)'
      and pg_get_functiondef(f.signature::regprocedure) ~ 'has_permission\(\s*p_company\s*,\s*''stock''\s*,\s*''read''') then
    raise exception 'Una función ya tiene el permiso viejo o fue cambiada: no se deshizo nada.';
  end if;
  if pg_get_functiondef('private.cleanup_target(text)'::regprocedure) !~ 'purchases_suppliers' then
    raise exception 'cleanup_target no es la de la 048: no se deshizo nada.';
  end if;
  for r in select definition from private.function_defs_pre048 order by signature loop execute r.definition; end loop;
  for r in select tbl, policy, qual from private.policy_defs_pre048 order by tbl, policy loop
    execute format('alter policy %I on public.%I using (%s)', r.policy, r.tbl, r.qual);
  end loop;
end $$;
revoke all on function private.cleanup_target(text) from public, anon, authenticated;
update public.permission_catalog c set enforced = b.enforced from private.permission_catalog_pre048 b where b.resource = c.resource;
drop table private.function_defs_pre048;
drop table private.policy_defs_pre048;
drop table private.permission_catalog_pre048;
commit;
