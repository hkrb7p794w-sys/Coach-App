# Inventar (Anhang zu Phase 1)

Grundlage der Prüfung. `Coach/` = `ios/Coach/`. Der Android-Teil dient nur der Information.

## iPhone: App, Heute, Training, Plan, Einstellungen

#### 1.1 Navigation
| Element | Beleg | Inhalt |
|---|---|---|
| TabView (4–5 Reiter) | App/RootView.swift:22-41 | Heute, Training, Ernährung, Gym (nur wenn `profile.trains(.strength)`), AI (Badge = ungelesene Empfehlungen) |
| Vollbild beim ersten Start | RootView.swift:96-98 | `OnboardingView`, solange `!profile.onboardingDone` (lässt sich nicht wegwischen) |
| Sheets an RootView | RootView.swift:75-94 | Geteilte Mahlzeit (`coach://meal/<code>`), Ranglisten-Einladung (`coach://join?…`), „Verschieben …“ aus der Mitteilung (`AdjustDaySheet`), Sonntags-Mitteilung (`NextWeekPlanSheet`) |
| Warnleiste | RootView.swift:43-45, 107-124 | `StorageWarningBanner` bei `CoachSchema.isTemporary` |
| Heute | Features/Today/TodayView.swift:63-163 | Toolbar: „Coach fragen“ (Sheet `ChatView`), „Einstellungen“ (Sheet `SettingsView`); `NavigationLink` „Diese Woche, Ziele und Verlauf“ → `WeekOverviewView` → `ActivityDetailView`, `ActivityListView`; Pull-to-Refresh = Abruf + Notiz |
| Training | Features/Training/TrainingView.swift:26-140 | Hub: Plan (Saison: `PlanView`, persönlich: `MyWeekView`), Gesundheit (`HealthDashboardView`), Erholung, Herzfrequenz, Aktivitäten, Trends, Schlaf-Coach, Fitness & Form, Wochenbericht; Saison: Schwimmen/Rad/Laufen/Almere/Marathon; persönlich: `PersonalSportPage` je Sportart. `navigationDestination` für die Route „Health“ |
| AI | Features/AI/AIView.swift | Empfehlungs-Inbox (Wischen: umgesetzt/verworfen, lange drücken: „Worauf beruht das?“), KI-Analyse, Chat, KI-Trainingsplan (Sheet `GymPlanView`), Prompt-Bibliothek |
| Einstellungen | Features/Settings/SettingsView.swift:24-71 | Profil (Vollbild `OnboardingView(isEditing:)`), Darstellung, Disziplinen, Erinnerungen, Garmin-Konto (inoffiziell, MFA), Personal API, Apple Health, Datenquellen, KI-Worker, KI-Stufen, Coach (Saison & Rennen nur `.season`, Begleiter & Rangliste, Quellen, Export/Import), Diagnose (Garmin, HealthKit) |
| Alerts | grep `\.alert(` = 0, `confirmationDialog` = 1 | keine Alerts im Bereich; destruktive Knöpfe ohne Rückfrage (IOS1-15) |

#### 1.2 Deep Links, Schnellaktionen, Intents, Hintergrund, Mitteilungen
| Art | Beleg | Details |
|---|---|---|
| URL-Schema `coach://` | project.yml (CFBundleURLTypes); RootView.swift:66-74 | `open/<route>` (`AppRoute`), `meal/<code>`, sonst Einladung `join?worker=…&token=…&league=…` |
| Schnellaktionen am App-Icon | App/AppRouter.swift:49-56, 66-86; CoachApp.swift:41-44 | dynamisch, erst nach dem ersten Wechsel in den Hintergrund gesetzt; Kaltstart über `configurationForConnecting` |
| App Intents / Siri | AppRouter.swift:92-160 | Training starten, Mahlzeit erfassen, Health öffnen, KI-Analyse starten (`openAppWhenRun`) |
| BGAppRefresh | AppModel.swift:184-197; CoachApp.swift:48-50; project.yml `BGTaskSchedulerPermittedIdentifiers` | `io.github.hkrb7p794w.coach.refresh`, frühestens 2 h, beim Wechsel in den Hintergrund neu geplant |
| Lokale Mitteilungen | Core/Coach/ReminderService.swift:41-54, 72-124 | Trainingserinnerung 14 Tage (Aktionen Erledigt / Verschieben … / Diese Woche auslassen), Schwimm-Ausrüstung (nur Saison), Sonntag „Nächste Woche planen“, „Tag auswerten“ (7 Tage), Mahlzeiten (2 Tage), Schlafenszeit (täglich wiederholt, Features/Training/SleepCoachView.swift:10-29); max. ≈45 von 64 |
| Wecker (AlarmKit, iOS 26) | Core/Health/WakeAlarmService.swift:46-96 | mit `#available` |
| Widgets/App Group | Core/Widgets/WidgetPublisher.swift | Snapshot bei aktiv/Hintergrund/nach Abruf; Wasser-Warteschlange |

#### 1.3 Einstellungen (UserDefaults, Standardwerte)
`CoachSettings` (Core/Coach/CoachSettings.swift:8-39, Init 201-309) – jeweils JSON-Blob je Schlüssel, Decodierfehler → Standardwert:

