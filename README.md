# Coach

Native iPhone-App, die Garmin-Coaching, Ernährung und Gym-Logging vereint – unabhängig von Home Assistant.

Kein eigener Server nötig:

```
iPhone (SwiftUI, SwiftData, Regeln in CoachCore)
  ├─ HTTPS ─► Garmin Connect Personal API (offiziell, Key im Keychain)
  ├─ HTTPS ─► Open Food Facts (Barcode, Daten unter ODbL)
  └─ HTTPS ─► Cloudflare Worker ─► Gemini / Groq (KI-Keys nur im Worker)
```

## Stand

| Phase | Inhalt | Status |
|---|---|---|
| 1 | Gerüst, CI, leere App mit HealthKit-Diagnose | fertig (PR 1) |
| 2 | Garmin-Anbindung (Personal API), lokale Datenhaltung, KI-Worker auf Cloudflare | fertig (PR 2) |
| 3 | Coach: Tagesempfehlung, Erholung, Wochen-Soll/Ist, Rennvorbereitung | fertig (PR 3) |
| 4 | Ernährung: Foto, Text, Barcode; Tagesziele nach Training; KI-Auswertung | fertig (PR 4) |
| 4b | Garmin-Werte wie im HA-Dashboard: Erholungsverläufe, SpO2, Atemfrequenz, VO2max, km/Woche, HF-Zonen | fertig (PR 6) |
| 5 | Gym: Plan, Sätze loggen, Progression, Sätze je Muskel, Verlauf, Speichern in Apple Health | fertig (PR 7) |
| 6 | Automatische Releases bei jedem Merge, SideStore-Quelle mit Update-Hinweis | fertig (PR 8) |
| 7 | Wissenschaftliche Basis: Quelle (DOI) je Regel, KI nur mit geprüften Fakten | fertig (PR 9) |
| 8 | Reiter „Plan“: alle Einheiten der Saison mit Inhalt (Lauf, Schwimmen, Rad, Gym) | fertig (PR 10) |
| 9 | Design-Überarbeitung (Designsystem, Heute-Ansicht) | in Arbeit (Heute fertig: PR 12) |
| 10 | Disziplinen wie im HA-Dashboard: Tests und Trends (CSS, FTP, Schwelle), Pace-Check, Wettkampfläufe, Zielzeit Almere, Marathon | fertig (PR 11, Pace-Check und aerobe Kopplung PR 13) |
| 11 | Tagesform & Leistung, Schlafanalyse, Wochenreport mit Vorschlägen, Chat, Erinnerungen | offen |
| 12 | Garmin-Konto als Hauptquelle (Readiness, Trainingsstatus, Endurance Score, Prognosen), Personal API als Rückfall | fertig (PR 15) |
| 13 | Personalisierung: Sportarten, Ziele, Wettkampf oder allgemeine Fitness, eigener Wochenplan mit Ruhetagen, Schutzgrenzen | fertig (PR 16) |
| 14 | Erzeugte Trainingspläne mit Progression (Laufen, Gym) und KI-Notiz für persönliche Profile | offen |
| 15 | Erinnerungen an Trainingstage (Mitteilung oder Karte unter „Heute“), Einheit verschieben oder diese Woche auslassen | fertig (PR 17) |
| 16 | Begleiter (Trainer, Avatar, z. B. Hund „Daisy“), der motiviert | fertig (PR 18) |
| 17 | Rangliste zwischen Nutzern (Punkte für Planerfüllung, keine Gesundheitsdaten), Einladungslink | fertig (PR 18) |
| 18 | Gym-App nach Vorbild GymBook: Übungsbibliothek mit Anleitung, eigene Routinen und Vorschläge, Verlauf mit 1RM und Rekorden, Wiederholungen in Reserve, KI-Tipps zur Gewichtssteigerung | fertig (PR 21) |
| 19 | Rezeptideen für die kommende Woche aus Tageszielen, Trainingsplan, Ernährungsweise, Allergenen und Lücken der letzten Wochen; Einkaufsliste | fertig (PR 22) |
| 20 | Einheiten ausführlich erklärt (Ablauf, Gefühl, Fehler, Glossar) | fertig (PR 23) |
| 21 | Sicherungen: Eingabeprüfung (Zielzeit gegen Prognose), Gewichtsverlauf mit Nachsteuerung, Laufumfang-Warnung, strengere Rezeptprüfung, Prüfbericht mit Musterpersonen in jeder PR | fertig (PR 24, Makros PR 25) |
| 22 | Vergleich mit Bezahl-Apps: Screenshots in CI, gemessener Verbrauch, Fitness/Form, Wochenbericht, Laufplan mit Steigerung, Gym-Komfort | fertig (PR 26) |
| 23 | Schlaf-Coach (Schlafenszeit, Regelmäßigkeit, Erinnerung) und Chat mit dem Coach aus den eigenen Daten | fertig (PR 31) |
| 24 | Aktivitätsdetails wie in Garmin Connect: Karte, Verlauf, Runden, Laufdynamik, Schwimmwerte, Trainingseffekt | fertig (PR 32) |
| 25 | Gym ersetzt GymBook: eigene Pläne, Übertragung nach Garmin Connect mit Sätzen, KI-Trainingsplan mit Fragebogen, Hinweise zu Stillstand und Volumen | fertig (PR 33) |
| 26 | Apple Health / Apple Watch als zweite Quelle: Schlaf, Ruhepuls, Kalorien, VO2max, Gewicht, Workouts (Garmin hat Vorrang) | fertig (PR 34) |
| 27 | Erinnerungen: Schwimm-Ausrüstung am Vorabend, sonntags „Nächste Woche planen“ mit Wochenplanung; GymBook-Verlauf importieren; Name IronLudi | fertig (PR 35) |
| 28 | „Heute“ aufgeräumt (Woche, Ziele, Verlauf eine Ebene tiefer), Erinnerungen kennen erledigte Einheiten | fertig (PR 36) |
| 29 | Übungsverlauf mit Zeitraum, Zoom mit zwei Fingern und bewegter Last je Einheit | fertig (PR 37) |
| 30 | Manueller KI-Coach: Export aller Daten eines Zeitraums für ChatGPT/Gemini/Claude, Import der Antwort mit Regelprüfung | fertig (PR 38) |
| 31 | KI-Import mit Auswahl: je Routine ersetzen/zusätzlich/weglassen, Wochenplan je Tag, Hinweise einzeln | fertig (PR 39) |
| 32 | Abnehm-Prognose (4/8/12 Wochen, Zieldatum, geschätztes Defizit) und Fokus während der Krafteinheit | fertig (PR 40) |
| 33 | Eigene wissenschaftliche Quellen in den Einstellungen, von der KI (Gemini Flash) mitberücksichtigt | fertig (PR 41) |
| 34 | Gym im Training: Fokus-Karte, Ziffernblock, RIR in der Pause, Rückgängig, Abschluss mit vergessenen Sätzen, Bildschirm an | fertig (PR 42) |
| 35 | Gym: Satzarten (Aufwärmen zählt nicht), Supersätze, Später/Ersetzen/Reihenfolge, Plausibilität, Pausen merken, Stange/Scheiben, Notizen | fertig (PR 43) |
| 36 | Gym: Ziel sichtbar, Karte „Nächste Einheit“, Abschluss mit Vergleich und „Nächstes Mal“, Auswertung mit Kalender | fertig (PR 43) |
| 37 | Live-Aktivität: Pause und nächster Satz auf dem Sperrbildschirm, „Satz erledigt“ ohne Entsperren | fertig (PR 44) |
| 38 | Ernährung schnell eintragen: Vorschläge zur Tageszeit, „wie gestern“, Suche, Wochenstreifen, Rest-Ring, nur Kalorien, Wasser | fertig (PR 46) |
| 39 | Ernährung Mengen und Entwurf: Portionen, kompakter Entwurf, Rezepte über den Entwurf, Erfassen in einem Schritt, fehlende Nährwerte, unbekannte Barcodes | fertig (PR 47) |
| 40 | Ernährung Planung: „Was jetzt?“, eigene Rezepte/Meal-Prep, Warteschlange ohne Netz, Woche, Einkaufsliste nach Abteilung, Erinnerung abends | fertig (PR 47) |
| 41 | Training Soll/Ist: Zuordnung je Einheit (Sportart, Dauer), verpasste Einheiten (nachholen, streichen, krank), Wochen-To-do mit Summen und Wischen, Training nachtragen | fertig (PR 49) |
| 42 | Training Verlauf: ein Feed für Garmin, Apple Health, Nachgetragenes und Gym (Doppelte zusammengeführt), Nach-dem-Training-Karte mit Anstrengung und Vorschlag für morgen, „Warum?“ auch im persönlichen Profil, Detail-Kopf mit Zonen, fehlende Daten | fertig (PR 50) |
| 43 | Gym-Einstellungen: Pausen je Übung und Standard, Aufwärm-Vorschlag, Abhaken nach Eingabe; Einstellungen nach Disziplin | fertig (PR 51) |
| 44 | Gym: Stoppuhr für Halteübungen mit Korrektur, Pause einklappbar | fertig (PR 52) |
| 45 | Training Heute: „Jetzt dran“ für beide Modi, Widerspruch Regel/Plan, Wochenbelastung aller Sportarten, Form in der Ampel, Vorschläge mit Diff und Regelprüfung, Wochenrückblick, Trends, Verlauf filtern | fertig (PR 53) |
| 46 | Ernährung: Mahlzeit diktieren (Spracherkennung auf Deutsch, wenn möglich auf dem Gerät) | fertig (PR 55) |
| 47 | Gym Paket 1 A: Plan geschafft (beenden/fortsetzen), nächste Übung mit Namen und Vorschau, Überspringen, keine Erinnerung im Training, Eingabe ohne Mitziehen, letzte 5 Leistungen, Gewicht/Wdh. auf dem Sperrbildschirm, Kabel-Crunch | fertig (PR 56) |
| 48 | Gym Paket 1 B: Trainingspläne leichter erreichbar, Übungsbibliothek mit Filter, Muskel-Heatmap | fertig (PR 57) |
| 49 | Gym Paket 1 C: Garmin – Sätze in die Uhr-Aktivität, keine doppelten Aktivitäten und Kalorien | fertig (PR 58) |
| 50 | Ernährung: Nährwerte aus dem Bundeslebensmittelschlüssel (BLS 4.0, offline), KI nur zum Zerlegen, BLS-Suche | fertig (PR 59) |
| 51 | KI A: austauschbare Anbieter (Gemini, Workers AI, Groq, eigener Server), KI-Stufen, Nutzungsprotokoll, Modellbewertung | fertig (PR 60) |
| 52 | KI B: Reiter „AI“ mit Empfehlungen nach Themen (neu, gelesen, umgesetzt, verworfen), Plan im Reiter Training | fertig (PR 61) |
| 53 | KI C: Export mit Datenauswahl und Formaten, Prompt-Bibliothek mit eigenen Prompts | fertig (PR 62) |
| 54 | Ernährung A: Zuletzt/Häufig/Rezepte/Favoriten beim Erfassen, gegessene Menge nachträglich anpassen | fertig (PR 63) |
| 55 | Ernährung B: Foto-Analyse ergänzen per Text und Hinweisen, nur neue Positionen | fertig (PR 64) |
| 56 | Ernährung C: Erinnerungen je Mahlzeit, konfigurierbares Dashboard | fertig (PR 65) |
| 57 | Ernährung D: Mahlzeiten teilen per Link | fertig (PR 66) |
| 58 | Health A: Body Battery mit Tagesverlauf, Aufwachwert und Bezug zu Schlaf/Stress; Ruhekalorien, Puls, Regenerationszeit, Belastung | fertig (PR 67) |
| 59 | Health B: Morning Report mit persönlichen Normalbereichen | fertig (PR 68) |
| 60 | Health C: konfigurierbare Health-Widgets, Wecker zur Aufstehzeit | fertig (PR 69) |
| 61 | Datenquellen A: gemeinsame Architektur (Vorrang je Datenart, keine Doppelten, Herkunft, Sync-Status), Integrationsmatrix | fertig (PR 70) |
| 62 | Datenquellen B: WHOOP (OAuth über den Worker) | geplant |
| 63 | Datenquellen C: Polar AccessLink | geplant |
| 64 | Gym-Rückmeldungen: Übersprungenes ausgegraut, Start erst mit dem ersten Satz, keine Erinnerung im Training, Fokus entfernt, Garmin nachholen, Wochenzählung | fertig (PR 71) |
| 65 | Onboarding und Personalisierung: Haupt-/Nebenziele, Prioritäten, Tracker; Wirkung auf Plan, KI, Dashboard, Belastung; Verlauf | fertig (PR 72) |
| 66 | Plattform A: Analyse (Widgets, Android, iOS-Versionen, Architektur), Schnellaktionen am App-Icon, Kurzbefehle/Siri, Navigation per Route | fertig (PR 73) |
| 67 | Plattform B: Homescreen- und Sperrbildschirm-Widgets (Heute, Gym, Ernährung, Health) mit App Group, Wasser-Knopf | fertig (PR 74) |
| 68 | Darstellung: Dunkelmodus wählbar (Wie System / Hell / Dunkel) | fertig (PR 76) |
| 69 | Qualität und Multi-User (Paket 8): Bericht, Gast-Tokens für Einladungen, Besitzer für geteilte Einträge, Speicherwarnung | fertig (PR 77) |
| 70 | Android-App „IronLudi Gym“ (Gym-Logging, Kotlin/Compose), private Download-Seite über den Worker, Installationsanleitung iPhone/Android | fertig (PR 78) |
| 71 | Android Ernährung Teil 1: Tagesziele, BLS 4.0, KI per Text/Foto, Barcode, Favoriten/Häufig/Wie gestern, KI-Zugang per Link | fertig (PR 79) |
| 72 | Android Ernährung Teil 2: Rezepte/Meal-Prep, Was jetzt?, Wochenplan + Einkaufsliste, Tag auswerten, Gewicht + Prognose, Teilen, Erinnerungen, Offline-Warteschlange | fertig (PR 80) |
| 73 | Ernährung: Wasser aus Getränken und Essen, Mahlzeiten-Widget (Sperrbildschirm/Homescreen, „+“ je Mahlzeit), Kamera-Knopf | fertig (PR 81) |
| 78 | Paket 12: Chat mit Daten passend zur Frage, Folgefragen, verständliche Fehler, Empfehlungen nach sieben Bereichen, messbare Chat-Qualität | fertig (PR 88) |
| 76 | Paket 10 Gym: Abschluss ohne leeren Bildschirm, Aufwärmvorschläge nach Übung und Niveau, Sperrbildschirm neu, Pausenton und Vibration wählbar, KI-Plan vollständig bedienbar, GymBook aus den Vorschlägen | fertig (PR 86) |
| 77 | Paket 11: Einstellungen nach Bereichen, Quellen nur noch auf Wunsch, Schlaf nach Wochentag, Feiertag und Wecker, einheitliche Pausenlogik, KI kennt Leistung über Pläne hinweg | fertig (PR 87) |
| 80 | Phase 77 aus dem Audit: eine Tagesampel für alle Reiter, kein Grün ohne Daten, Tageswechsel, Schlaf als Episode, Widgets nach Mitternacht | fertig (PR 91) |
| 81 | Phase 78 aus dem Audit: Ernährung nach echtem Trainingstag, Ampel wirkt auf die Ziele, Krafteinheiten nur einmal, Wochenfortschritt und Planvorschlag korrigiert, Einzellauf-Grenze | fertig (PR 92) |
| 82 | KI-Anbieter je Aufgabe: Cerebras und Mistral neu, Fotos an Gemini/Mistral, Pläne und Rezepte an Cerebras, kurze Hinweise an Groq, Reserve-Kette bei aufgebrauchtem Kontingent | fertig (PR 93) |
| 83 | GitHub Models (GPT-4.1, auch Fotos) als weiterer kostenloser Anbieter über das GitHub-Konto | fertig (PR 95) |
| 84 | Paket 13: Wettbewerbsanalyse (Pliability, TrainingPeaks, MacroFactor, Boostcamp, Hevy, Runna), Mobility-Bereich mit Selbsttests und Einheit nach Belastung | fertig (PR 96) |
| 85 | Datensicherung iPhone: täglich automatisch in einen Ordner (z. B. iCloud Drive), als Datei teilen, Einspielen auch beim ersten Start; führt zusammen | fertig (PR 97) |
| 86 | Mobility auf „Heute“ an Ruhe- und Erholungstagen, Mobility im KI-Kontext | fertig (PR 98) |
| 87 | Wöchentlicher Ernährungs-Check-in (Gewichtstrend und gemessener Verbrauch, Anpassung nur mit Zustimmung) | fertig (PR 99) |
| 88 | Anregungen aus MCI: Beschwerdebereiche (Mobility-Vorrang, Hinweis bei Übungen, KI) und Urlaub/Trainingspause | fertig (PR 100) |
| 89 | Einheiten auf Wunsch an die Garmin-Uhr senden (Laufen, Rad; Schwimmen im persönlichen Plan), Tag wählbar, erneutes Senden ersetzt; Schwimmeinheiten des Saisonplans bleiben beim Add-on | fertig (PR 101) |
| 90 | KI-Nutzung je Person: Tageslimit für Gäste (Standard 60), eigene Übersicht, Kostenübersicht für den Betreiber (`/v1/usage/all`), klare Meldung in der App | fertig (PR 102) |
| 91 | Konten für Freunde und Familie: Benutzername + Passwort, nur mit Einladung, Sitzungen je Gerät, Wiederherstellungscode, iPhone und Android | in Arbeit |
| 74 | Schutzgrenzen in jedem Pfad: BMI, Alter, Schwangerschaft, Essstörung, Zielgewicht auch bei neuen Wägungen und Anpassungen; KI ohne gesperrte Gewichtsziele; Adipositas-Bezug für Protein (Audit) | fertig (PR 83) |
| 75 | Paket 9 Ernährung: Erfassen zuerst, Rezeptideen ohne 502 (Woche in Teilen, nächster Anbieter bei unbrauchbarer Antwort), gemeinsam kochen mit Freigabe, Portionen oder Tage, Vorkoch-Prüfung | fertig (PR 84) |

