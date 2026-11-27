// Busca en src/ nombres de tablas y valores guardados de la base vieja (según mapa.json).
// Lo que queda a propósito está en PERMITIDOS, con el motivo.
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const raiz = fileURLToPath(new URL('../../..', import.meta.url));
const mapa = JSON.parse(readFileSync(join(raiz, 'supabase/base_nueva/mapa.json'), 'utf8'));

// [parte del archivo, palabra, motivo]
const PERMITIDOS = [
  ['', 'delete', 'respuesta de limpieza y método de Supabase'],
  ['CleanupButton', 'archive', 'respuesta de limpieza'],
  ['', 'bulk', 'nombre de diálogo de la interfaz'],
  ['PriceListsPage', 'import', 'nombre de diálogo de la interfaz'],
  ['', 'remove', 'acción de la interfaz'],
  ['ProductionJobCard', 'issue', 'acción de la interfaz (no es el tipo guardado)'],
  ['ProductionJobCard', 'return', 'acción de la interfaz (no es el tipo guardado)'],
  ['ProductionJobCard', 'cancel', 'acción de la interfaz'],
  ['SupplierAccountsPage', 'cancel', 'acción de la interfaz'],
  ['JobComponentsTable', 'pending', 'filtro calculado en pantalla'],
  ['SupplierAccountsPage', 'products', 'pestaña de la interfaz'],
  ['ProductionOverview', 'queued', 'clave que devuelve erp_production_dashboard'],
  ['Dashboard', 'cash', 'clave de una tarjeta del Inicio'],
  ['PurchasesOverview', 'open', 'clave de una tarjeta'],
  ['PurchasesOverview', 'partial', 'clave de una tarjeta'],
  ['PurchasesOverview', 'urgent', 'nivel visual de una alerta'],
  ['Overview', 'urgent', 'nivel visual de una alerta'],
  ['Dashboard', 'urgent', 'nivel visual de una alerta'],
  ['', 'items', 'recurso y nombre de lista vigentes'],
  ['', 'stock', 'recurso y módulo vigentes'],
  ['', 'ventas', 'nombre vigente'],
  ['', 'normal', 'prioridad vigente y estilo de PDF'],
  ['', 'manual', 'origen vigente'],
  ['', 'operario', 'rol vigente'],
  ['', 'vendedor', 'rol vigente'],
  ['AdminLayout', 'home', 'identificador de módulo del menú'],
  ['ItemsPage', 'import', 'parámetro de la dirección'],
  ['DeliveryNotesPage', 'sale', 'parámetro de la dirección'],
  ['PriceListsPage', 'settings', 'nombre de diálogo'],
  ['SalesOverview', 'sales', 'clave de una tarjeta'],
];

const viejos = new Map();
for (const [grupo, valores] of Object.entries(mapa.valores)) {
  if (typeof valores !== 'object') continue;
  for (const [viejo, nuevo] of Object.entries(valores)) {
    if (viejo !== nuevo) viejos.set(viejo, `${grupo} → ${nuevo}`);
  }
}
const tablas = Object.keys(mapa.tablas).filter((t) => !t.startsWith('private.'));

function archivos(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const ruta = join(dir, e.name);
    if (e.isDirectory()) return archivos(ruta);
    return /\.(js|jsx|css)$/.test(e.name) ? [ruta] : [];
  });
}

// Valores que se comparan o envían: no son rutas, claves de caché ni nombres de interfaz.
const IGNORAR_LINEA = /queryKey|invalidateQueries|^\s*import |className="|\bid: ['"]|module: ['"]|to: ['"]\/|^\s*\*|^\s*\/\/|\bkeys\b.*Set|\]\);?\s*$(?!.)/;
const hallazgos = [];

for (const ruta of archivos(join(raiz, 'src'))) {
  const nombre = ruta.slice(raiz.length).replaceAll('\\', '/');
  const lineas = readFileSync(ruta, 'utf8').split(/\r?\n/);
  const permitido = (palabra) => PERMITIDOS.some(([a, p]) => p === palabra && nombre.includes(a));
  lineas.forEach((linea, i) => {
    const anotar = (palabra, detalle) => {
      if (!permitido(palabra)) hallazgos.push(`${nombre}:${i + 1} «${palabra}» (${detalle}) ${linea.trim().slice(0, 90)}`);
    };
    for (const t of tablas) {
      if (mapa.tablas[t].nuevo === t) continue;
      if (new RegExp(`(from\\(\\s*['"]${t}['"]|table:\\s*['"]${t}['"])`).test(linea)) anotar(t, 'tabla');
    }
    if (ruta.endsWith('.css')) {
      for (const [v, detalle] of viejos) {
        if (new RegExp(`(\\.pr-status-|\\.pr-|\\.production-badge\\.|\\.delivery-status\\.|data-type="|data-status=")${v}\\b`).test(linea)) anotar(v, detalle);
      }
      return;
    }
    if (IGNORAR_LINEA.test(linea)) return;
    for (const [v, detalle] of viejos) {
      // Solo literales usados como valor: comparaciones, listas, opciones, argumentos.
      const patron = new RegExp(`([!=]==\\s*|\\.includes\\(|value=|useState\\(|\\?\\s*|:\\s*|\\[\\s*|,\\s*|\\(\\s*)['"]${v.replace('.', '\\.')}['"]`);
      if (patron.test(linea)) anotar(v, detalle);
    }
    if (/\?(type|status)=/.test(linea)) {
      for (const m of linea.matchAll(/\?(?:type|status)=([a-z_]+)/g)) {
        if (viejos.has(m[1])) anotar(m[1], 'valor en la dirección');
      }
    }
  });
}

for (const h of hallazgos) console.log(h);
console.log(hallazgos.length ? `${hallazgos.length} posibles restos` : 'Sin restos de la base vieja');
process.exitCode = hallazgos.length ? 1 : 0;
