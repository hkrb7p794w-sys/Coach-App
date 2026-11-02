# Paket 7 – App-Ausbau, Widgets und Plattformstrategie

Stand 02.11.2026. Bestandsaufnahme, Bewertung, Zielarchitektur und Reihenfolge. Umgesetzt wird in kleinen PRs;
ein Android-Rewrite wird **nicht** begonnen (Empfehlung unten).

## 1. Bestandsaufnahme

| Bereich | Stand |
|---|---|
| Deployment-Target | **iOS 18.0** (`ios/project.yml`, `deploymentTarget.iOS`), gebaut mit Xcode 26 (iOS-26-SDK), Swift 6, nur iPhone (`TARGETED_DEVICE_FAMILY: 1`), nur Hochformat |
| Ziele | App `Coach` (Anzeigename IronLudi), Erweiterung `CoachWidgets` (nur Live-Aktivität), `CoachCore` (SPM, ohne Apple-Frameworks, Linux-getestet), Worker (TypeScript) |
| Code-Umfang | CoachCore ≈ 21 000 Zeilen + 8 000 Zeilen Tests; App ≈ 23 000 Zeilen; Widgets/Shared ≈ 240; Worker ≈ 2 500 |
| Daten | SwiftData (`Records.swift`) und `CoachSettings` (UserDefaults, JSON) im Container der App; Geheimnisse im Keychain |
| Navigation | `TabView` mit fünf Reitern (Heute, Training, Ernährung, Gym nur mit Krafttraining, AI), je ein `NavigationStack`; Links `coach://join`, `coach://meal/<code>`; bisher keine Auswahl des Reiters von außen |
| Schon vorhanden | Live-Aktivität mit Knöpfen (`LiveActivityIntent`), AlarmKit-Wecker (iOS 26, mit Ersatzweg), Hintergrundabruf (`BGAppRefresh`), lokale Mitteilungen mit Aktionen |
| Nicht vorhanden (vor Paket 7) | Homescreen-Widgets, App Group, Schnellaktionen am App-Icon, App Shortcuts |
| Auslieferung | SideStore mit kostenloser Apple-ID: 7 Tage Laufzeit, höchstens 10 App-IDs je 7 Tage, nur App Groups als Zusatzrecht (HealthKit fällt dort weg, beim Nutzer funktioniert es) |

## 2. Technische Bewertung

### 2.1 Homescreen-Widgets (WidgetKit)

**Was WidgetKit kann – und was nicht**

| Art | Möglich | Grenzen |
|---|---|---|
| Statisch/aktualisiert | Zeitleiste (`TimelineProvider`), die App stößt mit `WidgetCenter.reloadTimelines` an | iOS teilt ein Tagesbudget zu (Apple: typisch 40–70 Aktualisierungen am Tag bei häufig gesehenen Widgets); Anstöße aus der App im Vordergrund zählen nicht. Keine Netzabrufe nötig – das Widget zeigt, was die App zuletzt geschrieben hat. |
| Interaktiv (ab iOS 17) | Nur `Button` und `Toggle` mit einem App Intent | Keine Texteingabe, kein Scrollen, keine Listen zum Wischen, keine eigenen Animationen. Der Intent läuft im Prozess der Erweiterung (nicht der App) – er darf also nur kleine, gemeinsame Daten ändern. |
| Konfigurierbar (ab iOS 17) | `AppIntentConfiguration`: Auswahl im Widget („Widget bearbeiten“), z. B. welcher Gesundheitswert | Optionen müssen ohne Netz und ohne App bestimmbar sein (Aufzählungen statt Freitext). |
| Sperrbildschirm (Accessory) | Kreis, Rechteck, Zeile – nur Anzeige | Nicht interaktiv. |
| Kontrollzentrum (ab iOS 18) | `ControlWidget` (Knopf/Schalter, auch Sperrbildschirm und Aktionstaste) | Nur Aktion, kein Inhalt; sinnvoll später für „Training starten“. |

