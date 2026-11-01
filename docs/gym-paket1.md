# Gym, Trainingssteuerung und Trainingsauswertung (Paket 1)

Stand: 01.11.2026. Analyse des Codes, Umsetzungsplan in drei PRs, Migrationen und offene Einschränkungen.

## Analyse (vorher)

| Bereich | Stand im Code | Problem |
|---|---|---|
| Ende des Plans | `FocusCard.allDone` zeigt nur „Alle Sätze erledigt“, der Knopf heißt „Einheit beenden“ | Kein „Fortsetzen“, keine aktive Frage |
| Nächste Übung | Mitteilung „Weiter mit dem nächsten Satz.“, Vorschau nur als Textzeile | Übungsname fehlt |
| Überspringen | nur „Später (Gerät belegt)“ = ans Ende schieben | Übung kann nicht ausgelassen werden |
| Erinnerungen | `ReminderService` plant den Trainingstag ein, solange keine Einheit gespeichert ist | Erinnerung kann mitten im Training kommen |
| Gewicht ändern | `WorkoutEdits.setWeight` zog offene Folgesätze mit gleichem Gewicht mit | Ungewollte Überschreibungen |
| Ziffernblock | Ziffern wurden an den alten Wert angehängt (80 → „808“) | Fehleingaben |
| Verlauf | eine Zeile „Letztes Mal“ | Keine Orientierung über mehrere Einheiten |
| Sperrbildschirm | Live-Aktivität mit „Satz erledigt“ und „Weiter“ | Gewicht/Wdh. nur in der App änderbar |
| Kabel-Crunch | Saisonplan ordnet `KNEELING_CABLE_CRUNCH` dem Körpergewichts-Crunch zu | 65 kg erschienen als „+65 kg Zusatz“ |
| Pläne | „Routinen“ eine Ebene unter „Gym“, Reihenfolge nur mit Pfeilen | Schwer zu finden |
| Muskeln | 9 grobe Muskelgruppen, Sätze je Gruppe der letzten 7 Tage | Keine Heatmap, indirekte Belastung fehlt |
| Garmin | eigene FIT-Datei als zweite Aktivität neben der Uhr-Aktivität | Doppelte Aktivität, doppelte Kalorien |

## Umsetzung

### PR A – Trainingsablauf, Eingabe, Sperrbildschirm, Kabel-Crunch

- **Plan geschafft:** Nach dem letzten offenen Satz (oder wenn nur Übersprungenes übrig ist) erscheint ein Blatt
  mit „Training beenden“, „Übung hinzufügen“ und „Training fortsetzen“. Die Fokus-Karte zeigt danach „Plan
  geschafft“ und bietet übersprungene Übungen zum Nachholen an. Keine Pause nach dem letzten Satz.
- **Nächste Übung:** Mitteilung zum Pausenende und Live-Aktivität sagen „Weiter mit Schulterdrücken“ beim
  Übungswechsel, sonst „Weiter mit Satz 3 · Bankdrücken“. Unter dem Satz steht eine Karte „Danach“ mit Name,
  Sätzen und Startwerten der nächsten Übung.
- **Überspringen:** auf der Fokus-Karte, in der Vorschau und im Übungsmenü; rückgängig und „Wieder aufnehmen“.
  Offene Sätze übersprungener Übungen werden nicht gespeichert und nicht als „vergessen“ gemeldet.
- **Keine Start-Erinnerung im Training:** Solange eine Einheit läuft, plant die App für heute keine
  Trainingserinnerung; Start und Ende planen neu.
- **Eingabe:** Gewicht und Wiederholungen nebeneinander in einem Bereich, je mit − und +. Der Ziffernblock zeigt
  beide Werte; die erste Taste ersetzt den alten Wert, unveränderte Felder bleiben unberührt. Jede Änderung
  betrifft nur diesen Satz (kein Mitziehen der Folgesätze mehr). Unplausible Werte fragen weiter nach.
- **Verlauf:** Unter der Eingabe die letzten 5 Einheiten der Übung, je bester Arbeitssatz („80 kg × 10“, Datum).
- **Sperrbildschirm:** Live-Aktivität mit Gewicht −/+ (ein Gewichtssprung der Übung) und Wiederholungen −/+
  (Halteübungen ±5 s), dazu „Satz erledigt“ und „Weiter“ (Pause überspringen).
- **Kabel-Crunch:** eigene Katalogregel `CABLE_CRUNCH` vor dem allgemeinen Crunch; ältere Einheiten werden beim
  Lesen umgedeutet (`ExerciseAliases`), die gespeicherten Daten bleiben unverändert.

