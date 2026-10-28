# Entscheidungen

Jede Entscheidung mit Datum, Begründung und Quelle. Neueste oben.


## 2026-10-28 – Ernährung: schnell eintragen

Erster PR der UX-Prüfung der Ernährung (Ziel: wiederkehrendes Essen in unter 3 Sekunden):
- **Schnell-Leiste**: die häufigsten Mahlzeiten der aktuellen Tageszeit (letzte 60 Tage, gleiche Lebensmittel und
  Mengen auf 10 g gerundet, `MealSuggestions`) und „wie gestern“ – ein Tipp trägt ein, „Rückgängig“ 5 Sekunden lang.
- **Suche** über eigene Lebensmittel und frühere Mahlzeiten (`FoodSearch`, ohne Groß-/Kleinschreibung und Umlaute,
  Wortanfang und Häufigkeit zuerst). Antippen öffnet den Entwurf, „+“ trägt sofort ein.
- **Wochenstreifen und Zeitpunkt**: jeder Tag der Woche ist auswählbar (ansehen, nachtragen); im Entwurf lässt sich
  der Zeitpunkt wählen, die Mahlzeit folgt der Uhrzeit.
- **Rest auf einen Blick**: Ring mit übrigen kcal, Protein/KH/Fett als „noch … g“ bzw. „… g drüber“
  (`NutritionBudget`); alle Nährstoffe unter „Alle Nährstoffe“.
- **Nur Kalorien** (Schätzung ohne Lebensmittel) und **Wasser** per Glas-Knopf (+250 ml, gedrückt halten für andere
  Mengen); Wasser erscheint nicht als Mahlzeit.

## 2026-10-27 – Live-Aktivität für die laufende Einheit

- Pause, nächster Satz und „Satz erledigt“ / „Weiter“ auf dem Sperrbildschirm und in der Dynamic Island
  (ActivityKit, Widget-Erweiterung `CoachWidgets`). Die Knöpfe sind `LiveActivityIntent`s; deren `perform()` läuft im
  Prozess der App, die dafür bei Bedarf im Hintergrund gestartet wird. Die App bindet die Knöpfe deshalb schon beim
  Start an die (gemeinsame) Einheit `GymViewModel.shared`.
  Apple: <https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities>,
  <https://developer.apple.com/documentation/appintents/liveactivityintent>.
- Kein besonderes Entitlement nötig, nur `NSSupportsLiveActivities`. Abschaltbar in Gym › Ausstattung und in den
  iOS-Einstellungen.