**Größte Hürde: gemeinsame Daten.** Die Widget-Erweiterung ist ein eigener Prozess und sieht den Container der
App nicht. Nötig ist eine **App Group**. Unter SideStore gilt (geprüft im Quellcode von SideStore,
`FetchProvisioningProfilesOperation.updateAppGroups` und `adjustedGroupIdentifier`):

- Kostenlose Teams dürfen App Groups (SideSign `Feature.swift`), SideStore legt sie beim Installieren an und weist
  App und Erweiterung zu. SideStore selbst nutzt so sein eigenes Widget.
- Die Gruppen-ID wird **umgeschrieben**: `group.<id>` wird zu `group.<id>.<TEAMID>`. Die App kennt die Team-ID nicht
  im Voraus. Lösung: Die tatsächliche Gruppe steht im eingebetteten Provisioning-Profil
  (`embedded.mobileprovision`, Schlüssel `com.apple.security.application-groups`) von App und Erweiterung; beide
  lesen sie zur Laufzeit und prüfen sie mit `containerURL(forSecurityApplicationGroupIdentifier:)`.
- Scheitert das (Gruppe fehlt), zeigt das Widget „In IronLudi öffnen“ statt veralteter Werte. Die App selbst bleibt
  unberührt – ihre Daten ziehen **nicht** in die App Group um (kein Risiko für bestehende Daten).
- Risiko: Kann SideStore die Gruppe nicht anlegen, bricht es die Installation ab
  (`updateAppGroups` wirft). Deshalb kommen Widgets in eine **eigene PR** mit eigenem Gerätetest; Rückweg ist das
  Entfernen des Entitlements.

**Datenfluss (Zielbild):** Die App schreibt nach jedem Abruf, jeder Mahlzeit und jeder Krafteinheit einen kleinen
`WidgetSnapshot` (JSON, in `CoachCore` definiert und getestet) in die App Group und stößt die Widgets an. Die
Widgets lesen nur diese Datei. Interaktive Knöpfe (z. B. „+250 ml Wasser“) schreiben in eine kleine
Warteschlange in der App Group, die die App beim nächsten Öffnen übernimmt; die Anzeige im Widget zählt die
wartenden Einträge sofort mit.

**Bewertete Widgets**

| Bereich | Widget | Art | Bewertung |
|---|---|---|---|
| Heute | Tagesübersicht: Ampel/Empfehlung, nächste Einheit, kcal übrig, Body Battery | aktualisiert | umsetzen (mittel/groß) |
| Gym | Nächstes geplantes Training, letzte Einheit, Wochenfortschritt (x/y Einheiten), Status (läuft/offen) | aktualisiert, Tippen öffnet `coach://open/startWorkout` | umsetzen |
| Ernährung | Tageskalorien, verbleibend, Protein-Fortschritt, letzte Mahlzeit | aktualisiert, konfigurierbar (kcal/Protein) | umsetzen |
| Ernährung | „+250 ml Wasser“ | **interaktiv** | umsetzen (Warteschlange) |
| Health | Body Battery, Schlaf, HRV, Recovery/Readiness | aktualisiert, konfigurierbar (Wert wählen) | umsetzen, nur Werte mit Daten |
| Sperrbildschirm | kcal übrig (Kreis), Body Battery (Kreis), nächste Einheit (Zeile) | nur Anzeige | umsetzen, klein |
| – | „Satz erledigt“ im Homescreen-Widget | – | nicht sinnvoll: das leistet die Live-Aktivität |
| – | Mahlzeit per Text/Foto im Widget erfassen | – | **geht nicht** (keine Eingabe in Widgets) → Knopf öffnet die App |

**Preis bei SideStore:** Die Widgets kommen in die vorhandene Erweiterung `CoachWidgets` – keine zusätzliche App-ID.
Die App Group selbst zählt nicht als App-ID.

### 2.2 Schnellaktionen und App Shortcuts