### PR B – Trainingspläne, Übungsbibliothek, Muskel-Heatmap

- „Trainingspläne“ (bisher „Routinen“) als erster Bereich im Gym-Reiter, mit „Neuer Plan“.
- Übungsbibliothek mit Suche und Filter nach Muskelgruppe, Muskeldarstellung je Übung.
- Plan-Editor: Übungen hinzufügen/entfernen, Reihenfolge per Ziehen, Heatmap des Plans.
- Belastungsmodell (siehe unten) mit Heatmap nach jeder Einheit, im Plan-Editor und in der Langzeitübersicht.

### PR C – Garmin

- Garmin Connect erlaubt kein Zusammenführen zweier Aktivitäten. Es gibt aber die Schnittstelle hinter „Sätze
  bearbeiten“ der Connect-Webseite (`/activity-service/activity/{id}/exerciseSets`, GET und PUT, inoffiziell; so
  auch python-garminconnect und strong-garmin-sync). Damit schreibt die App ihre Sätze in die Aktivität der Uhr:
  Kalorien, Herzfrequenz und Zeit bleiben, Übungen, Wiederholungen und Gewichte kommen dazu – eine Aktivität.
- Zuordnung über die Startzeit (Krafttraining, gleicher Tag, höchstens 2 h Abstand, Aktivität noch keiner anderen
  Einheit zugeordnet); die Garmin-ID wird an der Einheit gespeichert. Vor dem Schreiben sichert die App die
  ursprünglichen Sätze.
- Ohne Uhr-Aktivität wartet die Einheit bis zu 3 Stunden (Abgleich nach jedem Abruf) und wird dann wie bisher als
  FIT-Datei hochgeladen (abschaltbar).
- Die Verbindung steht als JSON an der Einheit (`GymSession.garmin`) – keine SwiftData-Migration.
- In der App: doppelte Krafttrainings (Upload und Uhr) werden erkannt und nur einmal gezählt – im Verlauf und
  bei den Kalorien.

## Belastungsmodell (PR B)

- Grundlage sind **Arbeitssätze je Muskel** (nicht Kalorien): Die Dosis-Wirkungs-Studien zu Muskelaufbau zählen
  Sätze je Muskel und Woche (Schoenfeld et al. 2017, Pelland et al. 2025).
- **Verbundübungen:** Hauptmuskel zählt den Satz voll, beteiligte Muskeln halb („fractional sets“ wie bei
  Pelland et al. 2025). Ein Satz wird je Muskel nur einmal gezählt – keine Doppelzählung über Muskelgruppen.
- **Intensität:** Sätze weit weg vom Versagen (RIR ≥ 5) zählen weniger; ohne Angabe zählt der Satz voll.
- **Regeneration:** Zeit seit der letzten nennenswerten Belastung je Muskel. Die App zeigt eine Schätzung
  („wahrscheinlich noch in der Erholung“), keine gemessene Ermüdung.

## Migrationen

- `GymSessionRecord` speichert die Einheit als JSON. Neue Felder (`LoggedExercise.skipped`) werden beim Lesen mit
  Standardwert ergänzt – keine SwiftData-Migration.
- PR C speichert die Garmin-Verbindung im JSON der Einheit (`GymSession.garmin`, optional) statt in neuen
  Datenbankfeldern: keine Migration, kein Risiko eines leeren Speichers nach einer fehlgeschlagenen Migration.
  Beim Setzen wird das gespeicherte JSON roh gelesen, damit Lese-Korrekturen (Kabel-Crunch) nicht hineingeschrieben
  werden.
- Vergangene Einheiten werden nicht umgeschrieben; Korrekturen (Kabel-Crunch) gelten nur beim Lesen.

## Offene Einschränkungen

- **Sperrbildschirm:** Zahlen eintippen geht dort nicht (iOS erlaubt nur Knöpfe). Interaktive Widgets auf dem
  Sperrbildschirm (Accessory-Widgets) sind in iOS 18 nicht interaktiv; die Live-Aktivität ist der Weg. Sie endet
  spätestens nach 8 Stunden (danach bis zu 4 Stunden nur sichtbar).
- **Garmin:** Die Satz-Schnittstelle ist inoffiziell und kann sich ändern; Garmin prüft die Übungsnamen gegen den
  FIT-Katalog. Unbekannte Unterkategorien schickt die App ohne Namen (nur Kategorie).
- **Übungsbilder/Animationen:** keine fremden Bilder (Lizenzen, App-Größe); stattdessen Muskeldarstellung und
  Anleitungstext.
- Nicht auf einem Gerät getestet; Prüfpunkte in `docs/todo.md`.
