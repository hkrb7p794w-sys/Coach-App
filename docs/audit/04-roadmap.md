# Roadmap

Vorschlag, die Befunde auf PRs zu verteilen: eine PR pro Phase, Nummerierung im Anschluss an Phase 73. Nichts davon ist umgesetzt;
jede Phase braucht deine Freigabe. Android-Phasen stehen am Ende und ruhen, bis du sie wieder aufnimmst.

## Arbeitsweise

- Jede Phase übernimmt die zugehörigen roten Audit-Tests aus PR #82 und macht sie grün. **PR #82 selbst wird nicht gemerget**, sonst
  wäre `main` rot.
- Zuerst `swift test`, `npm test` auf Linux. Einen iOS-Build per Label nur einmal je PR nach dem letzten Code-Commit (CI-Minuten).
- App-Tests aus `docs/audit/tests/ios/CoachTests/` werden in der jeweiligen Phase nach `ios/CoachTests/` verschoben.
- Aufwand: S bis 1 Tag, M einige Tage, L eine Woche und mehr.

## Phasen

### A. Sicherheit und Korrektheit

| Phase | Inhalt | Befunde | Aufwand |
|---|---|---|---|
| 74 | **Schutzgrenzen überall** (`GoalRules` zentral, Anpassung, Texte an KI, BMI bei neuen Wägungen, Ziel erreicht) | CORE1-14, -01, -02, -03, -04, -15, R2D-02, R5V-NEU-1, SCI-05, CORE1-22 | M |
| 75 | **Eingaben von außen** (Links mit Rückfrage, KI-Zahlen begrenzen, Plausibilität, Injection-Abgrenzung, Fehlertexte, Regelwiderspruch) | WRK-03, CORE2-04, WRK-07, -09 bis -15, R5B-01 | M |
| 76 | **Datenschutz und Worker-Betrieb** (Rohwerte, Einwilligung, Standardanbieter, Gast-Tokens, Rate Limit, Sperrliste, KI-Kennzeichnung) | CORE2-01, WRK-01, -04, -05, -06, -08, -16, -17, R2A-07, R5B-03, R3B-06, -07, -08 | M |
| 77 | **Tag und Ampel** (Tageswechsel, Neuberechnung, kein Grün ohne Daten, eine Ampel, Schlafepisoden, Schwellen, Widgets nach Mitternacht) | IOS2-01, -02, IOS1-02, R2A-01, -02, CORE2-05, -06, R5A-01, R3C-02, -03, SCI-12 | M |
| 78 | **Soll/Ist und Trainingstage** (geplanter Tag, Abgleich, Wochenfortschritt, Außerplanmäßig, Ampel wirkt auf Ernährung, Saisonfokus) | R2D-01, -05, -10, R4A-01 bis -07, R4B-06, R3C-01, IOS1-01, SCI-04 | M |

### B. Daten und Stabilität

| Phase | Inhalt | Befunde | Aufwand |
|---|---|---|---|
| 79 | **Daten sichern** (Sicherung/Wiederherstellung, Alles löschen, Speicherfehler, stilles Zurücksetzen, `VersionedSchema`, Speicherort der Datenbank) | MKT-1, R3B-01, -02, R2B-03 bis -06, IOS1-24 | M–L |
| 80 | **Garmin** (Token-Erneuerung, 429, Abruf je Quelle, stille Abmeldung, MFA, Doppel-Einheiten, Satznamen) | IOS1-05, -07, -08, CORE2-02, -03, -07, R4B-01, -02, -10 | M |
| 81 | **Offline und KI-Fallback** (Entwurf bleibt bei Fehlern, Datum der Warteschlange, Netzstatus, Abbruch, Fallback im Chat, Abbruch nicht als Fehler zählen) | IOS2-04, -05, IOS1-03, -04, R2C-11, R5B-02 | M |
| 82 | **Release-Pfad** (kein Hochladen von Nebenbranches, atomare Uploads, Privacy Manifest, Signaturwarnung) | R3B-03, -04, -05, R3B-I1, R3B-I3 | S–M |
| 83 | **Leistung** (`@Query` mit Prädikat, einmal decodieren, Messung mit Ein-Jahres-Datensatz) | IOS1-10, R2B-I3 | M |

### C. Erleben

| Phase | Inhalt | Befunde und Ideen | Aufwand |
|---|---|---|---|
| 84 | **Barrierefreiheit** (Kontraste, Status ohne Farbe, Charts, Dynamic Type, Pausenende, Reduced Motion) | IOS1-16, IOS2-17, -22, R2C-01 bis -10 | M |
| 85 | **Ohne Uhr, Einstieg, nur Ernährung** (Texte ohne Garmin-Zwang, Morgen-Check-in, Profil „Nur Ernährung“, Starterplan, Fortschritt „Daten sammeln“) | R2A-03 bis -09, R3A-01, R2A-I1, -I4, -I6, R3A-I1 | M |
| 86 | **Ernährung im Alltag** (Getränke, Rezept ohne Tagebuch, Vorrat zurückbuchen, Check-in, Morgen-Mitteilung) | R3A-02 bis -05, MKT-2, MKT-6, IOS2-07 | M |
| 87 | **Wissenschaftliche Verknüpfung** (Schlaf, krank, Kohlenhydrate am Vortag, Proteinverteilung, Betablocker, Zyklus, Schicht) | R2D-I02 bis -I06, -I13, R2D-06, R3A-06, -07, R5A-02, -03, R5A-I1, -I2, -I3 | M–L |
| 88 | **Mikrotexte und System** (Plural, Verweise, Mitteilungsziele, Siri-Rückmeldung, Live-Aktivität antippbar) | R5B-05 bis -11, R3C-04 bis -08, R4A-09, -10 | S–M |

### D. Ruhend: Android

Erst nach deiner Entscheidung. Zuerst die Sicherheitsthemen, weil sie reale Risiken sind: GoalRules-Sperren (AND-1, AND-2, SCI-02), Deep
Link (AND-4, WRK-02), Dezimaleingabe (AND-8), Rundung (AND-3). Danach Parität (siehe `02-paritaetsmatrix.md`).

## Reihenfolge

Phase 74 und 75 zuerst: Sie beheben den Blocker und die beiden Angriffswege. Phase 77 hat den größten sichtbaren Effekt im Alltag und
kann parallel zu 76 laufen, die Dateien überschneiden sich kaum. Phase 79 sollte vor jeder weiteren Modelländerung kommen, weil
`VersionedSchema` schwere Migrationen erst sicher macht.
