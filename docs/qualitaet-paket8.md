# Paket 8 – Qualitätskontrolle, Multi-User und Skalierung

Stand 02.11.2026 (`main` nach PR 76 plus diese PR). Grundlage sind das Lesen des Codes und die Prüfungen, die
tatsächlich gelaufen sind (Abschnitt 3). Was nur auf dem iPhone prüfbar ist, ist als **offen** markiert und nicht
als bestanden gezählt.

## Kurzfassung

- **Kritischer Fund, behoben:** Der Einladungslink der Rangliste enthielt das **Haupt-Token des Workers**. Wer ihn
  bekam (z. B. weitergeleitet per Messenger), hatte vollen Zugriff: KI auf Kosten der Kontingente, alle Ranglisten
  und geteilten Mahlzeiten, und über das Token auch die private SideStore-Quelle. Ein Zugriff ließ sich nicht
  einzeln entziehen. Jetzt stellt der Worker je Einladung ein eigenes **Gast-Token** aus, das sich einzeln sperren
  lässt. **Bereits verschickte Links enthalten weiterhin das Haupt-Token** – siehe „Notwendige Schritte“.
- **Fehler bei der Datentrennung, behoben:** Jede Person mit Zugang konnte fremde Ranglisten-Einträge
  überschreiben oder löschen und fremde geteilte Mahlzeiten zurückziehen. Einträge gehören jetzt dem Token, das
  sie angelegt hat.
- **Datenverlust-Risiko, entschärft:** Ließ sich der Datenspeicher nicht öffnen (z. B. nach einer misslungenen
  Migration), lief die App still nur im Arbeitsspeicher weiter; dort erfasste Mahlzeiten und Gym-Einheiten
  wären beim Beenden verloren gegangen. Jetzt erscheint ein deutlicher Warnhinweis. Die Datei selbst wurde schon
  vorher nicht angetastet.
- **Multi-User:** Die App ist bewusst **eine Person je iPhone**, ohne Benutzerkonten. Die Trennung der
  Gesundheits-, Trainings- und Ernährungsdaten ergibt sich daraus, dass sie das iPhone nie verlassen (außer
  gezielt an die KI). Für echte Konten fehlt eine Benutzerverwaltung – das ist ein Architekturschritt, der unten
  vorgeschlagen, aber nicht umgesetzt ist.
- **Skalierung:** Für die heutige Nutzung (Familie/Freunde, ein Worker) ausreichend. Engpässe sind die
  kostenlosen Kontingente (Workers KV: 1.000 Schreib- und 1.000 List-Zugriffe am Tag; KI-Anbieter) und eine
  fehlende Begrenzung je Person.

## 1. Multi-User und Skalierbarkeit

### 1.1 Ist-Architektur

| Baustein | Wo die Daten liegen | Wer darauf zugreift |
|---|---|---|
| Profil, Ziele, Einstellungen | `UserDefaults` auf dem iPhone (`CoachSettings`) | nur die App |
| Garmin-, Health-, Trainings-, Ernährungs-, Gym-Daten | SwiftData-Datei auf dem iPhone (`CoachSchema`) | nur die App; Widgets lesen eine Kurzfassung aus der App Group |
| Garmin-Zugang, Worker-Token | Keychain, `AfterFirstUnlockThisDeviceOnly` (nicht in Backups/anderen Geräten) | nur die App |
| KI | Cloudflare Worker, leitet an Gemini/Groq/Workers AI weiter; speichert nichts | App mit gültigem Token |
| Rangliste | Workers KV `LEAGUE`, Schlüssel `league:<code>:<mitglied>`: Name, Symbol, Punkte | alle mit Token und Code |
| Geteilte Mahlzeiten | Workers KV `LEAGUE`, `share:<code>`, 7 Tage | alle mit Token und Code |
| App-Verteilung | Workers KV `RELEASES`, Pfad aus dem Haupt-Token abgeleitet | wer den Pfad kennt |

Garmin wird von jedem iPhone direkt abgerufen; es gibt keinen Server, der Daten mehrerer Personen sammelt.

