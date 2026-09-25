# ERP Dromux · base inicial

React + Vite + Supabase + TanStack Query. Incluye login, alta inicial de empresa, membresías, permisos RLS, panel adaptable y navegación con secciones futuras.

## 1. Instalar en tu computadora

Necesitás Node.js compatible con Vite 6 (20.19+ o 22.12+) y npm. Descomprimí este proyecto en la carpeta donde trabajás y, desde `erp-dromux`, ejecutá:

```bash
npm install
cp .env.example .env.local
```

En Windows PowerShell, para la copia usá `Copy-Item .env.example .env.local`.

## 2. Conectar el proyecto nuevo de Supabase

En Supabase abrí tu proyecto ERP → **Connect / API Keys**. Editá `.env.local` con la **Project URL** y la **publishable key** (o clave `anon` legacy si no tenés publishable key). Esos valores pertenecen al proyecto ERP nuevo, no al de Dromux. Nunca pongas `service_role`, secret key, contraseña de base de datos ni tokens privados en una variable `VITE_`.

La plantilla `.env.example` contiene marcadores; no conocemos tus claves y por eso `.env.local` debe completarse en tu máquina. Git ignora este archivo.

## 3. Crear el esquema

La migración está en `supabase/migrations/202609240001_core.sql`. En esta primera instalación, abrí **SQL Editor** del proyecto ERP, pegá el contenido completo y ejecutalo **una sola vez**. Es para una base vacía. El archivo queda versionado para reproducir el esquema. No la vuelvas a ejecutar manualmente ni hagas luego `db push` del mismo archivo sin reconciliar el historial de migraciones: Supabase no registra una ejecución hecha en SQL Editor como migración CLI.

Alternativa recomendada si ya usás CLI: desde esta carpeta ejecutá `npx supabase login`, `npx supabase link --project-ref TU_PROJECT_REF`, `npx supabase db push`. En ese caso **no ejecutes el SQL en el editor**. No se incluyen datos de clientes ni secretos.

## 4. Primer usuario y arranque

En **Authentication → Users**, creá un usuario desde el Dashboard con correo y contraseña. Verificá que quede confirmado. Luego:

```bash
npm run dev
```

Abrí `http://localhost:5173`, iniciá sesión y creá la primera empresa desde la pantalla de bienvenida. El alta asigna el rol administrador y permisos; el sidebar y el panel se muestran después. La aplicación aún no tiene pantalla para invitar usuarios ni CRUD operativo: son las siguientes fases.

## Archivos principales

- `src/lib/supabase.js`: cliente del proyecto ERP.
- `src/contexts/AuthContext.jsx`: sesión, empresa activa, membresía, rol y `can(resource, action)`.
- `src/services/core.js`: consultas seleccionadas y creación de empresa.
- `src/components/AdminLayout.jsx`: panel y menú basado en permisos.
- `src/styles.css`: diseño adaptable.
- `supabase/migrations/202609240001_core.sql`: tablas, funciones y RLS.

`npm run build` verifica la compilación. TanStack Query mantiene los datos en memoria; al cerrar sesión se borra su caché. `localStorage` guarda solamente la empresa seleccionada. El stock y las transacciones vendrán en migraciones posteriores. Agregá módulos y políticas SQL juntos: esconder botones no concede ni revoca permisos reales.

## Segunda etapa: usuarios y roles

Si ya ejecutaste la migración inicial y tu panel funciona, **no vuelvas a ejecutar** `202609240001_core.sql`.

1. En Supabase, abrí el **SQL Editor del proyecto ERP** y ejecutá una vez el archivo completo `supabase/migrations/202609240002_users_roles.sql`. Si aplicaste la primera migración mediante CLI y conservás su historial, en cambio utilizá `npx supabase db push` para aplicar sólo las migraciones pendientes.
2. Copiá los archivos de `src` actualizados a tu proyecto local. Conservá tu `.env.local` y tus datos existentes.
3. Reiniciá Vite si hace falta. Entrá a **Configuración → Roles y permisos** para crear un rol, luego a **Configuración → Usuarios** para invitar a un correo.
4. Copiá el enlace generado y compartilo con la persona por el canal que prefieras. El enlace se muestra una sola vez, vence a los siete días y sólo lo puede aceptar una cuenta autenticada con ese correo confirmado. La aplicación no manda correos de invitación automáticamente.
5. La persona abre el enlace, inicia sesión o crea su cuenta, confirma el correo si Supabase se lo pide, y vuelve a abrir el mismo enlace para completar el ingreso.

En **Authentication → Providers → Email** mantené habilitado el registro por correo para que los usuarios nuevos puedan crear sus cuentas. En **Authentication → URL Configuration** agregá la URL desde la que van a usar el ERP a los Redirect URLs cuando lo alojes; para desarrollo local agregá `http://localhost:5173/**` si tu configuración de Supabase requiere redireccionar el correo de confirmación allí. No publiques el ERP para usuarios externos usando el SMTP de prueba de Supabase; configurá un proveedor de correo antes de invitar clientes reales.

