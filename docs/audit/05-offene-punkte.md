# Offene Punkte

## Rückfragen an dich

Das sind die Entscheidungen, die wirklich bei dir liegen.

1. **Weitere Prüfrunden?** Das Stopp-Kriterium ist nicht erreicht (siehe `00-zusammenfassung.md`). Weiterprüfen kostet viel Kontingent und
   wird nach dem bisherigen Verlauf vor allem kleinere Punkte finden.
2. **Standard-KI-Anbieter (WRK-01):** Die Gemini-Bedingungen erlauben für API-Clients mit Nutzer:innen im EWR, in der Schweiz und im UK nur
   Paid Services. Möglich sind: Gemini bezahlen, Workers AI als Standard, oder Gäste serverseitig auf „privat“ stellen. Das beeinflusst Kosten
   und Antwortqualität.
3. **KI-Kennzeichnung im Reiter AI (R5B-04):** `decisions.md:344` nennt die Herkunft bewusst nur per Langdruck. Für einen App-Store-Start
   empfehle ich eine sichtbare Herkunftszeile.
4. **Rechtliche Bewertung:** WRK-01, WRK-17 und R5B-03 (AI Act Art. 50, Art. 9 DSGVO) brauchen eine Fachperson. Bei rein privater Verteilung ist
   die Lage eine andere als bei einem Store-Start. Ich habe nur die Texte geprüft.
5. **Android:** Wann soll es wieder aufgenommen werden? Drei Blocker betreffen dort Personen unter 18 und mit BMI unter 18,5.

## Annahmen

- Geprüft wurde `main` @ 8baa407; zwischen 8baa407 und dem letzten Audit-Commit hat sich der Produktivcode nicht geändert.
- Schwere nach dem Maßstab im Audit-Auftrag: Blocker = Datenverlust, Sicherheitslücke, Absturz im Kernpfad oder gesundheitlich gefährliche Empfehlung.
- Android-Befunde aus Runde 1 bleiben dokumentiert, wurden aber nicht gegengeprüft.
- Die lokale Arbeitskopie liegt unter `C:\ca\Coach-App`, weil Windows-Pfade im Sitzungsordner zu lang waren.
- Für die Belegtests wurde der Entwurfs-PR #82 angelegt, weil lokal weder Swift, Node noch Java installiert sind. Es liefen nur Linux-Runner, kein macOS, kein `ios-build`-Label.

## Was nicht geprüft werden konnte

Grundsätzlich fehlten ein echtes Gerät, ein Simulator und echte Garmin-Daten. Nachholen lässt sich das über die Liste in `docs/todo.md`
und einen Screenshot-Lauf: Der letzte erfolgreiche Lauf von `screenshots.yml` stammt vom 27.10. (204 Commits alt) und zeigt weder Erfassen noch
aktive Einheit, Widgets oder die Live-Aktivität.

Die folgenden Punkte stammen aus den einzelnen Prüfbereichen.

### iPhone: Heute, Training, Plan, Einstellungen

- Nichts gebaut oder ausgeführt (kein Swift lokal). Die Tests in `tests/ios/ios/CoachTests/AuditIOS1Tests.swift` sind gegen die vorhandenen Signaturen geschrieben (Stil wie `GarminConnectSessionTests`, `TodayViewModelTests`, Suite `StubbedNetworkTests`), aber nicht kompiliert; laufen nur im Simulator (`ios-build.yml`).
- Screenshots sind 204 Commits alt (keine neueren erfolgreichen Läufe des Workflows „Screenshots“); Dark Mode/Dynamic Type des heutigen Stands nur über Code bewertet. Nachholen: Label `screenshots` an einer PR.
- VoiceOver-Reihenfolge, Haptik, Hintergrundabruf, HealthKit im gesperrten Zustand, Garmin-Refresh-Rotation: nur am Gerät (Punkte in `docs/todo.md` ergänzen).
- Kontrastwerte geschätzt aus Systemfarben, nicht gemessen.

