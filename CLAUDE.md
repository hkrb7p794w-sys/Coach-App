# CLAUDE.md – Coach-App

Native iPhone-App „Coach“: vereint Garmin-Coaching, Ernährung und (später) Gym-Logging.
Läuft unabhängig von Home Assistant und ohne eigenen Server: Garmin über die offizielle Personal API direkt
vom iPhone, KI über einen Cloudflare Worker (siehe `docs/decisions.md`). Der Nutzer hat **keinen Mac** (Windows-PC, iPad, iPhone):
Gebaut wird ausschließlich in GitHub Actions, installiert per SideStore (kostenlose Apple-ID).

## Struktur

| Pfad | Inhalt |
|---|---|
| `ios/project.yml` | XcodeGen-Spezifikation (das `.xcodeproj` wird erzeugt, nicht eingecheckt) |
| `ios/Coach/` | SwiftUI-App, MVVM: `App/`, `Features/<Bereich>/` (View + ViewModel), `Core/` (Health, API, Persistenz, UI-Bausteine) |
| `ios/CoachTests/` | App-Tests (Swift Testing), laufen nur im Simulator (macOS) |
| `ios/Packages/CoachCore/` | Reine Logik **ohne** Apple-Frameworks – testbar auf Linux mit `swift test` |
| `worker/` | Cloudflare Worker (TypeScript): KI-Weiterleitung Gemini → Groq, Prompts in `src/tasks.ts` |
| `docs/` | Entscheidungen (`decisions.md`) und Anleitungen für den Nutzer |
| `.github/workflows/` | `ios-build.yml` (macOS, nur manuell), `swift.yml` und `worker.yml` (Linux, bei PRs; Worker-Deploy auf `main`) |

Altbestand (nur lesen, Logik übernehmen, keine HA-/MQTT-Teile): `hkrb7p794w-sys/Garmin-AI-Coach`
(`garmin_ai_coach/` Coach-Regeln und Prompts, `ernaehrung/app/` Ernährung, `fit_coach/app/garmin_sync.py` Login mit MFA).

## Grundregeln

- **Regeln entscheiden, KI formuliert.** Tagesampel, Ziele und Progression sind deterministisch und getestet;
  Gemini/Groq liefern nur Text. Fällt die KI aus, bleibt die Empfehlung korrekt.
- **KI-Aufrufe und KI-API-Keys nur im Cloudflare Worker**, nie in der App. Der Garmin-Key des Nutzers wird in der
  App eingegeben und liegt nur im Keychain. Datenschutzmodus „reduziert“ ist Standard
  (keine Roh-Gesundheitswerte an kostenlose KI-Kontingente).
- **Keine Secrets im Repo** (Keys, Tokens, Garmin-Daten). Sie liegen in GitHub-Secrets bzw. als Worker-Secrets.
- **HealthKit ist optional.** SideStore mit kostenloser Apple-ID entfernt das Entitlement
  (siehe `docs/decisions.md`). Jede HealthKit-Funktion prüft `HealthAccessDiagnosis.isUsable` und hat einen Weg ohne.
- UI-Texte auf Deutsch mit echten Umlauten. Code-Bezeichner auf Englisch, Kommentare auf Deutsch.
- iOS 18+, Swift 6, Xcode 26 (Standard-Isolation `MainActor`, Approachable Concurrency).
- Logik, die sich ohne Apple-Frameworks formulieren lässt, gehört nach `CoachCore` – mit Tests. Dazu zählen die
  aus dem Altbestand übernommenen Regeln (Tagesampel, Baselines, Ernährungsziele, Progression).

## Befehle

```sh
# Worker (Node 22)
cd worker && npm ci && npm run lint && npm run typecheck && npm test

# Swift (Linux oder Mac, Swift 6.2)
swift format lint --strict --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore
swift format --in-place --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore
swift test --package-path ios/Packages/CoachCore

# iOS-Projekt (nur macOS)
cd ios && xcodegen generate
```

## CI

- `swift.yml`, `worker.yml`: automatisch bei PRs und auf `main` (günstige Linux-Runner). `swift.yml` schreibt bei
  Fehlern Compiler-/Testfehler und den `swift format`-Patch als PR-Kommentar (anwendbar mit `git apply`).
- `worker.yml` stellt den Worker nach dem Merge auf `main` bereit, sofern die Secrets gesetzt sind
  (`docs/einrichtung.md`).
- `ios-build.yml`: **nur manuell**, weil macOS-Minuten teuer sind. Auslösen per „Run workflow“ oder per
  PR-Label `ios-build` (Label wird beim Start entfernt). Ergebnis bzw. Fehlerauszug kommt als PR-Kommentar,
  die `.ipa` als GitHub-Release-Asset (PR-Builds als Vorabversion).
- Aus Claude-Code-Cloud-Sitzungen ist die Actions-API gesperrt: Builds per Label starten, Ergebnisse über
  Check-Runs (`/commits/{sha}/check-runs`), PR-Kommentare und Releases lesen.

## Konventionen

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `test:`, `refactor:`), Scope optional
  (`feat(ios): …`, `fix(worker): …`, `feat(core): …`).
- Eine PR pro Phase; Phasen und Stand siehe `README.md`.
- Entscheidungen gegen offizielle Doku prüfen und in `docs/decisions.md` mit Quelle festhalten.