| Schlüssel | Typ | Standard |
|---|---|---|
| coach.season | SeasonConfig | `.standard` (Almere-Werte) |
| coach.privacy | PrivacyMode | `.reduced` |
| coach.ai / coach.aiUsage / coach.insights | AISettings / [AIUsageEntry] / [Insight] | `AISettings()` / [] / [] |
| coach.profile | UserProfile | Migration: Saisonplan, wenn `garmin.lastSync` oder `coach.season` existiert, sonst neues Profil (Onboarding) |
| coach.planAdjustments | PlanAdjustments | leer, beim Start vor heute gekürzt |
| coach.reminders | ReminderSettings | an, 07:30, Ausrüstung an, Sonntag 18:00 an, „Tag auswerten“ aus, Mahlzeiten Standard |
| coach.companion, coach.league | CompanionSettings, LeagueSettings | Standard; League-ID einmal erzeugt und gespeichert |
| coach.gym, coach.recipes, coach.ownRecipes, coach.pantry, coach.favoriteMeals, coach.nutrition, coach.nutritionDashboard | (andere Agenten) | Standard |
| coach.weights | [WeightEntry] | [] (365 Tage) |
| coach.sleep, coach.healthDashboard, coach.sources, coach.userSources | | Standard / [] |
| coach.tests, coach.competitionDecisions, coach.heartRate | | [] / [:] / 0 = automatisch |
| coach.illnessDay, coach.handledMissed, coach.efforts, coach.closedReviews, coach.dismissedSuggestions, coach.importedNotes | | nil / [] / [:] / [] (60 behalten) / [] (60) / nil |

Weitere Schlüssel: `coach.note` (Notiz-Cache, TodayViewModel.swift:39), `garmin.lastSync|profile|profileDate|activityBackfill|racePredictions|weights` (GarminSyncService.swift:42-47), `garminConnect.email|displayName` (GarminConnectSession.swift:174-175), `garmin.keyExpiry` (SettingsViewModel.swift:7, Standard +1 Jahr), `health.importEnabled|lastImport|weights` (HealthImportService.swift:12-14), `ai.workerURL` (AIClient.swift:46), `AppAppearance.storageKey` (`@AppStorage`, Standard `.system`).
Keychain (`AfterFirstUnlockThisDeviceOnly`, Core/Security/SecretStore.swift:59): garminAPIKey, garminBearerToken, garminConnectToken, aiAppToken.

#### 1.4 Datenflüsse
- **Garmin-Konto (inoffiziell):** Login Anmeldeseite → 2–5 s Pause → Login → ggf. MFA (`needsCode`) → Ticket → Token-Tausch (Client-IDs der Reihe nach) → Profil (GarminConnectSession.swift:205-270). Token im Keychain, Erneuerung < 15 min vor Ablauf, bei 400/401 automatische Abmeldung (Z. 282), bei ≥ 500 altes Token, sonst `needsLogin` (Z. 283-284). Je Abruf Rückfall auf die Personal API, wenn ein Key da ist (GarminClient.swift:58-73).
- **Personal API:** Key → Bearer-Token (Keychain), bei 401 einmal neu tauschen (GarminClient.swift:83-110). Ablaufwarnung 14 Tage vorher, Datum vom Nutzer gepflegt.
- **Abruf** (GarminSyncService.swift:77-141): sequentiell ≈ 15 Endpunkte, Konto-Extras, Aktivitäten (Seiten), einmalig 13 Wochen Nachladen, Profil 1×/Tag, FIT-Analyse (max. N je Abruf). Jeder Endpunkt einzeln abgesichert. Danach Apple Health, Doppelte, Gym-Abgleich, Erinnerungen (AppModel.swift:150-182).
- **Apple Health** (HealthImportService.swift:73-175): fragt bei **jedem** Import `requestAuthorization`, ab `lastImport − 3 Tage` bzw. 120 Tage; Statistiken je Tag, Schlaf, Workouts (vollständiges Fenster), Gewicht 120 Tage.
- **KI** über Worker (AIClient.swift), Token im Keychain; Notiz einmal je Tag/Ampelstufe (`coach.note`).
- **SwiftData** `CoachSchema` (Core/Persistence/Records.swift:133-161), Payload als JSON-Blob je Datensatz, bei Öffnungsfehler In-Memory + Warnleiste.

#### 1.5 Zustände je Screen (vorhanden ✓ / fehlt ✗)
| Screen | leer | lädt | Fehler | offline | Erstnutzung | viele Daten | extreme Werte |
|---|---|---|---|---|---|---|---|
| Heute | ✓ Hinweis ohne Quelle (TodayView.swift:68-76), „Heute nichts geplant“ (NowViews.swift:76-79) | ✓ „Daten werden abgerufen …“ (TodayView.swift:423-428) | teilw.: Text orange ohne nächsten Schritt (TodayView.swift:429-433, IOS1-13) | ✗ offline = „N Endpunkte ohne Daten“ (IOS1-08) | ✓ über Onboarding | ✗ alle Datensätze ohne Prädikat, mehrfach decodiert (IOS1-10) | ✓ „Werte von gestern“ (NowViews.swift:59-63) |
| Training-Hub | ✓ „Noch keine Garmin-Werte. Ziehe nach unten …“ (TrainingView.swift:191-195) | ✗ kein Ladezustand | ✗ | ✗ | – | ✗ (IOS1-10) | ✓ `max(…,1)` in Schlafphasen (TrainingView.swift:284) |
| Gesundheit / Body Battery | ✓ `ContentUnavailableView` (HealthDashboardView.swift:60-70, BodyBatteryView.swift:16) | ✗ | ✗ | – | ✓ | ✓ 30/90 Tage | ✓ Y 0…100 |
| AI | ✓ „Gerade keine offenen Empfehlungen“ (AIView.swift:33-41) | ✓ | ✓ | über KI-Fehlertext | ✓ | ✓ | – |
| Chat | ✓ Vorschläge | ✓ „Coach denkt nach …“ | ✓ allgemeine Antwort, Grund nicht genannt (ChatView.swift:136-143) | wie Fehler | ✓ ohne Worker eigener Text (ChatView.swift:120-124) | – | – |
| Einstellungen/Garmin | – | ✓ `isBusy` überdeckt Formular | ✓ als grauer Text (SettingsView.swift:141-143) | – | – | – | – |
| Onboarding | ✓ Weiter gesperrt | – | ✓ `InputIssuesSection` | – | ✓ | – | ✓ Grenzen 30–250 kg, 120–230 cm, 14–100 J. (OnboardingView.swift:459-462) |