### 1.2 Benutzerverwaltung

| Frage | Befund |
|---|---|
| Eigene Konten für mehrere Personen? | **Nein.** Jede Person hat ihre eigene Installation mit eigenem Profil und Garmin-Konto. Ein iPhone = eine Person. |
| Sichere Authentifizierung? | Am Worker: Bearer-Token, Vergleich in konstanter Zeit, nur HTTPS. **Neu:** Haupt-Token (Betreiber:in) und Gast-Tokens (`g1.<id>.<HMAC>`, `worker/src/auth.ts`) – Gäste sind unterscheidbar und einzeln sperrbar (`REVOKED_GUESTS`). Keine Passwörter, kein Login. |
| Daten eindeutig einer Person zugeordnet? | Auf dem iPhone ja (nur eine Person). Im Worker **bisher nicht**: Alle teilten ein Token. **Neu:** Ranglisten-Einträge und geteilte Mahlzeiten speichern den Besitzer (`owner` = `owner` bzw. `guest:<id>`). |
| Einstellungen und Ziele getrennt? | Ja, je Installation. Zwei Personen auf **einem** iPhone sind nicht vorgesehen. |

### 1.3 Datentrennung und Datenschutz

| Frage | Befund |
|---|---|
| Trainings-, Gesundheits-, Ernährungsdaten nutzerspezifisch? | Ja – sie liegen nur auf dem eigenen iPhone. An den Worker gehen sie nur für KI-Aufgaben, im Standard „reduziert“ (`AIPolicy`, `PrivacyMode`); der Worker speichert sie nicht. |
| Nur Zugriff auf eigene Daten? | Für die iPhone-Daten ja (iOS-Sandbox). Für Worker-Daten: **vorher nein** (siehe 1.2), **jetzt** Schreiben/Löschen nur für den Besitzer. Lesen einer Rangliste oder Mahlzeit bleibt für alle mit Token **und** Code möglich – das ist der Zweck des Codes (rund 50 Bit Zufall). |
| Datenbankzugriffe abgesichert? | SwiftData nur lokal. KV nur über den Worker, Eingaben werden geprüft und gekürzt (`parseEntry`, `sanitizeMeal`), Größen begrenzt. |
| API-Endpunkte geschützt? | Alle `/v1/…` außer `/v1/health` verlangen ein Token. `/v1/health` verrät nur Version und welche KI-Anbieter eingerichtet sind (kein Geheimnis, aber eine Information). `/m/<code>` ist bewusst offen und enthält keinen Inhalt. `/sidestore/<key>/…` ist durch den geheimen Pfad geschützt. |
| Berechtigungen verwaltet? | **Neu:** zwei Rollen. Haupt-Token: alles, Einladungen ausstellen (`POST /v1/invite`), SideStore-Quelle. Gast: KI, Rangliste, Mahlzeiten teilen; keine Einladungen, keine SideStore-Quelle. Feinere Freigaben (z. B. „nur diese Person sieht meine Mahlzeit“) gibt es nicht. |

### 1.4 Gemeinsame Funktionen

| Funktion | Eignung |
|---|---|
| Mahlzeiten teilen | **Vorhanden** (Code-Link, 7 Tage, nur die Mahlzeit, keine Gesundheitsdaten). Jetzt mit Besitzer beim Zurückziehen. |
| Trainingspläne teilen | **Machbar ohne Umbau** nach demselben Muster wie Mahlzeiten: `POST /v1/share/routine` mit geprüften Feldern (Übungs-IDs, Sätze, Wiederholungen), Code-Link, Ablaufzeit. Die Routinen sind schon `Codable` in CoachCore. |
| Einander folgen, vernetzen | **Nicht vorhanden.** Die Rangliste ist die einzige Verbindung (Name + Punkte). „Folgen“ braucht dauerhafte Identitäten – die Gast-ID ist dafür die Grundlage, reicht aber allein nicht (kein Profil, keine Freundesliste). |
| Freigaben einzeln steuern | **Nicht vorhanden.** Heute gilt: Wer den Code hat, sieht den Inhalt. Für „nur für Person X“ müsste der Worker Empfänger-IDs prüfen – mit Gast-IDs möglich, siehe Empfehlung E3. |