Los permisos se vuelven a consultar cuando la aplicación recupera el foco y pueden tardar algunos segundos en actualizarse en una sesión abierta. La seguridad en base de datos se aplica inmediatamente mediante RLS y funciones SQL. El módulo todavía no implementa módulos operativos ni su RLS específico: estos permisos definen acceso a las pantallas iniciales y se conectarán a políticas de cada tabla conforme construyamos Inventario y Producción.

## Tercera etapa: suspensión de empresa y catálogos

Como el proyecto ya tiene las primeras dos migraciones, aplicá **solamente** `supabase/migrations/202609240003_company_status_catalogs.sql` en el SQL Editor del proyecto ERP. Si venías usando exclusivamente migraciones con CLI, usá `npx supabase db push` en vez del SQL Editor. No ejecutes otra vez el Core ni la segunda migración. Copiá los archivos `src` incluidos en este paquete, conservá tu `.env.local` y reiniciá Vite.

- `companies.active` nace en `true`. Al ponerlo en `false`, las funciones `private.has_permission()`, `private.is_company_member()` y `private.get_user_role()` dejan de autorizar las operaciones de esa empresa. El usuario autenticado ve una pantalla de suspensión si no tiene otra empresa activa.
- El estado se comprueba al abrir/volver a la pestaña y cada 60 segundos mientras el panel está abierto. RLS bloquea el acceso a datos inmediatamente, incluso antes del próximo refresco de React.
- **El administrador de una empresa no puede reactivarla desde el navegador.** Por ahora, la operación queda a cargo de quien administra el proyecto en Supabase: en el SQL Editor, identificado el UUID correcto, ejecutá `update public.companies set active = false where id = 'UUID-DE-LA-EMPRESA' returning id, name, active;`. Para reactivar, cambiá a `true`. Verificá previamente el UUID con `select id, name, active from public.companies order by created_at desc;`. No ejecutes esto con una clave pública de frontend.
- Los catálogos de **Unidades**, **Categorías** y **Depósitos** están en Configuración. Cada uno lista 25 registros por página, busca por nombre en el servidor, permite editar y desactivar sin perder el historial. Aún no hay stock, productos ni conversiones entre unidades: son etapas posteriores.
- Los roles `admin` de empresas existentes reciben los permisos nuevos. Roles personalizados preexistentes los pueden asignar desde **Roles y permisos**. Las nuevas empresas reciben esos permisos en el alta inicial.

Prueba corta: creá una unidad, una categoría y un depósito; luego en SQL Editor desactivá temporalmente tu empresa y comprobá que el panel muestre suspensión. Reactivala con el mismo UUID. Con la empresa suspendida, cualquier consulta a catálogos debe quedar denegada por RLS. Si tenés sólo esa empresa, dejá preparada en el editor la sentencia de reactivación antes de hacer la prueba.

**Alcance de seguridad:** la suspensión cubre los datos de estas tablas y las operaciones que usan las funciones de autorización del ERP. Nuevas tablas, funciones y políticas deberán apoyarse en `private.has_permission()` o `private.is_company_member()` para heredar el bloqueo. La sesión de Supabase Auth permanece válida y los datos personales de Auth no se borran por una suspensión.

## Cuarta etapa: maestro de ítems

Aplicá **solamente** `supabase/migrations/202609240004_items.sql` sobre el proyecto ERP que ya tiene las tres migraciones previas. Si administrás el historial únicamente con Supabase CLI, usá `npx supabase db push` en lugar de ejecutar el archivo en SQL Editor. Copiá los archivos `src` de la actualización a tu proyecto y conservá `.env.local`.

En el panel, abrí **Inventario → Todos los ítems**. También tenés accesos rápidos para materias primas y productos. La ficha incluye código, nombre, tipo, categoría opcional, unidad obligatoria, código de barras opcional, descripción, stock mínimo como referencia y una marca de seguimiento por lotes. El código es único por empresa sin distinguir mayúsculas y minúsculas. Las relaciones de categoría y unidad no pueden apuntar a otra empresa.

Podés crear, editar y desactivar ítems; la información permanece para el historial. Al crear un ítem, elegí una unidad activa. Los selectores muestran hasta 30 resultados y permiten filtrar por nombre desde Supabase. El listado de ítems pagina de a 25 y filtra en el servidor. El rol administrador existente recibe los permisos nuevos automáticamente; a los roles personalizados debés asignarles `items.read/insert/update` desde **Roles y permisos** según corresponda. Para usar los selectores, otorgales también lectura de unidades y categorías.

Prueba recomendada: creá una materia prima con la unidad y categoría existentes, editala, filtrá por tipo y comprobá que otro rol sin permiso `items.read` no pueda leerla. Creá otra empresa de prueba si necesitás comprobar que las relaciones nunca mezclan datos entre compañías. No hay cantidades disponibles ni valorización todavía: ambas vendrán con los movimientos de stock y su costo.

## Quinta etapa: stock y movimientos

Consultá `GUIA-INVENTARIO.md` para el proceso completo, instalación, prueba con cantidades y el uso opcional del código de barras. Esta etapa agrega `supabase/migrations/202609240005_stock_movements.sql`, las pantallas **Inventario → Stock por depósito** e **Inventario → Movimientos**, y un archivo de auditoría de solo lectura en `supabase/tests/20260924_stock_integrity.sql`.
