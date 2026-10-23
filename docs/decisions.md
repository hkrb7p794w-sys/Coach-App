# Entscheidungen

Jede Entscheidung mit Datum, Begründung und Quelle. Neueste oben.

## 2026-10-23 – Backend auf dem Windows-Mini-PC statt Raspberry Pi

Der Pi trägt Home Assistant; ein zusätzlicher Dienst würde HA ausbremsen. Der Mini-PC (Windows) übernimmt.
Empfohlen: Python direkt unter Windows (uv), Start über die Aufgabenplanung „beim Systemstart, unabhängig
von der Anmeldung“. Docker Desktop startet erst nach einer Benutzeranmeldung und braucht deutlich mehr RAM.
Ein Dockerfile bleibt für andere Rechner. Offen: Betriebszeiten des Mini-PCs (läuft bisher nur morgens).

## 2026-10-23 – Garmin-Abruf im Backend, nicht direkt vom iPhone

Geprüft: python-garminconnect 0.3.19 meldet sich über `sso.garmin.com/mobile/api/login` mit der
iOS-Client-ID `GCM_IOS_DARK` an, tauscht das Service-Ticket bei `diauth.garmin.com` gegen ein
OAuth2-Token und ruft `connectapi.garmin.com` auf (`garminconnect/client/sso.py`, `session.py`,
`constants.py`). Ein Swift-Nachbau wäre machbar, aber:

- Für die KI ist ohnehin ein Server nötig (Keys nie in der App).
- Der Login ist inoffiziell und ändert sich (zuletzt März 2026); die Python-Bibliothek wird gepflegt,
  ein eigener Swift-Port müsste von uns nachgezogen werden.
- Abrufe nur bei geöffneter App; Hintergrundaktualisierung ist unzuverlässig, Push gibt es mit
  kostenloser Apple-ID nicht.

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
  Garmin liefert Workouts, Schlaf und Herzfrequenz über das Backend; Krafttrainings werden lokal
  und optional bei Garmin gespeichert. Mit bezahltem Account und TestFlight geht HealthKit ohne Umbau.
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
