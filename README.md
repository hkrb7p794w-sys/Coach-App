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
| 4b | Garmin-Werte wie im HA-Dashboard: Erholungsverläufe, SpO2, Atemfrequenz, VO2max, km/Woche, HF-Zonen | in Arbeit (PR 6) |
| 5 | Gym: Plan, Sätze loggen, Progression, Sätze je Muskel, Verlauf, Speichern in Apple Health | in Arbeit (PR 7) |

## Installation auf dem iPhone

Siehe [docs/sidestore.md](docs/sidestore.md). Kurz: Release-Asset `Coach.ipa` laden und in SideStore öffnen.

Garmin, KI-Worker und App verbinden: [docs/einrichtung.md](docs/einrichtung.md).

## Entwicklung

Kein Mac nötig – gebaut wird in GitHub Actions. Details, Befehle und Regeln: [CLAUDE.md](CLAUDE.md).
Architekturentscheidungen mit Quellen: [docs/decisions.md](docs/decisions.md).
