# ImmoCheck, Arbeitsanweisung für Claude

Dieses Dokument beschreibt das Projekt so, dass du in Claude Code sofort weiterarbeiten und veröffentlichen kannst.

## Was das ist

Eine Single-File-Webanwendung für die Sicherheits- und Qualitätskontrolle von Immobilien. Der Nutzer legt Objekte an, führt Begehungen anhand von Fragenkatalogen durch, bewertet jeden Punkt mit einer Emoji-Skala von 1 bis 5, macht Fotos und lädt am Ende ein PDF-Protokoll herunter. Backend ist Supabase (Datenbank, Anmeldung, Dateispeicher), es gibt keinen eigenen Server.

Zielgruppe sind Immobilienbesitzer und Hausverwaltungen, die Anwendung wird am Handy während der Begehung bedient.

## Aufbau

```
src/app.html      Quelldatei. HIER wird editiert, nirgendwo sonst.
vendor/           supabase-js, jsPDF, jspdf-autotable als fertige Bundles
build.js          bettet vendor/ in src/app.html ein, erzeugt index.html
index.html        Ergebnis des Builds, wird von GitHub Pages ausgeliefert. NIE direkt bearbeiten.
setup.sql         komplettes Datenbank-Setup für Supabase, idempotent
deploy.sh         bauen, committen, pushen, GitHub Pages einschalten
test/smoke.mjs    Durchklick-Test mit Playwright
privat.json       lokale Zugangsdaten, steht in .gitignore, nie einchecken
```

Nach jeder Änderung an `src/app.html` **muss** `node build.js` laufen, sonst ändert sich die ausgelieferte Datei nicht.

## Veröffentlichen

```bash
./deploy.sh "Was sich geändert hat"
```

Das Skript baut, committet, pusht und schaltet beim ersten Lauf GitHub Pages ein. Danach ist der öffentliche Link nach etwa einer Minute aktuell. Voraussetzung ist eine angemeldete GitHub CLI (`gh auth status`).

Wenn der Nutzer sagt "veröffentliche", "lade hoch", "mach es live" oder Ähnliches: Build, kurzer Test, dann `deploy.sh` mit einer aussagekräftigen Nachricht auf Deutsch.

## Verbindung

Seit August 2026 sind Project URL und `anon` key **fest in `src/app.html` eingebaut**, damit sich Leute
einfach anmelden können, ohne selbst eine Datenbank einzurichten.

- Projekt: `immo-check`, Ref `mqmevpyatjsambervgtu`, Region eu-central-1
- Der `anon` key steht damit öffentlich in `index.html`. Das ist bei Supabase der vorgesehene Weg,
  geschützt wird über Row Level Security, die auf allen Tabellen aktiv ist.
- **Niemals den `service_role` key einbauen.** Vor jedem Push prüfen, dass im Token `"role":"anon"` steht.
- `ImmoCheck-privat.html` entsteht nur, wenn `privat.json` existiert, und darf nicht ins Repository.
  Die gleichnamige Datei in `Downloads` enthält private Zugangsdaten und ist tabu.

## Stand der Funktionen

Anmeldung mit E-Mail und Passwort, ohne Bestätigungsmail (Trigger `trg_auto_confirm_email`).
Erste Registrierung wird Administrator, alle weiteren stehen auf `wartend` und müssen freigeschaltet werden.

- **Gebäudestruktur:** Aufzüge, Kellerabteile, Dachbodenabteile, Zimmer, Gänge, Kellergeschosse,
  dazu Mehrfachauswahl für Leitungen und Ausstattung je Ebene.
- **Einheiten:** duplizieren (`duplicateUnit`) und mehrfach anlegen; `naechsteBezeichnung` zählt hoch
  („Top 1" wird „Top 2"), vergebene Namen werden übersprungen, Mieterdaten werden nicht mitkopiert.
- **Antworttypen:** `skala`, `ja_nein`, `messwert` (mit Einheit und Bereich), `auswahl`, `text`.
  Nur `skala` fließt in die Note.
- **Eigene Fragen je Objekt:** `criteria.property_id`. `S.criteria` lädt bewusst nur globale Punkte
  (`.is("property_id", null)`), sonst verschmutzen sie Katalog und Vorlagen.
- **Objektgebundene Kataloge:** `templates.property_id`.
- **Papierbogen:** `makePaperSheet()` druckt einen Ankreuzbogen, jede Antwortart bekommt die passende Form.
  Messwerte bekommen Einzelkästchen für die Ziffern.
- **Auslesen:** Kreuze und Ziffern werden lokal im Browser erkannt, ohne externen Dienst.
- **Auswertung:** `analysiere()` ist regelbasiert und liefert Ampel, Urteil, Empfehlung und Befunde.
- **Notizen und Diktat:** je Raum, Schadenswörter werden erkannt, fließt in die Auswertung.
- **Termine:** `inspection_plans` plus iCalendar-Datei mit Wiederholung und Erinnerung.

## Fallen, die schon einmal Fehler verursacht haben

Diese Punkte sind teuer erkauft. Bitte nicht rückgängig machen.

1. **Ampel nie grün bei unvollständiger Begehung.** Über 30 Prozent unbearbeitete Punkte müssen zu
   „Für ein Urteil wurde zu wenig geprüft" führen, sonst ist das Urteil irreführend.
2. **Örtliche Schwelle beim Bildauslesen.** Eine globale Otsu-Schwelle kippt bei ungleicher
   Ausleuchtung, und die hat jedes Handyfoto.