Offene Prüfpunkte mit echten Daten: `docs/todo.md`. Später, erst auf Zuruf: (Apple Health ist seit PR 34 umgesetzt, die Watch-App ist gestrichen)
technische Einstellungen für Mitnutzer ausblenden, Android-Version (bewertet in `docs/plattform-paket7.md`: erst bei Bedarf, dann
Compose-Oberfläche mit CoachCore über das Swift SDK für Android).

Maßstab für 7–12 ist der Funktionsumfang des Home-Assistant-Stands (Garmin AI Coach 0.29.3, Übergabe vom
26.10.2026).

## Installation auf dem iPhone

Siehe [docs/sidestore.md](docs/sidestore.md). Kurz: einmal die Quelle
`https://github.com/hkrb7p794w-sys/Coach-App/releases/latest/download/source.json` in SideStore eintragen und
Coach daraus installieren; neue Versionen meldet SideStore dann selbst.

Garmin, KI-Worker und App verbinden: [docs/einrichtung.md](docs/einrichtung.md).

## Entwicklung

Kein Mac nötig – gebaut wird in GitHub Actions. Details, Befehle und Regeln: [CLAUDE.md](CLAUDE.md).
Architekturentscheidungen mit Quellen: [docs/decisions.md](docs/decisions.md).
