-- Deshacer 046c: restaura las 2 funciones issue_production_material desde private.function_defs_pre046c.
begin;
do $$ declare r record; begin
  if (select count(*) from private.function_defs_pre046c) <> 2 then raise exception 'Copias incompletas: no se deshizo nada.'; end if;
  -- Guarda (revisión crítica P2-b): solo se deshace si las funciones siguen siendo las de 046c.
  if exists (select 1 from private.function_defs_pre046c f where pg_get_functiondef(f.signature::regprocedure) not like '%set_config(''dromux.production_job'',p_job::text,true)%') then
    raise exception 'Una de las funciones ya no es la de 046c (otra migración la cambió): no se deshizo nada.'; end if;
  for r in select definition from private.function_defs_pre046c loop execute r.definition; end loop;
end $$;
drop table private.function_defs_pre046c;
commit;