#### 1.6 grep-Zählungen (Bereich ohne Nutrition/Gym/Recipes)
`.font(.system(size:` 4 (davon 2 in Daisy-Canvas, 1 `SportIcon`, 1 `CompanionAvatar`) vs. semantische Schriftstile 347 · `accessibilityLabel` 27 · `accessibilityHidden` 9 · `accessibilityElement` 15 · `accessibilityValue` 0 · `accessibilityHint` 3 · `accessibilityReduceMotion` 1 (Daisy) · `@ScaledMetric` 0 · `Image(systemName:` 37 · feste `.frame(width:N,height:N)` 8 (Plan-Pfeile 44×44 ✓, Rest Deko) · fest codierte Farben `Color(hex:)` 20 (alle Daisy) · `.foregroundStyle(.green|red|orange|yellow)` 37, davon `.orange` für Text 19 · `sensoryFeedback` 2 · Swift Charts 18 · `.alert(` 0 · `Task {` 25, `isCancelled/checkCancellation` 0 · `try?` 145.

#### 1.7 CI-Screenshots
Workflow „Screenshots“: einziger erfolgreicher Lauf 40486577087 (27.10.2026, `feat/design-review`), Artefakte keine; Bilder hängen an der Vorabversion `screenshots-26-5` (Commit 222bf20, **204 Commits vor `main`**). Heruntergeladen nach `<SCRATCH>/dl/screens` (SE und Pro Max, hell/dunkel/große Schrift). Die Bilder zeigen noch den alten Reiter „Plan“ statt „AI“; Aussagen daraus nur mit Vorbehalt. Belegt: grüner Chip-Text „Laufen · Locker“ auf hellgrünem Grund (SE hell 01-heute), Trennung „Erhol-ung“/„Herzfr equen z“ bei AX-L (SE große Schrift 05) – letzteres ist mit 00e807e nach dem Screenshot behoben, daher kein Befund.

## iPhone: Ernährung, Gym, Widgets, Live-Aktivität

#### Ernährung (`Coach/Features/Nutrition`)
| Screen/Sheet | Datei | Zustände (Beleg) |
|---|---|---|
| Ernährung (Tag, Wochenstreifen, anpassbare Karten: Budget, Tagesübersicht, Wasser, Ideen, Schnell, Mahlzeiten, Nährstoffe) | NutritionView.swift:40-191 | leer: „Noch nichts erfasst …“ :283; lädt: Overlay „Wird ausgewertet …“ :96-100; Fehler: Alert „Hinweis“ :182-189; offline: „Wartet auf Netz“ :225-246; Vergangenheit: Wochenstreifen :561-605; Suche ohne Treffer :435-439 |
| Suche (eigene Lebensmittel, frühere Mahlzeiten, BLS ab 3 Zeichen) | NutritionView.swift:421-483 | leer vorhanden |
| Erfassen-Sheet (Kamera, Foto, Text, Diktat, Barcode, Nur Kalorien, Manuell, Schnell-Einträge/Favoriten/Rezepte) | CaptureViews.swift:11-153, MealShortcutViews.swift:21-135 | Diktat-Fehler :96-98; Favoriten/Rezepte leer MealShortcutViews.swift:49, 66 |
| Barcode (VisionKit + Eingabe), Produkt unbekannt | CaptureViews.swift:258-355, 156-211 | Scanner nicht verfügbar :276-278 |
| Nur Kalorien | NutritionView.swift:938-997 | Eintragen erst ab kcal > 0 :979 |
| Entwurf/Editor (Summe, Positionen ±, Zeitpunkt, KI-Ergänzung, Menge für alle) | MealEditor.swift:7-135, MealShortcutViews.swift:138-234 | unsichere Schätzung gelb :67-70; fehlende Makros :162-170 |
| Position (Portion/Gramm, BLS, Nährwerte) | MealEditor.swift:220-340, BLSViews.swift | Energie-Widerspruch :319-321 |
| Mahlzeit teilen / empfangen | MealShareViews.swift:34-185 | lädt :80 |
| Was jetzt? (KI) | NutritionPlanViews.swift:6-73 | lädt :35 |
| Eigene Rezepte / Meal-Prep | NutritionPlanViews.swift:75-236 | leer :85-87 |
| Woche und Auswertung | NutritionPlanViews.swift:238-298 | – |
| Gewichtsverlauf | WeightViews.swift | zu wenig Wägungen :74-80; Eingabe 30–250 kg :163-166 |
| Rezeptideen (Wochenplan), Detail, Einkaufsliste, Wünsche | Recipes/RecipeViews.swift:6, 156, 217, 293 | lädt :86-87; Fehler :40; KI aus RecipeViewModel.swift:90-92 |
| Übersicht anpassen | NutritionView.swift:717-748 | – |

