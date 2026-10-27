# Coach

Native iPhone-App, die Garmin-Coaching, Ernährung und Gym-Logging vereint – unabhängig von Home Assistant.

Kein eigener Server nötig:

```
iPhone (SwiftUI, SwiftData, Regeln in CoachCore)
  ├─ HTTPS ─► Garmin Connect Personal API (offiziell, Key im Keychain)
  ├─ HTTPS ─► Open Food Facts (Barcode, Daten unter ODbL)
  └─ HTTPS ─► Cloudflare Worker ─► Gemini / Groq (KI-Keys nur im Worker)
```

## Stand

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Gerüst, CI, leere App mit HealthKit-Diagnose | fertig (PR 1) |
| 2 | Garmin-Anbindung (Personal API), lokale Datenhaltung, KI-Worker auf Cloudflare | fertig (PR 2) |
| 3 | Coach: Tagesempfehlung, Erholung, Wochen-Soll/Ist, Rennvorbereitung | fertig (PR 3) |
| 4 | Ernährung: Foto, Text, Barcode; Tagesziele nach Training; KI-Auswertung | fertig (PR 4) |
| 4b | Garmin-Werte wie im HA-Dashboard: Erholungsverläufe, SpO2, Atemfrequenz, VO2max, km/Woche, HF-Zonen | fertig (PR 6) |
| 5 | Gym: Plan, Sätze loggen, Progression, Sätze je Muskel, Verlauf, Speichern in Apple Health | fertig (PR 7) |
| 6 | Automatische Releases bei jedem Merge, SideStore-Quelle mit Update-Hinweis | fertig (PR 8) |
| 7 | Wissenschaftliche Basis: Quelle (DOI) je Regel, KI nur mit geprüften Fakten | fertig (PR 9) |
| 8 | Reiter „Plan“: alle Einheiten der Saison mit Inhalt (Lauf, Schwimmen, Rad, Gym) | fertig (PR 10) |
| 9 | Design-Überarbeitung (Designsystem, Heute-Ansicht) | in Arbeit (Heute fertig: PR 12) |
| 10 | Disziplinen wie im HA-Dashboard: Tests und Trends (CSS, FTP, Schwelle), Pace-Check, Wettkampfläufe, Zielzeit Almere, Marathon | fertig (PR 11, Pace-Check und aerobe Kopplung PR 13) |
| 11 | Tagesform & Leistung, Schlafanalyse, Wochenreport mit Vorschlägen, Chat, Erinnerungen | offen |
| 12 | Garmin-Konto als Hauptquelle (Readiness, Trainingsstatus, Endurance Score, Prognosen), Personal API als Rückfall | fertig (PR 15) |
| 13 | Personalisierung: Sportarten, Ziele, Wettkampf oder allgemeine Fitness, eigener Wochenplan mit Ruhetagen, Schutzgrenzen | fertig (PR 16) |
| 14 | Erzeugte Trainingspläne mit Progression (Laufen, Gym) und KI-Notiz für persönliche Profile | offen |
| 15 | Erinnerungen an Trainingstage (Mitteilung oder Karte unter „Heute“), Einheit verschieben oder diese Woche auslassen | fertig (PR 17) |
| 16 | Begleiter (Trainer, Avatar, z. B. Hund „Daisy“), der motiviert | fertig (PR 18) |
| 17 | Rangliste zwischen Nutzern (Punkte für Planerfüllung, keine Gesundheitsdaten), Einladungslink | fertig (PR 18) |
| 18 | Gym-App nach Vorbild GymBook: Übungsbibliothek mit Anleitung, eigene Routinen und Vorschläge, Verlauf mit 1RM und Rekorden, Wiederholungen in Reserve, KI-Tipps zur Gewichtssteigerung | fertig (PR 21) |
| 19 | Rezeptideen für die kommende Woche aus Tageszielen, Trainingsplan, Ernährungsweise, Allergenen und Lücken der letzten Wochen; Einkaufsliste | fertig (PR 22) |
| 20 | Einheiten ausführlich erklärt (Ablauf, Gefühl, Fehler, Glossar) | fertig (PR 23) |
| 21 | Sicherungen: Eingabeprüfung (Zielzeit gegen Prognose), Gewichtsverlauf mit Nachsteuerung, Laufumfang-Warnung, strengere Rezeptprüfung, Prüfbericht mit Musterpersonen in jeder PR | fertig (PR 24, Makros PR 25) |
| 22 | Vergleich mit Bezahl-Apps: Screenshots in CI, gemessener Verbrauch, Fitness/Form, Wochenbericht, Laufplan mit Steigerung, Gym-Komfort | in Arbeit (PR 26) |

Später, erst auf Zuruf und wenn alles andere läuft: Apple Watch bzw. Apple Health als weitere Quelle,
technische Einstellungen für Mitnutzer ausblenden, Android-Version.

Maßstab für 7–12 ist der Funktionsumfang des Home-Assistant-Stands (Garmin AI Coach 0.29.3, Übergabe vom
26.10.2026).

## Installation auf dem iPhone

Siehe [docs/sidestore.md](docs/sidestore.md). Kurz: einmal die Quelle
`https://github.com/hkrb7p794w-sys/Coach-App/releases/latest/download/source.json` in SideStore eintragen und
Coach daraus installieren; neue Versionen meldet SideStore dann selbst.

Garmin, KI-Worker und App verbinden: [docs/einrichtung.md](docs/einrichtung.md).

## Entwicklung

Kein Mac nötig – gebaut wird in GitHub Actions. Details, Befehle und Regeln: [CLAUDE.md](CLAUDE.md).
Architekturentscheidungen mit Quellen: [docs/decisions.md](docs/decisions.md).
