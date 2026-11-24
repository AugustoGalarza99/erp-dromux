-- Dromux ERP · 037 · Topes de líneas para fábricas grandes (D-007, H-006).
-- ESTADO: PREPARADA, NO APLICADA. Aplicar solo con autorización para el entorno destino,
-- después de un respaldo y en este orden: respaldo -> esta migración -> comprobaciones -> publicar frontend.
--
-- Qué hace: sube el tope de `jsonb_array_length(<líneas>) not between 1 and 40` en 6 funciones.
-- Cómo: lee la definición VIGENTE de cada función en la base (pg_get_functiondef) y cambia solo
-- ese literal. No reescribe cuerpos desde los archivos locales (H-002: los cuerpos locales y los
-- remotos no se compararon), así que conserva SECURITY DEFINER, search_path, permisos y lógica.
-- Si una función no tiene exactamente una aparición del literal, aborta sin cambiar nada.
--
-- No toca: post_sale, adjust_sale, create_supplier_payment_order (dinero) ni
-- save_production_document_settings / purchase_suppliers_for_items (otro uso del número).

begin;

create temporary table _limites_037(signature text primary key, nuevo integer not null) on commit drop;
insert into _limites_037(signature, nuevo) values
  ('public.save_production_formula(uuid,uuid,numeric,jsonb)', 500),
  ('public.complete_production_now(uuid,uuid,numeric,numeric,uuid,text,date,text,text,jsonb,uuid,uuid,uuid)', 500),
  ('public.issue_delivery_note(uuid,text,uuid,text,text,jsonb,uuid)', 500),
  ('public.issue_sale_delivery_note(uuid,uuid,text,text,jsonb,uuid)', 200),
  ('public.create_purchase_order(uuid,uuid,text,jsonb)', 200),
  ('public.receive_purchase_order(uuid,uuid,uuid,text,jsonb)', 200);

do $$
declare
  r record;
  v_def text;
  v_new text;
  v_old constant text := 'between 1 and 40';
  v_count integer;
begin
  for r in select signature, nuevo from _limites_037 order by signature loop
    v_def := pg_get_functiondef(r.signature::regprocedure);
    v_count := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_count <> 1 then
      raise exception 'La función % tiene % apariciones de "%" (se esperaba 1). No se cambió nada.',
        r.signature, v_count, v_old;
    end if;
    v_new := replace(v_def, v_old, 'between 1 and ' || r.nuevo);
    execute v_new;
    if position('between 1 and ' || r.nuevo in pg_get_functiondef(r.signature::regprocedure)) = 0 then
      raise exception 'No se pudo comprobar el nuevo tope en %', r.signature;
    end if;
  end loop;
end
$$;

commit;
