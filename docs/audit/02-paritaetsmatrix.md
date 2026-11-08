# Feature-Paritätsmatrix

Stand 03.11.2026. `C/` = `ios/Packages/CoachCore/Sources/CoachCore/`, `Coach/` = `ios/Coach/`. Android-Spalten dienen nur der Information; Android ist zurückgestellt.

## 1. Ist-Stand der Coach-App (Inventar, im Code geprüft)

| Funktion | iOS | Beleg iOS | Android | Beleg Android |
|---|---|---|---|---|
| Barcode + Open Food Facts | vorhanden | `ios/Coach/Features/Nutrition/CaptureViews.swift:264` (`DataScannerViewController`), `C/Nutrition/OpenFoodFacts.swift:8` | vorhanden | `A/app/.../CaptureScreen.kt:55` (ML-Kit-Code-Scanner) |
| Unbekannter Barcode → Etikett abtippen/fotografieren (KI) | vorhanden | `CaptureViews.swift:155,174` | fehlt („Nährwerttabelle vom Etikett noch nicht“, `docs/android.md:24`) | – |
| Eigene Rezepte / Meal-Prep | vorhanden | `C/Nutrition/MealPlanning.swift:78` (`OwnRecipe`) | vorhanden | `A/core/.../Recipes.kt:418` |
| Favoriten / Zuletzt / Häufig / Wie gestern | vorhanden | `ios/Coach/Features/Nutrition/MealShortcutViews.swift:11` | vorhanden | `CaptureScreen.kt:264` |
| Wasser (inkl. aus Getränken/Essen) | vorhanden | `C/Nutrition/Hydration.swift:6` | vorhanden | `A/app/.../NutritionModel.kt:184` |
| Mikronährstoffe (44 Nährstoffe, BLS 4.0 offline) | vorhanden | `C/Nutrition/Nutrient.swift:5`, `C/Nutrition/BLS.swift:4` | vorhanden | `docs/android.md` Tabelle Z. 1, `Nutrition.kt` |
| Foto-/Text-/Sprach-Erfassung (KI über Worker) | vorhanden | `ios/Coach/Core/Speech/Dictation.swift:20`, `C/AI/AIPolicy.swift` | Foto/Text ja, Sprache fehlt | `docs/android.md` |
| Pausentimer | vorhanden (inkl. Live-Aktivität) | `GymViewModel.swift:192,206` (`RestAdvisor`), `ios/Shared/WorkoutActivity.swift:7` | teilweise (nur bei offener App) | `docs/android.md` letzter Absatz; `A/app/.../GymViewModel.kt:48` |
| Supersätze | vorhanden | `C/Gym/Routine.swift:15` (`supersetWithNext`) | fehlt | kein Treffer `superset` in `android/**/*.kt` |
| Satzarten Aufwärmen/Drop/Versagen | vorhanden | `C/Gym/GymSession.swift:5` | teilweise (nur Aufwärmen) | `A/app/.../HistoryScreen.kt:112` |
| Aufwärm-Vorschlag | vorhanden | `C/Gym/GymTools.swift:39` | fehlt | – |
| 1RM (Epley) | vorhanden | `C/Gym/GymStats.swift:5,7` | vorhanden | `A/core/.../Gym.kt:40` |
| Scheibenrechner | vorhanden | `C/Gym/GymTools.swift:4` (`PlateCalculator`) | fehlt | kein Treffer |
| Übungsverlauf mit Zoom | vorhanden | `C/Gym/GymStats.swift:33`, `ExerciseHistoryCharts.swift` | teilweise (Verlauf je Einheit) | `HistoryScreen.kt` |
| Rekorde / neue PRs je Einheit | vorhanden | `C/Gym/GymStats.swift:83,92` | fehlt | kein Treffer `record|Rekord` |
| Vorlagen/Routinen, KI-Plan mit Fragebogen | vorhanden | `C/Gym/Routine.swift`, `C/Report/CoachImport.swift:7` | Routinen ja | `RoutinesScreen.kt` |
| Plan-Import (GymBook, KI-Antwort) / -Export | vorhanden (Import GymBook + KI-Datei; Export als MD/JSON/CSV) | `C/Gym/GymBookImport.swift:9`, `C/Report/DataExport.swift:41-44` | Sicherung als JSON | `A/core/.../Gym.kt:187` |
| Kalenderintegration (EventKit/.ics) | **fehlt** | kein Treffer `EventKit|EKEventStore` in `ios/` | fehlt | – |
| Sicherung/Wiederherstellung aller Daten | **fehlt** (nur Export ohne Import; offener Punkt E2 in `docs/qualitaet-paket8.md:94`) | `CoachExchangeViews.swift:62` (nur `ShareLink`), einziger `fileImporter` ist GymBook (`GymLibraryViews.swift:466`) | vorhanden (Datei + Auto Backup) | `A/app/.../SettingsScreen.kt:40`, `Gym.kt:187` |
| Datenexport CSV | vorhanden (KI-Export, Zeitraum) | `C/Report/DataExport.swift:44` | fehlt (nur JSON-Sicherung) | – |
| FIT | vorhanden (Krafteinheit → Garmin) | `C/Fit/FitEncoder.swift:5` | fehlt | – |
| GPX | fehlt | kein Treffer | fehlt | – |
| Gerätewechsel | fehlt (Keychain `ThisDeviceOnly`, keine Sicherung; `docs/qualitaet-paket8.md:37`) | – | über Sicherungsdatei | – |
| Erinnerungen (Training, Mahlzeiten, Schlaf, Ausrüstung, Wochenplanung) | vorhanden | `ios/Coach/Core/Coach/ReminderService.swift:30` | Mahlzeiten | `A/app/.../Reminders.kt:4` |
| Wecker (AlarmKit, iOS 26) | vorhanden | `ios/Coach/Core/Health/WakeAlarmService.swift:6` | – | – |
| Streaks | vorhanden (Gym-Wochen, Liga) | `C/Gym/GymOverview.swift:87`, `C/Motivation/Adherence.swift:72` | fehlt | – |
| Wochenbericht / -rückblick | vorhanden | `C/Coach/WeeklyReport.swift:5` | fehlt | – |
| Monats-/Jahresrückblick | **fehlt** | kein Treffer `Monatsbericht|monthly` außer `MuscleLoad` | fehlt | – |
| Trends, Fitness/Ermüdung/Form (Banister) | vorhanden | `C/Coach/Trends.swift`, `C/Coach/FitnessForm.swift:8` | fehlt | – |
| Tagesform/Readiness | vorhanden (Garmin-Readiness + eigener Morning Report mit Normalbereichen) | `C/Health/MorningReport.swift:6`, `GarminSyncService.swift` | fehlt (kein Garmin/Health Connect) | `docs/android.md` „Bewusst nicht“ |
| Ruhetage / Entlastungswoche | Laufplan ja (jede 4. Woche 70 %, Tapering); Gym **ohne** Deload | `C/Profile/RunPlan.swift:9-10,15`; kein Treffer `deload` in `C/Gym`, `Features/Gym` | fehlt | – |
| Krankheits-/Verletzungsmodus | teilweise („War krank“ nur bei verpasster Einheit → einige Tage locker) | `ios/Coach/Features/Plan/SessionViews.swift:77`, `CoachSettings.swift:166` | fehlt | – |
| Mehrsprachigkeit | **nur Deutsch** | `ios/project.yml:9` (`developmentLanguage: de`), keine `.xcstrings`/`Localizable` | nur Deutsch | – |
| Einheitenwahl kg/lb, km/mi, kcal/kJ | **fehlt** (nur metrisch/kcal) | kein Treffer `pound|imperial|kJ` | fehlt | – |
| Darstellung hell/dunkel | vorhanden | `AppAppearance.swift` (PR 76) | nach System | `docs/android.md` |
| Homescreen-/Sperrbildschirm-Widgets | vorhanden (Heute, Ernährung, Mahlzeiten, Health, Gym; Wasser-Knopf) | `ios/CoachWidgets/HomeWidgets.swift:149-218` | fehlt | kein Glance |
| Live-Aktivität (Pause, „Satz erledigt“) | vorhanden | `ios/CoachWidgets/WorkoutLiveActivity.swift:20` | – | – |
| Siri/Kurzbefehle/Schnellaktionen | vorhanden | `ios/Coach/App/AppRouter.swift:141` (`AppShortcutsProvider`) | fehlt | – |
| Kontrollzentrum (`ControlWidget`) | fehlt (Paket 7 Schritt C offen) | `docs/plattform-paket7.md` §4 C; Bundle `WorkoutLiveActivity.swift:7` ohne Control | – | – |
| Watch-App | gestrichen | `README.md` „die Watch-App ist gestrichen“ | – | – |
| Workouts nach Apple Health schreiben | vorhanden | `ios/Coach/Core/Gym/WorkoutWriter.swift:42` | – (kein Health Connect) | – |
| Adaptives Kalorienziel (Verbrauch aus Gewicht + Zufuhr) | **teilweise**: Schätzung über 28 Tage, ≥ 14 erfasste Tage, Tage < 50 % Median raus, Vorschlag ±500 kcal, Übernahme manuell | `C/Nutrition/Expenditure.swift:8-60`, `WeightViews.swift:42,218` | **fehlt** (`docs/android.md:24`) | – |
| Gewichtstrend + Prognose | vorhanden | `C/Nutrition/WeightTrend.swift:25`, `WeightForecast.swift:8` | vorhanden | `NutritionCards.kt:38` |
| Laufpläne mit Progression | vorhanden (persönlich: +≤10 %, Deload, Taper) | `C/Profile/RunPlan.swift:3-10` | – | – |
| Schlaf-Coach | vorhanden | `C/Coach/SleepCoach.swift:28` | – | – |
| Körpermaße (Umfänge) | fehlt (nur Körperfett-%) | `NutritionSettingsView.swift:47` | fehlt | – |
| Fasten-Timer | fehlt | kein Treffer `Fasten|fasting` | fehlt | – |
| Zyklus | fehlt (nur Evidenztext) | `C/Evidence/Evidence.swift` | fehlt | – |

