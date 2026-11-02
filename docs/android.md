# Android-App „IronLudi“ (technisch)

Gym-Logging und Ernährung für Android, für eine Person ohne Garmin (Aufträge vom 02.11.2026). Bedienung und
Installation für Nutzer:innen: [`installation.md`](installation.md).

## Ernährung (wie auf dem iPhone)

| Funktion | Android | Quelle der Regeln |
|---|---|---|
| Tagesziele kcal/Protein/KH/Fett/Wasser + Mikronährstoffe | ✓ (Tagestyp je Wochentag bzw. Tag statt Garmin-Aktivitäten) | Port `NutritionPlanner.compute`, gleiche Formeln und Schutzgrenzen (REDs, ±1 %/0,5 % pro Woche) |
| Suche in 7.000 Lebensmitteln (BLS 4.0), offline | ✓ | Port `BLS.search`/`match`, gleiche `bls.tsv`, alle 24 Zuordnungsfälle der CoachCore-Tests |
| KI per Text, Foto (Kamera/Galerie), Ergänzen, „vielleicht vergessen“ | ✓ über den Worker (`meal_analyze`, `meal_amend`) | gleiche Aufgaben und Antwortschema wie iPhone |
| Barcode (Google-Code-Scanner) + Open Food Facts, Nummer von Hand | ✓ | Port `OpenFoodFacts` |
| Zuletzt, Häufig, Favoriten, Wie gestern, Schnell-Eintrag, Wasser, Portion anpassen, Rückgängig | ✓ | Port `MealSuggestions`, `MealShortcuts`, `MealPortion`, `QuickLog` |
| Wochenstreifen mit kcal je Tag, frühere Tage nachtragen | ✓ | |
| Eigene Rezepte/Meal-Prep mit Portionen, gekochtem Gewicht und Vorrat | ✓ (Teil 2) | Port `OwnRecipe` |
| „Was esse ich jetzt?“ (3 Gerichte zum Rest des Tages) | ✓ (Teil 2) über `meal_now` | Port `MealNow`, Prüfung Ernährungsweise/Allergene (`RecipePlanner.violations`) |
| Wochenplan mit Rezepten (KI) + Einkaufsliste nach Abteilung | ✓ (Teil 2) über `weekly_recipes` | Port `RecipePlanner.plan/fit/shoppingList`, `ShoppingAisle` |
| Tag auswerten (KI, gestützt auf die Regeln der App) | ✓ (Teil 2) über `nutrition_review` | Regeltexte aus `Evidence.swift` (`assets/evidence.json`) |
| Gewicht: Eingabe, Trend 28 Tage, Vorschlag ±kcal, Prognose beim Abnehmen | ✓ (Teil 2) | Port `WeightTrend`, `WeightForecast`, Schutzgrenzen `GoalRules` |
| Mahlzeiten teilen (Link/Code, 7 Tage) und geteilte öffnen | ✓ (Teil 2) über `/v1/share/meal` | gleiches Format wie iPhone, iPhone und Android tauschen untereinander |
| Erinnerungen je Mahlzeit + abends „Tag auswerten“ (keine, wenn schon eingetragen) | ✓ (Teil 2), AlarmManager | Port `ReminderPlanner.meals` |
| Alle Nährstoffe mit Ziel, Offline-Warteschlange für KI | ✓ (Teil 2) | |
| Rezept vom Foto, Nährwerttabelle vom Etikett, konfigurierbare Kartenreihenfolge, Verbrauch aus Gewicht + Zufuhr | **noch nicht** | |

