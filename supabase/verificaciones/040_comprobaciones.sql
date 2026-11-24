-- Comprobaciones de solo lectura para 040 (después de aplicarla). No leen datos de clientes.

-- 1) Columnas nuevas.
select table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and ((table_name = 'sale_lines' and column_name in ('price_list_id', 'list_unit_price', 'discount_percent', 'discount_reason', 'tax_percent'))
    or (table_name = 'price_settings' and column_name = 'max_discount_percent'))
order by 1, 2;
-- Esperado: 6 filas; discount_percent y max_discount_percent not null default 0.

-- 2) Funciones nuevas: security definer, search_path vacío, EXECUTE solo authenticated (las private, nadie).
select n.nspname, p.proname, p.prosecdef as security_definer, coalesce(array_to_string(p.proconfig, ','), '') as config,
  has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
  has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('save_price_settings', 'erp_price_settings', 'erp_resolve_sale_price',
  'erp_sale_prices', 'erp_sale_discount_policy', 'post_sale', 'post_sale_with_payment'))
  or (n.nspname = 'private' and p.proname = 'sale_resolve_price')
order by 1, 2;
-- Esperado: security_definer=true, config=search_path="", anon_exec=false; auth_exec=true en las public
-- (post_sale conserva su permiso anterior: comprobar que no cambió) y false en private.sale_resolve_price.

-- 3) post_sale quedó parcheada exactamente (esperado: 1 en cada columna).
select
  (length(d) - length(replace(d, 'private.sale_resolve_price', ''))) / length('private.sale_resolve_price') as usa_resolvedor,
  (length(d) - length(replace(d, 'v_item.sale_unit_price', ''))) / length('v_item.sale_unit_price') as usos_precio_item_restantes,
  position('discount_reason' in d) > 0 as guarda_descuento
from (select pg_get_functiondef(p.oid) as d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'post_sale') x;
-- Esperado: usa_resolvedor=1, usos_precio_item_restantes=0, guarda_descuento=true.

-- 4) Una sola versión de save_price_settings (con p_max_discount opcional) y permisos de columna de sale_lines.
select p.oid::regprocedure as firma from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'save_price_settings';
-- Esperado: 1 fila (6 parámetros, el último con valor por defecto).
select column_name, has_column_privilege('authenticated', 'public.sale_lines', column_name, 'SELECT') as auth_select
from information_schema.columns where table_schema = 'public' and table_name = 'sale_lines'
  and column_name in ('price_list_id', 'list_unit_price', 'discount_percent', 'discount_reason', 'tax_percent',
    'estimated_unit_cost') order by 1;
-- Esperado: las 5 nuevas auth_select=true; estimated_unit_cost=false (costo: no debe ser legible).

-- PRUEBAS DE COMPORTAMIENTO (base de prueba, 2 empresas y 3 roles; no incluidas aquí):
--  a) cliente con lista Mayorista: la venta sale al precio de esa lista; cliente sin lista: lista predeterminada;
--     sin ninguna: items.sale_unit_price (como antes de la 040).
--  b) expected_unit_price distinto del precio recalculado -> "El precio de ... cambió".
--  c) descuento <= tope: lo puede aplicar quien registra ventas; > tope: error para no admin; admin con motivo
--     >= 3 caracteres OK; admin sin motivo -> error. Tope 0 (por defecto): ningún no-admin puede descontar.
--  d) lista en USD, archivada o vencida: se ignora y se usa la siguiente regla.
--  e) misma request_id dos veces con las mismas líneas -> mismo resultado, una sola venta (idempotencia);
--     con otro descuento -> "Esta solicitud ya se utilizó con otros datos".
--  f) sale_lines guarda price_list_id, list_unit_price, discount_percent, tax_percent; total y cobro = neto.
--  g) post_sale_with_payment con cobro parcial/total sigue validando contra el total con descuento.
--  h) devolución (adjust_sale) calcula el crédito con el precio final cobrado.
--  i) un vendedor no puede leer costos ni margen por ninguna función nueva.
--  j) discount_percent con 'NaN', '1e-3', ' 5 ' y 5.005; precio de lista 10,05 con 50 % (el cliente y el servidor
--     deben coincidir en 5,03); motivo de espacios o símbolos -> rechazo; descuento que deja el precio en 0 -> rechazo.
--  k) llamada a save_price_settings con 5 parámetros nombrados: funciona y no cambia el tope.
--  l) erp_sale_prices con 200 productos; un vendedor puede leer sale_lines.list_unit_price y no estimated_unit_cost.