| Mechanismus | Wo es erscheint | Umsetzung |
|---|---|---|
| Home-Screen Quick Actions (`UIApplicationShortcutItem`) | Langes Drücken aufs App-Icon (höchstens 4 eigene) | **dynamisch** gesetzt, damit nur Passendes erscheint (kein „Training starten“ ohne Krafttraining, keine KI-Analyse ohne Worker); erscheinen nach dem ersten Öffnen |
| App Shortcuts (`AppShortcutsProvider`) | Spotlight, Kurzbefehle-App, Siri, Aktionstaste | ohne Einrichtung, deutsche Sätze („Training starten in IronLudi“) |
| Kontrollzentrum (`ControlWidget`, iOS 18) | Kontrollzentrum, Sperrbildschirm, Aktionstaste | später mit der Widget-Erweiterung möglich |

Aktionen: **Training starten** (laufende Einheit öffnen, sonst die nächste geplante starten – sie zählt erst mit
dem ersten Satz, ein versehentlicher Start schadet also nicht), **Mahlzeit erfassen** (Erfassen-Bildschirm für
heute), **Health öffnen** (Gesundheitsbereich im Reiter Training), **KI-Analyse starten** (Reiter AI, Analyse über
alle Themen – nur wenn eingerichtet und laut KI-Modus erlaubt).

**Kompatibilität mit der Navigation:** Bisher konnte niemand von außen einen Reiter wählen. Neu ist `AppRoute`
(CoachCore, getestet) mit `AppRouter` in der App: Eine Route wählt den Reiter, die Zielansicht übernimmt die Aktion
genau einmal (`take`). Dieselben Routen dienen Schnellaktionen, Kurzbefehlen und Links `coach://open/<route>` –
später auch den Widgets. Bestehende Links (`coach://join`, `coach://meal`) bleiben unverändert. Vor dem
Onboarding verfallen Routen; ohne Gym-Reiter landet „Training starten“ in „Training“ statt ins Leere.

### 2.3 Android

| Prüfpunkt | Befund |
|---|---|
| Aktuelles Framework | SwiftUI + SwiftData + WidgetKit/ActivityKit/AlarmKit/HealthKit – alles Apple-only. Nicht übertragbar. |
| Wiederverwendbar | **CoachCore** (≈ 21 000 Zeilen Regeln, Parser, Planung, Ernährung, Gym, Analysen + 8 000 Zeilen Tests) ist reines Swift ohne Apple-Frameworks und läuft schon auf Linux. **Worker** (KI, Rangliste, Teilen) ist plattformneutral über HTTPS. Datenformate (JSON-Payloads, Export) bleiben gleich. |
| Nicht wiederverwendbar | Die gesamte Oberfläche (≈ 23 000 Zeilen), Persistenz (SwiftData), Keychain, Garmin-Client/Sync-Dienste der App, Mitteilungen, Hintergrundabruf, Live-Aktivität, Wecker. |
| Datenbank/Backend | Kein eigenes Backend nötig – wie auf iOS lokal (Room/SQLite) plus der vorhandene Worker. Keine Daten-Synchronisierung zwischen iPhone und Android vorhanden (wäre ein eigenes Thema mit Konto und Server). |
| Health Connect | Gegenstück zu HealthKit (ab Android 14 Teil des Systems). Rechte je Datenart; Lesen im Hintergrund und älter als 30 Tage brauchen eigene Berechtigungen; für den Play Store ist eine Erklärung zur Nutzung von Gesundheitsdaten nötig. Garmin selbst würde weiter über den vorhandenen Garmin-Weg kommen. |
| Android-Widgets | Jetpack Glance; interaktiver als WidgetKit (Listen, Knöpfe mit beliebigen Aktionen), Daten direkt aus der App-Datenbank. |
| Hintergrundprozesse | WorkManager (periodisch ab 15 min, zuverlässiger planbar als `BGAppRefresh`). |
| Push | Die App nutzt nur lokale Mitteilungen; auf Android `NotificationManager`/`AlarmManager` (exakte Wecker brauchen eine Berechtigung). Echte Push-Mitteilungen bräuchten FCM und einen Server – wie auf iOS nicht vorgesehen. |
| Auslieferung | Einfacher als iOS: APK direkt installierbar, keine 7-Tage-Grenze. |

**Optionen**

