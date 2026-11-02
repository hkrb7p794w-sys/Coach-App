# Onboarding und Personalisierung (Paket 6)

Stand: 02.11.2026.

## Analyse (vorher)

- `UserProfile` hatte ein einzelnes Ziel `FitnessGoal` (Abnehmen, Muskeln aufbauen, Fitter werden …). Es steuert vor
  allem Ernährung und Gewicht (`GoalRules`, Kalorienziel) und den Wochenplan-Vorschlag (`SchedulePlanner`).
- Die KI bekam nur die Zeile „Ziel: …“ über `ChatContext.lines` (Chat, KI-Analyse, Tagesnotiz).
- Es gab keine Nebenziele, keine Prioritäten und keine Frage nach dem Tracker. Im Saisonplan gab es gar kein Ziel.

## Konzept: eine zentrale Stelle

- **`PersonalGoals`** im Profil: Hauptziel, bis zu zwei Nebenziele, bis zu drei Prioritäten (Reihenfolge =
  Wichtigkeit), gültig ab `since`. Ohne Angabe leitet `Personalization.derived` die Ziele aus dem alten Ziel ab;
  im Saisonplan ist das Wettkampfvorbereitung.
- **`TrackerSetup`** im Profil: ob ein Tracker genutzt wird und welche Anbieter.
- **`Personalization`** (CoachCore, getestet) ist die einzige Stelle, an der aus Zielen und Prioritäten etwas
  folgt. Alle Bereiche fragen dort nach, keiner wertet die Angaben selbst aus.

## Was jede Angabe bewirkt

Keine Angabe wird abgefragt, ohne dass sie etwas ändert:

| Angabe | Wirkung | Wo |
|---|---|---|
| Hauptziel | Wochenplan-Vorschlag: Muskelaufbau/Kraft mindestens 3–4 Krafteinheiten, Ausdauer 2–3 je Ausdauersport, Regeneration/Gesundheit höchstens 2 je Sport; Kürzungsreihenfolge | `SchedulePlanner` |
| Hauptziel + Nebenziele | Richtung für Ernährung und Gewicht (`FitnessGoal`, z. B. Fettabbau + Kraft = „Abnehmen und Muskeln aufbauen“) | Kalorienziel, `GoalRules` |
| Hauptziel | KI-Leitlinie: z. B. Muskelaufbau „Kraftvolumen und Progression bewerten, Ausdauer nur ergänzend“, Wettkampf „periodisieren, Tapering“ | `ChatContext` → Chat, KI-Analyse, Tagesnotiz |
| Nebenziele | mindestens 2 Kraft- bzw. Ausdauereinheiten | `SchedulePlanner` |
| Prioritäten | Reihenfolge der Empfehlungen im Reiter „AI“ (bei gleicher Dringlichkeit) | `InsightInbox.groups` |
| Prioritäten | Standard-Widgets im Gesundheitsbereich (nur solange nicht selbst angepasst) | `HealthDashboard` |
| Prioritäten | KI-Kontext „Prioritäten der Person“ | `ChatContext` |
| Recovery/Gesundheit (Hauptziel oder Top-2-Priorität) | Warnung schon ab 20 % statt 30 % mehr Wochenbelastung | `WeekLoad.check` |
| Tracker | primäres Gerät (Datenquellen), Apple-Health-Import einschalten (auch für WHOOP/Polar über Health), Hinweis zum Verbinden | `SourcePreferences`, `HealthImportService` |

Die Regeln bleiben die Regeln: Prioritäten ändern Reihenfolge, Gewichtung und Vorsicht. Sie ändern weder die
Ampel noch die Schutzgrenzen (`GoalRules`, REDs-Untergrenze).

## Änderungen und Verlauf

- **Ändern:** Einstellungen › Profil › „Ziele & Prioritäten“, in beiden Modi und ohne den Saisonplan zu verlassen.
  Der Tracker ist dort ebenfalls änderbar.
- **Verlauf:** Eine Änderung gilt ab heute (`updateGoals`). Der vorige Stand wandert mit seinem Startdatum in
  `goalHistory`; `goals(on:)` liefert, was an einem Tag galt.
  - Vor der ersten Festlegung gilt das abgeleitete Ziel „seit jeher“.
  - Mehrere Änderungen am selben Tag ersetzen sich.
- **Keine nachträgliche Verfälschung:**
  - Wochenberichte, Gym-Auswertungen und Aktivitäten hängen nicht vom Ziel ab.
  - Gespeicherte KI-Empfehlungen werden nicht neu bewertet.
  - Neue Ziele wirken nur auf künftige Empfehlungen und Vorschläge.

## Onboarding

- **Schritte:** Sportarten › Ziele › Prioritäten (optional) › Wettkampf/Ziele › Erfahrung › Über dich ›
  Wochenplan › Tracker (optional) › Zusammenfassung.
- **Kurz gehalten:**
  - Nebenziele und Prioritäten sind Chips.
  - Prioritäten haben sinnvolle Standards zum Ziel und sind mit „Überspringen“ übergehbar, ebenso der Tracker.
  - Ein Wettkampf als Ziel schaltet die Wettkampfabfrage direkt ein.
- **Tracker:**
  - Garmin wird nach dem Start in den Einstellungen verbunden.
  - Apple Health schaltet den Import direkt ein; WHOOP und Polar laufen über Apple Health.
  - Fitbit ist ehrlich als „derzeit nicht möglich“ markiert (siehe `docs/integrationen.md`).
