-- Deshace 038 (pedidos de compra internos).
-- ATENCIÓN: borra las tablas de pedidos. Si ya hay pedidos reales, exportalos antes: este script aborta
-- mientras existan filas (cámbialo solo si decidís descartarlos).
begin;

do $$
begin
  if exists (select 1 from public.purchase_requests) then
    raise exception 'Hay pedidos de compra cargados. Exportalos antes de deshacer la migración 038.';
  end if;
end
$$;

drop function if exists public.convert_purchase_request(uuid, uuid, uuid, text, jsonb, uuid);
drop function if exists public.reject_purchase_request(uuid, uuid, text);
drop function if exists public.cancel_purchase_request(uuid, uuid);
drop function if exists public.create_purchase_request(uuid, text, date, text, jsonb, uuid);
drop function if exists public.purchase_request_item_options(uuid, text);

drop table if exists public.purchase_request_submissions;
drop table if exists public.purchase_request_lines;
drop table if exists public.purchase_requests;
drop table if exists public.purchase_request_counters;
drop function if exists private.purchase_requests_guard();
drop function if exists private.purchase_request_lines_immutable();

delete from public.role_permissions where resource = 'purchase_requests';

-- Vuelve la lista blanca de recursos a su estado anterior (solo ese literal).
do $$
declare
  r record;
  v_def text;
  v_count integer;
begin
  for r in select * from (values
    ('public.create_company_role(uuid,text,text,jsonb)', '''items'', ''stock'', ''purchase_requests'')', '''items'', ''stock'')'),
    ('public.update_company_role(uuid,uuid,text,jsonb)', '''items'', ''stock'', ''purchase_requests'')', '''items'', ''stock'')'),
    ('public.create_company(text)', '(''stock''),(''purchase_requests'')) as r(resource)', '(''stock'')) as r(resource)')
  ) as t(signature, old_text, new_text) loop
    v_def := pg_get_functiondef(r.signature::regprocedure);
    v_count := (length(v_def) - length(replace(v_def, r.old_text, ''))) / length(r.old_text);
    if v_count = 1 then
      execute replace(v_def, r.old_text, r.new_text);
    else
      raise notice 'La función % no tiene el literal de 038 (¿ya estaba deshecho?). Se omite.', r.signature;
    end if;
  end loop;
end
$$;

commit;