3. **Passermarken auf allen vier Seiten einzeln prüfen.** Sonst wird die Ecke des blauen Kopfbalkens
   für eine Marke gehalten und alles verrutscht.
4. **Auflösung nicht senken.** Scans mit max 2600 px speichern, mit max 2400 px auslesen. Sonst sind
   die Ziffernkästchen nur wenige Pixel breit und die Zeichenerkennung bricht zusammen.
5. **Mindest-Tintenschwelle nicht anheben**, sonst fallen Komma und Minus komplett durch.
6. **Datum niemals über `toISOString()` formatieren.** In `naechsterTermin()` war der Termin dadurch
   je nach Zeitzone einen Tag zu früh. Örtlich formatieren.
7. **Kästchen leer drucken.** Die Bedeutung („1 = Ja, 2 = Nein") gehört neben die Frage, nicht in das
   Kästchen, sonst hält der Leser die gedruckten Zeichen für ein Kreuz.
8. **Schemaänderungen immer auch in `setup.sql`**, idempotent, und die `alter table` erst **nach** dem
   `create table` der betroffenen Tabelle.

## Was bewusst nicht automatisch geht

- **Freie Handschrift** wird nicht erkannt. Ziffern in vorgegebenen Kästchen ja, ganze Sätze nein.
  Anmerkungen werden abgetippt.
- **Diktat** läuft über die Spracherkennung des Browsers, also Google bei Chrome, Apple bei Safari.
  Das ist der einzige Teil, der Daten nach außen gibt; Kreuze und Ziffern rechnen lokal.
  Der Hinweis dazu steht in der Oberfläche und muss dort bleiben.
- **Outlook im Web** kann über einen Link keine Wiederholung anlegen, dafür ist die Termindatei da.

## Datenmodell

| Tabelle | Zweck |
|---|---|
| `profiles` | Nutzer mit `role` (admin, mitarbeiter) und `status` (aktiv, wartend, gesperrt) |
| `properties` | Immobilien mit Objektart, Adresse, Baujahr, Kontaktdaten |
| `units` | einzelne Wohnungen innerhalb eines Objekts |
| `categories` | 21 Prüfbereiche |
| `criteria` | 179 Prüfpunkte, mit `scope` (gebaeude, einheit, beide) und `critical` |
| `templates` + `template_criteria` | Fragenkataloge je Objektart |
| `inspections` | Begehungen mit Bewertung, `skipped_categories` als JSON |
| `inspection_items` | Einzelergebnisse mit `presence`, `rating`, `hidden`, Foto |

Alles ist per Row Level Security abgesichert. Die Hilfsfunktionen `is_active_user()` und `is_admin()` sind SECURITY DEFINER, damit die Policies nicht rekursiv werden. Die erste Registrierung wird per Trigger automatisch Administrator und aktiv, alle weiteren landen auf `wartend`.

Schemaänderungen gehören **immer** zusätzlich in `setup.sql`, sonst bekommen neue Installationen sie nicht. Das Skript muss idempotent bleiben (`create table if not exists`, `drop policy if exists`, `on conflict do nothing`).

## Konventionen

- Alle Texte in der Oberfläche auf Deutsch, gesiezt wird nicht, geduzt schon.
- Kein Gedankenstrich (Geviertstrich) in Texten, stattdessen Komma, Doppelpunkt oder zwei Sätze.
- Keine Frameworks, kein Build-Schritt außer `build.js`. Vanilla JavaScript, Template-Strings, direkte DOM-Manipulation.
- Farben stehen als CSS-Variablen in `:root`: Blau als Hauptfarbe, Rot als Akzent, heller Hintergrund.
- Nutzereingaben immer durch `esc()` schleusen, bevor sie in HTML landen.
- Jede Änderung an der Begehungsansicht muss den Zustand der aufgeklappten Bereiche erhalten, siehe `renderInspection()`.
- Ausgeblendete Punkte und ausgeschlossene Bereiche zählen nicht in die Bewertung, erscheinen aber nachvollziehbar im PDF.

## Testen

```bash
npm install playwright
npx playwright install chromium     # nur beim ersten Mal
node test/smoke.mjs "https://xxxx.supabase.co" "<anon key>"
```

Der Test startet einen lokalen Webserver, registriert einen Testnutzer, legt eine Immobilie an, führt eine Begehung durch, blendet eine Frage aus, schließt einen Bereich aus und erzeugt ein PDF. Er braucht eine echte Supabase-Datenbank, am besten eine getrennte Testinstanz. Aufräumen der Testdaten macht der Test nicht, das ist Absicht, damit man nachsehen kann.

Vor jeder Veröffentlichung mindestens `node build.js` und einen Blick in die Konsole des Browsers.

## Bekannte Stolpersteine

- Supabase liefert HTML-Dateien aus dem Storage als reinen Text aus, taugt also nicht zum Hosten dieser App.
- Der UMD-Build von supabase-js verträgt kein Inlining, deshalb liegt in `vendor/supabase.js` ein mit esbuild erzeugtes IIFE-Bundle. Neu bauen mit:
  `echo 'export * from "@supabase/supabase-js";' > entry.js && npx esbuild entry.js --bundle --format=iife --global-name=supabase --minify --outfile=vendor/supabase.js`
- jsPDF kennt keine Emojis. Im PDF werden Bewertungen deshalb als Text und Zahl ausgegeben, nicht als Symbol.
- Supabase im Gratis-Tarif erlaubt nur zwei aktive Projekte und verschickt nur wenige Mails pro Stunde. Deshalb ist die E-Mail-Bestätigung per Trigger überbrückt und sollte zusätzlich im Dashboard abgeschaltet werden.
