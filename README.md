# Coach

Native iPhone-App, die Garmin-Coaching, Ernährung und Gym-Logging vereint – unabhängig von Home Assistant.

Kein eigener Server nötig:

```
iPhone (SwiftUI, SwiftData, Regeln in CoachCore)
  ├─ HTTPS ─► Garmin Connect Personal API (offiziell, Key im Keychain)
  ├─ HTTPS ─► Open Food Facts (Barcode)
  └─ HTTPS ─► Cloudflare Worker ─► Gemini / Groq (KI-Keys nur im Worker)
```

## Stand

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Gerüst, CI, leere App mit HealthKit-Diagnose | in Arbeit |
| 2 | Garmin-Anbindung (Personal API), lokale Datenhaltung, KI-Worker auf Cloudflare | offen |
| 3 | Coach: Tagesempfehlung, Erholung, Wochen-Soll/Ist, Rennvorbereitung | offen |
| 4 | Ernährung: Foto, Text, Barcode; Tagesziele nach Training; KI-Auswertung | offen |
| 5 | Gym: Übungen, Sätze, Verlauf, Speichern in HealthKit bzw. Garmin | offen |

## Installation auf dem iPhone

Siehe [docs/sidestore.md](docs/sidestore.md). Kurz: Release-Asset `Coach.ipa` laden und in SideStore öffnen.

## Entwicklung

Kein Mac nötig – gebaut wird in GitHub Actions. Details, Befehle und Regeln: [CLAUDE.md](CLAUDE.md).
Architekturentscheidungen mit Quellen: [docs/decisions.md](docs/decisions.md).