Erfassungswege: Foto/Kamera, Text, Diktat → KI `meal_analyze` (NutritionViewModel.swift:267-304); Barcode → Open Food Facts mit Cache `FoodRecord` (:338-363, Core/Nutrition/NutritionServices.swift); BLS-Suche (NutritionView.swift:434); Schnell-Eintrag; Favoriten/Häufig/„Wie gestern“ (:794-836); Rezept (:251-259); Wasser (:498-502); geteilte Mahlzeit.

#### Gym (`Coach/Features/Gym`)
| Screen | Datei | Zustände |
|---|---|---|
| Gym-Hub (heute/nächste Routine, Fortsetzen, Pläne, Übungen, Auswertung, letzte Einheiten) | GymView.swift:7-167 | unbeendet / nicht gestartet :34-43; kein Plan :287, :231-233 |
| Aktive Einheit: Fokus-Karte / Liste | ActiveWorkoutView.swift:35-330, 821-961 | keine Einheit :53; Plan geschafft :309-329, 996-1030 |
| Pausentimer (groß/klein, ±15 s, RIR-Abfrage) | ActiveWorkoutView.swift:687-794 | – |
| Supersätze, Aufwärmen, Satzart, Ersetzen, Reihenfolge, Notiz, Stange | ActiveWorkoutView.swift:1035-1250; GymViewModel.swift:135-145, 248-257 | – |
| Halte-Stoppuhr + Korrektur | ActiveWorkoutView.swift:599-682 | – |
| Ziffernblock mit Plausibilitätsrückfrage | ActiveWorkoutView.swift:1255-1452 | Warnung :1340-1348 |
| Abschluss (Prüfung, Ergebnis, Bestleistungen, Heatmap, Nächstes Mal) | ActiveWorkoutView.swift:1457-1593 | speichert :1517 |
| Verlauf / Detail / Garmin-Abgleich | GymView.swift:436-576, 619-652 | Löschen mit Rückfrage :638-650 |
| Bibliothek, Übungsdetail mit Charts, Routinen-Editor, Ausstattung | GymLibraryViews.swift, ExerciseHistoryCharts.swift | Suche leer :29; keine Sätze :199 |
| Auswertung (Kalender, Hinweise, Heatmap, Progression, Volumen) | GymView.swift:579-616, MuscleViews.swift | keine Daten :315 |
| KI-Trainingsplan | GymPlanView.swift | KI aus :93-94 |
| GymBook-Import, Garmin-Übertragung, Apple Health | Core/Gym/GymBookReader.swift, GarminStrengthService.swift, WorkoutWriter.swift | Fehlertexte vorhanden |

#### Widgets und Live-Aktivität
- Heute (small/medium), Ernährung (small/medium/circular/rectangular/inline; medium mit „+250 ml“-AppIntent und „Erfassen“), Mahlzeiten (medium/rectangular/circular, „+“ je Mahlzeit per Link), Health (small + 3 accessory), Gym (small/medium/rectangular) – CoachWidgets/HomeWidgets.swift:149-231. `.containerBackground` bei allen 5 Widgets (grep: 5). Leerzustand „IronLudi einmal öffnen“ / „App-Gruppe fehlt“ :236-249. Zeitleiste jetzt + Mitternacht :22-33.
- Live-Aktivität: Sperrbildschirm (Titel, Übung, Detail, Pausentimer, ±Gewicht/±Wdh., „Satz erledigt“, „Weiter“), Dynamic Island expanded/compact/minimal – WorkoutLiveActivity.swift:20-133. Intents Shared/WorkoutActivity.swift:121-187, laufen im App-Prozess über `WorkoutActions.handler` (Core/Gym/WorkoutActivityController.swift:24-34).

#### Datenflüsse
- SwiftData: `MealRecord`, `FoodRecord` (unique `key`), `GymSessionRecord` (JSON-Payload) – Core/Nutrition/NutritionRecords.swift, Core/Gym/GymRecords.swift.
- Laufende Einheit: UserDefaults `gym.activeSession`, bei jeder Änderung geschrieben (GymViewModel.swift:717-724). Offline-KI-Warteschlange: UserDefaults + Foto in Application Support (Core/Nutrition/PendingAnalysis.swift).
- App Group: Snapshot + `reloadAllTimelines` nur in `WidgetPublisher.publish` (Core/Widgets/WidgetPublisher.swift:31-35), aufgerufen bei `.active`, nach Sync und bei `.background` (App/CoachApp.swift:25-40, App/AppModel.swift:189). Wasser aus dem Widget: Warteschlange mit `NSFileCoordinator` (Shared/WidgetStore.swift:47-57), Übernahme bei `.active` (WidgetPublisher.swift:10-28).
- Worker: `meal_analyze`, `meal_amend`, `nutrition_label`, `meal_now`, `nutrition_review`, `gym_hints`, `gym_plan`, `weekly_recipes`. Open Food Facts direkt vom iPhone. HealthKit: Workout schreiben (WorkoutWriter.swift:32-55). Garmin: FIT-Upload bzw. PUT der Sätze (GarminStrengthService.swift).

