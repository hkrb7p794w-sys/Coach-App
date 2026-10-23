# CLAUDE.md – Coach-App

Native iPhone-App „Coach“: vereint Garmin-Coaching, Ernährung und (später) Gym-Logging.
Läuft unabhängig von Home Assistant. Der Nutzer hat **keinen Mac** (Windows-PC, iPad, iPhone):
Gebaut wird ausschließlich in GitHub Actions, installiert per SideStore (kostenlose Apple-ID).

## Struktur

| Pfad | Inhalt |
|---|---|
| `ios/project.yml` | XcodeGen-Spezifikation (das `.xcodeproj` wird erzeugt, nicht eingecheckt) |
| `ios/Coach/` | SwiftUI-App, MVVM: `App/`, `Features/<Bereich>/` (View + ViewModel), `Core/` (Health, API, Persistenz, UI-Bausteine) |
| `ios/CoachTests/` | App-Tests (Swift Testing), laufen nur im Simulator (macOS) |
| `ios/Packages/CoachCore/` | Reine Logik **ohne** Apple-Frameworks – testbar auf Linux mit `swift test` |
| `backend/` | Python-Dienst (FastAPI, uv): Garmin-Sync, Regeln, KI-Aufrufe |
| `docs/` | Entscheidungen (`decisions.md`) und Anleitungen für den Nutzer |
| `.github/workflows/` | `ios-build.yml` (macOS, nur manuell), `swift.yml` und `backend.yml` (Linux/Windows, bei PRs) |

Altbestand (nur lesen, Logik übernehmen, keine HA-/MQTT-Teile): `hkrb7p794w-sys/Garmin-AI-Coach`
(`garmin_ai_coach/` Coach-Regeln und Prompts, `ernaehrung/app/` Ernährung, `fit_coach/app/garmin_sync.py` Login mit MFA).

## Grundregeln

- **Regeln entscheiden, KI formuliert.** Tagesampel, Ziele und Progression sind deterministisch und getestet;
  Gemini/Groq liefern nur Text. Fällt die KI aus, bleibt die Empfehlung korrekt.
- **KI-Aufrufe und API-Keys nur im Backend**, nie in der App. Datenschutzmodus „reduziert“ ist Standard
  (keine Roh-Gesundheitswerte an kostenlose KI-Kontingente).
- **Keine Secrets im Repo** (Keys, Tokens, Tailscale-Namen, Garmin-Daten). Sie liegen in GitHub-Secrets bzw.
  in der `.env` des Backends.
- **HealthKit ist optional.** SideStore mit kostenloser Apple-ID entfernt das Entitlement
  (siehe `docs/decisions.md`). Jede HealthKit-Funktion prüft `HealthAccessDiagnosis.isUsable` und hat einen Weg ohne.
- UI-Texte auf Deutsch mit echten Umlauten. Code-Bezeichner auf Englisch, Kommentare auf Deutsch.
- iOS 18+, Swift 6, Xcode 26 (Standard-Isolation `MainActor`, Approachable Concurrency).
- Logik, die sich ohne Apple-Frameworks formulieren lässt, gehört nach `CoachCore` – mit Tests.

## Befehle

```sh
# Backend
cd backend && uv sync && uv run ruff check . && uv run ruff format --check . && uv run pytest

# Swift (Linux oder Mac, Swift 6.2)
swift format lint --strict --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore
swift format --in-place --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore
swift test --package-path ios/Packages/CoachCore

# iOS-Projekt (nur macOS)
cd ios && xcodegen generate
```

## CI

- `swift.yml`, `backend.yml`: automatisch bei PRs und auf `main` (günstige Linux-/Windows-Runner).
- `ios-build.yml`: **nur manuell**, weil macOS-Minuten teuer sind. Auslösen per „Run workflow“ oder per
  PR-Label `ios-build` (Label wird beim Start entfernt). Ergebnis bzw. Fehlerauszug kommt als PR-Kommentar,
  die `.ipa` als GitHub-Release-Asset (PR-Builds als Vorabversion).
- Aus Claude-Code-Cloud-Sitzungen ist die Actions-API gesperrt: Builds per Label starten, Ergebnisse über
  Check-Runs (`/commits/{sha}/check-runs`), PR-Kommentare und Releases lesen.

## Konventionen

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `test:`, `refactor:`), Scope optional
  (`feat(ios): …`, `fix(backend): …`).
- Eine PR pro Phase; Phasen und Stand siehe `README.md`.
- Entscheidungen gegen offizielle Doku prüfen und in `docs/decisions.md` mit Quelle festhalten.
