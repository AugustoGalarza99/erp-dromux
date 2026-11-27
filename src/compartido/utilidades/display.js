/*
 * Texto "para personas": nada de identificadores internos en pantalla.
 * Los lotes iniciales se crean en la base con el código "Inicial <depósito> <uuid>";
 * el valor guardado no se toca (sirve para operar), solo lo que se muestra.
 */
const UUID_SOURCE = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const UUID_ANYWHERE = new RegExp(UUID_SOURCE, 'gi');
const INITIAL_LOT = new RegExp(`^Inicial\\s*(.*?)\\s*${UUID_SOURCE}$`, 'i');

/* "2026-11-23" → "23/11/2026" (sin desfase de zona horaria). */
export function dateEs(value) {
  const text = String(value ?? '');
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  return match ? `${match[3]}/${match[2]}/${match[1]}` : text;
}

/*
 * Fecha y hora en formato de 24 horas. Sin `hourCycle`, algunos navegadores muestran las 13:05
 * como "01:05" sin aclarar si es de tarde.
 */
export const dateTimeEs = (value) =>
  new Date(value).toLocaleString('es-AR', { hourCycle: 'h23' });

export const hasInternalId = (text) => new RegExp(UUID_SOURCE, 'i').test(String(text ?? ''));

export function stripIds(text) {
  return String(text ?? '')
    .replace(UUID_ANYWHERE, '')
    .replace(/\s{2,}/g, ' ')
    .replace(/[\s·:-]+$/, '')
    .trim();
}

/* Código de lote legible: "Inicial (central)" en lugar de "Inicial central 9f3a…". */
export function lotLabel(code) {
  const text = String(code ?? '').trim();
  const initial = text.match(INITIAL_LOT);
  if (initial) return initial[1] ? `Inicial (${initial[1]})` : 'Inicial';
  return stripIds(text) || 'Sin código';
}
