# Health, Recovery und Schlaf (Paket 2)

Stand: 02.11.2026. Analyse der Datenquellen, Plan in drei PRs und offene Grenzen.

## Datenquellen (Analyse)

| Wert | Garmin-Konto (Connect) | Personal API | Apple Health | In der App vorher |
|---|---|---|---|---|
| Schlafdauer, Score, Phasen, Ein-/Aufwachzeit | ja | ja | Dauer und Phasen (Watch) | ja |
| Ruhepuls | ja | ja | ja | ja |
| HRV (Nacht, 7 Tage, Baseline, Status) | ja | ja | nur SDNN (anderes Maß, nur wenn eingeschaltet) | ja |
| Stress (Ø, im Schlaf) | ja | ja | – | ja |
| Body Battery hoch/tief/aktuell, geladen/verbraucht | ja | Tageszusammenfassung | – | nur Kacheln |
| Body Battery Tagesverlauf | `bodyBattery/reports/daily` | – | – | **fehlte** (Parser erwartete `calendarDate`, die Antwort hat `date`) |
| Body Battery beim Aufwachen | `bodyBatteryAtWakeTime` | – | – | fehlte |
| Training Readiness, Regenerationszeit | ja (`recoveryTime` in Minuten) | – | – | Readiness ja, Regenerationszeit fehlte |
| Trainingsstatus, akute/chronische Last | ja (`acuteTrainingLoadDTO`) | – | – | Status ja, Last fehlte |
| VO2max, Fitnessalter, Endurance Score | ja | teils | VO2max | ja |
| Schritte, aktive kcal | ja | ja | ja | ja |
| Ruhekalorien (Grundumsatz) | `bmrKilocalories` | ja | `basalEnergyBurned` | fehlte (nur in Summe) |
| Puls tief/hoch des Tages | `minHeartRate`/`maxHeartRate` | ja | – | fehlte |
| Gewicht | ja | – | – (App-eigene Wägungen) | ja (Ernährung) |
| Atemfrequenz, SpO2 | ja | ja | ja | ja |

Body Battery ist ein Garmin-Wert (Firstbeat). Apple Health hat nichts Vergleichbares; ohne Garmin zeigt die App
keinen Ersatzwert, sondern sagt, dass er fehlt.

## Plan

- **PR A – Body Battery und fehlende Garmin-Werte:** Tagesverlauf (Viertelstunden, Ortszeit), Wert beim Aufwachen,
  30-Tage-Verlauf mit persönlichem Bereich, Zusammenhang mit Schlaf und Stress (Vergleich eigener Tage). Dazu
  Ruhekalorien, Puls tief/hoch, Regenerationszeit, akute/chronische Belastung. `PersonalNorm` für persönliche
  Normalbereiche.
- **PR B – Morning Report:** Kompakte Übersicht am Morgen (Schlaf, Phasen, Ruhepuls, HRV, Stress, Body Battery,
  Erholung, Belastung, Schlafempfehlung, geplante Einheiten) mit Einordnung gegen den eigenen Bereich und
  Empfehlung nach festen Regeln. Fehlende Werte werden genannt, nie geschätzt.
- **PR C – Health-Widgets und Wecker:** Konfigurierbarer Gesundheitsbereich (hinzufügen, entfernen, ein-/ausblenden,
  Reihenfolge, Darstellung), nur Widgets mit vorhandenen Daten. Wecker zur empfohlenen Aufstehzeit über AlarmKit.

## Persönliche Normalbereiche

`PersonalNorm`: Mittelwert ± eine Standardabweichung der letzten 30 Tage, heute nicht mitgezählt, mindestens
7 Tage; die Spanne ist mindestens ±3 % des Mittelwerts, damit sehr gleichmäßige Verläufe nicht jede Kleinigkeit
melden. Rund zwei Drittel der eigenen Tage liegen darin. Bei HRV gilt vorrangig Garmins Baseline (HRV-Status).

## Health-Widgets (PR C)

