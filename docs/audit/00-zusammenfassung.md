# Audit der Coach-App: Zusammenfassung

Stand: `main` @ 8baa407 (PR #81), Audit vom 03. bis 08.11.2026, Branch `docs/audit`, Entwurfs-PR #82 (nicht mergen).
Der Produktivcode wurde nicht verändert. Android wurde auf Wunsch ab Runde 2 nicht weiter geprüft; die Befunde aus Runde 1
stehen getrennt als „zurückgestellt“ in `01-befunde.md`.

## Gesamtbild

Die App ist in Breite und fachlicher Fundierung weit über dem, was Einzelapps bieten: 70 zitierte Quellen (DOI/PMID) wurden in
PubMed geprüft, alle existieren und stützen die Aussage. Der Secret-Scan über 307 Commits fand nichts. Pausentimer,
Widgets und die Grundstruktur „Regeln entscheiden, KI formuliert“ sind solide gebaut.

Die Schwächen liegen an drei Stellen:

1. **Schutzregeln greifen nur an einem Eingang.** `GoalRules` wirkt beim Speichern des Profils, aber nicht bei Wägungen, bei
   übernommenen Kalorien-Anpassungen, in KI-Prompts oder im Saisonmodus. Das ist der einzige Blocker und die Ursache mehrerer
   hoher Befunde.
2. **Vertrauen in Eingaben von außen.** Links setzen die Worker-Adresse, KI-Zahlen laufen ungeprüft durch `Int(Double)`, und
   Rohwerte rutschen im Modus „reduziert“ über Wochenbericht-Sätze in den Chat.
3. **Zahlen stimmen nicht überall überein.** Tageswechsel, Neuberechnung nach dem Bearbeiten, Ampel ohne Daten und die
   Zuordnung von Einheiten führen dazu, dass Reiter und Widgets Verschiedenes zeigen.

| | iPhone + Worker | Android (zurückgestellt) |
|---|---|---|
| Blocker | 1 | 3 |
| Hoch | 15 | 2 |
| Mittel | 112 | 18 |
| Niedrig | 96 | 8 |
| **Summe** | **224** | **31** |

8 weitere Einträge waren Duplikate und sind in ihren Hauptbefund eingegangen.

**Belegt durch Tests** (Linux-CI, Entwurfs-PR #82): 54 Audit-Tests in CoachCore (52 rot, die 2 grünen sind beabsichtigte
Gegenproben), 9 von 9 im Worker rot, 8 von 8 im Android-Core rot. Kein bestehender Test ist rot. Die 8 App-Tests
unter `docs/audit/tests/ios/CoachTests/` brauchen den Simulator und liefen nicht.

**Gegenprüfung:** Alle 24 Blocker-/Hoch-Befunde außerhalb von Android wurden gezielt zu widerlegen versucht: 16 bestätigt, 6 auf
Mittel herabgestuft, 2 Duplikate, 0 widerlegt.

## Top 10 Maßnahmen

| # | Maßnahme | Befunde | Aufwand |
|---|---|---|---|
| 1 | Schutzgrenzen zentral in `NutritionPlanner.compute` erzwingen und jede Stelle anbinden, die Ziele, Anpassung oder Ziel-Texte verwendet | CORE1-14, CORE1-01, -02, -03, -04, -15, R2D-02, R5V-NEU-1 | M |
| 2 | Links dürfen Worker-Adresse und Token nicht ohne sichtbare Rückfrage ändern; Token nie an einen neuen Host senden | WRK-03 | S |
| 3 | Datenschutzmodus lückenlos machen, Standardanbieter und Einwilligung klären | CORE2-01, WRK-17, WRK-01, WRK-09, R2A-07 | M |
| 4 | KI-Zahlen vor der Umwandlung begrenzen, Plausibilitätsgrenzen für KI- und Teilen-Werte, Regelwiderspruch im Text erkennen | CORE2-04, WRK-10, WRK-11, R5B-01 | S |
| 5 | Tageswechsel und Neuberechnung: Datum im Aktualisierungsschlüssel, Summen nach dem Bearbeiten, Widgets nach Mitternacht | IOS2-01, IOS2-02, IOS1-02, R3C-02, R3C-03 | S |
| 6 | Eine Tagesampel für alle Reiter, kein Grün ohne Daten, Schlafphasen als Episode bewerten, Schwellen ungerundet prüfen | R2A-01, R2A-02, CORE2-06, R5A-01, CORE2-05 | M |
| 7 | Soll/Ist und Trainingstage korrigieren: geplanter Tag aus dem echten Plan, keine Doppel-Abhaken durch Garmin-Rückläufer, Spaziergänge zählen nicht als Einheit | R2D-01, R4A-01, R4A-06, R4B-06 | M |
| 8 | Sicherung/Wiederherstellung als Datei, „Alle Daten löschen“, Speicherfehler sichtbar machen, `VersionedSchema` | MKT-1, R3B-02, R2B-04, R2B-05, R2B-06, R3B-01 | M |
| 9 | Garmin stabilisieren: eine Token-Erneuerung gleichzeitig, 429 mit Backoff statt „neu anmelden“, Abruf je Quelle, keine Doppel-Einheiten | IOS1-05, CORE2-03, CORE2-07, CORE2-02, R4B-01, R4B-02 | M |
| 10 | Barrierefreiheit: Kontraste, Status nicht nur über Farbe, Charts für VoiceOver, Pausenende hörbar | IOS1-16, R2C-01, R2C-02, R2C-03, R2C-04 | M |

## Alleinstellungsmerkmale

Details, Gegenbelege und Quellen stehen in `02-paritaetsmatrix.md`, Abschnitt 4.

- **Training, Erholung, Ernährung und Gym in einer App, ohne Bezahlschranke.** Garmin verknüpft Ernährung erst seit 01/2026 und nur in Connect+.
- **Regeln entscheiden, KI formuliert, Quelle je Regel.** Die großen KI-Coaches liefern LLM-Antworten ohne Quelle je Regel.
- **Offline-Nährwerte aus BLS 4.0** statt nutzergenerierter Datenbanken.
- **Manueller KI-Coach** mit Export und Import samt Regelprüfung.
- **Datenschutzarchitektur ohne eigenen Server**, sobald Maßnahme 3 umgesetzt ist.
- **Adaptiver Verbrauch** nach MacroFactor-Art ohne Abo; es fehlt nur der Check-in-Ablauf.

Den Vorsprung vergrößern vor allem domänenübergreifende Regeln, die keine Einzelapp bieten kann: Schlafmangel pausiert das
Defizit (R2D-I03), „krank“ wirkt auf Plan und Ziele (R2D-I04), Kohlenhydrate am Vortag harter Einheiten (R2D-I02), und die Ampel
steuert den Tagestyp (R2D-I13).

## Stopp-Kriterium: nicht erreicht

Du hast verlangt, erst aufzuhören, wenn zwei aufeinanderfolgende Runden nichts Neues mehr bringen. **Das ist nicht erfüllt.** Ich
habe nach fünf Runden abgebrochen, weil das Nutzungskontingent mehrfach erschöpft war, und erkläre deshalb ausdrücklich
nicht, dass es keine weiteren Vorschläge gibt.

| Runde | Blickwinkel | Neue Befunde (iPhone + Worker) | Neue Ideen |
|---|---|---|---|
| 1 | Bestandsaufnahme nach Dimensionen | 118 (+ 31 Android) | 28 |
| 2 | Neuling, ohne Garmin, Power-User, unerwartetes Verhalten, Sehbehinderung, offline, beide Profilmodi, Profi-Coach | 43 | 35 |
| 3 | Nur Ernährung, 65+, Datenschutz, SideStore-Release, Systemintegration, Querschnitt | 23 | 12 |
| 4 | Bisher nicht zitierte Dateien (rund 6.000 Zeilen) | 24 | 4 |
| 5 | Zyklus, Schichtarbeit, Mikrotexte, KI-Fallback, Gegenprüfung | 16 | 8 |

Die Zahl sinkt, die Schwere auch: Runde 5 brachte noch einen hohen Befund (R5A-01), die übrigen sind Mittel oder Niedrig. Dass
Runde 4 wieder anstieg, lag an bisher ungelesenem Code. Inzwischen ist bis auf drei kleine Dateien (zusammen 80 Zeilen) jede
Quelldatei in mindestens einem Bericht zitiert. Zitiert heißt nicht fehlerfrei geprüft. Weitere Runden würden nach diesem Verlauf
vermutlich weitere, überwiegend kleinere Punkte finden. Was grundsätzlich nicht prüfbar war, steht in `05-offene-punkte.md`.

## Dateien

| Datei | Inhalt |
|---|---|
| `01-befunde.md` | alle Befunde, nach Schwere sortiert, Android getrennt |
| `02-paritaetsmatrix.md` | Wettbewerbsvergleich mit Quellen |
| `03-ideen.md` | eigene Vorschläge, priorisiert |
| `04-roadmap.md` | Verteilung auf PRs und Phasen |
| `05-offene-punkte.md` | nicht Verifizierbares, Annahmen, Rückfragen |
| `06-inventar.md` | Inventar aus Phase 1 (Anhang) |
| `tests/` | App-Tests, die nur im Simulator laufen |