### 1.5 Technische Skalierbarkeit

| Bereich | Befund | Engpass ab |
|---|---|---|
| Datenbank auf dem iPhone | SwiftData mit eindeutigen Schlüsseln (`dayKey`, `garminID`, `id`), wächst nur mit den eigenen Daten. | kein Engpass durch mehr Personen |
| Workers KV (kostenlos) | 100.000 Lesezugriffe, **1.000 Schreib-**, 1.000 Lösch- und **1.000 List-Zugriffe am Tag**, 1 Schreibzugriff je Schlüssel und Sekunde; Änderungen sind bis zu ~60 s verzögert sichtbar. Ein Ranglisten-Abgleich kostet 1 Schreib- und 2 List-Zugriffe. | rund 500 Ranglisten-Abgleiche am Tag über **alle** Personen; danach schlagen sie bis 0 Uhr UTC fehl |
| Rangliste | höchstens 20 Mitglieder je Code, alles in den Metadaten (eine List-Abfrage) | bewusst klein |
| Worker (kostenlos) | 100.000 Anfragen am Tag | weit weg |
| KI | kostenlose Kontingente von Gemini, Groq und Workers AI (10.000 Neurons/Tag) mit Ausweichen auf den nächsten Anbieter; **keine Begrenzung je Person** | eine Person mit vielen Anfragen kann das Kontingent für alle aufbrauchen |
| Garmin | jedes iPhone ruft selbst ab (offizielle Personal API bzw. eigener Login) | skaliert mit, je Person eigene Limits |
| Hintergrund | `BGAppRefreshTask` je iPhone, iOS bestimmt den Zeitpunkt | skaliert mit |
| Verteilung | SideStore mit kostenloser Apple-ID: 3 Apps, 7 Tage Gültigkeit, je Person eigene Apple-ID | organisatorisch, nicht technisch |

Quellen: Workers-KV-Preise und -Limits <https://developers.cloudflare.com/kv/platform/pricing/>,
<https://developers.cloudflare.com/kv/platform/limits/> (Stand 30.10.2026).

### 1.6 Verbesserungsvorschläge (Architektur, nicht umgesetzt)

| # | Vorschlag | Begründung | Aufwand / Risiko |
|---|---|---|---|
| E1 | **Begrenzung je Person** im Worker (Cloudflare Rate Limiting Binding oder Zähler je Gast-ID und Tag) | verhindert, dass eine Person das KI-Kontingent für alle verbraucht; mit Gast-IDs jetzt erstmals möglich | klein, gering |
| E2 | **Sicherung und Wiederherstellung** der lokalen Daten (Export als Datei in „Dateien“/iCloud Drive, Import) | Mahlzeiten und Gym-Einheiten liegen nur auf dem iPhone; App löschen oder iPhone verlieren = weg. Garmin-Werte kommen wieder, diese nicht. | mittel, gering |
| E3 | **Freigaben an Personen** (Empfänger-Gast-IDs beim Teilen, „Folgen“ als Liste im KV) | Grundlage für gemeinsame Pläne und Vernetzung | mittel |
| E4 | **Versioniertes SwiftData-Schema** (`VersionedSchema` + `SchemaMigrationPlan`) vor der nächsten nicht-trivialen Modelländerung | heute nur automatische (leichte) Migration; eine schwere Änderung würde den Speicher nicht öffnen (jetzt mit Warnung statt still) | klein, muss vor der Modelländerung kommen |
| E5 | Für echte Konten mit vielen Personen: **Benutzerkonten mit Anmeldung** (z. B. „Mit Apple anmelden“) und serverseitige Daten in D1 mit Besitzer-Spalte | nur nötig, wenn Daten geräteübergreifend oder für Fremde bereitstehen sollen; widerspricht heute „ohne eigenen Server, Daten bleiben auf dem iPhone“ | groß – **nicht ohne Auftrag** |