#### Timer (positiv belegt)
Pause ist **datumsbasiert**: `restEndsAt` (GymViewModel.swift:24, 427), Anzeige `Text(timerInterval:)`/`ProgressView(timerInterval:)` (ActiveWorkoutView.swift:697, 724-735), Ende per `Task.sleep` bis zum Datum (:116-127) plus lokale Mitteilung (`RestAlarm` :6-21). Nach Rückkehr aus dem Hintergrund stimmt die Anzeige. Halte-Stoppuhr ebenfalls datumsbasiert (:607-611). Einheit über Mitternacht: `ActiveSessionState` rechnet mit Alter statt Kalendertag (CoachCore Gym/ActiveSessionState.swift:23-31) – unkritisch.

### 2. Taps

| Aufgabe | Weg | Taps | Beleg |
|---|---|---|---|
| Essen loggen, häufigster Weg (Foto) | Reiter Ernährung → „+“ → „Kamera“ → Auslöser → „Foto verwenden“ → „Analysieren“ → „Speichern“ | **7** | NutritionView.swift:209-219; CaptureViews.swift:34, 131-136; MealEditor.swift:106 |
| per Text | Reiter → „+“ → Textfeld → (tippen) → „Analysieren“ → „Speichern“ | 5 + Tippen | CaptureViews.swift:70-75 |
| per Diktat | Reiter → „+“ → „Sprechen“ → „Fertig gesprochen“ → „Analysieren“ → „Speichern“ | 6 | CaptureViews.swift:77-95 |
| Essen loggen, schnellster Weg | Reiter Ernährung → „+“ in „Schnell: …“ / „Wie gestern“ (5 s Rückgängig) | **2** (1, wenn Reiter offen) | NutritionView.swift:360-368, 857-861, 504-521 |
| über Widget | Mahlzeiten-Widget „+“ → Erfassen mit vorgewählter Mahlzeit → weiter wie oben | 1 + 4–5 | HomeWidgets.swift:398; NutritionView.swift:109-116 |
| Satz loggen (Fokus-Karte, Werte vorbefüllt) | „Satz erledigt“ | **1** | ActiveWorkoutView.swift:574-582 |
| Satz mit anderem Gewicht | Zahl → Ziffern → „Übernehmen“ → „Satz erledigt“ (oder ± je Schritt) | 3 + Ziffern | ActiveWorkoutView.swift:430, 1322-1328 |
| Satz vom Sperrbildschirm | „Satz erledigt“ | **1**, ohne Entsperren | WorkoutLiveActivity.swift:120-124 |
| Wasser +250 ml in der App | Reiter Ernährung → „+250 ml“ (primaryAction; nur bei sichtbarer Karte „Wasser“ mit Ziel) | **2** | NutritionView.swift:345-349, 653-666 |
| Wasser +250 ml im Widget | Ernährung-Widget (mittel) „250 ml“ | **1** | HomeWidgets.swift:515-517 |

Einhandbedienung: großes „+“ und Rückgängig unten (NutritionView.swift:205-223), „Satz erledigt“ im Daumenbereich (ActiveWorkoutView.swift:167-177). „Beenden“/„Ausblenden“ oben in der Toolbar (:57-73) – für seltene Aktionen vertretbar.

## CoachCore: Ernährung, Gym, Profil

| Bereich | Dateien | Zeilen | Wichtigste Regeln |
|---|---|---|---|
| Nutrition | 17 | 2.784 | `NutritionPlanner` (Mifflin, PAL, Makros, REDs-Untergrenze, Wasser, Mikros), `WeightTrend`, `WeightForecast`, `Expenditure`, `OpenFoodFacts`, `BLS`, `RecipePlanner`, `MealNow`, `MealSplit`, Portionen |
| Gym | 17 | 2.978 | `GymProgression` (Doppelprogression, Regeln A–D, Wiedereinstieg), `GymStats` (Epley), `PlateCalculator`, `WarmUp`, `MuscleLoad`, `GymCoach`, `GymBookImport`, `WorkoutFlow` |
| Profile | 15 | 2.978 | `GoalRules`, `UserProfile`, `InputCheck`, `Personalization`, `RunPlanner`, `WeekLoad`, `LoadCheck`, `SessionMatch`, Wochenplan |
| Motivation | 4 | 511 | `WeekAdherence`, `ScoreRules`, `League`, Begleiter |
| App | 2 | 148 | `AppRoute`, `QuickActions` |
| **Summe** | **55** | **9.399** | Tests im Paket: 67 Dateien in `Tests/CoachCoreTests` |

Jeder öffentliche Typ des Bereichs wird in mindestens einer Testdatei erwähnt (grep über 90 Namen, kein Treffer ohne
Test). Die Lücken liegen in **Zweigen**, nicht in Typen (siehe Abschnitt 5).

Swift-6-Concurrency: `swift-tools-version: 6.0` (Package.swift), keine `nonisolated(unsafe)`, kein `@unchecked
Sendable`, keine globalen `static var` mit Zustand (nur berechnete, z. B. `BLS.swift:40`). `BLS.table` ist ein
`static let` mit `Sendable`-Struktur – sicher. Datumslogik nutzt durchgehend `CalendarDay` mit UTC-Mittag
(`Garmin/CalendarDay.swift:35–52`), `now`/`today` werden injiziert. Keine Befunde zu Concurrency.