### iPhone: Ernährung, Gym, Widgets

- Kein Swift lokal: Die 4 Tests sind nicht kompiliert, Signaturen und Zugriffsmodifikatoren gegen den Code geprüft (`@testable import Coach`). Ausführen: CI `ios-build` per Label bzw. Simulator.
- SwiftUI-Präsentation (IOS2-08), Live-Activity-Größen/Hintergrundstart (IOS2-09/10/11), Kamera-Rechte (IOS2-14), VoiceOver (IOS2-22): nur Gerät/Simulator.
- Widgets unter SideStore (App Group) und Widget-Dunkelmodus (folgt System).
- CoachCore-Rechnungen (Ziel 0, Prozent, Hydration) – Core-Prüfung.

### CoachCore: Ernährung, Gym, Profil

- Ausführung der Tests: kein Swift lokal. Nachholen: Dateien nach `ios/Packages/CoachCore/Tests/CoachCoreTests/`
  kopieren, `swift test --package-path ios/Packages/CoachCore` (CI `swift.yml`, Container `swift:6.2-noble`; die
  Exit-Tests brauchen Swift ≥ 6.2).
- Semantik von GymBook `ZTIME` und Vorzeichen bei „Dips am Barren“ (CORE1-08/19): echtes Backup auslesen.
- Ob die Ernährungs-UI bei Essstörung Kalorienziele ausblendet: in `ios/Coach` kein Bezug auf `HealthFlag` gefunden
  (grep oben); im Simulator gegenprüfen.
- Inhaltliche Richtigkeit der BLS-Zuordnung über alle 7.140 Zeilen: nur Stichproben (Hühnerei, Hafer).

### CoachCore: Coach, Garmin, Health

- **Kompilieren/Ausführen der Tests:** Lokal gibt es kein `swift`. Die APIs habe ich gegen die Quellen geprüft (`@testable import`, interne Memberwise-Inits `WeeklyReport.Totals()`, `InsightAnalysis.Fact`). Die Exit-Tests brauchen Swift 6.2 Testing (`#expect(processExitsWith:)`) und sind auf macOS/Linux begrenzt. Nachholen über die CI `swift.yml` mit den Dateien unter `tests/ios/...`.
- **CORE2-03/07/12/13** liegen im App-Target (`CoachTests`, nur macOS-Simulator). Nachholen mit `URLProtocol`-Stub-Tests.
- **CORE2-08/19:** Bedeutung des Garmin-HRV-Status und Reihenfolge der Readiness-Liste nicht offline belegbar. Nachholen mit dem Garmin-Handbuch und Rohantworten aus `RawResponseRecord` (Diagnose-Ansicht).
- **CORE2-16/17/18:** Für die Belege bräuchte ich echte FIT-Dateien (Smart Recording, Enhanced-Felder) bzw. ein Reise-Szenario.
- Worker-seitige Begrenzung bzw. Grounding (`worker/src/*.ts`) nur gelesen, soweit für CORE2-04 nötig; Details gehören in den Worker-Bericht.

### Worker und Workflows

- Tests nicht ausgeführt (kein node/swift lokal). Nachholen: Dateien nach `worker/test/` bzw. `CoachCoreTests/` kopieren, `npm test` / `swift test`; erwartet: alle neuen Tests rot.
- Ob `REVOKED_GUESTS` heute als Variable oder Secret gesetzt ist (Dashboard): `wrangler secret list` bzw. Dashboard ansehen.
- Groq-Datenrichtlinien und Tageslimits: console.groq.com prüfen.
- Ob Gemini Wiederholungen bei 429 aufs Kontingent anrechnet und die CPU-Grenze (10 ms) bei 8-MB-Bildern: Worker-Logs (CPU-Zeit) auswerten.
- Rechtliche Bewertung (Art. 9, Verantwortlichkeit gegenüber Gästen) durch Fachperson.

