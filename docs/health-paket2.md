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