| Option | Wiederverwendung | Aufwand | Bewertung |
|---|---|---|---|
| Native Kotlin/Compose, CoachCore nach Kotlin portieren | nur Worker | Gesamte App neu (≈ 44 000 Zeilen + Tests), zwei Logik-Stände pflegen | verworfen: Regeln doppelt, Abweichungen vorprogrammiert |
| Flutter / React Native für beide | nur Worker | Gesamte iOS-App neu, Widgets/Live-Aktivität/HealthKit weiter nativ | verworfen: verliert die native iOS-Qualität, bringt nichts für den Hauptnutzer |
| Kotlin Multiplatform (Logik in Kotlin, UI je nativ) | Worker, später Logik | CoachCore neu in Kotlin, iOS-App müsste umziehen | verworfen: Umbau der funktionierenden iOS-Logik ohne Not |
| **Native Android-Oberfläche (Compose) + CoachCore in Swift über das Swift SDK für Android** | CoachCore + Tests + Worker | Nur Oberfläche, Persistenz, Plattformdienste neu; Brücke Swift↔Kotlin (JNI, `swift-java`) | **empfohlen, sobald Android wirklich gebraucht wird** |

Zum Swift SDK für Android: Seit Swift 6.3 (März 2026) ist Android ein offiziell unterstütztes Ziel; das SDK ist
noch jung, die Brücke `swift-java` noch vor 1.0 (laut Sekundärquelle 0.4.x, nicht selbst geprüft). Vor einem
Start ist ein **Machbarkeitstest** nötig: CoachCore für Android bauen und zwei Funktionen (Tagesampel, Ernährungsziel)
aus Kotlin aufrufen.

**Empfehlung:** Jetzt keine Android-App. Es gibt aktuell keinen Android-Nutzer, und die iOS-Funktionen sind noch nicht
auf dem Gerät getestet. Vorbereitung ohne Mehraufwand: Logik weiter konsequent in CoachCore (Grundregel), keine
Apple-Typen in CoachCore-Schnittstellen, Datenformate als JSON. Wenn Android kommt: erst der Machbarkeitstest,
dann eine schmale erste Version (Heute, Ernährung erfassen, Garmin-Abruf) mit Compose.

### 2.4 iOS-Kompatibilität

**Tatsächlich verwendet:** Deployment-Target **iOS 18.0** für App und Erweiterung (`ios/project.yml`), SDK iOS 26
(Xcode 26). iOS 18 läuft auf iPhone XS/XR und neuer (A12) – **dieselben Geräte wie iOS 17**. Eine niedrigere
Mindestversion brächte also kein einziges zusätzliches Gerät, kostete aber die `Tab`-API und weitere Anpassungen.
iOS 26 verlangt mindestens iPhone 11 (A13): Ein Anheben würde XS/XR ausschließen und brächte nur AlarmKit ohne
Prüfung – nicht sinnvoll. **Empfehlung: iOS 18.0 beibehalten.**

| Funktion | Mindest-iOS | In der App |
|---|---|---|
| SwiftUI `Tab`-API, `TabView(selection:)` mit Werten | 18 | Reiterleiste |
| SwiftData, `@Observable`, `#Predicate` | 17 | Persistenz, ViewModels |
| Interaktive Widgets, `AppIntentConfiguration` | 17 | Homescreen-Widgets (PR B) |
| Knöpfe in der Live-Aktivität (`LiveActivityIntent`) | 17 | Gym-Live-Aktivität |
| `ControlWidget` (Kontrollzentrum) | 18 | noch nicht genutzt |
| App Shortcuts, App Intents | 16 | Kurzbefehle (diese PR) |
| Swift Charts, `DataScannerViewController` (Barcode), `PhotosPicker` | 16 | Verläufe, Barcode, Fotos |
| **AlarmKit (Wecker)** | **26** | mit `#available`; darunter Hinweis auf die Uhr-App und die Schlafenszeit-Erinnerung |

**Auf älteren oder kleineren Geräten eingeschränkt:**