## CoachCore: Coach, Garmin, Health

| Bereich | Dateien (Zeilen) | Kerninhalt |
|---|---|---|
| Coach | `Recommendation.swift` (169), `CoachingNote.swift` (152), `PersonalNote.swift` (57), `ChatContext.swift` (119), `FitnessForm.swift` (99), `SleepCoach.swift` (133), `WeeklyReport.swift` (102), `HeartRateZones.swift` (429), `SeasonPlan.swift` (404) u. a. | Tagesampel, KI-Eingaben (`daily_note`, `personal_note`, `coach_chat`), CTL/ATL/TSB, Schlaf-Coach, Zonen |
| Garmin | `GarminConnect.swift` (406), `DailyMetrics.swift` (365), `GarminActivity.swift` (227), `GarminEndpoint.swift` (160), `GarminToken.swift` (92), `JSONValue.swift` (154), `SyncPlan.swift` (44), `CalendarDay.swift` (95) | SSO/MFA/DI-OAuth2, Parser, Zeitraumplanung |
| Health | `MorningReport.swift` (365), `PersonalNorm.swift` (53), `HealthImport.swift` (302), `BodyBattery.swift` (130) u. a. | Morning Report, persönlicher Normbereich, Apple-Health-Zuordnung |
| Analysis/Fit | `AerobicDecoupling.swift` (211), `PaceCheck.swift` (227), `FitDecoder.swift` (278), `ZipArchive.swift` (84), `Inflate.swift` (193) | Pa:HR, Schwellenprüfung, FIT/ZIP |
| Integration | `SourceMerge.swift` (180), `SyncLedger.swift`, `DataProvider.swift` | Quellenvorrang, Doppelte |
| AI/Report | `AIPolicy.swift` (136), `Insights.swift` (353), `CoachImport.swift` (285), `CoachExport.swift` (292) | KI-Stufen, KI-Analyse, manueller Coach |
| App-Garmin | `Core/Garmin/GarminClient.swift` (144), `GarminConnectSession.swift` (234), `GarminSyncService.swift` (349), `Core/Security/SecretStore.swift` | Netz, Token, Sync, Keychain |

**Alle Worker-Aufrufe in `ios/Coach`** (`grep -rn "ai.run\|ai.send"`), alle laufen durch `AIClient.run` → `AIPolicy.allows` (KI-**Stufe**). `PrivacyMode` wird dagegen **nicht** zentral erzwungen, sondern muss je Eingabe-Bauer beachtet werden:

| Aufgabe | Aufrufstelle | Eingabe-Bauer | PrivacyMode beachtet? |
|---|---|---|---|
| `daily_note` | `Features/Today/TodayViewModel.swift:183` | `CoachingNote.input` | ja (`vitals`, `neutralReasons`) |
| `personal_note` | `TodayViewModel.swift:206` | `PersonalNote.input` | ja |
| `coach_chat` | `Features/Today/ChatView.swift:130` | `ChatContext.input` | teilweise – **Leck CORE2-01** |
| `ai_insights` | `Features/AI/AIViewModel.swift:72` | `CoachFacts.analysis` → `ChatContext.lines` + Zusatzzeilen | teilweise – **Leck CORE2-01** |
| `gym_hints` | `Features/Gym/GymViewModel.swift:289` | `GymHints.input` | keine Gesundheitsrohwerte (Gewichte/Wdh.) |
| `gym_plan` | `Features/Gym/GymPlanView.swift:169` | `GymCoach.planInput` | keine Gesundheitsrohwerte; Freitext „Einschränkungen“ |
| `meal_now`, `weekly_recipes`, `nutrition_review`, `meal_analyze`, `meal_amend`, `nutrition_label` | `Features/Nutrition/NutritionViewModel.swift:127/487/285/320/200`, `Features/Recipes/RecipeViewModel.swift:102` | jeweils lokal | keine Vitalwerte; `nutrition_review` sendet nur Ampel-Label (`NutritionView.swift:551-557`) |
| `ping` | `Features/Settings/SettingsViewModel.swift:150` | – | keine Daten (läuft auch bei Stufe „Aus“, bewusst getestet `AIPolicyTests.swift:22`) |
| Nicht-KI: `v1/league`, `v1/share/meal`, `v1/health`, `v1/invite` | `Core/Coach/LeagueService.swift:47/80`, `Features/Nutrition/MealShareViews.swift:14-24`, `AISettingsViews.swift:143` | – | kein KI-Kontingent |
| Export (manuell, ohne Worker) | `Features/Settings/CoachExchangeViews.swift` → `CoachExport.markdown` | Rohwerte (Ruhepuls, Schlaf, Gewicht) | bewusst ungefiltert; kein Hinweis „enthält Gesundheitsdaten“ (anders als `PromptLibraryViews.swift:108`) → CORE2-15 |

## Worker: Routen

