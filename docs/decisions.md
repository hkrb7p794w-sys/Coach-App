# Entscheidungen

Jede Entscheidung mit Datum, Begründung und Quelle. Neueste oben.

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