- iOS 18–25: kein Wecker aus der App (AlarmKit) – Ersatzweg vorhanden.
- Ohne Dynamic Island (vor iPhone 14 Pro, alle SE): Live-Aktivität nur auf dem Sperrbildschirm.
- Aktionstaste (ab iPhone 15 Pro): Kurzbefehle darauf legen geht nur dort; sonst Siri, Spotlight, Kurzbefehle-App.
- Barcode-Scanner (`DataScannerViewController`) braucht A12 und neuer – mit iOS 18 immer erfüllt; die App prüft
  `isSupported` trotzdem.
- HealthKit: unter SideStore mit kostenloser Apple-ID kann das Recht fehlen (bekannt, Weg ohne vorhanden).

## 3. Langfristige Architektur

| Erweiterung | Eignung heute | Nötige Verbesserung |
|---|---|---|
| Mehrere KI-Anbieter | **gut**: Anbieter-Registry im Worker (`providers.ts`), Modus und Kontingente in der App, Schlüssel nur im Worker | keine |
| Native iOS-Widgets | **mittel**: Daten liegen nur im App-Container | `WidgetSnapshot` in CoachCore + App Group (PR B). Bewusst kein Umzug der SwiftData-Datenbank in die Gruppe. |
| Schnellaktionen / Deep Links | **neu gut**: `AppRoute`/`AppRouter` (diese PR) | – |
| Android | **mittel**: CoachCore plattformneutral, Worker neutral | Machbarkeitstest Swift SDK für Android, erst bei Bedarf |
| Erweiterte Gesundheitsdaten | **gut**: `DailyMetrics` + optionale JSON-Felder ohne Migration, `DataKind`/`MetricsMerge` je Datenart, `HealthWidget` erweiterbar | keine |
| Neue Trainingsarten | **mittel**: `TrainingSport`, `TodayPlan.Sport` und weitere Sport-Aufzählungen nebeneinander; eine neue Sportart berührt ~25 Dateien (der Compiler findet alle `switch`) | erst bei der ersten neuen Sportart zusammenführen – vorher wäre es Umbau ohne Nutzen |
| Weitere externe Schnittstellen | **gut**: `DataProvider` mit Fähigkeiten, `SyncLedger`, Herkunft je Wert; OAuth-Geheimnisse im Worker | je Anbieter ein Konnektor (WHOOP/Polar geplant) |

Bewusst **nicht** geändert: `AppModel` als zentrale Abhängigkeit (wächst, ist aber übersichtlich gegliedert),
Datenbankort, Aufteilung der Reiter. Keine dieser Änderungen hätte für Paket 7 einen nachvollziehbaren Nutzen.

## 4. Priorisierung und Schritte

| # | Schritt | Nutzen | Risiko | Stand |
|---|---|---|---|---|
| A | `AppRoute`/`AppRouter`, Schnellaktionen am App-Icon, App Shortcuts, diese Analyse | hoch, sofort spürbar | gering (keine neuen Rechte) | diese PR |
| B | Homescreen- und Sperrbildschirm-Widgets (Heute, Gym, Ernährung, Health) mit App Group, konfigurierbar, „+250 ml Wasser“ interaktiv | hoch | mittel (App Group unter SideStore) | nächste PR |
| C | Kontrollzentrum/Aktionstaste („Training starten“, „Mahlzeit erfassen“) | mittel | gering | nach Gerätetest von B |
| D | Android-Machbarkeitstest (CoachCore mit Swift SDK für Android) | nur bei Bedarf | – | zurückgestellt |

Quellen: Apple-Doku „Keeping a widget up to date“ (Budget, Anstöße aus der App), „Adding interactivity to widgets
and Live Activities“ (nur Button/Toggle mit App Intents), „Making a configurable widget“
(`AppIntentConfiguration`), „Add Home Screen quick actions“ (`UIApplicationShortcutItem`, höchstens vier
dynamische+statische sichtbar), „App Shortcuts“ (`AppShortcutsProvider`); SideStore-Quellcode
(<https://github.com/SideStore/SideStore>, `FetchProvisioningProfilesOperation.swift`, Stand 02.11.2026); Swift SDK
für Android: <https://www.swift.org/> (Swift 6.3, März 2026), Übersicht
<https://www.i-programmer.info/news/193-android/18484-swift-sdk-for-android-now-in-preview.html>.