| Route | Methode | Auth | Rolle | Eingabeprüfung | Größenlimit | Beleg |
|---|---|---|---|---|---|---|
| `/sidestore/<32hex>/source.json\|Coach.ipa\|icon.png` | GET | geheimer Pfad = SHA-256("sidestore:"+Haupt-Token)[0..32], Vergleich in konstanter Zeit | nur wer den Pfad kennt | Regex streng, kein Traversal | – | `sidestore.ts:89-98` |
| `/android/<32hex>/` und `/IronLudi-Gym.apk` | GET | Pfad aus SHA-256("android:"+Haupt-Token) | Pfad wird an Gäste weitergegeben | Regex streng, HTML maskiert | – | `android.ts:225-232` |
| `/v1/health` | GET | keine | alle | – | – | `index.ts:60-68` (verrät Anbieter + Modelle) |
| `/m/<10 Zeichen>` | GET | keine | alle | Regex `[a-z0-9]{10}`, keine Inhalte | – | `share.ts:149` ff. |
| `/v1/invite` | POST | Bearer | nur Haupt-Token (403 für Gäste) | – | – | `index.ts:87-92` |
| `/v1/ai/generate` | POST | Bearer Haupt/Gast | beide | Aufgabe via `Object.hasOwn`, `input` Objekt, max. 4 Bilder, MIME-Liste; Felder je Aufgabe per `text()`/`list()` gekürzt | 8 MB (Zeichen, nicht Bytes) | `index.ts:110-134`, `tasks-util.ts` |
| `/v1/league/<code>` | GET | Bearer | beide | Code `[a-z0-9-]{6,40}` | – | `league.ts:121-135` |
| `/v1/league/<code>/members/<id>` | PUT/DELETE | Bearer | Besitzer je Eintrag | `parseEntry` | **keins vor `JSON.parse`** | `league.ts:137-164` |
| `/v1/share/meal` | POST | Bearer | beide | `sanitizeMeal` | 24.000 Zeichen (nach vollem Lesen) | `share.ts:104-123` |
| `/v1/share/meal/<code>` | GET/DELETE | Bearer | Lesen alle mit Code, Löschen Besitzer | Code-Regex | – | `share.ts:126-146` |

Positiv: keine CORS-Header (nur native Clients), kein KV-Key-Injection/Pfad-Traversal (alle Schlüsselteile per Regex),
`text()` ersetzt `\s+` durch Leerzeichen → keine Zeilen-/Rollen-Injection in Prompts, Promptgröße je Aufgabe begrenzt,
HMAC-Gast-Token (60 Bit ID + 256 Bit MAC), Share-Code 50 Bit, keine `pull_request_target`, Secrets nur per `env:`.
Secret-Scan (307 Commits, `git log --all -E -G` nach `AIza`, `gsk_`, `ghp_`, `github_pat_`, `sk-…`, `BEGIN … PRIVATE KEY`,
`AKIA`, `xox[bp]-`, Gast-Token-Muster, `ApiKey …`, OAuth-/Garmin-Token, Base64 ≥ 120 Zeichen, `.jks/.keystore/.p12/
.mobileprovision/.env`, echte `*.workers.dev`-Adressen; gelöschte Dateien: nur `backend/` (FastAPI-Health-Check) und
Bilder): **keine Funde**. Die zwei Treffer für `sidestore|android/<32hex>` sind Testwerte mit `coach-ai.example.workers.dev`.

## Android

#### Navigation
- Eine Activity (`MainActivity`, `singleTask`), Compose ohne Navigationsbibliothek. 5 Reiter (`app/GymApp.kt:28–34`):
  Training, Ernährung, Verlauf, Pläne, Übungen. Reiter-Zustand `rememberSaveable` (Standard **Training**, `GymApp.kt:49`).
- Unterseiten als Stapel `Page` (`GymApp.kt:37–44`, mit `listSaver` über Prozessende gesichert): SessionDetail,
  ExerciseDetail, RoutineEditor, Settings, NutritionSettings, Recipes. Zurück: `BackHandler` (`GymApp.kt:61`); kein
  Predictive-Back-Opt-in im Manifest (`android:enableOnBackInvokedCallback` fehlt).
- Vollbild-Dialoge (`Dialog(usePlatformDefaultWidth=false)` + Scaffold): CaptureDialog (Erfassen), MealEditorDialog,
  FoodSearchDialog, ExercisePickerDialog. AlertDialogs: Ladewarnung, Tagestyp, Portion, Busy, Meldung, Barcode von Hand,
  Geteilte Mahlzeit, Schnell-Eintrag, Eigenes Lebensmittel, Gewicht, Rezept bearbeiten, Training beenden/verwerfen,
  Training löschen, Als Plan speichern, Plan löschen, Eigene Übung, Uhrzeit (TimeInput), Mahlzeit löschen.
  Keine Bottom-Sheets. Ein Snackbar (Rückgängig nach Schnell-Eintrag, `NutritionScreen.kt:102–106`).
- Deep Links: `ironludi://connect?worker=&token=` und `coach://meal/<code>` (`AndroidManifest.xml:37–50`).

