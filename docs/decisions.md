# Entscheidungen

Jede Entscheidung mit Datum, Begründung und Quelle. Neueste oben.

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