### Fachliche Regeln

- **Tests nicht ausgeführt** (lokal kein swift/java). Signaturen sind gegen den Quelltext geprüft (`NutritionSettings`,
  `GarminActivity`-Eigenschaften `var`, `NutritionTargets.profile` public, `GoalRules.bmi` public; Kotlin
  `NutritionSettings(...)` mit benannten Parametern, `Nutrient.KCAL.key`). Nachholen: `swift test --package-path
  ios/Packages/CoachCore --filter AuditSCI` bzw. `./gradlew -PcoreOnly :core:test --tests '*AuditSCI*'`.
- **Garmins HRV-Status-Algorithmus** ist proprietär. Ob er einem 7-Tage-ln-rMSSD-Mittel gegen ±0,5 SD entspricht, ist
  nicht verifizierbar (Garmin-Handbuch beschreibt nur „7-Tage-Schnitt gegen Baseline“).
- **Worker-Prompts** (`worker/src/tasks.ts`) habe ich nicht fachlich geprüft (z. B. ob die KI Mengen für Koffein/Protein
  nennt). Gehört zum Worker-Audit.
- **DGE-Originaltabellen** für Mg/Zn/Vitamin C wurden nur aus dem Gedächtnis gegen den Code abgeglichen (Jod per Web
  bestätigt). Nachholen über dge.de/wissenschaft/referenzwerte.
- **UI-Texte in `WeightViews.swift`** (Fußtext zur Untergrenze) sind nur per Codelesen geprüft, nicht im laufenden Gerät.

### Marktvergleich