#### Screens und Zustände
| Screen | Leer | Lädt | Fehler | Offline | Erstnutzung | Viele Daten |
|---|---|---|---|---|---|---|
| Training (Start/aktiv) | Tipp-Text ohne Pläne | – | – | ok (lokal) | „Freies Training starten“ | `Stats.last` je Karte, ok |
| Ernährung | „Noch nichts eingetragen“ | nicht abbrechbarer Busy-Dialog | AlertDialog `message` | Warteschlange (`pending`) | Karte „Körperwerte eintragen“ | alle Summen pro Recomposition über alle Mahlzeiten |
| Erfassen | Schnellwahl-Listen | „BLS wird geladen …“ | über NutritionScreen | KI-Knöpfe deaktiviert + Hinweis | – | BLS-Suche/eigene Suche je Tastendruck im Main-Thread |
| Rezepte & Woche | Texte je Reiter | **kein** Busy/Fehler sichtbar (AND-9) | **unsichtbar** | Knopf deaktiviert | – | – |
| Verlauf | Text | – | – | ok | – | LazyColumn ok |
| Pläne/Editor | Text | – | – | ok | – | – |
| Übungen | Liste (59) | – | – | ok | – | ok |
| Einstellungen | – | – | Text-Meldung | – | – | – |
| Ernährung einstellen | – | „Status: wird geprüft …“ | Status-Text | „Keine Verbindung: …“ | – | – |

#### Einstellungen (Schlüssel = Feld in `AppData`, gespeichert in `gym.json`)
| Schlüssel | Standard | Beleg |
|---|---|---|
| `settings.restSeconds` | 90 | `core/Model.kt:123` |
| `settings.keepScreenOn` | true | `core/Model.kt:124` |
| `nutrition.weightKg/heightCm/age/isFemale` | 75 / 180 / 35 / Mann | `core/NutritionTargets.kt:78–81` |
| `nutrition.activityFactor` | 1,4 | `:83` |
| `nutrition.goal` / `diet` | halten / **alles** (iOS: pescetarisch, `swift/Nutrition/NutritionTargets.swift:144`) | `:85–86` |
| `nutrition.weeklyChangePercent`, `energyAdjustmentKcal`, `targetWeightKg`, `bodyFatPercent` | null / 0 / null / null | `:84–94` |
| `weekDayTypes` / `dayTypes` | leer → Ruhetag | `core/Diary.kt:10–11` |
| `reminders.*` | 08:00, 12:30, 16:00, 19:00, alle aus; review aus | `core/Planning.kt:22–27` |
| `recipePreferences` | keine Allergene, 30 min, 1 Person, Snacks an, kein Meal-Prep | `core/Recipes.kt:36–44` |
| SharedPreferences `worker.xml`: `url`, `token` | leer | `app/WorkerClient.kt:25–35` |

#### Datenflüsse
- **gym.json** (`filesDir`): synchron im ViewModel-Konstruktor geladen (`GymViewModel.kt:59–68`), nach jeder Änderung
  ganz neu kodiert und über `gym.json.tmp` + `renameTo` geschrieben (`:84–93`, ohne `fsync`), Mutex + „nur neuester
  Stand“. Reminder-Empfänger lesen dieselbe Datei (`Reminders.kt:35–38`).
- **Worker**: `POST /v1/ai/generate` (meal_analyze, meal_amend, meal_now, nutrition_review, weekly_recipes),
  `POST /v1/invite` (Prüfung), `POST/GET /v1/share/meal`; Bearer-Token; Timeouts 15 s Verbindung / 120 s Lesen
  (`WorkerClient.kt:84, 138–161`). Fotos: 1280 px, JPEG 80 %, Base64 (`NutritionModel.kt:491–507`).
- **Open Food Facts**: `GET world.openfoodfacts.org/api/v2/product/<ean>` ohne Token, eigener User-Agent.
- **Google Code Scanner** (Play-Dienste, ohne Kamera-Berechtigung), Fallback „Nummer eingeben“.
- **Kamera**: `TakePicture` in `cache/photos/mahlzeit.jpg` über FileProvider; Galerie `PickVisualMedia`.
- **AlarmManager**: nur nächste Erinnerung, `setAndAllowWhileIdle(RTC_WAKEUP)` (inexakt, keine
  `SCHEDULE_EXACT_ALARM` nötig), Neuplanung bei `onResume`, Datenänderung, Auslösen, `BOOT_COMPLETED`,
  `MY_PACKAGE_REPLACED` (`Reminders.kt:40–53, 108–112`). Kanal „reminders“ wird erst beim ersten Melden angelegt (`:69`).
- **Berechtigungen**: INTERNET, VIBRATE, POST_NOTIFICATIONS (Laufzeit-Abfrage nur beim Einschalten eines Schalters),
  RECEIVE_BOOT_COMPLETED; `queries` IMAGE_CAPTURE. Keine Kamera, kein Exact-Alarm.
- **Build**: minSdk 26, target/compileSdk 35, AGP 8.11.1, Kotlin 2.2.10, R8 **aus** (`app/build.gradle.kts:39`),
  Release-Signatur aus CI-Secrets, sonst Debug-Signatur ohne Bereitstellung (`android.yml:48–60, 101`).

#### Taps (Zählung aus dem Code)
- **Essen loggen, wiederkehrend**: Ernährung-Reiter (1) › Erfassen (2) › „Häufig/Wie gestern/Favorit“ (3) – sofort
  eingetragen mit Rückgängig. Ab Kaltstart +1, weil die App immer auf „Training“ startet.
- **Essen per Suche**: Erfassen (1) › Suchfeld + Tippen (2) › Treffer (3) › Editor „Speichern“ (4).
- **Satz loggen** (vorbelegt aus letzter Einheit): ✓ (1). Mit Änderung: Feld kg (1) + tippen, Feld Wdh. (2) + tippen, ✓ (3).