Empfehlung: E1, E2 und E4 als nächste Schritte; E3, wenn Trainingspläne geteilt werden sollen; E5 nur bei einer
bewussten Entscheidung für einen Dienst mit vielen fremden Personen.

## 2. Funktionalität (Paket 7 und seither)

| Anforderung | Stand |
|---|---|
| Schnellaktionen am App-Icon (Training starten, Mahlzeit erfassen, Health, KI-Analyse) | vollständig umgesetzt (PR 73), Gerätetest offen |
| App Shortcuts/Siri | vollständig umgesetzt (PR 73), Gerätetest offen |
| Navigation per Route, kompatibel mit bestehender Navigation | vollständig umgesetzt (PR 73), Tests in CoachCore |
| Homescreen-Widgets Heute, Gym, Ernährung, Health, konfigurierbar | vollständig umgesetzt (PR 74), Gerätetest offen (App Group unter SideStore) |
| Interaktive Widgets | teilweise: „+250 ml Wasser“. „Satz erledigt“ gibt es auf dem Sperrbildschirm (Live-Aktivität). Mehr ist möglich, aber nicht umgesetzt. |
| Kontrollzentrum/Aktionstaste (Paket 7 C) | noch nicht umgesetzt (bewusst nach dem Gerätetest der Widgets) |
| Android-Analyse mit Empfehlung | vollständig (Doku); Android-App bewusst nicht begonnen |
| Widgets im App-Dunkelmodus | technisch nicht realisierbar: WidgetKit folgt immer dem System |
| iOS-Deployment-Target dokumentiert | vollständig (iOS 18.0, `docs/plattform-paket7.md`) |
| Garmin-Übungsnamen statt „Unbekannt“ | umgesetzt (PR 75), Gerätetest offen |
| Dunkelmodus wählbar | umgesetzt (PR 76), Gerätetest offen. **Die Version ist noch nicht ausgeliefert:** Der Build auf `main` nach PR 76 wurde abgebrochen, weil GitHub keinen macOS-Runner zuteilte („not acquired by Runner“). Der Build nach dieser PR liefert den Dunkelmodus mit aus. |

## 3. Regressionstests – was wirklich gelaufen ist

| Prüfung | Wo | Ergebnis |
|---|---|---|
| Worker: Lint (Biome), Typprüfung, 93 Tests (16 Dateien, davon neu `auth.test.ts` und Besitzer-Tests in `league`/`share`) | lokal in dieser Sitzung | **bestanden** |
| CoachCore: `swift format lint`, rund 500 Tests (Linux) | CI `lint-test` dieser PR | siehe PR (Swift ist in dieser Sitzung nicht installiert, lokal **nicht** gelaufen) |
| App-Tests im Simulator (`CoachTests`, u. a. Rangliste mit Gast-Token) und Release-Build | CI `ios-build` dieser PR | siehe PR |
| Musterpersonen-Bericht (Schutzregeln Energie, Protein, Ruhetage …) | CI | zuletzt bei PR 76: alle Schutzregeln eingehalten |
| Gerätetests (`docs/todo.md`) | iPhone | **offen: 36 Prüfpunkte, keiner von mir durchführbar** |

Bereiche aus dem Auftrag und womit sie abgedeckt sind:

| Bereich | automatisch geprüft | nur am Gerät prüfbar |
|---|---|---|
| Trainingsaufzeichnung (Gym) | `GymFlowTests`, `GymViewModelTests`, Live-Aktivität-Logik | Sperrbildschirm, Haptik |
| Garmin-Synchronisierung | Parser, Endpunkte, `GarminStrengthSyncTests`, keine Doppelten | echte Konten, Übungsnamen in Connect |
| Datenbankzugriffe | eindeutige Schlüssel, ViewModel-Tests mit In-Memory-Speicher | Migration einer echten Datei |
| Health-Daten | `BodyBatteryTests`, Morning-Report-Tests | HealthKit-Rechte unter SideStore |
| KI-Analysen | Worker-Tests (Anbieterwechsel, JSON, Grounding), `AIPolicyTests` | Qualität der Texte |
| Ernährungstagebuch | `NutritionViewModelTests`, BLS-, Rezept-, Teilen-Tests | Kamera, Diktat |
| Navigation | `AppRouteTests` | Schnellaktionen, Widgets-Tipps |
| Einstellungen | `PersonalizationAppTests`, `AppAppearanceTests` | Dunkelmodus in allen Ansichten |

