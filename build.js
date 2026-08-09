#!/usr/bin/env node
/**
 * Baut aus src/app.html die auslieferbaren Dateien.
 *
 *   node build.js
 *     -> index.html          (öffentliche Version, fragt beim ersten Start nach der Datenbank)
 *     -> ImmoCheck-privat.html  (nur wenn privat.json existiert, mit fest eingebauter Verbindung)
 *
 * Die drei Bibliotheken aus vendor/ werden direkt in die HTML eingebettet,
 * damit die App eine einzige Datei ohne Netzabhängigkeiten bleibt.
 */
const fs = require("fs");
const path = require("path");

const wurzel = __dirname;
const quelle = path.join(wurzel, "src", "app.html");
let html = fs.readFileSync(quelle, "utf8");

const libs = [
  ["https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.47.10/dist/umd/supabase.js", "vendor/supabase.js"],
  ["https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js", "vendor/jspdf.umd.min.js"],
  ["https://cdn.jsdelivr.net/npm/jspdf-autotable@3.8.4/dist/jspdf.plugin.autotable.min.js", "vendor/jspdf.plugin.autotable.min.js"]
];

for (const [url, datei] of libs) {
  const tag = `<script src="${url}"></script>`;
  if (!html.includes(tag)) {
    console.error("Script-Tag nicht gefunden:", url);
    process.exit(1);
  }
  const code = fs.readFileSync(path.join(wurzel, datei), "utf8").replace(/<\/script>/gi, "<\\/script>");
  html = html.replace(tag, `<script>/* ${path.basename(datei)} */\n${code}\n</script>`);
}

fs.writeFileSync(path.join(wurzel, "index.html"), html);
console.log("index.html geschrieben:", Math.round(html.length / 1024) + " KB");

const privatDatei = path.join(wurzel, "privat.json");
if (fs.existsSync(privatDatei)) {
  const { url, key } = JSON.parse(fs.readFileSync(privatDatei, "utf8"));
  if (!url || !key) {
    console.error("privat.json braucht die Felder url und key");
    process.exit(1);
  }
  let privat = html
    .replace('"__SUPABASE_URL__"', JSON.stringify(url))
    .replace('"__SUPABASE_KEY__"', JSON.stringify(key));
  if (privat.includes("__SUPABASE_URL__")) {
    console.error("Platzhalter konnten nicht ersetzt werden");
    process.exit(1);
  }
  fs.writeFileSync(path.join(wurzel, "ImmoCheck-privat.html"), privat);
  console.log("ImmoCheck-privat.html geschrieben (nicht im Repo, steht in .gitignore)");
} else {
  console.log("privat.json fehlt, private Version wurde übersprungen");
}