- Hinzugefügte Widgets in Reihenfolge, je mit Darstellung (nur Wert, Verlauf 7 Tage, Verlauf 30 Tage) und
  Sichtbarkeit (`HealthDashboard`, gespeichert als `coach.healthDashboard`). Ausblenden behält Platz und Darstellung,
  Entfernen nimmt das Widget aus der Liste; „Hinzufügen“ bietet nur Widgets mit Daten der letzten 30 Tage an.
- Widgets ohne Daten werden nicht angezeigt und unten mit ihrer möglichen Quelle genannt („nur Garmin“ …).
- Jede Karte ordnet den letzten Wert gegen den eigenen Bereich ein; Farbe nur bei Werten mit klarer Richtung
  (Ruhepuls höher = orange, Body Battery höher = grün), sonst neutral.
- Ersatzquellen: Gewicht aus eigenen Wägungen, Garmin und Apple Health; Trainingsbelastung ohne Garmin-Konto aus
  den eigenen Aktivitäten (gleiche Grundlage wie „Fitness & Form“).

## Wecker (PR C)

| Weg | Möglich? | Bestätigung | Bewertung |
|---|---|---|---|
| AlarmKit (`AlarmManager`, iOS 26) | ja, echter System-Wecker: klingelt auch lautlos und im Fokus, erscheint auf Sperrbildschirm und Watch | einmalige Erlaubnis (`NSAlarmKitUsageDescription`), danach ohne Rückfrage | **gewählt** |
| Uhr-App direkt (`clock-alarm://` u. Ä.) | nicht dokumentiert, kein Stellen von Weckern | – | verworfen |
| Kurzbefehl „Wecker erstellen“ | nur, wenn die Person selbst einen Kurzbefehl anlegt | Kurzbefehl-App | Fallback nur als Hinweis |
| Lokale Mitteilung | ja | Mitteilungs-Erlaubnis | kein Wecker (stumm im Lautlos-Modus), gibt es schon als Schlafenszeit-Erinnerung |

- Gestellt wird eine Uhrzeit (`Alarm.Schedule.relative`), kein fester Zeitpunkt: Zeitumstellung und Zeitzonenwechsel
  ändern die Weckzeit nicht. Einmalig, Mo–Fr oder täglich.
- Immer höchstens ein IronLudi-Wecker: ein neuer ersetzt den alten; „Wecker löschen“ nimmt ihn heraus. Vom System
  entfernte Wecker werden nicht mehr als gestellt angezeigt.
- Zwei Vorschläge: Weckzeit aus dem Schlaf-Coach oder „jetzt ins Bett“ (jetzt + 15 min Einschlafen + Schlafbedarf,
  auf 5 min aufgerundet).
- Unter iOS 18–25 gibt es keinen Wecker aus der App, nur den Hinweis auf die Uhr-App.
- Ein Widget-Ziel ist nicht nötig: AlarmKit erwartet die Erweiterung nur für Wecker mit Countdown-Anzeige.

## Welche Kennzahlen (Punkt 5)

| Bereich | In der App | Bewusst weggelassen |
|---|---|---|
| Gesundheit | Ruhepuls, Puls tief/hoch, Gewicht, SpO2, Atemfrequenz, Schritte, Kalorien | Fitnessalter (ändert sich kaum), Stockwerke, Intensitätsminuten (doppelt zu Aktivitäten) |
| Schlaf | Dauer gegen Bedarf, Score, Phasen, Regelmäßigkeit (Schlaf-Coach) | Schlafstress als eigenes Widget (steckt in Stress/Body Battery) |
| Erholung | HRV (Status vor Einzelnacht), Body Battery beim Aufwachen, Stress, Readiness, Regenerationszeit | Einzelne Readiness-Faktoren (Garmin rechnet sie schon ein) |
| Belastung | akute/chronische Last der Uhr, sonst eigene Tageslast; Wochenbelastung und Form | ACWR als eigene Zahl (nur als Einordnung im Morning Report) |
| Leistung | VO2max, Endurance Score, Wettkampfprognosen (Training) | Lactate-Threshold-Verlauf (zu selten gemessen) |

Kriterium: Ein Wert kommt nur dazu, wenn er eine Entscheidung verändert (Belastung heute, Schlafenszeit, Trend
über Wochen). Sonst bleibt er in der Diagnose sichtbar.