## 4. Datenqualität

| Prüfpunkt | Befund |
|---|---|
| Doppelte Datensätze | Garmin-Aktivitäten eindeutig über `garminID`, Tageswerte über `dayKey`, Quellen über `key`; Gym-Einheiten und Garmin-Kraft werden zusammengeführt (Tests „keine Doppelten“). Wasser aus dem Widget wird über eine Warteschlange genau einmal übernommen (`WidgetActionQueue`, Tests). |
| Inkonsistente Daten | Datenquellen mit Vorrang und Herkunft (`DataSourceTests`). Rangliste: Wochenpunkte alter Wochen zählen 0. |
| Fehlerhafte Berechnungen | Regeln in CoachCore mit Tests; Schutzgrenzen (REDs, ±1 %/Woche, Protein, Fett) im Musterpersonen-Bericht. |
| Datenverlust | **Fund:** stiller Wechsel in den Arbeitsspeicher, wenn die Datei nicht öffnet – jetzt mit Warnung (Abschnitt Kurzfassung). **Offen:** kein Backup der lokalen Daten (E2). |
| Falsche Zuordnungen | Garmin-Übungen: eigene Übungen landeten als „Unbekannt“ – behoben in PR 75. |
| Datenbankmigrationen | nur automatische leichte Migration, kein versioniertes Schema (E4). Bisherige Änderungen waren additive Felder mit Standardwert. |
| Trennung von Nutzerdaten | Auf dem iPhone durch das Ein-Personen-Modell gegeben. Im Worker **Fund behoben** (Besitzer je Eintrag). |

## 5. UX und Design (geänderte Bereiche)

| Prüfpunkt | Befund |
|---|---|
| Einladung | Vorher sofort teilbar, jetzt ein Tipp mehr („Einladungslink erstellen“ → „teilen“). Bewusst: Jeder Link ist ein eigener Zugang. Gäste sehen den Hinweis, den Code weiterzugeben. |
| Dunkelmodus | Systemfarben überall; Auswahl unter Einstellungen › Darstellung. Daisy behält ihren hellen Kreis (gewollt). |
| Widgets | Platzhalter bei fehlenden Daten, „veraltet“-Hinweis bei Health-Werten; unbestätigt am Gerät. |
| Fehlerzustände | Einladung: Fehlertext unter dem Knopf. Speicherfehler: Warnleiste oben. |
| Unklare Zustände | `/v1/health` zeigt im Worker, ob das Token gesetzt ist; die App meldet 401 als „nicht autorisiert“. Ein gesperrter Gast sieht dasselbe – eine eigene Meldung „Zugang entzogen“ gibt es nicht. |

## 6. Technische Qualität und Sicherheit

