-- Dromux ERP · 046b (archivo 046b_precio_proveedor_es_costo.sql; la 047 sigue siendo Producción)
-- ESTADO: PREPARADA, NO APLICADA. Requiere 046 aplicada. Decisión del propietario 24/11/2026: el precio que cobra el proveedor
-- (materia prima) ES costo => se ve solo con costs_materials (cierra el resto de H-011).
-- Qué hace: las funciones que devuelven precios de proveedor y las políticas de supplier_items y supplier_price_adjustments
-- exigen ADEMÁS costs_materials:read. Método de 037/046 (definición vigente, patrón explícito, conteo = 1, aborta si no coincide).
-- NO se toca (queda ABIERTO, hallazgo H-011b): purchase_order_lines y purchase_receipt_lines (precio de lo ya comprado; la
-- cantidad es necesaria para recibir) y purchase_receivable_lines. Decidir si se separa el precio en otra vista.
-- Efecto: un rol de compras SIN costs_materials no ve precios de proveedores ni arma órdenes con precio sugerido. El
-- "Encargado de compras" debe llevar costs_materials (lo tilda el administrador). Deshacer: reparacion/0_deshacer_046b.sql.
begin;

create table private.function_defs_pre047p (signature text primary key, definition text not null);
create table private.policy_defs_pre047p (tbl text, policy text, qual text, with_check text, primary key (tbl, policy));
alter table private.function_defs_pre047p enable row level security;
alter table private.policy_defs_pre047p enable row level security;
revoke all on private.function_defs_pre047p, private.policy_defs_pre047p from public, anon, authenticated;

create temporary table _m (signature text primary key, pat text not null) on commit drop;
insert into _m values
  ('public.purchase_material_options(uuid,text,uuid)',
    '(\(private\.has_permission\(p_company,''purchases_orders'',''read''\) or private\.has_permission\(p_company,''purchases_suppliers'',''read''\)\))'),
  ('public.purchase_supplier_quotes(uuid,uuid,uuid)',
    '(\(private\.has_permission\(p_company,''purchases_orders'',''read''\) or private\.has_permission\(p_company,''purchases_suppliers'',''read''\)\))'),
  ('public.supplier_cost_comparison(uuid,uuid,uuid)',
    '(\(private\.has_permission\(p_company,''purchases_orders'',''read''\) or private\.has_permission\(p_company,''purchases_suppliers'',''read''\)\))'),
  ('public.supplier_quote_catalog(uuid,uuid,uuid,text,integer)',
    '(private\.has_permission\(p_company,''purchases_suppliers'',''read''\))'),
  ('public.supplier_adjustment_preview(uuid,uuid,uuid,numeric)',
    '(private\.has_permission\(p_company,''purchases_suppliers'',''update''\))');

do $$
declare r record; d text; n int; v_before text; v_after text;
begin
  for r in select * from _m order by 1 loop
    d := pg_get_functiondef(r.signature::regprocedure);
    select count(*) into n from regexp_matches(d, r.pat, 'g');
    if n <> 1 then raise exception '% tiene % apariciones (se esperaba 1). No se cambió nada.', r.signature, n; end if;
    insert into private.function_defs_pre047p values (r.signature, d);
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_before from pg_proc where oid = r.signature::regprocedure;
    execute regexp_replace(d, r.pat, '(\1 and private.has_permission(p_company,''costs_materials'',''read''))');
    select prosecdef::text || coalesce(proconfig::text,'') || has_function_privilege('anon', oid, 'execute')::text
      || has_function_privilege('authenticated', oid, 'execute')::text into v_after from pg_proc where oid = r.signature::regprocedure;
    if v_before is distinct from v_after then raise exception 'Cambió la seguridad de %', r.signature; end if;
    if pg_get_functiondef(r.signature::regprocedure) not like '%costs_materials%' then
      raise exception 'No se aplicó el cambio en %', r.signature; end if;
  end loop;

  for r in select * from (values ('supplier_items','supplier_items_read'), ('supplier_price_adjustments','supplier_price_adjustments_read')) v(t, p) loop
    select count(*) into n from pg_policies where schemaname='public' and tablename=r.t and policyname=r.p
      and qual like '%purchases_suppliers%' and qual not like '%costs_materials%';
    if n <> 1 then raise exception 'Política % no tiene la forma esperada', r.p; end if;
    insert into private.policy_defs_pre047p select r.t, r.p, qual, with_check from pg_policies
      where schemaname='public' and tablename=r.t and policyname=r.p;
    execute format('alter policy %I on public.%I using ((select private.has_permission(company_id,%L,%L)) and (select private.has_permission(company_id,%L,%L)))',
      r.p, r.t, 'purchases_suppliers', 'read', 'costs_materials', 'read');
  end loop;
end $$;

commit;