- **Preis bei SideStore:** Jede App-Erweiterung braucht eine eigene App-ID; mit kostenloser Apple-ID sind es höchstens
  10 App-IDs je 7 Tage (AltStore-FAQ: <https://faq.altstore.io/altstore-classic/app-ids>). IronLudi braucht damit 2
  statt 1. Falls die Installation daran scheitert: Erweiterung aus `project.yml` entfernen, die App funktioniert
  unverändert (Pause dann wie bisher per Mitteilung).

## 2026-10-27 – Gym: Start und Abschluss

Dritter PR der UX-Prüfung:
- **Ziel sichtbar**: Die Fokus-Karte zeigt, was die Progression vorschlägt („Ziel heute: 62,5 kg × 6–10 (+2,5 kg) –
  letztes Mal 60 × 10/10/10“, `GymTarget`). Abweichungen muss niemand begründen: Die Progression rechnet ohnehin mit
  dem, was tatsächlich eingetragen wird.
- **Nächste Einheit**: eine Karte mit großem Start-Knopf; im persönlichen Modus die Routine nach der zuletzt trainierten
  (`RoutineRotation`), mit Dauer und Hinweis „Beine seit n Tagen“. Andere Routinen als Leiste darunter.
- **Abschluss**: Volumen gegenüber der letzten gleichen Einheit, „Nächstes Mal“ je Übung und die Hinweise (KI oder
  Regeln) – sie stehen nicht mehr vor dem Training auf der Startseite.
- **Auswertung** als eigene Seite: Kalender (Einheiten je Woche, Serie), Hinweise, Fortschritt, Sätze je Muskel. Die
  Startseite zeigt nur noch die letzten 3 Einheiten, der ganze Verlauf liegt dahinter.
- **Fokus per Kurzbefehl** schaltet erst nach dem ersten Satz ein – der kurze App-Wechsel fällt in die Pause.
- **Große Schrift**: Werte und ± Knöpfe wachsen mit Dynamic Type (`@ScaledMetric`).

## 2026-10-27 – Gym: Satzarten, Supersätze, Gerät belegt

Zweiter PR der UX-Prüfung:
- **Satzarten** (Arbeitssatz, Aufwärmen, Drop-Satz, bis zum Versagen). Aufwärmsätze werden gespeichert, zählen aber
  nicht für Volumen, Bestleistungen und Progression (`LoggedExercise.doneSets`); „Aufwärmsätze einfügen“ legt sie
  aus dem Aufwärmschema an. Gewicht ändern zieht nur Folgesätze derselben Art mit (rückgängig machbar).
- **Supersätze**: gleiche `supersetID`; die Fokus-Karte wechselt A1 → A2 ohne Pause, die Pause kommt nach der Runde
  (`WorkoutFlow.afterCompleting`). In Routinen per „Supersatz mit nächster Übung“.
- **Gerät belegt**: „Später“ (ans Ende), „Ersetzen“ (gleiche Muskelgruppe, eigene Ausstattung; erledigte Sätze bleiben
  bei der alten Übung), Reihenfolge per Ziehen.
- **Pausen**: ±15 s gilt für die Übung auch beim nächsten Mal; RIR 0–1 bei Grundübungen verlängert die laufende
  Pause einmal um 30 s (längere Pausen erhalten Leistung bei schweren Sätzen: Schoenfeld et al. 2016,
  <https://pubmed.ncbi.nlm.nih.gov/26605807/>; Grgic et al. 2017, <https://pubmed.ncbi.nlm.nih.gov/28933024/>);
  10 s vor Ende eine leichte Vibration.
- **Sonderfälle**: Rückfrage bei unplausiblen Eingaben (über 350 kg, mehr als 1,5 × bisheriges Höchstgewicht + 10 kg,
  über 50 Wiederholungen); Unterstützung bei Körpergewichtsübungen als negatives Gewicht (zählt als Last 0);
  „kg je Hantel“ und „je Seite“; Scheibenrechner pro Satz mit eigener Stange und eigenen Scheiben; Notiz je Übung;
  Einheiten im Verlauf werden erst nach Rückfrage gelöscht.

## 2026-10-27 – Gym im Training: Fokus-Karte statt Formular

Ergebnis der UX-Prüfung (drei PRs, dies ist der erste):
- **Fokus-Karte** als Standard: nur der nächste offene Satz, Gewicht und Wiederholungen groß, ± Knöpfe mit 60 pt,
  „Satz erledigt“ im Daumenbereich. Danach springt die Karte selbst weiter (`WorkoutFlow`, getestet); übersprungene
  Übungen kommen am Ende dran. Die Liste aller Übungen bleibt per Umschalter erreichbar.
- **Ziffernblock** statt Stepper: Tippen auf eine Zahl öffnet einen großen Block mit Schnelltasten (±Schritt,
  +5, +10, „wie Satz n“). 60 → 80 kg sind 3 statt 8 Tipps.
- **RIR** ist keine Pflicht mehr nach jedem Satz, sondern eine freiwillige Frage mit großen Knöpfen in der Pause.
- **Ent-Haken** beendet keine laufende Pause mehr und lässt sich (wie Satz/Übung löschen) rückgängig machen.
- **Beenden** speichert nicht mehr sofort: Zusammenfassung, vergessene Sätze (eingetragen, nicht abgehakt) lassen
  sich übernehmen; danach Bestleistungen und Status.
- **Bildschirm an** während der Einheit (`isIdleTimerDisabled`, abschaltbar), Vibration beim Abhaken und am
  Pausenende. Apple: <https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled>,
  <https://developer.apple.com/documentation/swiftui/view/sensoryfeedback(_:trigger:)>.

## 2026-10-27 – Eigene wissenschaftliche Quellen

- Einstellungen › Coach › „Eigene wissenschaftliche Quellen“: Kurzbeleg, DOI/PMID/Link, Kernaussage (höchstens
  300 Zeichen) und Themen. Die App hängt passende Quellen bei jeder KI-Anfrage an die belegten Regeln an
  (`UserSources.inject`, höchstens 8, nach den Regeln der App); der Worker behandelt sie wie die eingebauten
  Regeln (Prompt-Abschnitt „Belegte Regeln“, Quellenprüfung der Antwort). Dafür war keine Worker-Änderung nötig.
- Sie ändern nur Formulierung und Begründung der KI. Tagesampel, Ziele, Progression und Schutzgrenzen bleiben bei
  den geprüften Regeln („Regeln entscheiden, KI formuliert“); eigene Quellen sind als solche gekennzeichnet.
- Auch der Export für externe KIs enthält sie.

## 2026-10-27 – Abnehm-Prognose und Fokus während der Einheit

- Prognose (`WeightForecast`) im Gewichtsverlauf, nur beim Abnehmen: erwartetes Gewicht nach 4, 8 und 12 Wochen
  und bis zum Zielgewicht mit dem dafür geschätzten Defizit pro Tag. Grundlage sind dieselben Grenzen wie bei den
  Ernährungszielen: Tempo aus `GoalRules` (Standard 0,5 %, höchstens 1 % des Körpergewichts pro Woche, Garthe et
  al. 2011), Defizit höchstens 25 % des Bedarfs, nie unter BMI 18,5. Das Tempo bezieht sich auf das jeweils
  aktuelle Gewicht (pro Woche etwas weniger kg). 7.700 kcal je kg sind eine Näherung; wegen Wasser und Anpassung
  des Stoffwechsels (Hall et al. 2011) steuert die App über die Wägungen nach (`WeightTrend`).
- Fokus: iOS erlaubt Apps nicht, einen Fokus zu schalten. Die App startet beim Beginn und Ende einer Krafteinheit
  zwei Kurzbefehle der Person über `shortcuts://x-callback-url/run-shortcut` (Aktion „Fokus festlegen“) und
  kehrt über `coach://gym` zurück. Quelle: <https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios>.
  Standardmäßig aus, weil die Kurzbefehle einmal eingerichtet werden müssen.

## 2026-10-27 – Manueller KI-Coach (Export und Import)

- Export: eine Markdown-Datei je Zeitraum (7/30/90/365 Tage oder eigener Zeitraum) mit Profil, Plan, Routinen,
  Tageswerten, Aktivitäten, Krafteinheiten mit allen Sätzen, Ernährung und Gewicht. Markdown, weil ChatGPT,
  Gemini und Claude Tabellen und Text darin zuverlässig lesen; eine Datei, damit alles gebündelt hochgeladen wird.
  Oben steht die Anleitung für die KI samt Antwortformat und unten die Liste der erlaubten Übungs-IDs.
- Import: die Antwort einfügen; die App liest den Codeblock ```ironludi``` (JSON) mit `routinen`, `wochenplan`
  und `hinweise`. Es gilt weiter „Regeln entscheiden“: dieselbe Prüfung wie beim KI-Trainingsplan
  (`GymCoach.validatePlan`: bekannte Übungen, Ausstattung, Sätze 1–5, Pausen, Wochenvolumen), Wochenplan nur im
  eigenen Plan mit `ScheduleCheck`-Hinweisen, Übernahme erst nach Vorschau. Ernährungsziele werden nicht
  importiert, weil sie an die Schutzgrenzen (`GoalRules`) gebunden sind.
- Die Export-Datei enthält Gesundheitsdaten; die App weist darauf hin und teilt sie nur über das iOS-Teilen-Menü.
- Übernommen wird nur, was die Person auswählt (`CoachImport.Selection`): je Routine „bestehende ersetzen“, „zusätzlich
  anlegen“ (bei gleichem Namen mit Zusatz „(KI)“) oder „nicht übernehmen“, optional alle bisherigen löschen; beim
  Wochenplan je geändertem Tag mit Vergleich bisher/neu und Wahl dauerhaft oder nur nächste Woche; Hinweise einzeln.

## 2026-10-27 – „Heute“ aufgeräumt, Erinnerungen kennen Erledigtes

- „Heute“ zeigt oben nur, was heute zählt: Empfehlung, Einheiten, Coach-Notiz, Warnungen, abends die
  Schlafenszeit, heute Erledigtes. Rest der Woche, Wochenziele, eigene Ziele, Rangliste und die letzten
  Aktivitäten liegen unter „Diese Woche, Ziele und Verlauf“. Der letzte Abruf steht klein darunter.
- Erinnerungen werden nach jedem Abruf (Garmin, Health) und nach jeder Krafteinheit neu geplant. Mit Training
  am selben Tag (mindestens 15 Minuten oder eine Krafteinheit) entfällt die heutige Erinnerung; im Saisonplan
  zählt das Erledigte der Woche wie unter „Heute“ (`TodayPlan.done`), z. B. keine Ausrüstungs-Erinnerung für
  Donnerstag, wenn am Dienstag schon geschwommen wurde.
- Die Watch-App fürs Gym ist gestrichen; der Testlauf mit echten Daten steht in `docs/todo.md`.

## 2026-10-27 – GymBook-Verlauf importieren, App heißt IronLudi

- Import aus dem GymBook-Backup (`.database`, SQLite/Core Data, GymBook 7.1.9): `ZEXERCISELOG` je Satz mit
  `ZDAY`, `ZTIME` (Sekunden seit Mitternacht), `ZFREQUENCYVALUE` (Wiederholungen bzw. Sekunden),
  `ZQUANTITYVALUE` (kg), `ZSKIPPED`; Übung aus `ZEXERCISE`, Routine aus `ZWORKOUT`. Gelesen mit der SQLite-
  Bibliothek von iOS, nur lesend und aus einer Kopie. Ausgelassene Sätze und Ausdauer-Einträge entfallen.
- Übungen mit gleichem Bewegungsablauf werden der Bibliothek zugeordnet (`GymBookImport.mapping`), damit
  Progression und Verlauf zusammenpassen; Varianten mit anderem Gerät (z. B. Multipresse) werden eigene Übungen.
- Jede Einheit bekommt eine feste ID aus Tag und Routine: erneutes Importieren legt nichts doppelt an; Tage, die
  schon in der App erfasst sind, werden übersprungen. Die Backup-Daten kommen nicht ins Repo.
- Angezeigter Name „IronLudi“ (`CFBundleDisplayName`, Texte, SideStore-Quelle). Bundle-ID und Dateiname der IPA
  bleiben, sonst sähe SideStore eine neue App und die Daten auf dem iPhone wären weg.

## 2026-10-27 – Erinnerungen: Ausrüstung am Vorabend, Wochenplanung am Sonntag

- Lokale Mitteilungen (`UNCalendarNotificationTrigger`) wie die Trainings-Erinnerungen, ohne Server und ohne
  Push-Berechtigung (SideStore). Geplant werden jeweils 14 Tage; iOS erlaubt höchstens 64 ausstehende Mitteilungen,
  Quelle: <https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app>.
- Schwimm-Ausrüstung: am Vorabend um 18 Uhr, wenn die Schwimmeinheit des Saisonplans Ausrüstung braucht
  (`eq` in den Schwimmschritten: Pull-Buoy, Paddles, Flossen, Schnorchel). Der eigene Wochenplan kennt keine
  Ausrüstung je Einheit, dort gibt es diese Erinnerung nicht.
- Sonntags „Nächste Woche planen“ (Uhrzeit einstellbar, Standard 18 Uhr). Antippen öffnet die Wochenplanung:
  eigener Wochenplan → die Tage der nächsten Woche nur für diese Woche ändern (`WeekPlan` in `PlanAdjustments`,
  der Wochenplan bleibt); Saisonplan → Einheiten und Ausrüstung der nächsten Woche.

## 2026-10-27 – Apple Health und Apple Watch als zweite Quelle

- Import aus HealthKit (`HealthImportService`, Zuordnung in `CoachCore/Health/HealthImport`): Schlaf mit Phasen,
  Ruhepuls, Schritte, aktive und Gesamtkalorien, Atemfrequenz, Sauerstoffsättigung, VO2max, Gewicht und Workouts.
  Abfragen über `HKStatisticsCollectionQueryDescriptor` (Tageswerte) und `HKSampleQueryDescriptor` (Schlaf,
  Workouts, Gewicht), Quelle: <https://developer.apple.com/documentation/healthkit/hkstatisticscollectionquerydescriptor>.
- Garmin hat Vorrang, Health füllt nur Lücken. Workouts mit gleicher Sportart, die höchstens 10 Minuten
  auseinander starten oder sich zu mehr als der Hälfte überlappen, gelten als Duplikat (Garmin Connect schreibt
  seine Aktivitäten selbst nach Health). Von der App selbst geschriebene Krafteinheiten werden übersprungen.
- HRV: Apple speichert SDNN (`heartRateVariabilitySDNN`), Garmin nächtliche RMSSD. Die Werte sind nicht
  austauschbar; Health-HRV wird nur ohne Garmin übernommen, damit die persönliche Baseline aus einer Messart besteht.
- Schlaf: je Nacht eine Quelle (die mit Schlafphasen, sonst die mit dem meisten Schlaf), Überlappungen zählen
  einmal; Schlaf, der zwischen 10 und 18 Uhr beginnt, gilt als Nickerchen.
- Health-Workouts bekommen negative IDs (aus der UUID), damit sie nie mit Garmin-IDs kollidieren und keine
  Garmin-Details oder FIT-Dateien angefragt werden.
- HealthKit bleibt optional (SideStore, siehe Eintrag vom 23.10.); ohne Berechtigung meldet die App das in den
  Einstellungen.

## 2026-10-27 – Gym ersetzt GymBook

- Die vier GymBook-Pläne (Lower, Push & Pull B, Pull A, Push A) sind als Vorlagen mit den zuletzt genutzten
  Gewichten als Startwert hinterlegt (`RoutineTemplates.gymBook`). Kabelvarianten und Dips am Barren sind neu in
  der Bibliothek. Annahme: „Dips 79 kg“ ist das Körpergewicht bzw. die Maschinenlast aus GymBook.
- Übertragung nach Garmin Connect: Die App schreibt eine FIT-Datei (Sport „training“, Unterart „strength“) mit
  `set`-Nachrichten (Übungskategorie, Wiederholungen, Gewicht, Dauer, Pausen) nach dem Profil des Garmin FIT SDK
  (`@garmin/fitsdk` 21.218.0, `profile.js`) und lädt sie über den Upload-Dienst hoch (409 = schon vorhanden).
  Abschaltbar, weil eine parallel auf der Uhr aufgezeichnete Einheit sonst doppelt erscheint.
- KI-Trainingsplan: Fragebogen (Ziel, Tage, Minuten, Schwerpunkt, Beschwerden), Eingabe aus Ausstattung,
  Verlauf und Profil. Der Worker lässt nur Übungen aus der gesendeten Bibliothek zu und verwirft Hinweise mit
  fremden Zahlen; die App begrenzt Sätze (1–5), Wiederholungen und Pausen (45–240 s) und prüft das Wochenvolumen
  je großem Muskel gegen 10–20 Sätze (Schoenfeld et al. 2017, PMID 27433992; Pelland et al. 2025, PMID 41343037)
  und die Häufigkeit von zwei Tagen pro Woche (Schoenfeld et al. 2016, PMID 27102172). Ohne KI gibt es den
  Regel-Vorschlag.
- KI-Hinweise im Gym-Reiter bekommen zusätzlich die Beobachtungen der Regeln (`GymCoach.observations`):
  Stillstand über drei Einheiten, zu wenig oder zu viele Sätze je Muskel in 7 Tagen, nur ein Trainingstag je Muskel.

## 2026-10-27 – Aktivitätsdetails wie in Garmin Connect

- **Wunsch des Nutzers:** Bei erfassten Einheiten alle Details sehen, die auch die Garmin-App zeigt.
- **Quellen:** Aktivitätsliste (`/activitylist-service/…`, jetzt mit Bewegungszeit, Tempo, Höhe, Kadenz,
  Laufdynamik, Leistung, Schwimmwerten, Temperatur, Trainingseffekt-Schwerpunkt), beim Öffnen ergänzt aus
  `/activity-service/activity/{id}` (`summaryDTO`), dazu die FIT-Datei für Karte, Verlauf und Runden. Feldnamen wie in
  python-garminconnect bzw. FIT-SDK-Profil (`record`: Position, Höhe, Kadenz, Temperatur; `lap`: Tempo, Auf-/Abstieg,
  Kadenz, Leistung, kcal). Die FIT-Datei bleibt im Cache (offline).
- **Darstellung:** Übersicht als Kacheln, Karte mit Strecke, Diagramme (Herzfrequenz, Pace umgekehrt wie bei Garmin,
  Höhe, Kadenz, Leistung), Rundentabelle, danach alle Abschnitte. Nur vorhandene Werte erscheinen. Laufkadenz aus
  FIT (ein Fuß) wird auf Schritte pro Minute verdoppelt.

## 2026-10-27 – Schlaf-Coach und Chat (Runde 3)

- **Schlaf-Coach (Vorbild Whoop):** Schlafbedarf heute Nacht = Ziel (7–9 h, Watson et al. 2015) plus ein Viertel
  des Defizits der letzten 7 Nächte, höchstens 60 Minuten (Praxiswert); mehr Schlaf verbesserte Leistung bei
  Sportlern (Mah et al. 2011, PMID 21731144). Schlafenszeit = Weckzeit − Bedarf − 15 Minuten Einschlafen. Streuung
  der Einschlafzeit > 60 Minuten löst einen Hinweis auf feste Zeiten aus (Windred et al. 2024). Einschlaf- und
  Aufwachzeit kommen aus `sleepStartTimestampLocal`/`sleepEndTimestampLocal` (Connect) bzw. Start + Versatz
  (Personal API). Optionale Erinnerung 30 Minuten vorher.
- **Chat mit dem Coach:** Worker-Aufgabe `coach_chat`. Die App schickt Fakten aus ihren Regeln (Tagesampel,
  Plan, Laufwoche, Schlaf, Ernährungsziel, Gewichtstrend, Form, Wochenbericht) und die letzten 6 Nachrichten.
  Im Modus „reduziert“ nur Einordnungen (z. B. „Schlaf im Schnitt unter 7 Stunden“, „Gewicht leicht fallend“),
  keine Rohwerte. Antworten mit Zahlen, die nicht in der Anfrage stehen, verwirft der Worker; die App zeigt dann
  einen Hinweis statt einer Antwort. Bei Beschwerden rät der Coach zu ärztlicher Abklärung, keine Diagnosen.
  Der Verlauf wird nicht gespeichert.

## 2026-10-27 – Vergleich mit Bezahl-Apps, Runde 2

- **Screenshots in CI** (`screenshots.yml`, Label `screenshots`): UI-Test mit Beispieldaten (`-demo`, nur im Speicher,
  erfundene Musterperson) auf iPhone SE und 17 Pro Max, hell, dunkel und große Schrift, Deutsch. Bilder als
  Vorabversion `screenshots-…`, weil Actions-Artefakte aus der Cloud-Sitzung nicht lesbar sind. Ein Lauf kostet etwa
  30–40 macOS-Minuten (×10 im privaten Repo) – nur gezielt starten.
  - Befunde der ersten Runde: Wochentage brachen bei großer Schrift zeichenweise um, Titel in der Training-Übersicht
    mitten im Wort, Tagesaktionen abgeschnitten, „Last“ statt „Belastung“, Nachkommastellen bei Gramm. Behoben.
- **Gemessener Verbrauch (MacroFactor):** Intake-Balance-Methode, Verbrauch = mittlere erfasste Zufuhr − Gewichtstrend
  × 7.700 kcal/kg (Gilmore et al. 2014, PMID 25057153; Sanghvi et al. 2015, PMID 26040640). Mindestens 14 erfasste Tage
  in 28; Tage unter 50 % des Medians gelten als unvollständig; außerhalb von 1,1–3,5 × Grundumsatz unplausibel, weil
  Selbstauskünfte die Zufuhr oft unterschätzen (Lichtman et al. 1992, PMID 1454084). Liegt eine plausible Messung vor,
  ersetzt sie den Vorschlag aus dem Gewichtstrend (keine doppelte Anpassung).
- **Fitness, Ermüdung, Form (TrainingPeaks):** gleitende Mittel der Garmin-Belastung über 42/7 Tage nach dem
  Impulse-Response-Modell (Clarke & Skiba 2013, PMID 23728131). Keine Verletzungswarnungen aus dem Verhältnis
  (Impellizzeri et al. 2020, PMID 32502973). Zonen in % der Fitness sind Praxiswerte (intervals.icu), so gekennzeichnet.
  Dazu ein Wochenbericht gegen die Vorwoche mit festen Hinweisen.
- **Laufplan mit Steigerung (Runna):** Minuten je Laufeinheit aus dem tatsächlichen Schnitt der letzten vier Wochen,
  Aufbau höchstens +10 %, jede vierte Woche 70 % (Bell 2023), Tapering 70 %/50 % (Wang 2023), Obergrenze nach
  Erfahrung; Gewichtung locker 1 / Qualität 0,9 / lang 1,4 und Inhalte der Qualitätseinheit sind Praxiswerte.
- **Gym-Komfort (Strong, Hevy):** Aufwärmsätze, Scheibenrechner, Pause ±15 s, Mitteilung bei Pausenende.
- **Nicht umgesetzt:** Live Activity auf dem Sperrbildschirm – braucht eine App-Erweiterung mit eigener App-ID; ob
  SideStore sie mit kostenloser Apple-ID signiert, ist ungeprüft.

## 2026-10-27 – Energie entscheidet über die Makros (Bewertungsrunde 1)

- **Fund im Prüfbericht:** An Trainingstagen lag Fett bei 14–18 % der Energie und die Summe der Makros über der
  Tagesenergie (z. B. 3.350 kcal am Langlauf-Tag einer Einsteigerin mit Abnehmziel). Ursache: Kohlenhydrate nach
  Tagestyp (bis 8 g/kg) wurden unabhängig von der Energie gesetzt, geplante Einheiten zählten mit 0 kcal.
- **Neu:** Geplante Einheiten gehen mit (MET − 1) × kg × Stunden in die Energie ein (MET 5 Kraft, 7 Ausdauer;
  Compendium, Ainsworth et al. 2011, PMID 21681120; Dauer leicht 45, moderat 60, hart 90 Minuten als Annahme, bis
  Garmin die echte Einheit liefert). Die Kohlenhydrate werden gekürzt, bis Fett 20 % behält, aber nie unter die
  Untergrenze der Spanne nach Thomas et al. 2016 (moderat 5, hoch 6, sehr hoch 8 g/kg). Bewusste Abweichung von
  `targets.py` im Altbestand.
- Der Prüfbericht prüft jetzt zusätzlich „Fett 20–35 %, Makros ergeben die Tagesenergie“.

## 2026-10-27 – Sicherungen gegen unpassende Empfehlungen

- **Frage des Nutzers:** Wie stellen wir sicher, dass Pläne, Vorschläge und Rezepte zu den Angaben passen und nicht
  irreführen? Umgesetzt sind vier Sicherungen und ein Prüfbericht.
- **Eingabeprüfung (`InputCheck`):** unplausible Körperdaten, Zielgewicht in die falsche Richtung, Wettkampf in der
  Vergangenheit. Zielzeit bzw. Zielpace werden mit der Wettkampfprognose der Uhr verglichen (zwischen zwei Strecken
  log-log interpoliert): bis 3 % schneller realistisch, bis 10 % ehrgeizig, darüber sehr ehrgeizig. Die Schwellen sind
  Praxiswerte und als solche gekennzeichnet.
- **Gewichtsverlauf (`WeightTrend`):** Formeln für den Energiebedarf liegen im Einzelfall oft daneben, und der Körper
  reagiert verzögert (Hall et al. 2011, PMID 21872751). Die App vergleicht deshalb den Trend (lineare Regression über
  28 Tage, mindestens 8 Wägungen über 14 Tage) mit dem geplanten Tempo und schlägt Anpassungen von höchstens 250 kcal
  pro Schritt und ±500 kcal insgesamt vor; die Person übernimmt sie selbst. Abnehmen über 1 % pro Woche löst immer
  „mehr essen“ aus. Tägliches Wiegen half beim Abnehmen (Steinberg et al. 2013, PMID 23512320; 2015, PMID 25683820).
  Wägungen kommen manuell oder aus Garmin Connect (`/weight-service/weight/range/{start}/{end}?includeAll=true`,
  Gewicht in Gramm; Pfad aus python-garminconnect 0.3.20, am echten Konto noch zu prüfen).
- **Laufumfang (`LoadCheck`):** Warnung, wenn die letzten 7 Tage mehr als 30 % über dem Schnitt der drei Wochen davor
  liegen und mindestens 5 km mehr sind (Nielsen et al. 2014, PMID 25155475; die 10-%-Regel schützte nicht, Buist et
  al. 2007).
- **Rezepte:** Zutaten mit versteckten Allergenen oder tierischen Bestandteilen (Pesto, Worcestersauce, Mayonnaise,
  Fischsauce …) werden erkannt; Nährwerte je 100 g, die nicht zu 4/4/9 kcal je g passen oder physikalisch unmöglich
  sind, führen zum Verwerfen des Rezepts.
- **Prüfbericht (`coach-report`):** sechs Musterpersonen (u. a. Untergewicht mit Abnehmwunsch, vegane
  Halbmarathonläuferin mit Nussallergie, Saisonplan) werden in jeder PR durchgerechnet; feste Schutzregeln
  (REDs-Untergrenze, Abnehmtempo, Protein 1,4–2,2 g/kg, BMI-Sperre, Ruhetag, Pause bei schlechter Erholung,
  Rezeptprüfung) müssen eingehalten sein, sonst schlagen die Tests fehl. Der Bericht steht als PR-Kommentar.

## 2026-10-26 – Einheiten ausführlich erklärt

- **Wunsch des Nutzers:** Einheiten wie die Schwimmtrainings nicht nur kurz zusammenfassen, sondern in der App
  ausführlicher erklären.
- **`UnitGuides` (CoachCore):** Jede Einheit bekommt Zweck, Ablauf Schritt für Schritt, Gefühl, typische Fehler und
  ein Glossar der vorkommenden Begriffe (CSS, Abschlag, Zipper, Seitlage, Pull-Buoy, Sighting, Sweet Spot, FTP, Over-Under,
  VO2max, Kadenz, Schwelle, Marathontempo …).
  - Beim Schwimmen wird jeder Abschnitt des Ablaufs erklärt; das Tempo relativ zur CSS wird in Worte gefasst.
  - Die Texte sind feste Bausteine ohne KI.
  - Zahlen kommen nur aus dem Plan, den eigenen Testwerten oder belegten Regeln (z. B. 4×4 bei 90–95 % HFmax).
- **Eigener Wochenplan:** Ein Tipp auf eine Einheit öffnet dieselbe Erklärung. Werte des Saisonplans (CSS, FTP) kommen
  dort nicht vor.

## 2026-10-26 – Rezeptideen für die kommende Woche

- **Regeln legen die Tagesziele fest:** Für jeden Tag der kommenden Woche (Montag bis Sonntag) rechnet die App
  Energie, Protein, Kohlenhydrate und Fett. Grundlage ist dieselbe Logik wie für „heute“ (`NutritionPlanner.compute`
  mit den geplanten Einheiten des Wochenplans inklusive Ausnahmen bzw. des Saisonplans). Kohlenhydrate richten sich
  nach dem Trainingstag (Thomas et al. 2016), Protein nach dem Ziel, und die Energie hat die REDs-Untergrenze.
- **Weitere Eingaben:**
  - Ernährungsweise und Ziel, Allergene, Abneigungen, Zubereitungszeit, Snack und Meal-Prep.
  - Lücken der letzten 14 Tage: Nährstoffe aus den erfassten Mahlzeiten unter 80 % des Ziels, nur Tage mit
    mindestens 2 Mahlzeiten.
  - Die 15 am häufigsten genutzten Lebensmittel.
- **KI schlägt vor (Worker-Aufgabe `weekly_recipes`):** Die Zutaten kommen mit Menge und Nährwerten je 100 g, im
  selben Schema wie bei der Mahlzeiten-Analyse. Nährwert-Datenbanken (USDA, Open Food Facts) waren aus der
  Entwicklungsumgebung nicht erreichbar. Deshalb gibt es keine eingebaute Nährwerttabelle; die Werte sind als
  KI-Schätzung gekennzeichnet.
- **Die App prüft jede Antwort:**
  - Jede Zutat wird gegen Ernährungsweise und Allergene geprüft (Schlüsselwörter, pflanzliche Ersatzprodukte
    ausgenommen). Unpassende Rezepte werden verworfen und genannt.
  - Die Mengen werden ans Energieziel angepasst (Faktor 0,75–1,33, auf 5 g gerundet). Liegt der Tag danach mehr
    als 15 % daneben, erscheint ein Hinweis.
  - Ohne KI gibt es keine Rezepte, nur die Tagesziele.
- **Einkaufsliste:** Gleiche Zutaten der Woche werden zusammengefasst und mit der Personenzahl multipliziert,
  abhakbar und teilbar. Ein Rezept lässt sich mit einem Tippen als Mahlzeit eintragen.

## 2026-10-26 – Gym-App: Bibliothek, Routinen, RIR und KI-Tipps

- **Vorbild GymBook:** Übungsbibliothek (51 Übungen mit Muskeln, Geräten und 2–3 Technikhinweisen), eigene
  Übungen, Routinen, Satz-Erfassung mit „Letztes Mal“ und Pausen-Timer, Verlauf je Übung mit Höchstgewicht und
  geschätztem 1RM, Rekorde nach jeder Einheit. Übungen aus dem Garmin-Katalog behalten ihre IDs und
  Progressionswerte, damit alte Einheiten weiter zählen.
- **Vorschläge für Routinen:** Jeder große Muskel kommt mindestens zweimal pro Woche dran (Schoenfeld et al. 2016,
  doi:10.1007/s40279-016-0543-8). Bei 1–3 Krafttagen Ganzkörper, bei 4 Ober-/Unterkörper, ab 5 Push/Pull/Beine plus
  Ober-/Unterkörper. Die Wiederholungsbereiche liegen in der Mitte: Muskeln wachsen über ein breites Lastspektrum
  ähnlich (Schoenfeld et al. 2017, doi:10.1519/JSC.0000000000002200). Einsteiger machen 2 Sätze, sonst 3; die
  Pausen (Grundübung 120 s, sonst 90 s) sind Praxiswerte.
- **Wiederholungen in Reserve (RIR):** optional nach jedem Satz (0–4+). Die RIR-Skala ist praktikabel und valide
  (Helms et al. 2016, doi:10.1519/SSC.0000000000000218; Zourdos et al. 2016, doi:10.1519/JSC.0000000000001049).
  Muskelaufbau nimmt zu, je näher Sätze am Versagen enden (Robinson et al. 2024, doi:10.1007/s40279-024-02069-2),
  Versagen selbst bringt kaum mehr (Refalo et al. 2023, doi:10.1007/s40279-022-01784-y).
  - Neue Regel D in `GymProgression`: Bleiben in allen Arbeitssätzen mindestens 4 Wiederholungen in Reserve, wird
    sofort ein Sprung erhöht.
  - Die Schwelle 4 ist ein Praxiswert.
  - Die Regeln A–C (Doppelprogression, ACSM 2009) bleiben unverändert.
- **KI-Tipps (Worker-Aufgabe `gym_hints`):** Die Regeln entscheiden Gewicht und Wiederholungen. Die KI formuliert
  daraus 2–4 Hinweise; Punkte mit Zahlen, die nicht in den Fakten stehen, verwirft der Worker (`grounding.ts`). Ohne
  KI zeigt die App die Entscheidungen der Regeln.

## 2026-10-26 – Mehrere Nutzer:innen, Rangliste und Begleiter

- **Kein Konto nötig:** Jede Installation ist bereits ein eigener Zugang. Profil, Garmin-Konto (Keychain),
  Mahlzeiten und Gym-Daten liegen nur auf dem jeweiligen iPhone. Gemeinsam ist nur der Worker.
- **Einladungslink** `coach://join?worker=…&token=…&league=…` (eigenes URL-Schema, kein Entitlement nötig). Er
  richtet den Worker ein und tritt der Rangliste bei. Weil er das App-Token enthält, weist die App darauf hin,
  ihn nur an vertraute Personen zu schicken.
- **Rangliste im Worker** (`worker/src/league.ts`, KV „coach-league“): Es werden nur Name, Symbol, Punkte,
  Serie und „x von y Einheiten“ gespeichert, keine Gesundheitswerte. Einträge verfallen nach 90 Tagen; höchstens
  20 Mitglieder. Alles steht in den KV-Metadaten (≤ 1024 Byte), sodass ein `list()` die ganze Rangliste liefert.
  Quelle: <https://developers.cloudflare.com/kv/api/list-keys/>
- **Punkte:** Es zählen nur geplante Einheiten, die erledigt wurden (10 je Einheit, +20 für die ganze Woche).
  Zusätzliches Training zählt nicht, ausgelassene Tage zählen nicht als geplant. Die Serie zählt Wochen mit
  mindestens 80 %. Belege: Punkte und Stufen für erreichte eigene Ziele erhöhten die Aktivität in randomisierten
  Studien, auch in Familien und mit Wettbewerb (Patel et al. 2017, doi:10.1001/jamainternmed.2017.3458; Patel
  et al. 2019, doi:10.1001/jamainternmed.2019.3505). Die Metaanalyse von Mazeas et al. 2022
  (doi:10.2196/26779) fand einen kleinen bis mittleren Effekt (g = 0,42), der nach Ende schwächer wird. Dass
  nur der eigene Plan zählt, ist eine Designentscheidung: kein Anreiz zum Übertraining, Ruhetage gehören dazu.
- **Begleiter** (Hund, Katze, Trainer:in; eigener Name und Foto): Er formuliert mit festen Sätzen, was die
  Regeln ohnehin sagen. Bei niedriger Erholung lobt er das Ausruhen, nach einem verpassten Tag gibt es keine
  Vorwürfe. Für die Wirkung virtueller Begleiter allein gibt es keine belastbare Evidenz. Er ist deshalb nur
  eine freundliche Darstellung und keine eigene Empfehlung. Das Foto bleibt lokal (`PhotosPicker` braucht keine
  Fotomediathek-Berechtigung).

## 2026-10-26 – Erinnerungen als lokale Mitteilungen, Ausnahmen nur für eine Woche

- Push über APNs braucht einen Server und das Entitlement `aps-environment`, das kostenlose Konten bzw.
  SideStore nicht bekommen. Lokale Mitteilungen (`UNUserNotificationCenter`, `UNCalendarNotificationTrigger`)
  brauchen beides nicht und funktionieren offline. Quelle:
  <https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app>
- iOS hält höchstens 64 geplante Mitteilungen je App; die App plant deshalb nur die nächsten 14 Tage und plant
  bei jedem Öffnen sowie nach jeder Planänderung neu. Quelle:
  <https://developer.apple.com/documentation/uikit/uilocalnotification> („the system keeps the soonest-firing 64
  notifications … and discards the rest“).
- Aktionen in der Mitteilung: „Erledigt“, „Verschieben …“ (öffnet die App mit passenden Tagen),
  „Diese Woche auslassen“. Ohne Erlaubnis zeigt „Heute“ dieselben Knöpfe.
- Auslassen und Verschieben ändern nur die laufende Woche (`PlanAdjustments`); der Wochenplan bleibt. Tagesampel,
  Ernährung und Gym rechnen mit dem angepassten Plan. Zieltage werden wie der Wochenplan bewertet
  (`ScheduleCheck`), zwei fordernde Ausdauertage direkt hintereinander landen hinten (Seiler 2006).
- Saisonplan: nur Erinnerung an die festen Einheiten, ohne Verschieben; offene Einheiten verteilt der Saisonplan
  selbst.

## 2026-10-26 – Garmin-Konto (inoffiziell) zuerst, Personal API als Rückfall

- Auftrag des Nutzers: Der inoffizielle Login soll die Hauptquelle sein, die offizielle Personal API nur
  einspringen. Grund: Readiness, Trainingsstatus, Endurance Score und Wettkampfprognosen gibt es nur so.
- `garth` (OAuth1 über die alte Mobile-Anmeldung) funktioniert seit März 2026 nicht mehr. Garmin hat die
  Anmeldung geändert und prüft TLS-Fingerabdrücke (garth-README: „deprecated“; python-garminconnect
  Issue #332). Übernommen ist deshalb der Ablauf aus python-garminconnect 0.3.20 (Strategie „mobile“):
  - Anmeldeseite laden, nach 2–5 s `POST /mobile/api/login` (`clientId=GCM_IOS_DARK`), bei Bedarf
    Bestätigungscode über `/mobile/api/mfa/verifyCode`.
  - Ticket gegen ein DI-OAuth2-Token tauschen (`diauth.garmin.com`), danach Abrufe auf
    `connectapi.garmin.com` mit den Kopfzeilen der Garmin-App.
  - Die App läuft auf einem echten iPhone (URLSession). Ihr TLS-Fingerabdruck ist der von iOS, genau den
    imitiert python-garminconnect mit `curl_cffi`.
- Das Passwort wird nicht gespeichert, nur das Token (Schlüsselbund) und die E-Mail-Adresse. Läuft die
  Erneuerung ab, meldet die App „neu anmelden“.
- Rückfall je Abruf: Scheitert das Konto (abgelaufen, 403/429, unbekannter Pfad), übernimmt die Personal API,
  sofern ein Key hinterlegt ist. Der Abrufbericht zeigt, welche Quelle wie oft geantwortet hat.
- Endpunkte nur über das Konto: `metrics-service/metrics/trainingreadiness/{date}`,
  `…/trainingstatus/aggregated/{date}`, `…/endurancescore?calendarDate=`, `…/racepredictions/latest/{displayName}`,
  dazu Tageswerte und Schlaf in der Connect-Form (`usersummary/daily/{displayName}`,
  `dailySleepData/{displayName}`). Feldnamen wie im Altbestand (`ha_publish.extract_metrics`).
- Die Training Readiness fließt in die Tagesampel ein; die Regel gab es schon (`RecoveryEvaluator`).
- Ungeprüft, weil nur auf dem iPhone mit echtem Konto testbar: ob Garmin die Anmeldung von dort durchlässt.
  Falls nicht, meldet die App den Grund, und die Personal API übernimmt.

## 2026-10-26 – Repo privat, SideStore-Auslieferung über den Worker

- Auf Wunsch des Nutzers ist das Repo privat (Trainingsplan und Gewichte waren öffentlich). Release-Dateien
  privater Repos sind ohne Anmeldung nicht ladbar, SideStore kann keine Zugangsdaten mitschicken.
- Lösung ohne neue Secrets: Der iOS-Build legt `Coach.ipa`, `icon.png` und `release.json` in Workers KV
  (Namespace `coach-releases`, frei: 1 GB, 1.000 Schreibvorgänge/Tag, Werte bis 25 MiB; IPA ≈ 3 MB). Der
  Worker baut daraus die Quelle unter `/sidestore/<key>/source.json`, `key` = erste 32 Hex-Zeichen von
  SHA-256("sidestore:" + COACH_APP_TOKEN). Quelle: Cloudflare-Doku „Workers KV › Limits“.
- Kosten: GitHub Free hat für private Repos 2.000 Actions-Minuten im Monat, macOS-Minuten zählen zehnfach
  (GitHub-Doku „About billing for GitHub Actions“). Ein iOS-Build dauert etwa 4 Minuten, also etwa
  40 Freiminuten, das reicht für rund 50 Builds im Monat. Linux-Läufe (Tests, Worker) zählen einfach.

## 2026-10-26 – Personalisierung: Profil, Ziele, eigener Wochenplan

Auftrag: Die App passt sich der Person an (Sportarten, Ziel, Wettkampf oder allgemeine Fitness, Wochenplan mit
Ruhetagen). Anlass ist die Nutzung durch eine zweite Person (Abnehmen, nur Laufen und Gym).

**Aufbau**
- `UserProfile` (CoachCore): Sportarten, Hauptziel, optional Wettkampf, eigene Ziele (Laufstrecke, Pace, Ruhepuls,
  Zielgewicht), Erfahrung je Sportart, Wochenplan, Gesundheitsangaben. Modus `season` (bisheriger Almere-Plan, wer
  die App schon mit Garmin-Daten nutzt) oder `personal` (alle anderen, Einrichtungsassistent beim ersten Start).
- `ScheduleCheck`: prüft den selbst gewählten Wochenplan (Ruhetag, Serien, zwei fordernde Tage hintereinander,
  Intensitätsverteilung, Krafthäufigkeit, Wettkampf). Hinweise ohne Quelle sind als „Praxisregel“ markiert.
- `ScheduleAdvisor`: vergleicht die Tagesampel mit dem eigenen Plan. Bei niedriger Erholung wird eine fordernde
  Einheit auf den nächsten freien Tag verschoben, bei mittlerer lockerer gemacht, Ruhetage werden bestätigt.
- `SchedulePlanner`: Planvorschlag für die verfügbaren Tage. Probiert alle Verteilungen durch und nimmt die mit den
  wenigsten Regelverstößen; höchstens 6 Einheiten, damit ein Tag frei bleibt.
- `GoalRules`: Ziel → Ernährung (neues Ziel „Umformen“, Wochentempo in % des Körpergewichts) mit Schutzgrenzen.
- Ernährung, Heute, Plan, Training und Gym richten sich nach dem Profil; der Saisonplan bleibt unverändert.

**Schutzgrenzen (Sicherheit vor Wunsch)**
- Abnehmen höchstens 1 % des Körpergewichts pro Woche, Standard 0,5 %; Aufbau höchstens 0,5 %.
- Keine Gewichtsziele bei Schwangerschaft/Stillzeit, Essstörung, unter 18 Jahren oder BMI unter 18,5 (auch ein
  Zielgewicht unter BMI 18,5 wird nicht angesteuert). Defizite bleiben zusätzlich durch die Energieverfügbarkeits-
  grenze begrenzt (IOC REDs 2023, bestand schon). Bei Erkrankung oder Verletzung rät die App zum Arzt.

**Belege** (alle in PubMed geprüft, in `Evidence.swift` mit DOI)
- Aktivität: WHO 2020 (150–300 min moderat oder 75–150 min intensiv, Krafttraining; eigene Empfehlungen für
  Schwangere und chronisch Kranke).
- Abnehmen: Garthe 2011 (0,7 % vs. 1,4 % pro Woche, mehr Magermasse bei langsamem Tempo); ACSM 2009 und Swift 2014
  (Sport allein bringt ohne hohes Volumen nur etwa 2 kg; Krafttraining erhält Magermasse); Hudson 2020 und Morton 2018
  (mehr Protein erhält bzw. baut Magermasse, über etwa 1,6 g/kg kein Zusatznutzen für den Aufbau); Nedeltcheva 2010
  (Schlafmangel verschiebt den Gewichtsverlust von Fett zu Magermasse, kleine Studie).
- Zunehmen/Aufbau: Larson-Meyer 2022 (300–500 kcal Überschuss üblich, 0,45 kg/Woche für viele schwer erreichbar;
  Praxisregel).
- Ruhepuls und Fitness: Hespanhol Junior 2015 (nach einem Jahr Laufen −6,7 Schläge/min bei Inaktiven, 49 Studien),
  Reimers 2018 (191 Studien, Ausdauertraining senkt den Ruhepuls); Milanović 2015 (Intervalle steigern die VO2max
  etwas stärker); Pedisic 2019 (Laufen senkt das Sterberisiko um 27 %, auch einmal pro Woche).
- Wochenplan: Seiler 2006 und weitere (überwiegend lockere Einheiten, bestand schon); Bell 2023 (Deload-Konsens).

**Bewusst anders als verbreitet**
- Die „10-%-Regel“ für den Laufumfang ist nicht belegt: Buist 2007 (532 Einsteiger, RCT) fand keinen Unterschied bei
  Verletzungen, Nielsen 2014 sah nur ab etwa 30 % Steigerung tendenziell mehr entfernungsbedingte Verletzungen
  (nicht signifikant). Die App steigert vorsichtig und nie über 30 % und kennzeichnet das als Praxisregel.
- Kein Training nach Zyklusphase: McNulty 2020 und Elliott-Sale 2020 (Metaanalysen, Qualität niedrig) finden nur
  unbedeutende Unterschiede und lassen keine allgemeinen Regeln zu. Die App passt sich deshalb nach Befinden und
  Erholung an, nicht nach Zyklusphase. Kein Training „nach Pille“.
- Nicht geprüft/aufgenommen: Verhaltensforschung zu Gewohnheiten und Vorsätzen (Gollwitzer & Sheeran, Lally et al.)
  stehen nicht in PubMed; ohne geprüfte Quelle fließen sie nicht ein.

**Noch offen (nächster Schritt):** erzeugte Trainingspläne mit Progression für Laufen und Gym (Wochenumfang aus dem
Garmin-Stand, Entlastungswoche alle vier Wochen, Ziel-Pace/-Distanz) sowie die KI-Notiz für persönliche Profile.
Bis dahin zeigt der Gym-Reiter nur das freie Erfassen von Sätzen.

## 2026-10-26 – FIT-Auswertung: aerobe Kopplung und Pace-Check

- Runden und Zeitreihen liefert die Personal API nur als FIT-Datei (`/download-service/files/activity/{id}`,
  ZIP); `get_activity_splits`/`get_activity_details` des Altbestands gibt es dort nicht (offizieller Client
  `client.py`, Stand 26.10.2026). Die App entpackt das ZIP und liest die FIT-Nachrichten `record` und `lap`
  selbst (`CoachCore/Fit`, Feldnummern laut FIT-SDK-Profil), ohne Apple-Frameworks, damit die Tests auf Linux
  laufen.
- `decoupling.py` (Methode 3: HF-Zonen-Filter, 10 min Aufwärmen weg, Zeitreihe, Rundenmethode als Ersatz) und
  `pace_check.py` sind unverändert portiert, ebenso die Einordnung harter Einheiten aus `tagesform.py`.
  Erwartungswerte: über 1.000 Zufallsfälle, berechnet mit dem Original-Code, dazu eine mit `fit_tool` erzeugte
  FIT-Datei, die `fitparse` unabhängig gelesen hat.
- Zeitbasis der Zeitreihe ist die Uhrzeit ab dem ersten Messpunkt (Garmins `sumDuration` war die Zeit bei
  laufender Uhr); bei Auto-Pause verschiebt sich die Hälftengrenze minimal.
- Höchstens sechs FIT-Abrufe je Synchronisierung, Ergebnisse als JSON im App-Support-Ordner (90 Tage). RPE kommt
  aus `/activity-service/activity/{id}` (`summaryDTO.directWorkoutRpe`) und wird zwei Tage lang nachgefragt.
- Wissenschaft: Herz-Kreislauf-Drift (Coyle & González-Alonso 2001, doi:10.1097/00003677-200104000-00009) und
  „Durability“ (Maunder et al. 2021, doi:10.1007/s40279-021-01459-0) begründen die Kennzahl; die 5-%-Grenze ist
  ein Praxiswert und so gekennzeichnet. Pace-Check: 4×4-Ziel 90–95 % HFmax (Helgerud et al. 2007), Schwelle an
  der Schwellen-HF verankert; als Praxisregel markiert, der Feldtest bleibt maßgeblich.

## 2026-10-26 – Disziplinen, Zielzeit Almere und Marathon

- Portiert aus den HA-Ansichten Schwimmen, Rad, Laufen, Saison und Marathon: Paces aus der CSS (`swim_paces`),
  Rad-Zonen in % FTP (`bike_zones`), Lauf-Paces (`run_paces`), geschätzte Zielzeit Almere (1,9 km / 94 km /
  21,1 km plus 3 und 2 min Wechsel, Korridor 5:30–6:00 h, Aussage nur mit Benchmarks jünger als 8 Wochen),
  Marathon-Ausblick mit Longrun-Leiter aus dem Saisonplan. Tests prüfen die Werte gegen das HA-Dashboard.
- Testwerte werden mit Datum gespeichert (`TestRecord`): Verläufe für CSS, FTP und Schwelle, Aktualität für die
  Zielzeit. Eintragen direkt auf der Seite der Disziplin.
- CSS-Test nach Wakayoshi et al. 1992 (PubMed, doi:10.1055/s-2007-1021282) als neue Regel `swim.css`.
- Marathon ≈ Halbmarathon × 2,15–2,2 ist ein Praxiswert ohne Studie und in der App so benannt.
- Noch offen: Pace-Check (`pace_check.py`) und aerobe Kopplung (`decoupling.py`) brauchen Runden bzw. FIT-Daten
  der Aktivitäten.

## 2026-10-26 – Saisonplan als Reiter „Plan“

- Quelle: `coach_plan.jinja` (48 Wochen, je Woche Zwift-, Schwimm-, Qualitäts-, Z2- und Langlauf-Einheit,
  Musterwoche und Prioritäten je Phase, Zwift-Bibliothek Z01–Z15) und `swim_plan.json` (Schwimmschritte) aus dem
  Altbestand, unverändert als `CoachCore/Resources/season-plan.json` übernommen.
- Platzhalter wie im Altbestand aus den Testwerten: `§S±n§` CSS + n s/100 m, `§Wnn§` % FTP, `§T§` Schwelle,
  `§I§` Schwelle −23 bis −18 s/km, `§E§` Schwelle +65 bis +100 s/km, `§MP§` Marathonpace, `§R§` Renn-Laufpace
  (neu in Saison & Ziele, Standard 5:42 /km). Tests prüfen die Werte gegen das HA-Dashboard (4:32–4:37, 6:00–6:35).
- Wettkampf-Läufe 🏁 lassen sich annehmen oder ablehnen (dann gilt die Alternative), Schlüssel wie im Altbestand
  (`wk-lauf-<Montag>-q|l`). Erledigt-Haken: Garmin-Aktivitäten der Woche und Krafteinheiten der App; der Longrun
  zählt ab 80 % der geplanten Länge, Rad nur mit Distanz (Zwift + Uhr nicht doppelt).
- Navigation: fünf Tabs (Heute, Plan, Training, Ernährung, Gym), Einstellungen über das Zahnrad in „Heute“
  (Apple HIG: Tab-Bar für 2–5 Hauptbereiche).

## 2026-10-26 – Wissenschaftliche Basis und Kontrolle der KI

- Auftrag des Nutzers: Empfehlungen sollen auf begutachteter Wissenschaft beruhen, die KI darf nichts erfinden.
- `CoachCore/Evidence`: 31 Veröffentlichungen (DOI bzw. PMID am 26.10.2026 in PubMed geprüft, Grundlage ist
  `docs/wissenschaft-und-quellen.md` der HA-Übergabe) und 20 Regeln. Jede Regel hat eine Kernaussage und eine
  ehrliche Einstufung: „gut belegt“, „belegt, Schwellen aus der Praxis“ oder „Praxisregel“ (z. B. Ruhepuls
  +5 Schläge – vorsichtig gewählt, ohne Studie für genau diesen Wert). Tests stellen sicher, dass jede Regel
  eine bekannte Quelle hat.
- Die App zeigt unter Tagesnotiz, Ernährungsauswertung, Gym-Progression, Volumen und HF-Zonen die Grundlage mit
  Links (doi.org bzw. PubMed); alle Regeln unter Einstellungen › Wissenschaftliche Grundlagen.
- Worker (`grounding.ts`): Systemanweisung (nur Fakten aus der Anfrage, keine neuen Zahlen/Quellen, keine
  Diagnosen, nie mehr Training fordern), Temperatur 0,2, belegte Regeln als einzige erlaubte Begründung.
  Jede Antwort wird geprüft: Punkte mit Zahlen, die nicht in der Anfrage stehen, werden verworfen (0–3 als
  Zählwörter frei), Quellen nur aus den mitgeschickten Regeln. Bleibt nichts übrig, antwortet der Worker mit
  502 und die App zeigt die regelbasierte Notiz.
- Grenze: Die Zahlenprüfung erkennt erfundene Werte, nicht falsche Schlussfolgerungen ohne Zahlen. Dafür gibt es
  die feste Systemanweisung und die Regeln; die Entscheidung selbst trifft weiterhin nie die KI.

## 2026-10-26 – Gym in der App, Workouts in Apple Health

- HealthKit funktioniert auf dem Gerät des Nutzers trotz SideStore (Diagnose „funktioniert“, Rückmeldung
  26.10.2026). Krafteinheiten werden deshalb als Workout (`traditionalStrengthTraining`) in Apple Health
  gespeichert. Die Prüfung zur Laufzeit bleibt: Ohne HealthKit wird lokal gespeichert und der Eintrag lässt sich
  später nachholen.
- Sätze werden in der App erfasst. Garmin bekommt sie nicht: Die Personal API ist nur lesend; Schreiben ginge nur
  über den optionalen inoffiziellen Login.
- Übungszuordnung (`exercise_names.py`), Trainingsplan mit Wochentagen (`gym_plan.json`, Lower flexibel Di/Do),
  Doppelprogression (`gym_progress.py`, ACSM 2009) und Sätze je Muskel (Karte `coach-gym`) sind unverändert
  portiert; Erwartungswerte der Tests sind mit dem Python-Code nachgerechnet.
- Vorbefüllen: Steht eine Steigerung an und ist die Tagesampel grün, schlägt die App das neue Gewicht vor
  (wieder bei der Untergrenze); sonst die Werte der letzten Einheit, ohne Verlauf die Werte aus dem Plan.
- Die laufende Einheit liegt zusätzlich in den UserDefaults, damit sie einen Neustart der App übersteht.

## 2026-10-26 – Garmin-Werte wie im Home-Assistant-Dashboard

- Abgeglichen mit `dashboard/garmin-coach.dashboard.json` im Altbestand (Reiter Erholung, Laufen/Rad/Schwimmen,
  Herzfrequenz). Neu in der App (Reiter „Training“): Verläufe über 28 Tage für HRV-7-Tage-Schnitt, Ruhepuls,
  Schlaf und Body Battery; Tageswerte inkl. Atemfrequenz, SpO2, Schlafphasen, Body Battery geladen/verbraucht,
  VO2max (Laufen/Rad), Fitnessalter; Kilometer pro Woche je Sportart (12 Wochen); Herzfrequenzzonen.
- Quellen in der Personal API (offizieller Client, `client.py`): Tageszusammenfassung und Schlaf
  (SpO2, Atemfrequenz, Schlafphasen), `spo2acclimation`, `fitnessage/v2`, `heartRateZones/v2`; VO2max aus den
  Aktivitäten (`vO2MaxValue`) und dem Profil (`vo2MaxRunning`/`vo2MaxCycling`); Zeit in Zonen aus
  `hrTimeInZone_1…5` der Aktivitätsliste. Feldnamen wie in den Connect-Endpunkten; Abweichungen zeigt die
  Garmin-Diagnose.
- Herzfrequenzzonen unverändert aus `hr_zones.py` portiert (Friel in % LTHR, HFmax nur aus bestätigten
  Messwerten, Verteilung der letzten 4 Wochen, Hinweise) und getestet.
- Nicht über die Personal API verfügbar: Training Readiness, Trainingsstatus, Endurance Score. Sie folgen mit dem
  optionalen inoffiziellen Login. Die aerobe Kopplung (HF-Pace-Drift, `decoupling.py`) braucht die Auswertung der
  FIT-Dateien und folgt später.
- Aktivitäten werden einmalig 13 Wochen rückwirkend geladen (Wochenbalken, HFmax).

## 2026-10-24 – Ernährung ohne BLS-Abgleich (vorerst)

- Tagesziele (`targets.py`: Mifflin-St Jeor, Kohlenhydrate je Tagestyp nach Thomas/Erdman/Burke 2016, Protein je
  Ziel, Fett 20–35 %, DGE-Mikronährstoffe, Flüssigkeit), Mahlzeit-Analyse (`analyze.py`) und Open Food Facts
  (`off.py`) sind portiert. Erwartungswerte der Zielberechnung sind unabhängig mit der Formel des Altbestands
  nachgerechnet (Test).
- Der Abgleich mit dem Bundeslebensmittelschlüssel (BLS 4.0, 14 MB, CC BY 4.0) fehlt noch: Der Download von
  blsdb.de ist aus der Build-Umgebung gesperrt und hat einen wechselnden Link mit Bot-Sperre. Nährwerte kommen
  daher aus der KI-Schätzung (je 100 g) bzw. von Open Food Facts; eigene, gespeicherte Lebensmittel haben
  Vorrang vor der KI-Schätzung. Möglicher nächster Schritt: BLS-Datei einmalig bereitstellen und als SQLite im
  App-Bundle oder im Worker (Cloudflare D1) nutzen.
- Fotos werden vor dem Versand auf höchstens 1280 px verkleinert und neu als JPEG kodiert (EXIF/GPS fallen weg)
  und nicht gespeichert.
- Open Food Facts direkt aus der App (eigener User-Agent laut OFF-Doku), gefundene Produkte werden lokal
  gemerkt; ein zweiter Scan braucht kein Netz.
- Ernährung und Training werden gemeinsam von der KI ausgewertet (Worker-Aufgabe `nutrition_review`): Tagestyp,
  Training, Wochenplan, Tagesampel, Ziel/Ernährungsweise und der Stand je Nährstoff.

## 2026-10-23 – Coach-Logik auf dem iPhone, Saison konfigurierbar

- Tagesampel (`recommendation.py`), Saisonplan mit Phasen, Wochen-Soll und Musterwoche (`plan.py`) sowie das
  Wochenvolumen (`app.py`) sind nach `CoachCore` portiert und unter Linux getestet. Grenzen und Texte sind
  unverändert; die Phasengrenzen der Standardsaison stimmen mit dem Altbestand überein (Test).
- Renntermine und Testwerte (FTP, CSS, Pace) sind in der App einstellbar statt fest im Code; Watt- und
  Pace-Angaben im Plan rechnen sich daraus.
- Die Struktur der Saison (Marathon als Zwischenziel, danach Mitteldistanz) ist weiterhin fest. Eine andere
  Saisonstruktur braucht eine Code-Änderung in `SeasonPlan`.
- Training Readiness liefert die Personal API nicht; die Regel ist vorhanden und greift, sobald der Wert
  (z. B. über den optionalen inoffiziellen Zugang) verfügbar ist.
- Datenschutz verbessert: Im Modus „reduziert“ gehen auch die Begründungen der Tagesampel ohne Rohwerte an
  die KI (der Altbestand schickte dort z. B. „Ruhepuls 58 bpm“ mit).
- Die KI-Notiz wird je Tag und Ampelstufe zwischengespeichert; ohne Worker zeigt die App die regelbasierte
  Notiz (`fallback_note` im Altbestand).

## 2026-10-23 – KI-Worker in TypeScript, Prompts im Worker

- Cloudflare Workers Free erlauben 10 ms CPU-Zeit je Anfrage (Warten auf `fetch` zählt nicht). Fotos werden als
  Base64 an Gemini weitergereicht; das ist in V8 (TypeScript) billig, in Python-Workers (Pyodide) teurer.
  Quelle: Cloudflare-Doku „Workers › Platform › Limits“. Daher TypeScript mit Biome (Lint/Format) und Vitest.
- Prompts liegen im Worker (`worker/src/tasks.ts`), die App schickt nur Aufgabe und abgeleitete Werte. Eine
  Prompt-Änderung braucht so nur einen Worker-Deploy, keine neue App-Version (Neuinstallation per SideStore).
- Der Worker ist ohne `COACH_APP_TOKEN` gesperrt (503) und vergleicht das Token in konstanter Zeit.
- Fund beim Portieren: Die Nachfolgemodell-Erkennung des Altbestands nahm einen Satzpunkt in den Modellnamen
  auf („…models/gemini-3.6-flash.“); im Worker korrigiert und getestet.

## 2026-10-23 – Kein eigener Server: Garmin über die Personal API, KI über einen Cloudflare Worker

Der Nutzer möchte keinen dauerhaft laufenden Rechner (Pi trägt Home Assistant, Mini-PC läuft nur morgens).

- **Garmin:** Seit Oktober 2026 gibt es die offizielle *Garmin Connect Personal API*: Key selbst in Garmin
  Connect erzeugen (30 Tage bis 1 Jahr), per `POST https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token`
  mit `Authorization: ApiKey <key>` gegen ein 24-h-Bearer-Token tauschen, dann lesend abrufen
  (HRV, Schlaf, Ruhepuls, Body Battery, Stress, Aktivitäten inkl. FIT-Datei, Gewicht, HF-Zonen, Profil).
  Quelle: offizieller Client <https://github.com/garmin/connect-personal-api-python>
  (`constants.py`, `auth.py`, `client.py`, Stand 21.10.2026). Die App ruft die API direkt auf; der Key liegt
  nur im Keychain des iPhones.
  Grenzen: nur lesen (kein Schreiben zu Garmin), Training Readiness/Erholungszeit fehlen nach Berichten,
  Rate-Limits unveröffentlicht, Key muss spätestens jährlich von Hand erneuert werden.
- **KI:** Gemini (Ausweichmodelle) und Groq laufen über einen Cloudflare Worker, der nur die API-Keys hält
  und Anfragen mit einem App-Token weiterreicht. Keine Keys in der App.
- **Logik** (Tagesampel, Baselines, Wochen-Soll/Ist, Ernährungsziele, Progression) läuft auf dem iPhone in
  `CoachCore` und wird auf Linux getestet.
- **Daten** liegen in SwiftData auf dem iPhone (Gerätebackup plus Export in die Dateien-App).
- Unterschied zu einem Dauerbetrieb-Server: Garmin-Daten werden beim Öffnen der App und gelegentlich per
  Hintergrundaktualisierung geholt. Server-Push wäre mit kostenloser Apple-ID ohnehin nicht möglich.
- Optional später (Phase 5): inoffizieller Garmin-Login nur für Schreibfunktionen (Gym-Sätze), abschaltbar.

Verworfen: Backend auf dem Raspberry Pi (bremst Home Assistant) und auf dem Windows-Mini-PC (läuft nicht
dauerhaft); GitHub-Actions-Cron (siehe unten).

## 2026-10-23 – Inoffizieller Garmin-Login nur als Fallback

Geprüft: python-garminconnect 0.3.19 meldet sich über `sso.garmin.com/mobile/api/login` mit der
iOS-Client-ID `GCM_IOS_DARK` an, tauscht das Service-Ticket bei `diauth.garmin.com` gegen ein
OAuth2-Token und ruft `connectapi.garmin.com` auf (`garminconnect/client/sso.py`, `session.py`,
`constants.py`). Inoffiziell und mehrfach von Garmin geändert (zuletzt März 2026), daher nur noch für
Funktionen, die die Personal API nicht bietet.

GitHub-Actions-Cron verworfen: Cloudflare filtert je nach Netz (Rechenzentrums-IPs riskant), MFA ist
ohne Mensch nicht lösbar, rotierende Tokens müssten in Secrets zurückgeschrieben werden.

## 2026-10-23 – HealthKit ist optional (SideStore mit kostenloser Apple-ID)

- Apple erlaubt HealthKit für kostenlose Konten („Apple Developer“-Spalte):
  <https://developer.apple.com/help/account/reference/supported-capabilities-ios>
- SideStore schaltet es aber nicht frei: In SideSign (`Sources/Models/Feature.swift`, Stand 13.10.2026)
  sind für kostenlose Teams nur App Groups und Inter-App Audio erlaubt, HealthKit ist gar nicht als
  Feature hinterlegt. Beim Signieren bleiben nur Entitlements aus dem Provisioning-Profil
  (`Sources/CodeSigning/CodeSignerAPI.swift`). `com.apple.developer.healthkit` fällt weg.
- Folge: Die App prüft HealthKit zur Laufzeit (`HealthAccessDiagnosis`) und funktioniert ohne.
  Garmin liefert Workouts, Schlaf und Herzfrequenz über die Personal API; Krafttrainings werden lokal
  gespeichert. Mit bezahltem Account und TestFlight geht HealthKit ohne Umbau.
- Die IPA wird mit `ldid` und den Entitlements pseudo-signiert, damit SideStore sie sieht und der
  Gerätetest aussagekräftig ist.

## 2026-10-23 – Groq ist neu

Im alten Repo gibt es keinen Groq-Fallback (auch nicht in der Historie); dort wird nur zwischen
Gemini-Modellen gewechselt (404-Nachfolger, „lite“ bei 503). Diese Logik wird übernommen, Groq kommt
als zusätzliche Stufe dazu.

## 2026-10-23 – Build ohne Mac

- `macos-15`-Runner, Xcode 26.x (iOS-26-SDK, Deployment-Target iOS 18). Xcode 26 ist auch für einen
  späteren TestFlight-Upload Voraussetzung.
  Quelle: <https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md>
- XcodeGen erzeugt das Projekt; `CODE_SIGNING_ALLOWED=NO`; SideStore signiert beim Installieren.
- Plattformunabhängige Logik liegt in `CoachCore` und wird auf Linux getestet (günstiger als macOS).
