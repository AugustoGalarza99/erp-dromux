-- Deshacer 046b: restaura 5 funciones y 2 políticas desde las copias private.*_pre047p.
begin;
do $$ declare r record; begin
  if (select count(*) from private.function_defs_pre047p) <> 5 or (select count(*) from private.policy_defs_pre047p) <> 2 then
    raise exception 'Copias incompletas: no se deshizo nada.'; end if;
  for r in select definition from private.function_defs_pre047p loop execute r.definition; end loop;
  for r in select * from private.policy_defs_pre047p loop
    execute format('alter policy %I on public.%I using (%s)', r.policy, r.tbl, r.qual); end loop;
end $$;
drop table private.function_defs_pre047p; drop table private.policy_defs_pre047p;
commit;