KI-Zugang: Gast-Token aus dem Link der iPhone-App („Android-Link erstellen“, `#zugang=…` auf der Download-Seite →
`ironludi://connect?worker=…&token=…`) oder von Hand in Ernährung › Zahnrad › KI-Zugang. Gespeichert in privaten
App-Einstellungen, ausgenommen von Android-Backups (`res/xml/*backup*`). An die KI gehen nur Text/Foto der Mahlzeit,
Ernährungsweise und Namen eigener Lebensmittel – keine Körperwerte.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `android/core/` | Reine Kotlin-Logik ohne Android: Datenmodell, Doppelprogression (Port von `GymProgression` aus CoachCore), Statistik, Trainingsablauf, Sicherung/Zusammenführen. Tests: `GymCoreTest`. |
| `android/app/` | Jetpack Compose (Material 3, Hell/Dunkel nach System): Reiter Training, Verlauf, Pläne, Übungen; Einstellungen mit Pausenzeit, Bildschirm-an und Sicherung. |
| `android/app/src/main/assets/exercises.json`, `bls.tsv` | Übungsbibliothek, **erzeugt** aus `ExerciseLibrary.swift`/`ExerciseCatalog.swift`, und die BLS-Tabelle aus CoachCore, beides mit `python3 android/tools/export_exercises.py` (CI prüft mit `--check`). |
| `.github/workflows/android.yml` | Linux-Runner: `:core:test`, `:app:assembleRelease`, APK als Artefakt; auf `main` Upload nach Workers KV. |
| `worker/src/android.ts` | Private Download-Seite `/android/<key>/` und APK; `<key>` = SHA-256("android:" + Haupt-Token), erste 32 Hex-Zeichen. |

Daten: eine JSON-Datei `gym.json` im App-Speicher (Trainings und Mahlzeiten), atomar geschrieben (Zwischendatei +
Umbenennen). Ist sie nicht lesbar, legt die App eine Kopie an und warnt statt zu überschreiben. Berechtigungen:
`INTERNET` (KI über den Worker, Open Food Facts), `VIBRATE`, `POST_NOTIFICATIONS` und `RECEIVE_BOOT_COMPLETED`
(Erinnerungen, Standard aus). Keine Kamera-Berechtigung (Fotos über die Kamera-App,
Barcodes über den Google-Code-Scanner der Play-Dienste).
Android Auto Backup ist an (`allowBackup`), dazu Sicherung/Einspielen als Datei (führt über IDs zusammen, nichts
geht verloren).

## Signaturschlüssel (einmalig, Pflicht vor der ersten Installation)

Android installiert ein Update nur, wenn es mit **demselben Schlüssel** signiert ist. Der Schlüssel liegt nur als
GitHub-Secret, nie im Repo. Ohne die Secrets baut die CI nur mit Debug-Signatur (jeder Lauf anders) und lädt
**nichts** hoch.

1. GitHub › Repo › Settings › Secrets and variables › Actions › **New repository secret**.
2. `ANDROID_KEYSTORE_PASSWORD` = Passwort, `ANDROID_KEYSTORE_B64` = Schlüsseldatei als Base64 (beides aus der
   Datei, die Claude erzeugt hat, oder selbst: `keytool -genkeypair -keystore ironludi.jks -storetype PKCS12
   -alias ironludi -keyalg RSA -keysize 3072 -validity 18250` und `base64 -w0 ironludi.jks`).
3. Den Schlüssel zusätzlich privat aufheben (z. B. Passwort-Manager). Geht er verloren, lassen sich installierte
   Apps nicht mehr aktualisieren: dann Sicherung speichern, neu installieren, Sicherung einspielen.
4. Danach baut der nächste Merge auf `main` (oder Actions › Android › Run workflow) die signierte Version und stellt
   sie bereit.

## Lokal

```sh
cd android
./gradlew -PcoreOnly :core:test     # ohne Android-SDK (z. B. Claude-Code-Sitzung)
./gradlew :core:test :app:assembleRelease   # mit Android-SDK
python3 tools/export_exercises.py   # nach Änderungen an der Swift-Bibliothek
```

## Bewusst nicht in Version 1

Garmin, Health Connect, Widgets, Rangliste und die in der Tabelle als „noch nicht“ markierten Punkte. Die Logik dafür liegt in Swift (CoachCore); ein Port
lohnt erst bei Bedarf (siehe `docs/plattform-paket7.md`, Abschnitt 2.3). Pausentimer läuft nur, solange die App
offen ist (keine Benachrichtigung im Hintergrund).
