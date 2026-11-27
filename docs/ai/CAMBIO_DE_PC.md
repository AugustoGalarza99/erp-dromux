# Seguir el trabajo en otra PC

## Antes de dejar la PC actual
1. Confirmar que el último commit se subió a GitHub (`git status` debe decir que está al día con `origin/main`).
2. Copiar a un pendrive u otro medio privado (**no viajan con Git**):

| Archivo | Para qué | ¿Imprescindible? |
|---|---|---|
| `.env.nueva.local` | Dirección y clave pública de la base nueva | Sí (o rehacerlo, ver abajo) |
| `.env.local` | Lo mismo para la base vieja | No |
| `docs/ai/referencias/*.xlsx` | Planilla de referencia con datos reales | Solo si se va a usar |
| `.claude/settings.local.json` | Permisos que ya aceptaste en Claude | No |

`node_modules/` y `dist/` no se copian: se vuelven a crear.

## En la PC nueva
1. Instalar **Git**, **Node.js** (en la anterior: Node 26.13.1, npm 11.20.0), **VS Code** y la aplicación **Claude** (con la misma cuenta).
2. Bajar el proyecto (pide iniciar sesión en GitHub):
   ```powershell
   git clone https://github.com/AugustoGalarza99/erp-dromux.git C:\Augusto\erp-dromux
   ```
3. Dentro de la carpeta, instalar lo necesario:
   ```powershell
   npm ci
   ```
4. Poner `.env.nueva.local` en la raíz del proyecto. Si no lo tenés, crear el archivo con estas dos líneas; la clave **pública** está en Supabase → Project Settings → API Keys (nunca la `service_role` ni una `sb_secret_`):
   ```text
   VITE_SUPABASE_URL=https://nummzswhycklmzbgacnl.supabase.co
   VITE_SUPABASE_PUBLISHABLE_KEY=(clave publicable)
   ```
5. Comprobar que todo anda:
   ```powershell
   npm run base:probar
   ```
   ```powershell
   npm run build:nueva
   ```
   `base:probar` tarda unos minutos; esperado: flujo 66/66 y cambios 661/661.
6. Abrir Claude en esa carpeta y verificar que aparezca el conector de **Supabase** (solo lectura) con acceso al proyecto `nummzswhycklmzbgacnl`; si no, volver a conectarlo.
7. Pegar el prompt de `docs/ai/PROMPT_PROXIMA_SESION.md`. En el navegador de Claude hay que iniciar sesión de nuevo.

## Qué no se traslada
La memoria interna de Claude y el historial de conversaciones quedan en la PC anterior. Lo necesario está en `docs/ai/ESTADO.md` y en `CLAUDE.md`.
