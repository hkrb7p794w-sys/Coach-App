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
| 12 | Optional: inoffizieller Garmin-Login (Readiness, Trainingsstatus, Endurance Score, Schreiben zu Garmin) | offen |

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
