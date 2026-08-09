<div align="center">

# 🏠 ImmoCheck

**Digitale Sicherheits- und Qualitätskontrolle für Immobilien**

Begehung durchführen, bewerten, fotografieren, Protokoll als PDF.
Eine einzige HTML-Datei. Keine Installation, kein Abo, keine fremden Server.

</div>

---

## Warum

Wer Wohnungen oder Häuser besitzt oder verwaltet, prüft sie regelmäßig: Rauchmelder, Feuchtigkeit, Elektrik, Fluchtwege, Dach, Heizung. Meistens auf Zetteln, im Kopf oder gar nicht. Wenn dann etwas passiert, fehlt der Nachweis.

ImmoCheck macht daraus einen wiederholbaren Ablauf: Objekt anlegen, Begehung starten, 179 Prüfpunkte durchgehen, bewerten, fotografieren, PDF erzeugen. Beim nächsten Mal siehst du sofort, was sich verändert hat.

## Was drin ist

- **179 Prüfpunkte in 21 Kategorien** — Dach, Fassade, Keller, Fenster, Elektro, Heizung, Sanitär, Brandschutz, Sicherheit, Schimmel, Schadstoffe, Innenräume, Küche, Treppenhaus, Außenanlagen, Aufzug, Energie, Entsorgung, Dokumente, Mietverhältnis
- **Sieben Fragenkataloge je Objektart** — vom Kompaktcheck für die Einzimmerwohnung (43 Fragen) über Wohnung (87), Einfamilienhaus, Mehrfamilienhaus und Gewerbe bis zur vollständigen Prüfung (179). Dazu ein Sicherheits-Schnellcheck mit 24 kritischen Punkten
- **Eigene Kataloge** — neu anlegen oder aus einem bestehenden kopieren und anpassen, Frage für Frage
- **Während der Begehung anpassen** — Fragen umformulieren, einzelne Punkte ausblenden oder ganze Bereiche mit Begründung ausschließen. Beides erscheint nachvollziehbar im Protokoll und fließt nicht in die Bewertung ein
- **Bewertung mit fünf Emojis** — 😡 sehr schlecht · 🙁 schlecht · 😐 mittel · 🙂 gut · 😍 sehr gut
- **Vorhanden / Nicht vorhanden / Nicht relevant** je Punkt, dazu Notiz, Mangel-Markierung, Priorität und Frist
- **Fotos direkt aus der Handykamera**, automatisch verkleinert und verschlüsselt gespeichert
- **Eigene Prüfpunkte** jederzeit ergänzen, auf Wunsch dauerhaft im Katalog
- **Verlauf je Objekt** mit Bewertungstrend über alle Begehungen
- **PDF-Protokoll** mit Objektdaten, Gesamtnote, Mängelliste, allen Kategorien und Fotoanhang
- **Passend für jede Objektgröße** — Einzimmerwohnung, Einfamilienhaus, Mehrfamilienhaus oder ganze Wohnanlage mit einzeln prüfbaren Einheiten
- **Team mit Freigabe** — die erste Registrierung wird Administrator, alle weiteren sehen nichts, bis sie freigegeben werden
- **Läuft am Handy**, gebaut für die Begehung vor Ort, speichert jede Eingabe sofort

## Deine Daten bleiben bei dir

Es gibt keinen zentralen Server dieses Projekts. Die App ist eine reine HTML-Datei, die sich mit **deiner eigenen** [Supabase](https://supabase.com)-Datenbank verbindet. Objekte, Protokolle und Fotos liegen ausschließlich dort, in deinem Konto, in deiner Region. Der Zugriff ist per Row Level Security direkt in der Datenbank abgesichert, nicht nur in der Oberfläche.

## In fünf Minuten startklar

1. **Datenbank anlegen.** Auf [supabase.com](https://supabase.com) kostenlos registrieren, neues Projekt erstellen (Region frei wählbar, für Europa etwa Frankfurt).
2. **Tabellen anlegen.** Im Projekt links auf **SQL Editor**, den Inhalt von [`setup.sql`](setup.sql) einfügen, **Run**. Das legt alle Tabellen, die Sicherheitsregeln, den Fotospeicher und die 179 Prüfpunkte an.
3. **E-Mail-Bestätigung abschalten.** Unter **Authentication → Providers → Email** die Option *Confirm email* ausschalten.
4. **Zugangsdaten kopieren.** Unter **Project Settings → API** die **Project URL** und den **anon public** Schlüssel.
5. **App öffnen** und beide Werte eintragen. Fertig. Deine erste Registrierung ist automatisch Administrator.

Die App kannst du einfach lokal öffnen, auf deinen Webspace legen oder über GitHub Pages betreiben. Es ist eine einzige Datei ohne Abhängigkeiten zur Laufzeit.

## Bewertungslogik

- Gesamtnote = Durchschnitt aller vergebenen Bewertungen von 1 bis 5
- **Mangel** wird manuell markiert und bekommt Priorität und Frist
- **Kritisch** ist ein sicherheitsrelevanter Punkt, der als *nicht vorhanden* markiert ist, oder ein Punkt mit Priorität *kritisch*
- *Nicht relevant* fließt nicht in die Note ein

## Rollen

| | Administrator | Mitarbeiter | Nicht freigegeben |
|---|---|---|---|
| Objekte und Begehungen sehen und bearbeiten | ✓ | ✓ | – |
| Eigene Prüfpunkte anlegen | ✓ | ✓ | – |
| Standard-Prüfpunkte bearbeiten | ✓ | – | – |
| Team freigeben und sperren | ✓ | – | – |

## Technik

Eine HTML-Datei mit eingebettetem JavaScript, ohne Build-Schritt und ohne Framework. [Supabase](https://supabase.com) für Datenbank, Anmeldung und Dateispeicher, [jsPDF](https://github.com/parallax/jsPDF) für die Protokolle. Beide Bibliotheken sind in die Datei eingebettet, es wird zur Laufzeit nichts von fremden Servern nachgeladen.

```
index.html    die komplette App
setup.sql     Datenbank-Setup für Supabase, inklusive Prüfkatalog und Vorlagen
```

## Fragenkataloge

Nicht jede Immobilie braucht alle 179 Fragen. Beim Start einer Begehung wählst du den Katalog, der zur Objektart passt, die Vorauswahl richtet sich nach der erfassten Objektart:

| Katalog | Fragen | Gedacht für |
|---|---|---|
| Einzimmerwohnung, Kompaktcheck | 43 | kleine Mieteinheit, etwa 15 Minuten |
| Wohnung | 87 | einzelne Wohnung ohne Gebäudetechnik |
| Einfamilienhaus | 166 | Haus mit eigenem Grundstück |
| Mehrfamilienhaus und Wohnanlage | 163 | Gebäude und Allgemeinbereiche |
| Gewerbeobjekt | 146 | Betreiberpflichten und Verkehrssicherung |
| Sicherheits-Schnellcheck | 24 | die Runde zwischendurch |
| Vollständige Prüfung | 179 | Übernahme, Ankauf, Jahresrunde |

Eigene Kataloge legst du unter **Vorlagen** an, entweder leer oder als Kopie eines bestehenden.

## Hinweis

ImmoCheck unterstützt bei der eigenen Dokumentation und ersetzt keine gesetzlich vorgeschriebene Prüfung durch Sachverständige, Rauchfangkehrer oder Elektrofachkräfte. Prüfpflichten und Intervalle unterscheiden sich je nach Land und Objektart.

## Lizenz

MIT. Nutzung, Anpassung und Weitergabe frei, auch gewerblich.
