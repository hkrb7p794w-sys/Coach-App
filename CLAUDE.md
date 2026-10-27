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
| `ios/CoachWidgets/`, `ios/Shared/` | Widget-Erweiterung für die Live-Aktivität der Gym-Einheit; `Shared` gehört zu App und Erweiterung |
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
- **HealthKit ist optional.** SideStore mit kostenloser Apple-ID kann das Entitlement entfernen; beim Nutzer
  funktioniert es (Stand 26.10.2026, siehe `docs/decisions.md`). Jede HealthKit-Funktion prüft Verfügbarkeit bzw.
  Berechtigung und hat einen Weg ohne.
- **Die App passt sich der Person an** (`UserProfile` in `CoachCore/Profile`): `mode == .season` ist der bisherige
  Almere-Saisonplan, `.personal` alles andere. Neue Funktionen müssen beide Modi bedenken und dürfen keine
  Werte des Saisonplans (FTP, Schwellenpace, Almere) für andere Personen anzeigen. Gewichtsziele nur mit den
  Schutzgrenzen aus `GoalRules` (siehe `docs/decisions.md`).
- UI-Texte auf Deutsch mit echten Umlauten. Code-Bezeichner auf Englisch, Kommentare auf Deutsch.
- iOS 18+, Swift 6, Xcode 26 (Standard-Isolation `MainActor`, Approachable Concurrency).
- Logik, die sich ohne Apple-Frameworks formulieren lässt, gehört nach `CoachCore` – mit Tests. Dazu zählen die
  aus dem Altbestand übernommenen Regeln (Tagesampel, Baselines, Ernährungsziele, Progression).

## Befehle

```sh
# Worker (Node 22)
cd worker && npm ci && npm run lint && npm run typecheck && npm test

# Swift (Linux oder Mac, Swift 6.2)
swift format lint --strict --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore ios/Shared ios/CoachWidgets
swift format --in-place --recursive --configuration ios/.swift-format ios/Coach ios/CoachTests ios/Packages/CoachCore ios/Shared ios/CoachWidgets
swift test --package-path ios/Packages/CoachCore

# iOS-Projekt (nur macOS)
cd ios && xcodegen generate
```

## CI

- `swift.yml`, `worker.yml`: automatisch bei PRs und auf `main` (günstige Linux-Runner). `swift.yml` schreibt bei
  Fehlern Compiler-/Testfehler und den `swift format`-Patch als PR-Kommentar (anwendbar mit `git apply`).
- `worker.yml` stellt den Worker nach dem Merge auf `main` bereit, sofern die Secrets gesetzt sind
  (`docs/einrichtung.md`).
- `ios-build.yml`: bei jedem Push auf `main` (Release `vX.Y.<Lauf>`, Upload nach Workers KV für die private
  SideStore-Quelle des Workers, siehe `docs/sidestore.md`), in PRs per Label `ios-build` (Label wird beim Start entfernt; Ergebnis bzw.
  Fehlerauszug als PR-Kommentar, Release als Vorabversion) oder per „Run workflow“.
- **PRs merged Claude selbst** (Auftrag des Nutzers vom 26.10.2026): sobald `lint-test`, `check` und der
  iOS-Build per Label grün sind, per REST-API mergen (`PUT /repos/{owner}/{repo}/pulls/{n}/merge`,
  Merge-Commit). Der Check „Workers Builds: ironludi“ gehört nicht zum Repo (Cloudflare-Anbindung) und zählt
  nicht. Danach baut `main` die neue Version für SideStore.
- Das Repo ist privat: macOS-Minuten zählen zehnfach gegen 2.000 Freiminuten im Monat. iOS-Builds per Label
  nur einmal je PR (nach dem letzten Code-Commit), nicht nach reinen Formatierungs-Commits.
- Aus Claude-Code-Cloud-Sitzungen ist die Actions-API gesperrt: Builds per Label starten, Ergebnisse über
  Check-Runs (`/commits/{sha}/check-runs`), PR-Kommentare und Releases lesen.

## Konventionen

- Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`, `ci:`, `test:`, `refactor:`), Scope optional
  (`feat(ios): …`, `fix(worker): …`, `feat(core): …`).
- Eine PR pro Phase; Phasen und Stand siehe `README.md`.
- Entscheidungen gegen offizielle Doku prüfen und in `docs/decisions.md` mit Quelle festhalten.
