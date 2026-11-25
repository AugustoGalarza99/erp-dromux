-- Deshacer 046. Restaura las 34 funciones y las 17 políticas de Compras a su definición de ANTES de la 046 (copias en
-- private.function_defs_pre046 y private.policy_defs_pre046) y el catálogo de permisos (acciones y "exigido") a su estado
-- previo (private.permission_catalog_pre046). No toca role_permissions: los permisos de los roles quedan como estén
-- (las filas purchase_requests:manage y las de otras pantallas siguen ahí sin efecto).
-- ATENCIÓN: después de deshacer, el servidor vuelve a exigir el módulo "purchases" completo: un rol con acceso parcial a
-- Compras queda SIN esas pantallas y el Vendedor vuelve a ver costos de materiales (H-011). Si 047 o posterior ya está
-- aplicada, NO usar este archivo: primero deshacer esas migraciones en orden inverso.
begin;

do $$
declare
  r record;
begin
  if (select count(*) from private.function_defs_pre046) <> 34 or (select count(*) from private.policy_defs_pre046) <> 17 then
    raise exception 'Las copias de la 046 no están completas: no se deshizo nada.';
  end if;
  for r in select definition from private.function_defs_pre046 order by signature loop
    execute r.definition;
  end loop;
  for r in select tbl, policy, qual, with_check from private.policy_defs_pre046 order by tbl, policy loop
    execute format('alter policy %I on public.%I', r.policy, r.tbl)
      || case when r.qual is not null then ' using (' || r.qual || ')' else '' end
      || case when r.with_check is not null then ' with check (' || r.with_check || ')' else '' end;
  end loop;
end
$$;

update public.permission_catalog c set actions = b.actions, enforced = b.enforced
from private.permission_catalog_pre046 b where b.resource = c.resource;

drop table private.function_defs_pre046;
drop table private.policy_defs_pre046;
drop table private.permission_catalog_pre046;

commit;
