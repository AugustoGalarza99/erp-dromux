-- Dromux ERP · 046c · H-E1: entregar a una orden el insumo que ella misma reservó.
-- ESTADO: PREPARADA, NO APLICADA. Requiere 046/046b aplicadas. Aplicar con respaldo; deshacer: reparacion/0_deshacer_046c.sql.
-- Síntoma (Fase 1, 24/11/2026): al entregar a la OF 1 los 30 l de un lote que la propia orden tenía reservado al 100 %, el servidor
-- respondía "Stock libre insuficiente en el depósito y lote elegidos" aunque la pantalla mostraba 30 disponibles.
-- Causa (verificada leyendo las definiciones vigentes): public.post_stock_operation descuenta la reserva de la propia orden
-- (v_own) solo si la variable de transacción `dromux.production_job` está fijada, pero NINGUNA función la fija, así que el
-- permiso para usar la propia reserva nunca se activa. Solo funcionaba entregar de un lote/depósito con stock libre extra.
-- Corrección mínima: public.issue_production_material y private.issue_production_material fijan `dromux.production_job` (solo
-- dentro de la transacción) justo antes de llamar a public.post_stock_operation y la limpian después. No se toca post_stock_operation
-- (dinero/stock: sin cambios en sus reglas); además post_stock_operation ya valida que la orden esté en cola o en proceso.
-- Limitación conocida (revisión crítica P2-a): se limpia a vacío en vez de restaurar un valor previo; hoy nadie más fija la variable.
-- También activa la reserva propia en complete_production_now y en los ajustes al terminar (043): incluir en las pruebas.
-- Método de 037/046: definición vigente + patrón explícito + conteo = 1 + atributos de seguridad idénticos antes y después.
begin;

create table private.function_defs_pre046c (signature text primary key, definition text not null);
alter table private.function_defs_pre046c enable row level security;
revoke all on private.function_defs_pre046c from public, anon, authenticated;

do $$
declare
  r record; d text; n int; v_before text; v_after text;
  v_pat constant text := '(v_operation:=public\.post_stock_operation\(p_company,p_component,p_warehouse,\s*null,''issue'',p_quantity,''Orden producción ''\|\|p_job::text,\s*gen_random_uuid\(\),v_lot,null\);)';
begin
  for r in select s from (values
    ('public.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid)'),
    ('private.issue_production_material(uuid,uuid,uuid,uuid,text,numeric,text,uuid)')) v(s) order by 1 loop
    d := pg_get_functiondef(r.s::regprocedure);
    select count(*) into n from regexp_matches(d, v_pat, 'g');
    if n <> 1 then raise exception '% tiene % apariciones del patrón (se esperaba 1). No se cambió nada.', r.s, n; end if;
    insert into private.function_defs_pre046c values (r.s, d);
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_before from pg_proc where oid = r.s::regprocedure;
    execute regexp_replace(d, v_pat,
      'perform pg_catalog.set_config(''dromux.production_job'',p_job::text,true);' || E'\n  ' || '\1' || E'\n  '
      || 'perform pg_catalog.set_config(''dromux.production_job'','''',true);');
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_after from pg_proc where oid = r.s::regprocedure;
    if v_before is distinct from v_after then raise exception 'Cambió la seguridad de %', r.s; end if;
    if pg_get_functiondef(r.s::regprocedure) not like '%set_config(''dromux.production_job'',p_job::text,true)%' then
      raise exception 'No se aplicó el cambio en %', r.s; end if;
  end loop;
end $$;

commit;
