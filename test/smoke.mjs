/**
 * Durchklick-Test für ImmoCheck.
 *
 *   node test/smoke.mjs "https://xxxx.supabase.co" "<anon key>"
 *
 * Startet einen lokalen Webserver für index.html, legt einen Testnutzer an,
 * erstellt eine Immobilie, führt eine Begehung durch, bearbeitet und blendet
 * eine Frage aus, schließt einen Bereich aus und erzeugt ein PDF.
 *
 * Braucht eine echte Supabase-Datenbank. Am besten eine getrennte Testinstanz,
 * denn der erste registrierte Nutzer wird automatisch Administrator.
 */
import { chromium } from 'playwright';
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const wurzel = path.dirname(fileURLToPath(import.meta.url)) + '/..';
const [, , URL_ARG, KEY_ARG] = process.argv;
if (!URL_ARG || !KEY_ARG) {
  console.error('Aufruf: node test/smoke.mjs "https://xxxx.supabase.co" "<anon key>"');
  process.exit(1);
}

const html = fs.readFileSync(path.join(wurzel, 'index.html'), 'utf8')
  .replace('"__SUPABASE_URL__"', JSON.stringify(URL_ARG))
  .replace('"__SUPABASE_KEY__"', JSON.stringify(KEY_ARG));

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' });
  res.end(html);
}).listen(8123);

const fehler = [];
const log = (...a) => console.log('•', ...a);
const b = await chromium.launch();
const ctx = await b.newContext({ acceptDownloads: true, viewport: { width: 1280, height: 950 } });
const p = await ctx.newPage();
p.on('pageerror', e => fehler.push('PAGEERROR: ' + e.message));
p.on('console', m => { if (m.type() === 'error') fehler.push('CONSOLE: ' + m.text().slice(0, 180)); });

try {
  await p.goto('http://localhost:8123/');
  await p.waitForTimeout(2200);
  await p.click('#tab-signup');
  await p.fill('#in-name', 'Testprüfer');
  await p.fill('#in-email', `test${Date.now()}@immocheck.local`);
  await p.fill('#in-pass', 'test123456');
  await p.click('#auth-btn');
  await p.waitForSelector('#app:not(.hidden)', { timeout: 25000 });
  log('Anmeldung funktioniert');

  await p.click('#nav-tabs button:has-text("Vorlagen")');
  await p.waitForSelector('text=Standard-Kataloge', { timeout: 15000 });
  await p.waitForTimeout(600);
  log('Vorlagen werden geladen');

  await p.click('#nav-tabs button:has-text("Immobilien")');
  await p.waitForTimeout(1200);
  await p.click('button:has-text("+ Immobilie")');
  await p.waitForSelector('.modal');
  await p.fill('input[name="name"]', 'Testobjekt ' + new Date().toISOString().slice(0, 10));
  await p.selectOption('select[name="object_type"]', 'einzimmerwohnung');
  await p.click('.modal button[type="submit"]');
  await p.waitForSelector('h1:has-text("Testobjekt")', { timeout: 15000 });
  log('Immobilie angelegt');

  await p.click('button:has-text("+ Neue Begehung")');
  await p.waitForSelector('.tpl-list', { timeout: 10000 });
  const katalog = await p.textContent('.tpl.on .txt strong');
  await p.click('.modal button[type="submit"]');
  await p.waitForSelector('.stickybar', { timeout: 30000 });
  await p.waitForTimeout(1500);
  const anzahl = await p.$$eval('.crit', c => c.length);
  log(`Begehung gestartet: ${katalog.trim()} mit ${anzahl} Fragen`);

  await p.click('.cat >> nth=0 >> .cat-head');
  await p.waitForTimeout(400);
  await p.click('.cat >> nth=0 >> .crit >> nth=0 >> .pres button[data-v="vorhanden"]');
  await p.waitForTimeout(700);
  await p.click('.cat >> nth=0 >> .crit >> nth=0 >> .emojis button >> nth=4');
  await p.waitForTimeout(700);
  log('Bewertung gesetzt');

  p.once('dialog', d => d.accept('Im Test nicht relevant'));
  await p.click('.cat >> nth=0 >> .crit >> nth=1 >> .item-menu button');
  await p.waitForSelector('.menu-pop');
  await p.click('.menu-pop button:has-text("Frage ausblenden")');
  await p.waitForTimeout(2500);
  if (!(await p.$('.hidden-box'))) fehler.push('FEHLER: ausgeblendete Frage nicht sichtbar');
  log('Frage ausgeblendet');

  p.once('dialog', d => d.accept('Im Test ausgeschlossen'));
  await p.click('.cat >> nth=1 >> button:has-text("Bereich ausschließen")').catch(async () => {
    await p.click('.cat >> nth=1 >> .cat-head');
    await p.waitForTimeout(400);
    await p.click('.cat >> nth=1 >> button:has-text("Bereich ausschließen")');
  });
  await p.waitForTimeout(2500);
  if (!(await p.$('.cat.skipped'))) fehler.push('FEHLER: Bereich wurde nicht ausgeschlossen');
  log('Bereich ausgeschlossen');

  p.once('dialog', d => d.accept());
  await p.click('button:has-text("Begehung abschließen")');
  await p.waitForSelector('button:has-text("PDF herunterladen")', { timeout: 25000 });
  await p.waitForTimeout(1200);

  const dl = p.waitForEvent('download', { timeout: 60000 });
  await p.click('button:has-text("PDF herunterladen")');
  const d = await dl;
  const ziel = '/tmp/immocheck-test.pdf';
  await d.saveAs(ziel);
  log('PDF erzeugt:', Math.round(fs.statSync(ziel).size / 1024) + ' KB ->', ziel);
} catch (e) {
  fehler.push('ABBRUCH: ' + e.message);
} finally {
  await b.close();
  server.close();
}

console.log('\n' + (fehler.length ? 'PROBLEME:\n' + fehler.join('\n') : 'ALLE TESTS BESTANDEN'));
process.exit(fehler.length ? 1 : 0);