---

## 2. Feature-Paritätsmatrizen

### 2.1 Ernährung

| Funktion | Wettbewerber (wer, URL) | Coach iOS | Android | Aufwand | Bemerkung |
|---|---|---|---|---|---|
| Barcode | MyFitnessPal nur Premium ([MFP Premium+](https://www.myfitnesspal.com/premium-plus), [Kimola-Analyse](https://kimola.com/reports/myfitnesspal-removes-free-barcode-scanner-feature-140890)); Yazio nur PRO ([NutriScan](https://nutriscan.app/blog/posts/yazio-pricing-2026-free-vs-pro-what-pro-unlocks-33b26f8fc7)); Garmin Connect+ UPC ([Garmin-Handbuch](https://www8.garmin.com/manuals/webhelp/GUID-D3BE589F-1A6C-4B6F-9ABC-07DB9AA6C739/EN-US/GUID-476303CC-9A30-4D97-B3E2-978EAE76647B.html)); Bevel gratis ([Bevel App Store](https://apps.apple.com/us/app/bevel-all-in-one-health-app/id6456176249)) | vorhanden `CaptureViews.swift:264` | vorhanden `CaptureScreen.kt:55` | – | Kostenlos = Vorteil gegenüber MFP/Yazio |
| Foto-KI | MFP Meal Scan (Premium) ([Winter Release 2026](https://lite.aol.com/sports/other/story/0022/20260224/9659625.htm)); Yazio PRO; Cronometer Gold seit 02/2026 ([Cronometer Blog](https://cronometer.com/blog/cronometer-updates-whats-new-improved)); Lose It Snap It, Foodvisor ([Drittquelle Nutrola](https://nutrola.app/en/blog/nutrola-vs-lose-it-vs-foodvisor-2026)) | vorhanden (Worker, BLS-Abgleich) | vorhanden | – | Besonderheit: KI zerlegt nur, Nährwerte aus BLS (`decisions.md` „BLS 4.0“) |
| Spracheingabe | MFP Voice Log (Premium) | vorhanden `Dictation.swift:20` | fehlt | S (Android `SpeechRecognizer`) | |
| Mikronährstoffe | Cronometer 80+ ([calorie-trackers.com](https://www.calorie-trackers.com/reviews/cronometer/)) | vorhanden (44) | vorhanden | – | BLS-Tiefe nahe Cronometer, offline |
| Wasser | Yazio frei, MFP | vorhanden | vorhanden | – | |
| Eigene Rezepte/Meal-Prep | MFP, Yazio, Cronometer | vorhanden | vorhanden | – | gekochtes Gewicht + Vorrat ist überdurchschnittlich |
| Wochenplan + Einkaufsliste | MFP Premium+ 99,99 $/Jahr, Meal Planner nur 6 Länder ([MFP](https://www.myfitnesspal.com/premium-plus), [Winter Release](https://lite.aol.com/sports/other/story/0022/20260224/9659625.htm)) | vorhanden (`RecipePlan.swift`) | vorhanden | – | Vorteil: Trainingsplan + Allergene + Lücken fließen ein |
| Adaptiver Verbrauch / wöchentlicher Check-in | MacroFactor: Startformel, dann ab Tag 3 laufend aus Zufuhr + Gewicht; Teil-Logs < 50 % werden markiert; Ziele folgen dem Verbrauch wöchentlich ([MacroFactor Accuracy](https://macrofactor.com/algorithm-accuracy/), [Stronger by Science](https://www.strongerbyscience.com/welcome-to-macrofactor/)) | teilweise: `Expenditure.swift` (28 Tage, ≥ 14 Tage, Vorschlag manuell) | fehlt | S (iOS: Check-in-Karte + Übernahme), M (Android-Port) | Methode fast identisch zu MacroFactor (Intake-Balance, 50-%-Schwelle); fehlt: früherer Start, wöchentlicher Check-in-Ablauf, automatisches Nachziehen innerhalb `GoalRules` |
| Tagesziel nach Training | Garmin Connect+ (Verbrauch + Zufuhr in einer App, [Barchart/Garmin PR](https://www.barchart.com/story/news/36881764/stay-on-top-of-nutrition-goals-in-garmin-connect)) | vorhanden (`NutritionTargets.swift`) | vorhanden (Tagestyp) | – | |
| Fasten-Timer | Yazio (frei, Pro-Ausbau) | fehlt | fehlt | S | geringe Priorität, für Zielgruppe optional |
| GLP-1-Begleitung | MFP „coming soon“/teilweise ([Winter Release](https://lite.aol.com/sports/other/story/0022/20260224/9659625.htm)) | fehlt | fehlt | M | nicht Kernzielgruppe |
| Nährwerttabelle per OCR ohne KI | (keiner explizit gefunden) | teilweise (Foto → KI) | fehlt | M | On-Device-Vision möglich, ohne Worker, ohne Kosten |

### 2.2 Training/Coaching

| Funktion | Wettbewerber | Coach iOS | Android | Aufwand | Bemerkung |
|---|---|---|---|---|---|
| Tagesempfehlung aus Erholung | Garmin Coach: tägliche Anpassung an Schlaf/Stress/Erholung, „warum“-Erklärung ([Garmin Coach](https://connect.garmin.com/features/coach), [Garmin Blog](https://www.garmin.com/en-GB/blog/?p=12369)); Gentler Streak ([App Store](https://apps.apple.com/us/app/gentler-streak-workout-tracker/id1576857102)); Whoop Strain-Ziel | vorhanden (Tagesampel, „Warum?“, PR 50/53) | fehlt | L (Android ohne Datenquelle) | |
| Fitness/Ermüdung/Form | intervals.icu frei ([intervals.icu Forum](https://forum.intervals.icu/t/what-does-this-mean-google-pmc-chart/109508)), TrainingPeaks | vorhanden `FitnessForm.swift:8` | fehlt | – | Coach warnt bewusst nicht mit ACWR (Impellizzeri 2020) – wissenschaftlich sauberer |
| Adaptiver Laufplan | Runna (Pace Insights, „Not Feeling 100%“, Hitze, [the5krunner](https://the5krunner.com/2026/09/28/is-runna-ai/)); Garmin Run Coach | vorhanden (`RunPlan.swift`, Umfang +≤10 %) | – | – | Pace-Anpassung je Einheit fehlt |
| Krank/Beschwerden-Modus | Runna „Not Feeling 100%“ 3–14 Tage ([the5krunner](https://the5krunner.com/2026/09/28/is-runna-ai/)); Hevy „Injury management“ geplant ([Hevy Juli 26](https://www.hevyapp.com/community-updates/july-26/)) | teilweise (`SessionViews.swift:77`) | fehlt | S–M | proaktiv „heute krank/Schmerz“ fehlt |
| Hitzeanpassung | Runna (07/2026) | fehlt | – | S (Regel; Temperatur aus Garmin-Aktivität/Eingabe) | ohne Wetter-API (WeatherKit braucht bezahlten Account) |
| Rad-Adaptivität / FTP ohne Test | TrainerRoad AI FTP Detection ([road.cc](https://road.cc/content/tech-news/trainerroad-rolls-out-adaptive-training-after-beta-success-287713)) | teilweise (FTP-Trend Saisonmodus) | – | L | Nische |
| Wochen-/Monatsrückblick | Strava Athlete Intelligence (30-Tage-Vergleich, [iphone-ticker](https://www.iphone-ticker.de/bei-strava-wertet-kuenftig-ki-die-trainings-aus-243126/)); Hevy Monats-Achievements ([Hevy](https://www.hevyapp.com/community-updates/july-26/)) | Woche vorhanden, Monat fehlt | fehlt | S | |
| KI-Chat zu eigenen Daten | Whoop Coach (OpenAI, [Whoop Community](https://www.community.whoop.com/t/what-llm-are-you-using-to-power-the-in-app-coach/272.md)); Oura Advisor ([Oura](https://ouraring.com/blog/oura-advisor)); Garmin Active Intelligence (Connect+ 6,99 $/Monat); Fitbit Gemini Coach (Premium, [Google Blog](https://blog.google/products/fitbit/personal-health-coach-public-preview/)); Bevel Intelligence 3.0 mit proaktiven Check-ins ([Lifestack](https://lifestack.ai/blog/bevel-app-review)); Athlytic „Ask Athlytic“ ([App Store](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755)) | vorhanden (Chat, Reiter AI, `ChatContext.swift`) | fehlt (nur Ernährungs-KI) | – | Coach: Fakten nummeriert + Regelprüfung |
| Proaktiver Morgen-Check-in | Bevel 3.0, Garmin Active Intelligence (beim Aufwachen, nach Training, abends, [the5krunner](https://the5krunner.com/2026/04/20/garmin-connect-plus-review/)) | teilweise (Morning Report im Reiter, keine Mitteilung; kein Treffer in `ReminderService.swift`) | – | S (lokale Mitteilung nach `BGAppRefresh`) | ohne Server machbar |
| Blutwerte | Whoop Advanced Labs ([Whoop](https://www.whoop.com/us/en/press-center/whoop-launches-advanced-labs-uploads-us/)) | fehlt | fehlt | M | Nische; Datenschutz heikel |

### 2.3 Gym

| Funktion | Wettbewerber | Coach iOS | Android | Aufwand | Bemerkung |
|---|---|---|---|---|---|
| Pausentimer | Hevy, Strong ([Hevy Features](https://www.hevyapp.com/features/), [Strong](https://www.strong.app/)) | vorhanden + Live-Aktivität | teilweise (nur Vordergrund) | M (Foreground-Service/Benachrichtigung) | |
| Supersätze | Hevy, Strong | vorhanden | fehlt | M | |
| Aufwärmrechner | Hevy „Warm Up Set Calculator“, Strong „Warm-up Calculator“ | vorhanden | fehlt | S (Port `GymTools`) | |
| Scheibenrechner | Hevy „Weight Plate Calculator“ | vorhanden | fehlt | S (Port) | |
| PR-Hinweis live | Hevy „Live Personal Record Notification“ | vorhanden (Abschluss) `GymStats.swift:92` | fehlt | S | |
| Live-Aktivität | Hevy | vorhanden | – | – | |
| Widgets | Hevy | vorhanden | fehlt | M (Glance) | |
| Apple Watch | Strong (meistgelobt, [aitoolsbakery](https://aitoolsbakery.com/blog/hevy-vs-strong-app/)), Hevy | gestrichen (SideStore App-ID-Limit) | – | L | Live-Aktivität + Garmin-Sätze als Ersatz |
| CSV-Export | Strong ([strong.app](https://www.strong.app/)), Fitbod ([Indiehackers](https://www.indiehackers.com/post/fitbod-app-review-2026-honest-take-after-real-testing-45d5f07a1b)); GymStreak keiner ([Indiehackers](https://www.indiehackers.com/post/gym-streak-review-2026-my-honest-take-on-gymstreak-app-359b48d0e3)) | vorhanden (KI-Export CSV) | JSON | S | |
| Körpermaße | Strong „Body Part Measurements“, Hevy „Body Measurements“, Liftosaur ([Liftosaur](https://www.liftosaur.com/blog/posts/liftosaur-overview/)) | fehlt | fehlt | S | |
| Programmierbare Progression | Liftosaur (Liftoscript), JEFIT Adaptive Plan ([JEFIT](https://www.jefit.com/blog/jefit-vs-fitbod)) | vorhanden (Doppelprogression, RIR, KI-Plan mit Regelprüfung) | vorhanden (Port) | – | |
| Deload/Entlastungswoche Gym | JEFIT Mesozyklus; Hevy Trainer | fehlt | fehlt | S | Laufplan hat es schon (`RunPlan.swift:9`) |
| Übung tauschen einmalig/dauerhaft | Hevy Trainer (Beta) | vorhanden („Ersetzen“, PR 43) | ? | – | |
| Strava-Sync Kraft | Hevy ([Hevy](https://www.hevyapp.com/community-updates/july-26/)) | Garmin statt Strava (`FitEncoder`) | – | – | Garmin→Strava erledigt den Rest |

### 2.4 Plattform

| Funktion | Wettbewerber | Coach iOS | Android | Aufwand | Bemerkung |
|---|---|---|---|---|---|
| Widgets | Hevy, MFP, Garmin | vorhanden | fehlt | M | |
| Live-Aktivität | Hevy; Garmin „Live Activity Stats“ (Connect+) | vorhanden | – | – | |
| Siri/Kurzbefehle | Strong „Siri Shortcuts“ | vorhanden | fehlt | – | |
| Kontrollzentrum/Aktionstaste | (Apple-Standard seit iOS 18) | fehlt | – | S | geplant Paket 7 C, keine neue App-ID |
| Watch-KI | Apple Workout Buddy ([Apple Newsroom](https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected)) | gestrichen | – | – | |
| Cloud-Sync / Gerätewechsel | Strong Cloud, Hevy-Konto, Liftosaur Cloud | fehlt | Datei | M (Datei-Sicherung) | iCloud/CloudKit nicht mit kostenloser Apple-ID (s. §5) |
| Kalender | (Runna Rennkalender, [TechRadar](https://www.techradar.com/health-fitness/fitness-apps/strava-owned-runna-just-launched-the-feature-ive-been-waiting-for-to-plan-my-race-calendar)) | fehlt | fehlt | S (.ics-Export) / M (EventKit) | |
| Health Connect | Standard bei Android-Trackern | – | fehlt | M | |
| Mehrsprachigkeit | alle Großen | nur Deutsch | nur Deutsch | L | erst bei Launch außerhalb DACH |
| Einheiten lb/mi/kJ | Strong, Hevy, MFP | fehlt | fehlt | M | für DACH-Nutzer gering |

---

## 3. Häufige Nutzerkritik je Gruppe – und ob Coach es besser macht

| Gruppe | Kritik | Quelle | Coach besser? |
|---|---|---|---|
| MyFitnessPal | Barcode hinter Paywall (meistgenannter Punkt in Negativbewertungen), lange Videowerbung, Redesign | [Kimola](https://kimola.com/reports/myfitnesspal-removes-free-barcode-scanner-feature-140890), [Unstar 2026](https://unstar.app/blog/is-myfitnesspal-premium-worth-it-paywall-app-reviews-2026), [MyNetDiary Scorecard 02/2026](https://www.mynetdiary.com/diet-app-scorecard-february-2026.html) (Konkurrenz) | **Ja**: Barcode gratis, keine Werbung |
| MFP/Lose It | Nutzerdatenbank ungenau, Foto erkennt Portionen falsch | [Nutrola](https://nutrola.app/en/blog/why-is-lose-it-snap-it-not-very-accurate) (Konkurrenz) | **Ja, teilweise**: BLS 4.0 statt Nutzerdaten; Portionen bleiben KI-Schätzung |
| Yazio | Abo nach Testphase unklar, Barcode/Foto nur PRO | [Trustpilot](https://www.trustpilot.com/review/yazio.com?page=5), [NutriScan](https://nutriscan.app/blog/posts/yazio-pricing-2026-free-vs-pro-what-pro-unlocks-33b26f8fc7) | **Ja** (kein Abo) |
| Cronometer | Eintragen langsam (~45 s/Mahlzeit), Oberfläche veraltet, Support | [Nutrola](https://nutrola.app/en/blog/cronometer-review-2026) (Konkurrenz), [Trustpilot](https://ie.trustpilot.com/review/cronometer.com) | **Ja**: Diktat, „wie gestern“, Widget-„+“ |
| MacroFactor | Lücken beim Loggen verschlechtern die Schätzung; Wasser/Natrium-Schwankungen | [Gainframe](https://gainframe.app/blog/macrofactor-review/), [MacroFactor](https://macrofactor.com/algorithm-accuracy/) | gleich (gleiche Methode, `Expenditure.swift` filtert Teil-Tage) |
| Hevy | Pro-Gating, gelegentliche Abstürze | [aitoolsbakery](https://aitoolsbakery.com/blog/hevy-vs-strong-app/) (Affiliate) | Ja (alles frei); Stabilität ungetestet |
| Strong | Stillstand der Entwicklung trotz Abo; Free nur 3 Routinen | [MacPowerUsers](https://talk.macpowerusers.com/t/gym-iphone-app-recommendation/32667) | Ja |
| GymStreak | kein Export, aggressive KI-Progression | [Indiehackers](https://www.indiehackers.com/post/gym-streak-review-2026-my-honest-take-on-gymstreak-app-359b48d0e3) | Ja (Export, deterministische Progression) |
| Whoop | Abo-Pflicht, „Whoopgate“-Upgradegebühren, HF-Genauigkeit, Kraft schlecht erfasst | [Millennialhawk](https://millennialhawk.com/whoop-50-health-and-fitness-tracker-review/), [Whoop Community](https://www.community.whoop.com/t/a-once-loyal-user-s-honest-reflection-on-whoop-s-direction/8284), [the5krunner](https://the5krunner.com/2025/10/31/2026-whoop-5-0-mg-review-discount-accuracy-strain-recovery-athletes/) | Ja für Kraft (Sätze/Volumen statt nur HF) |
| Garmin Connect+ | Active Intelligence „dünn“, wiederholt Offensichtliches; Paywall | [the5krunner 04/2026](https://the5krunner.com/2026/04/20/garmin-connect-plus-review/) | **Ja**: Regeln mit Quelle, „Warum?“, Belastung↔Ernährung |
| Runna | Verletzungswelle laut WSJ (Physios), zu schnelle Pace-Steigerung | [the5krunner](https://the5krunner.com/2026/09/28/is-runna-ai/) | **Ja**: +≤10 %, Deload, Laufumfang-Warnung (PR 24) |
| Gentler Streak/Athlytic | Kernfunktionen nur mit Apple Watch, Watch/iPhone-Werte uneinheitlich | [Lifestack](https://lifestack.ai/blog/gentler-streak), [Athlytic App Store](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755) | Ja (Garmin oder Apple Health) |
| KI-Coaches allgemein | Whoop-Chats nicht verknüpft; Oura nutzt Daten für Partnerangebote/Training | [Whoop Community](https://www.community.whoop.com/t/what-llm-are-you-using-to-power-the-in-app-coach/272.md), [ConductAtlas](https://conductatlas.com/platform/oura/oura-privacy-policy/ai-used-for-personalized-wellness-guidance/) (Drittquelle) | Ja: Datenschutzmodus „reduziert“, kein eigener Server |

---

## 4. Alleinstellungsmerkmale (mit Gegenbeleg)

| USP | Beleg Coach | Wettbewerber bieten es nicht / nur teilweise | Vorsprung vergrößern |
|---|---|---|---|
| **Training ↔ Erholung ↔ Ernährung ↔ Gym in einer App, alle Funktionen gratis** | Tagesziel nach Training (`NutritionTargets.swift`), Ampel mit Form, Gym-Sätze nach Garmin (`FitEncoder.swift`) | Garmin verknüpft Ernährung erst seit 01/2026 und nur in Connect+ ([Garmin-Handbuch](https://www8.garmin.com/manuals/webhelp/GUID-D3BE589F-1A6C-4B6F-9ABC-07DB9AA6C739/EN-US/GUID-476303CC-9A30-4D97-B3E2-978EAE76647B.html)); Hevy/Strong ohne Ernährung; MFP/Yazio ohne Belastung; Bevel kommt am nächsten, aber KI-Ebene kostet ([Lifestack](https://lifestack.ai/blog/bevel-app-review)) | Morgen-Mitteilung „Heute: locker + 2.400 kcal, 140 g Protein“ (eine Karte, alle Bereiche) |
| **Regeln entscheiden, KI formuliert; Quelle (DOI) je Regel** | `C/Evidence/Evidence.swift` (72 DOI-Treffer), `AIPolicy.swift` | Garmin Active Intelligence, Whoop Coach, Oura Advisor, Fitbit Gemini: LLM-Antworten ohne Quellenangabe je Regel; Fitbod „AI“ ist Empfehlungsalgorithmus ([Sensai](https://www.sensai.fit/blog/hevy-vs-strong-vs-fitbod-vs-jefit)) | In jeder Empfehlung „Quelle“ antippbar; Prüfbericht der Musterpersonen öffentlich machen |
| **Offline-Nährwerte aus BLS 4.0 statt Nutzerdatenbank** | `C/Nutrition/BLS.swift`, `bls.tsv` (7.000 Lebensmittel) | MFP/Lose It nutzergenerierte Datenbanken; Cronometer verifiziert, aber online und US-zentriert | OCR der Nährwerttabelle auf dem Gerät (Vision) → komplett ohne KI |
| **Datenschutz: kein eigener Server, keine Rohwerte an Gratis-KI, Keychain** | CLAUDE.md, `docs/integrationen.md` „Datenschutz und Tokens“ | Oura AGB erlauben Nutzung für KI-Weiterentwicklung/Partner ([ConductAtlas](https://conductatlas.com/platform/oura/oura-privacy-policy/ai-used-for-personalized-wellness-guidance/)); Gentler Streak ähnlich gut (HealthKit lokal) | Datenschutz-Übersicht „Was verlässt das Gerät?“ je Funktion |
| **Manueller KI-Coach (Export → beliebige KI → Import mit Regelprüfung)** | `C/Report/CoachImport.swift:7`, `DataExport.swift` | Hevy nur ChatGPT-Plugin ohne Rückimport ([Hevy Features](https://www.hevyapp.com/features/)); sonst nichts gefunden | Import auch für Ernährungspläne |
| **Sicherer Laufaufbau** (10 %, Deload, Taper, Laufumfang-Warnung) | `RunPlan.swift:3-10` | Runna: Verletzungsberichte 2026 ([the5krunner](https://the5krunner.com/2026/09/28/is-runna-ai/)) | Pace-Anpassung je Einheit mit derselben Begrenzung |
| **Adaptiver Verbrauch MacroFactor-artig gratis** | `Expenditure.swift` | MacroFactor kostenpflichtig ([App Store](https://apps.apple.com/app/id1553503471)), MFP/Yazio ohne | Check-in-Ablauf ergänzen (Lücke #2) |

---

## 5. Machbarkeitsrahmen (CLAUDE.md, decisions.md, SideStore)

- **Kostenlose Apple-ID:** keine Push-Mitteilungen und kein iCloud/CloudKit (Personal Team: „provisioning for … iCloud, … Push Notifications … not possible“, [Microsoft Xamarin Free Provisioning](https://learn.microsoft.com/th-th/previous-versions/xamarin/ios/get-started/installation/device-provisioning/free-provisioning); Apple-Forum [Thread 84760](https://developer.apple.com/forums/thread/84760)). SideStore erlaubt als Zusatzrecht nur App Groups (`docs/plattform-paket7.md` §1 und §2.1, geprüft im SideStore-Quellcode). Daraus folgt: Server-Push, CloudKit-Sync, WeatherKit = nicht machbar; lokale Mitteilungen, `BGAppRefresh`, App Intents, Widgets, ControlWidget, `fileExporter` in iCloud Drive (vom Nutzer gewählter Ort, kein Entitlement) = machbar.
- **App-ID-Limit** (10 je 7 Tage, `plattform-paket7.md` §1): neue Erweiterungen vermeiden → ControlWidget in `CoachWidgets` statt eigener Erweiterung; Watch-App bleibt gestrichen.
- **Kein Server, KI nur im Worker:** alles Folgende ist lokal oder über vorhandene Worker-Endpunkte.

## 6. Top-15-Lücken mit höchstem täglichem Nutzen

| # | Lücke | Nutzen | Plattform | Aufwand | Prüfung CLAUDE.md / SideStore |
|---|---|---|---|---|---|
| 1 | **Sicherung/Wiederherstellung aller Daten als Datei** (SwiftData + Einstellungen, ohne Secrets) | Schutz vor Datenverlust beim App-Löschen/SideStore-Problem/Gerätewechsel; Android hat es (`Gym.kt:187`) | iOS | M | `fileExporter`/`fileImporter`, kein Entitlement; offen seit `qualitaet-paket8.md:94` (E2). Keychain bleibt `ThisDeviceOnly` |
| 2 | **Wöchentlicher Ernährungs-Check-in** mit gemessenem Verbrauch und automatisch übernommenem Ziel (innerhalb `GoalRules`, Rückgängig) | täglich korrekte Ziele ohne Nachdenken (MacroFactor-Kern) | iOS | S | Regel bereits da (`Expenditure.adjustment`), nur Ablauf/Karte; Schutzgrenzen bleiben |
| 3 | **Verbrauch aus Gewicht + Zufuhr auf Android** | gleiche Ziele ohne Garmin – für den Android-Nutzer *die* Kernfunktion | Android | M | Port `Expenditure`/Tests; in `docs/android.md:24` als „noch nicht“ |
| 4 | **Android-Pausentimer im Hintergrund** (Benachrichtigung mit Countdown, Vibration) | jede Krafteinheit | Android | M | Foreground-Service/`AlarmManager`; keine Server-Push nötig |
| 5 | **Android Gym-Parität**: Supersätze, Scheibenrechner, Aufwärmvorschlag, PR-Hinweis | jede Einheit | Android | M | reiner Port aus CoachCore (Grundregel „Logik in CoachCore“ → Kotlin-Port mit gleichen Testfällen wie bisher) |
| 6 | **Proaktive Morgen-Mitteilung** (Ampel + Tagesziel + nächste Einheit) nach Hintergrundabruf | täglicher Einstieg wie Bevel 3.0/Garmin AI | iOS | S | lokale Mitteilung; Text aus Regeln, KI optional; Datenschutzmodus unberührt |
| 7 | **Android-Widgets** (Glance): kcal übrig, „+250 ml“, nächstes Training | mehrmals täglich | Android | M | lokal |
| 8 | **Kontrollzentrum/Aktionstaste** „Training starten“, „Mahlzeit erfassen“, „+Wasser“ | Schnellzugriff | iOS | S | in vorhandener Erweiterung, keine App-ID (Paket 7 C) |
| 9 | **„Heute nicht fit“-Modus** (krank/Schmerz/wenig Zeit, 3–14 Tage) für Lauf + Gym | häufige Realität; Runna-Vorbild | iOS (+Android Gym) | S–M | Regeln (`MissedSessions` erweitern), beide Profilmodi bedenken |
| 10 | **Gym-Entlastungswoche** (automatisch nach Stillstand/Ermüdung oder alle n Wochen) | Progression langfristig | iOS+Android | S | Regel mit Quelle wie `RunPlan.swift:9` |
| 11 | **Nährwerttabelle per On-Device-OCR** (Vision `VNRecognizeTextRequest`, Android ML Kit Text) statt KI | unbekannte Barcodes ohne Netz/KI-Kontingent | beide | M | entlastet Worker-Kontingent, besser für Datenschutz |
| 12 | **Kalender**: geplante Einheiten als .ics teilen bzw. EventKit-Schreiben | Planung im Alltag | iOS | S (.ics) / M (EventKit) | EventKit braucht nur Usage-String, kein Entitlement; Hypothese – unter SideStore nicht getestet |
| 13 | **Monats-/Jahresrückblick** (Volumen, PRs, km, Ernährungstreue) | Motivation (Strava/Hevy) | iOS | S | aus vorhandenen Daten, Regeln |
| 14 | **Health Connect auf Android** (Gewicht, Schritte, Schlaf, Workouts) | automatische Daten statt Eingabe | Android | M–L | lokal; Play-Erklärung entfällt bei APK-Verteilung (Hypothese) |
| 15 | **Körpermaße** (Taille, Hüfte, Arm) mit Verlauf | Fortschritt trotz Waagen-Plateau (Rekomposition) | beide | S | passt zu `goal .loseAndBuild` (`UserProfile.swift:65`) |

Bewusst nicht in die Top 15: Mehrsprachigkeit und lb/mi/kJ (L/M, für den aktuellen deutschsprachigen Nutzerkreis kein täglicher Nutzen; vor einem echten App-Store-Launch außerhalb DACH aber Pflicht), Watch-App (gestrichen, App-ID-Limit), Cloud-Sync (CloudKit nicht machbar; Datei-Sicherung #1 deckt Gerätewechsel ab), GPX-Export (Garmin liefert das selbst).

## 7. Nicht prüfbar

- Ob die Funktionen auf dem Gerät tatsächlich so laufen (kein Simulator/Mac; `docs/todo.md` listet offene Gerätetests). Nachholen: Screenshots aus `screenshots.yml` bzw. Gerätetest.
- Apple-Tabelle „Supported capabilities“ war per WebFetch nicht lesbar (Häkchen fehlen) – Aussage zu Push/iCloud stützt sich auf Microsoft-Doku und Apple-Forum; vor Entscheidungen die Seite <https://developer.apple.com/help/account/reference/supported-capabilities-ios> im Browser prüfen.
- Ob ein iCloud-Gerätebackup die Daten einer per SideStore installierten App wiederherstellt – Hypothese, nicht verifizierbar ohne Gerät.
- Viele Wettbewerberbewertungen stammen aus Konkurrenz-Blogs (Nutrola, NutriScan, MyNetDiary, Setgraph) – Tendenz plausibel, Zahlen nicht belastbar.
- Exakter MacroFactor-Algorithmus (Glättung, Check-in-Regel) ist nicht öffentlich ([MacroFactor](https://macrofactor.com/algorithm-accuracy/)).