- Ob die Funktionen auf dem Gerät tatsächlich so laufen (kein Simulator/Mac; `docs/todo.md` listet offene Gerätetests). Nachholen: Screenshots aus `screenshots.yml` bzw. Gerätetest.
- Apple-Tabelle „Supported capabilities“ war per WebFetch nicht lesbar (Häkchen fehlen) – Aussage zu Push/iCloud stützt sich auf Microsoft-Doku und Apple-Forum; vor Entscheidungen die Seite <https://developer.apple.com/help/account/reference/supported-capabilities-ios> im Browser prüfen.
- Ob ein iCloud-Gerätebackup die Daten einer per SideStore installierten App wiederherstellt – Hypothese, nicht verifizierbar ohne Gerät.
- Viele Wettbewerberbewertungen stammen aus Konkurrenz-Blogs (Nutrola, NutriScan, MyNetDiary, Setgraph) – Tendenz plausibel, Zahlen nicht belastbar.
- Exakter MacroFactor-Algorithmus (Glättung, Check-in-Regel) ist nicht öffentlich ([MacroFactor](https://macrofactor.com/algorithm-accuracy/)).

### Neuling und ohne Garmin

- Echte Darstellung (Farben, Reihenfolge der Systemdialoge, leerer Erfahrungsschritt): ohne Mac/Simulator nicht
  ausführbar. Nachholen: Screenshot-Workflow mit Szene „Neuinstallation ohne Tracker“ und „nur Apple Health (Schritte)“.
- Fehlschlagende Tests: keine geschrieben. R2A-01 sitzt im App-Ziel (`TodayViewModel`, nur Simulator-Tests). Ein
  CoachCore-Test geht erst, wenn die vorgeschlagene Funktion `RecoveryEvaluator.hasInputs` existiert.

**Anzahl NEUER Befunde: 9** (Hoch 1, Mittel 5, Niedrig 3). **Anzahl NEUER Ideen: 6** (R2A-I1 bis I6; I7 ist ein Duplikat).

### Power-User

- Tatsächliche Ruckler/Speicher bei einem Jahr Daten (R2B-01): braucht Gerät/Instruments oder Idee R2B-I3.
- SideStore-Ablauf (7 Tage) und Neusignieren: laut Code bleiben App-Container, Keychain (`AfterFirstUnlockThisDeviceOnly`, `SecretStore.swift:59`) und App Group erhalten, solange dieselbe Apple-ID/Team-ID signiert. Beim Wechsel der Apple-ID ändert SideStore die Bundle-ID → neue App ohne Daten (dann greift MKT-Lücke 1 „Sicherung“). Ohne Gerät nicht verifizierbar.
- Live-Aktivität nach App-Update während laufender Einheit: Gerätetest nötig.
- Speicher-voll-Verhalten von SwiftData (R2B-04): Fehlerweg im Code eindeutig, Laufzeitverhalten Hypothese.
- Mitteilungen erst verweigert, später erlaubt: **geprüft ohne Befund** (`ReminderService.swift:76-87` liest den Status bei jeder Aktualisierung, `CoachApp.swift:35` beim Aktivwerden).
- Widget-Speicherlimit: Snapshot ist klein (`WidgetPublisher.swift:121-123`, nur Tageswerte) – kein Risiko gefunden.

**Neu: 10 Befunde (Mittel 5, Niedrig 5), 6 Ideen. Testdatei: 1.**

### Sehbehinderung und offline

- Tatsächliche VoiceOver-Ausgabe der automatischen Chart-Elemente und SF-Symbol-Beschreibungen (R2C-02, R2C-09): nur am Gerät/Simulator mit Accessibility Inspector.
- Live-Aktivität bei AX-Schrift (R2C-14) und Kartenkacheln offline (R2C-13): Gerätetest.
- Kontrastwerte sind aus den Standard-Systemfarben (hell) berechnet, nicht gemessen.
- Funkloch-Verhalten (R2C-11): Network Link Conditioner auf dem iPhone (Entwickler-Einstellungen) – ohne Mac nur über ein per SideStore installiertes Gerät mit aktivierten Entwickleroptionen.
- Android wurde auf Wunsch des Nutzers in dieser Runde nicht bewertet.

**Anzahl NEUER Befunde: 15** (Mittel 5: R2C-01, -02, -03, -04, -11; Niedrig 10; kein Blocker/Hoch). **Anzahl NEUER Ideen: 10.**

### Profilmodi und Profi-Coach

- Tests nicht ausgeführt (lokal kein `swift`). Signaturen gegen den Quelltext geprüft: `WeekSchedule.set` und
  `templateItems` public, `NutritionPlanner.plannedDayType`/`compute` public, `DayType: Comparable`, `Weekday(day:)`
  public, `NutritionTargets.Source.planned`. 03.11.2026 ist ein Dienstag. Nachholen:
  `swift test --package-path ios/Packages/CoachCore --filter AuditR2D`.
- Zahlen in R2D-01 per Handrechnung (Formel `NutritionTargets.swift:287-375`); Rundung kann ±10 kcal abweichen,
  ändert die Aussage nicht.
- R2D-04: SwiftUI-Lebenszyklus (wann `GymView.update()` zum ersten Mal läuft) nicht im Gerät geprüft.
- R2D-02: Wie stark die KI dem „Ziel: Abnehmen“ folgt, nicht live geprüft (Worker nicht aufgerufen).
- PMIDs für Schwellnus 2016 und Flint 2000 mehrdeutig; Thomas 2016 als Positionspapier ohne eindeutige PMID im
  Lookup. Nachholen per PubMed-Suche mit Titel.

**Anzahl neuer Befunde: 10** (Hoch 2, Mittel 6, Niedrig 2). **Anzahl neuer Ideen: 13.**
Testdatei: `tests/ios/ios/Packages/CoachCore/Tests/CoachCoreTests/AuditR2DPlannedDayTests.swift`.

### Nur Ernährung und 65+

- Tests nicht ausgeführt (kein `swift` lokal). Signaturen gegen den Quelltext geprüft: `OpenFoodFacts.product(from:barcode:)`,
  `Product.item()`, `Hydration.total`, `HeartRateZoneCalculator.observedMax` sind public; `GarminActivity(id:)` mit
  `var typeKey/startLocal/maxHeartRate/durationSeconds` (Muster wie `MetricsAndZonesTests.swift:12-20`). Ausführen: Datei
  nach `ios/Packages/CoachCore/Tests/CoachCoreTests/` kopieren, `swift test --package-path ios/Packages/CoachCore --filter AuditR3A`.
- R3A-03/04/05 liegen im App-Target (SwiftUI-Ablauf); nur am Gerät/Simulator nachstellbar.
- Ob Open Food Facts für jedes Getränk `categories_tags` mit `en:beverages` liefert, nicht stichprobenartig geprüft
  (kein Netzabruf); Rückfall über `serving_quantity_unit == "ml"` empfohlen.
- Wie Betablocker Garmins HRV-Status beeinflussen, ist proprietär; R3A-06 stützt sich auf die allgemeine Physiologie.

### Datenschutz und Release

- Ob Widget-Erweiterungen unter SideStore zum **3-App-Limit** zählen: AltStore-FAQ nennt nur App-IDs je Erweiterung (<https://faq.altstore.io/altstore-classic/app-ids>), Blogs widersprechen sich. Gerätetest: SideStore + IronLudi + eine dritte App installieren.
- Ob das **Data-Protection-Entitlement** für die Widget-Erweiterung (R3B-07) mit kostenloser Apple-ID signiert wird – SideStore-Quelltext (`Feature.swift`) prüfen bzw. Gerätetest.
- Ob lokale Mitteilungen nach Ablauf des Profils noch zugestellt werden (R3B-I1): Gerätetest mit abgelaufenem Profil.
- Tatsächlicher SwiftData-Pfad auf dem Gerät (R3B-01): Diagnoseanzeige nachrüsten oder `container.configurations.first?.url` im Simulator-UI-Test ausgeben.
- iCloud-Gerätebackup enthält die SwiftData-Datei (kein `isExcludedFromBackup`); ohne Advanced Data Protection nicht Ende-zu-Ende-verschlüsselt – bewusst offen gelassen, weil es mangels eigener Sicherung (MKT-Lücke 1) derzeit der einzige Wiederherstellungsweg ist.

**Neu: 8 Befunde (Mittel 5, Niedrig 3), 3 Ideen. Testdateien: keine** (R3B-01…08 betreffen App-Konfiguration, Workflow und Gerätverhalten; kein CoachCore-Unit-Test kann sie sinnvoll rot zeigen).

### Systemintegration

- Verhalten am Gerät (kein Mac/Simulator): Ob WidgetKit nach dem Mitternachts-Eintrag tatsächlich zeitnah neu lädt,
  wie oft `BGAppRefresh` nachts läuft (bestimmt die Dauer von R3C-02/03) und ob SideStore die App Group für die
  Erweiterung anlegt. Nachholen: Gerätetest aus `docs/todo.md` (Widgets) mit Uhrzeit-Protokoll im Snapshot
  (`createdAt` im Widget klein anzeigen).
- Siri-Erkennung der deutschen Phrasen und Verhalten der Aktionstaste: nur am Gerät mit deutscher Siri prüfbar.
- 8-Stunden-Grenze der Live-Aktivität: Code beendet sie nur über `GymView.onChange` (`GymView.swift:128-131`); nach
  `runningHours` (5 h) ändert sich `liveState` ohne Ereignis nicht – ob iOS sie vorher entfernt, ist nur am Gerät
  zu sehen (Teilaspekt von IOS2-11, daher nicht gezählt).

**Neu: 8 Befunde (Mittel 3, Niedrig 5), 6 Ideen.** Testdatei:
`tests/ios/Packages/CoachCore/Tests/CoachCoreTests/AuditR3CTests.swift` (2 fehlschlagende Tests: R3C-02, R3C-06).

### Plan und Abgleich

- Tests nicht ausgeführt (kein `swift` lokal). Signaturen gegen den Quelltext geprüft (`UserProfile.init`-Reihenfolge,
  `SessionMatcher.match(gymDays: Set)`, `ScheduleAdvisor.advice` mit Standard-`schedule`, `TodayFocus.personal`,
  `ManualActivity.make`). Nachholen: `swift test --filter AuditR4APlanTests` im CI (macOS-Runner).
- R4A-07: Dass SwiftData beim Einfügen mit gleichem `.unique`-Wert ersetzt (Upsert) statt zu scheitern, ist
  dokumentiertes Verhalten; ob der Nutzer den Verlust bemerkt, nur am Gerät.
- R4A-08: Darstellung im Plan-Reiter mit verschobenem Datum nur am Gerät/Simulator; Logik per Code belegt.

**Ergebnis: 10 neue Befunde (1 Hoch, 7 Mittel, 2 Niedrig), 1 neue Idee.**
Testdatei: `tests/ios/Packages/CoachCore/Tests/CoachCoreTests/AuditR4APlanTests.swift` (9 Tests zu R4A-01 bis R4A-07).

### Analyse und Sync

- Kompilieren/Ausführen: lokal kein `swift`; Signaturen gegen die Quellen geprüft (`GarminActivity(id:)`, `typeKey`/`minElevation` öffentlich, `FitRecord`/`FitActivity`-Init, `CoachingNote.evidenceInput`, `ChatContext.evidence`, `UserSources.inject`). Nachholen über CI `swift.yml`.
- R4B-01/02/04/10 liegen im App-Target bzw. hängen von Garmin/AlarmKit/HealthKit auf dem Gerät ab; Nachweis per `URLProtocol`-Stub bzw. Gerätetest.
- Ob Garmin bei Zeitüberschreitung den ersten PUT schon übernimmt (R4B-02), ist ohne Mitschnitt nicht belegbar.

### Zyklus und Schichtarbeit

- Wie Garmin Tagschlaf nach Nachtschicht als Hauptschlaf erkennt und welchem `calendarDate` er zugeordnet wird
  (betrifft Garmin-Nutzer:innen; R5A-01 gilt nur für Apple Health). Nachholen: Garmin-Export einer Person mit
  Nachtschicht ansehen.
- Wie fein die Apple Watch Schlafphasen tatsächlich stückelt (für R5A-01 entscheidend: ab der ersten Phase, die
  nach 10 Uhr beginnt, fehlt der Rest). Nachholen: HealthKit-Export (`export.xml`, `HKCategoryTypeIdentifierSleepAnalysis`).
- Größe der zyklischen Gewichtsschwankung je Person (R5A-02 rechnet mit ±0,5 kg als Annahme).
- Ob die Lutealphase die Tagesampel tatsächlich auf „locker“ kippt (Ruhepuls-Regel +5 bpm, MorningReport ≥ 2 Signale):
  Hypothese, ohne echte Zyklus- und Messdaten nicht belegbar – deshalb nur als Idee (R5A-I3), nicht als Befund.

### Mikrotexte und KI-Fallback

- Tippfehler: nur Mustersuche und Sichtung seltener Wörter, keine Rechtschreibprüfung (kein Werkzeug lokal). Nachholen: Strings exportieren und durch ein Korrekturprogramm laufen lassen.
- Worker-Tests nicht ausgeführt (kein node lokal). Nachholen: Datei nach `worker/test/` kopieren, `npm test`; beide Tests müssen rot sein.
- Wie oft ein Modell der Ampel tatsächlich widerspricht: braucht echte Läufe (z. B. 50 × `daily_note` mit Stufe `pause`).
- Darstellung (Zeilenumbruch, Abschneiden langer Texte): ohne Gerät nicht geprüft; siehe R2C-05.
- Rechtslage Art. 50: Fachperson; Stand der Übergangsfrist im Amtsblatt prüfen.
