import { readFile, writeFile } from 'node:fs/promises';

const [version, title, ...changeEntries] = process.argv.slice(2);
if (!/^\d{3,}$/.test(version ?? '') || !title?.trim() || !changeEntries.length) {
  process.stderr.write('Uso: npm run release -- 029 "Título" "Cambio 1" "Cambio 2"\n');
  process.exitCode = 1;
} else {
  const metaPath = new URL('../public/meta.json', import.meta.url);
  const updatesPath = new URL('../public/updates.json', import.meta.url);
  const current = JSON.parse(await readFile(metaPath, 'utf8'));
  const history = JSON.parse(await readFile(updatesPath, 'utf8'));
  if (Number(version) <= Number(current.version)) {
    throw new Error(`La nueva versión debe ser mayor que ${current.version}.`);
  }
  const date = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'America/Argentina/Buenos_Aires',
  }).format(new Date());
  const cleanTitle = title.trim();
  const next = { version, publishedAt: date, title: cleanTitle };
  history.unshift({ ...next, changes: changeEntries.map((entry) => entry.trim()) });
  await writeFile(metaPath, `${JSON.stringify(next, null, 2)}\n`);
  await writeFile(updatesPath, `${JSON.stringify(history, null, 2)}\n`);
  process.stdout.write(`Versión ${version} preparada. Ejecutá npm run build y publicá dist/.\n`);
}