| Thema | Befund |
|---|---|
| Authentifizierung | siehe 1.2; HMAC-Gast-Tokens ohne Speicher, Vergleich in konstanter Zeit. |
| Autorisierung | zwei Rollen, Besitzer je Eintrag; Einladen nur mit Haupt-Token. |
| Geheimnisse | KI-Keys nur als Worker-Secrets; Tokens nur im Keychain (`ThisDeviceOnly`); keine Secrets im Repo. |
| Weitergabe des Haupt-Tokens | **behoben** für neue Einladungen. „SideStore-Quelle teilen“ gibt weiterhin einen aus dem Haupt-Token abgeleiteten Pfad weiter: Er erlaubt nur das Laden der App, nicht den Zugriff auf KI oder Daten (SHA-256, nicht umkehrbar). |
| Eingaben | Worker kürzt und prüft alle Felder, begrenzt Größe (8 MB KI, 24 KB Mahlzeit), Bildtypen, Zahl der Bilder. |
| Fehlerbehandlung | Worker: 4xx mit deutscher Meldung, 5xx ohne Interna. App: Fehler im UI statt Absturz; Speicherfehler jetzt sichtbar. |
| Protokolle | Worker protokolliert nur Fehlermeldungen der Anbieter, keine Prompts oder Gesundheitswerte. |
| Hintergrund | Abruf über `BGAppRefreshTask`, Widgets mit Mitternachts-Eintrag; kein Dauerbetrieb. |
| Wartbarkeit | Logik in CoachCore mit rund 500 Tests; Worker 93 Tests; Entscheidungen mit Quelle in `docs/decisions.md`. |
| Rest-Risiken | (1) bereits verschickte Einladungen mit Haupt-Token, (2) keine Begrenzung je Person (E1), (3) kein Backup (E2), (4) Gerätetests offen. |

## 7. Abschluss

**Erfolgreich umgesetzt:** Paket 7 A und B, Garmin-Übungsnamen, Dunkelmodus; in dieser PR Gast-Tokens, Besitzer
für Ranglisten-Einträge und geteilte Mahlzeiten, Warnung bei nicht lesbarem Speicher.

**Nicht bestandene Tests:** keine der ausgeführten. Nicht ausgeführt: alle 36 Gerätetests.

**Offene Anforderungen:** Paket 7 C (Kontrollzentrum), weitere interaktive Widgets, Teilen von Trainingsplänen,
Folgen/Vernetzen, Freigaben an einzelne Personen, Benutzerkonten.

### Notwendige Schritte für dich

1. **Falls du schon Einladungslinks verschickt hast:** Haupt-Token wechseln. Sonst haben die Empfänger weiter
   vollen Zugriff. Neues Token als GitHub-Secret `COACH_APP_TOKEN` setzen → der nächste Merge stellt den Worker
   neu bereit → in der App unter Einstellungen › KI-Worker das neue Token eintragen → **die SideStore-Quelle
   ändert sich mit** (neuen Link aus den Einstellungen in SideStore hinzufügen, alten entfernen) → Freund:innen
   neu einladen. Hast du keine Links verschickt, ist nichts zu tun.
2. Einen Gast sperren: seine ID (Antwort von `/v1/invite`, steht nicht in der App) in die Worker-Variable
   `REVOKED_GUESTS` eintragen. Einfacher bei wenigen Personen: wie in 1. das Haupt-Token wechseln.
3. Gerätetests aus `docs/todo.md`, zuerst Widgets (App Group) und die neue Einladung.

**Bewertung Multi-User-Fähigkeit:** geeignet für mehrere Personen mit **je eigener** Installation, die einen
Worker gemeinsam nutzen (Familie, Freundeskreis). Nicht geeignet als Dienst mit Konten für Fremde: keine
Anmeldung, keine serverseitigen Nutzerdaten, keine feinen Freigaben. Die Datentrennung ist durch „Daten bleiben
auf dem iPhone“ stark; die gemeinsamen Funktionen im Worker sind jetzt nach Besitzer getrennt.

**Bewertung Skalierbarkeit:** Gesundheits- und Trainingsdaten skalieren ohne Grenze mit (alles auf dem
jeweiligen iPhone). Gemeinsame Funktionen tragen im kostenlosen Cloudflare-Plan einige Dutzend aktive Personen;
der erste Engpass sind die 1.000 KV-Schreib- und List-Zugriffe am Tag, der zweite die KI-Kontingente ohne
Begrenzung je Person. Mit dem bezahlten Workers-Plan (5 US-$/Monat) entfallen die KV-Tagesgrenzen.

**Empfehlung für die nächste Phase:** (1) E1 Begrenzung je Gast, (2) E2 Sicherung/Wiederherstellung,
(3) E4 versioniertes Schema, (4) Gerätetests und danach Paket 7 C, (5) Trainingspläne teilen nach dem
Mahlzeiten-Muster mit Besitzer und Ablaufzeit.
