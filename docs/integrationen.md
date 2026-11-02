# Mehrere Tracker und Datenmanagement (Paket 5)

Stand: 02.11.2026. Analyse, Integrationsmatrix, Architektur und Synchronisierung. Leitlinie: Eine Anbindung gilt
erst als vorhanden, wenn sie gebaut und getestet ist. Was nur auf dem Papier geht, steht hier als „geplant“.

## Ausgangslage (Analyse)

- **Garmin:** zwei Wege: das Garmin-Konto (Connect-Endpunkte mit Login und MFA) und die offizielle Personal API mit
  Key. `GarminSyncService` holt Tageswerte (Zusammenfassungen, HRV, Schlaf, Body Battery, SpO2, Readiness …) und
  Aktivitäten.
- **Apple Health:** `HealthImportService` liest Tageswerte, Schlaf, Workouts und Gewicht über HealthKit.
- **Speicher (SwiftData):**
  - `DailyMetricsRecord`: ein JSON-Datensatz `DailyMetrics` je Tag;
  - `ActivityRecord`: `GarminActivity` je Aktivität, Garmin-IDs positiv, Apple-Health-Workouts mit negativer ID
    aus der UUID;
  - dazu `RawResponseRecord`, Mahlzeiten und Gym.
- **Zusammenführung vorher:**
  - Garmin schrieb direkt in `DailyMetricsRecord`.
  - Apple Health füllte nur Lücken.
  - Workouts aus Health wurden übersprungen, wenn eine Garmin-Aktivität zur selben Zeit existierte.
- **Herkunft vorher:** Die Herkunft der einzelnen Werte ging verloren, und eine Vorrang-Einstellung gab es nicht.

## Integrationsmatrix

Quellen: Herstellerdokumentation, soweit erreichbar, sonst die verlinkten Fachartikel. Die Seiten von WHOOP und
Polar waren aus der Cloud-Sitzung nicht direkt abrufbar; vor dem Bau der jeweiligen Anbindung neu prüfen.

| | Garmin | WHOOP | Fitbit | Polar |
|---|---|---|---|---|
| Offizielle API | Health API/Personal API (Key); zusätzlich inoffiziell Connect | WHOOP API v2 | Fitbit Web API **abgeschaltet am 30.10.2026**; Nachfolger Google Health API (`health.googleapis.com/v4`) | AccessLink v3 (dazu „Dynamic API“ v4) |
| Zugang | Personal API: Key vom Nutzer; Health API: Partnerprogramm | Kostenlose App im WHOOP-Developer-Dashboard (Client-ID/Secret) | Google-Cloud-Projekt, Google-OAuth, für Gesundheits-Scopes Prüfung durch Google | Kostenloser Client in Polar Flow (admin.polaraccesslink.com) |
| Kosten | keine | derzeit keine (WHOOP behält sich Gebühren vor) | keine; Prüfung aufwendig | keine |
| Authentifizierung | Key bzw. Login mit MFA (Tokens im Keychain) | OAuth 2.0 Authorization Code, `offline` für Refresh-Token, Refresh-Tokens rotieren | Google OAuth 2.0 | OAuth 2.0 Authorization Code, danach Nutzer registrieren |
| Client-Secret | – | ja → nur im Worker | ja → nur im Worker | ja → nur im Worker |
| Historische Daten | Zeiträume bis 180 Tage je Aufruf | ja, seitenweise | je Endpunkt | eingeschränkt (Berichte nennen 28–90 Tage je Datenart; Transaktionsmodell) |
| Webhooks | Health API (Partner) | Schlaf, Recovery, Workouts (je updated/deleted), HMAC-SHA256 | Google Health API: offen | Trainings (und Schlaf), wenig dokumentiert |
| Daten | alles der Matrix unten | Recovery, Schlaf, Zyklen/Strain, Workouts, Körpermaße | Aktivität, Schlaf, HRV, Ruhepuls, Gewicht | Trainings mit HF, Tagesaktivität, Schlaf, Nightly Recharge, Cardio Load |
| Über Apple Health | Garmin Connect schreibt Workouts, Schritte, Schlaf u. a. | Schlaf, Ruhepuls, Atemfrequenz, SpO2, Workouts; **keine HRV, keine Recovery/Strain** | **keine** native Synchronisierung | Polar Flow schreibt Trainings, Herzfrequenz, Schritte, Schlaf |
| In der App | **ja** | geplant | **nicht verfügbar** | geplant |

