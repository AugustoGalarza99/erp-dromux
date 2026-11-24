-- Deshace 037: vuelve el tope de líneas a 40 en las 6 funciones.
-- No borra datos: los documentos ya creados con más de 40 líneas se conservan; solo no se pueden crear nuevos.
begin;

do $$
declare
  r record;
  v_def text;
  v_new text;
  v_found integer;
begin
  for r in select * from (values
    ('public.save_production_formula(uuid,uuid,numeric,jsonb)', 500),
    ('public.complete_production_now(uuid,uuid,numeric,numeric,uuid,text,date,text,text,jsonb,uuid,uuid,uuid)', 500),
    ('public.issue_delivery_note(uuid,text,uuid,text,text,jsonb,uuid)', 500),
    ('public.issue_sale_delivery_note(uuid,uuid,text,text,jsonb,uuid)', 200),
    ('public.create_purchase_order(uuid,uuid,text,jsonb)', 200),
    ('public.receive_purchase_order(uuid,uuid,uuid,text,jsonb)', 200)
  ) as t(signature, actual) loop
    v_def := pg_get_functiondef(r.signature::regprocedure);
    v_found := position('between 1 and ' || r.actual in v_def);
    if v_found = 0 then
      raise notice 'La función % no tiene el tope % (¿ya estaba en 40?). Se omite.', r.signature, r.actual;
      continue;
    end if;
    v_new := replace(v_def, 'between 1 and ' || r.actual, 'between 1 and 40');
    execute v_new;
  end loop;
end
$$;

commit;