Quellen:
[WHOOP OAuth](https://developer.whoop.com/docs/developing/oauth/),
[WHOOP API 2026 (Terra)](https://tryterra.co/blog/whoop-api-data-access-permissions-limitations-2026),
[WHOOP API (Thryve)](https://www.thryve.health/blog/whoop-api-data-access-integration),
[Google Health API Newsletter](https://developers.google.com/health/newsletters),
[Fitbit-Abschaltung (Open Wearables)](https://openwearables.io/blog/fitbit-web-api-shutdown-2026-migration-guide),
[Polar AccessLink v4](https://www.polar.com/polar-api-v4/),
[Polar-Beispiel](https://github.com/polarofficial/accesslink-example-python),
[Polar API (Open Wearables)](https://openwearables.io/blog/polar-api-training-hrv-nightly-recharge-data),
[WHOOP und Apple Health (Constant)](https://trainconstant.com/blog/whoop-apple-health),
[Wearables und Apple Health (Sensai)](https://www.sensai.fit/blog/wearable-apple-health-integration-what-syncs-oura-whoop-garmin).

### Was heißt das für diese App?

- **Ohne Mac und ohne bezahlten Apple-Account** gibt es keine Push-Mitteilungen vom Server. Webhooks von WHOOP oder
  Polar könnte nur der Worker empfangen. Die App holt die Daten beim Öffnen und im Hintergrundabruf ab.
- **Client-Secrets gehören nicht in die App** (CLAUDE.md). Code-Tausch und Token-Erneuerung laufen über den Worker,
  die Tokens danach im Keychain des iPhones.
- **WHOOP und Polar** sind machbar. Dafür braucht es:
  - eine eigene App beim Hersteller (Client-ID/Secret als Worker-Secret);
  - eine Redirect-URL `coach://oauth/<anbieter>`;
  - je Anbieter ein Modul: Abruf, Parser auf `DailyMetrics`/`GarminActivity`, Tests mit Beispielantworten.
- **Bis dahin bringt Apple Health WHOOP- und Polar-Daten schon herein.** Der Vorrang je Datenart sorgt dafür, dass
  nichts doppelt zählt. Bei WHOOP fehlen dabei HRV und Recovery.
- **Fitbit:** Die Web API ist abgeschaltet. Die Google Health API braucht ein Google-Cloud-Projekt und für
  Gesundheitsdaten eine Prüfung der App durch Google. Für eine privat per SideStore verteilte App ist das
  unverhältnismäßig. Fitbit ist daher als „nicht verfügbar“ markiert; neu bewerten, falls Google einen einfacheren
  Weg für persönliche Apps anbietet.

## Architektur

- **Herstellerunabhängige Modelle:** `DailyMetrics` (Tageswerte) und `GarminActivity` (mit Alias `TrainingActivity`)
  sind die internen Modelle für alle Anbieter. Herkunft steht nicht im Wert, sondern daneben.
- **Anbieter-Katalog** (`DataProvider`): je Anbieter
  - Verfügbarkeit (`available`/`planned`/`unavailable`);
  - Datenarten (`capabilities`);
  - Stärken (`strengths`).
- **Datenarten** (`DataKind`): Aktivitäten, Herzfrequenz im Training, Schlaf, HRV, Ruhepuls, Stress, Kalorien,
  Schritte, Trainingsbelastung, Recovery, Körperwerte.
- **Vorrang** (`SourcePreferences`): Gewählte Quelle je Datenart vor dem primären Gerät (aber nur bei dessen Stärken)
  vor der allgemeinen Rangfolge. So ist das primäre Gerät nicht automatisch überall die beste Quelle. Beispiel:
  Garmin primär, WHOOP verbunden → Schlaf und HRV von WHOOP, Training von Garmin.
- **Zusammenführung Tageswerte** (`MetricsMerge`): je Datenart genau eine Quelle, immer als ganze Gruppe, z. B.
  Schlafdauer, Phasen und Zeiten zusammen. Das verhindert doppelte Kalorien und gemischte, widersprüchliche Werte.
  Fehlen bei der bevorzugten Quelle Werte für den Tag, springt die nächste ein.
- **Zusammenführung Aktivitäten** (`ActivityMerge`):
  - Als dieselbe Einheit gilt: gleiche Sportart, Start höchstens 10 min auseinander oder mehr als die Hälfte
    überlappend.
  - Es bleibt nur die bevorzugte Quelle, damit auch deren Kalorien, Herzfrequenz und Belastung.
  - Zwei Aktivitäten desselben Anbieters werden nie zusammengelegt (z. B. Ein- und Auslaufen).
- **Speicher:**
  - `SourceRecord` (neues SwiftData-Modell) hält je Anbieter und Tag die Rohwerte sowie die Herkunft je Aktivität.
  - `DailyMetricsRecord` ist daraus berechnet; alle Ansichten lesen weiter dort.
  - Beim ersten Start gelten alle bisherigen Tageswerte als Garmin-Werte (`SourceStore.migrateIfNeeded`), damit
    nichts verloren geht.
- **Herkunft je Datensatz** (`SourceEntry`):
  - Anbieter, Datenart, externe ID (bei Tageswerten der Tag);
  - Tag und Beginn, Importzeitpunkt, letzte Änderung;
  - Prüfsumme und Status (`active`, `superseded`, `deleted`).
  - In der App sichtbar ist nur „Herkunft der Werte von heute“ unter Einstellungen › Datenquellen.

## Synchronisierung

- **Automatisch:** Beim Öffnen der App, wenn der letzte Abruf mindestens 15 min her ist, sowie im
  Hintergrundabruf von iOS.
- **Manuell:** „Jetzt alle abrufen“ (Datenquellen) bzw. nach unten ziehen.
- **Status je Anbieter** (`ProviderSyncState`): letzter Versuch, letzter Erfolg, Fehlertext und Zahl der
  Fehlschläge.
- **Fehler:**
  - Nach Fehlschlägen wartet der automatische Abruf 1, 5, 15, 60 min, dann 6 h.
  - Der Erfolgstag bleibt dabei stehen, der nächste Abruf holt die Lücke (mit 3 Tagen Überlappung) nach.
  - Ein Endpunkt, der ausfällt, stoppt die anderen nicht; das war vorher schon so.
- **Erkennen bereits importierter Daten:** Ein Datensatz gilt nur dann als geändert, wenn sich seine Prüfsumme
  ändert.
- **Ersetzte Doppelte:** Sie bleiben als `superseded` vermerkt und werden beim nächsten Abruf nicht wieder angelegt.
- **Geändert:** neue Prüfsumme → Datensatz aktualisiert, Tag neu berechnet.
- **Gelöscht:**
  - Nur wenn ein Abruf den Zeitraum vollständig geliefert hat (Apple Health: ja), gelten fehlende Einträge als
    gelöscht; die Aktivität wird entfernt.
  - Bei Garmin wird nur seitenweise geblättert, daher keine Löschungen ableiten.
  - WHOOP liefert Lösch-Webhooks; mit eigener Anbindung lassen sich diese nutzen.
- **Neu berechnen:** Nach geänderten Vorrang-Einstellungen werden alle Tage aus `SourceRecord` neu zusammengeführt
  und Doppelte neu bewertet.

## Datenschutz und Tokens

- Garmin-Key, Garmin-Tokens und künftige OAuth-Tokens liegen im Keychain, nie im Repo oder in UserDefaults.
- Client-Secrets der Hersteller liegen nur als Worker-Secrets. Der Worker tauscht Codes und erneuert Tokens, speichert
  aber keine Gesundheitsdaten.
- Herkunftsdaten bleiben auf dem iPhone. Der KI-Export enthält weiter nur die zusammengeführten Werte im gewählten
  Datenschutzmodus.

## Nächste Schritte (je Anbieter ein eigener PR)

1. **WHOOP:**
   - Worker-Endpunkte `/v1/oauth/whoop/token` und `/refresh` (Secret im Worker);
   - Anmeldung in der App (`ASWebAuthenticationSession`, Redirect `coach://oauth/whoop`);
   - Abruf `v2/recovery`, `v2/activity/sleep`, `v2/activity/workout`, `v2/cycle`;
   - Parser auf `DailyMetrics` (HRV als RMSSD) und Aktivitäten.
   - Vorausgesetzt: eine WHOOP-App im Developer-Dashboard.
2. **Polar:** wie WHOOP. Dazu kommen Nutzer-Registrierung und Transaktionen (Trainings, Tagesaktivität), Schlaf,
   Nightly Recharge und Cardio Load.
3. **Fitbit:** erst bei einfacherem Zugang zur Google Health API.
