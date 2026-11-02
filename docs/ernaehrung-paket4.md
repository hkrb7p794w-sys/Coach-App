# Ernährung, Mahlzeiten und Food-Tracking (Paket 4)

Stand: 02.11.2026. Analyse, Plan in vier PRs, Datenmodell und offene Grenzen.

## Analyse (vorher)

| Bereich | Stand im Code | Lücke |
|---|---|---|
| Datenmodell | `MealRecord` (SwiftData) mit Positionen als JSON (`[MealItem]`), `FoodRecord` für eigene Lebensmittel, `OwnRecipe` in den Einstellungen | Keine Favoriten; Portionsänderung überschreibt die Mengen ohne Rückweg |
| Erfassen | Erfassen-Bildschirm mit Foto, Text, Diktat, Barcode, Schnell-Kalorien, manuell; Schnell-Leiste im Reiter (häufig je Tageszeit, „wie gestern“, Rezepte mit Vorrat) | Zuletzt/Häufig/Rezepte/Favoriten fehlen beim Erfassen selbst |
| Portion | „× ½ / 1½ / 2“ im Entwurf | Bei gespeicherten Einträgen kein „nur 75 % gegessen“ |
| Erinnerungen | Training, Ausrüstung, Wochenplanung, „Tag auswerten“ | Keine Erinnerung je Mahlzeit |
| Foto-Analyse | `meal_analyze` mit Bild und Text, BLS-Zuordnung, Entwurf zum Bearbeiten | Übersehene Bestandteile nur von Hand ergänzbar |
| Dashboard | Kalorienring, Makrobalken, Mahlzeitenliste in fester Reihenfolge | Nicht konfigurierbar |
| Teilen | – | Keine Weitergabe an andere |

## Plan

- **PR A – Schnell erfassen und Portionen:** Schnellauswahl im Erfassen-Bildschirm (Zuletzt, Häufig, Rezepte,
  Favoriten; „+“ trägt mit einem Tipp ein). Favoriten als eigene Vorlagen (`FavoriteMeal`). „Gegessene Menge“ für
  gespeicherte Einträge (25/50/75/100 % oder frei), immer bezogen auf die ursprüngliche Menge (`plannedGrams`).
- **PR B – Foto-Analyse ergänzen:** „Fehlt etwas?“ im Entwurf: per Text („150 g Hähnchenbrust und 1 EL Olivenöl“)
  oder Antippen von Hinweisen auf oft Übersehenes (Öl, Soße, Getränk). Die KI liefert nur neue Positionen; Bestehendes
  wird nie überschrieben. Schätzungen bleiben gekennzeichnet, alles bleibt bearbeitbar.
- **PR C – Erinnerungen und Dashboard:** Essenszeiten je Mahlzeit mit eigenem Schalter; keine Mitteilung, wenn die
  Mahlzeit schon erfasst ist. Konfigurierbare Karten im Ernährungsreiter (ein/aus, Reihenfolge).
- **PR D – Teilen:** Mahlzeit als Link weitergeben (Worker, zeitlich begrenzt); der Empfänger sieht eine Vorschau
  und übernimmt sie in sein Tagebuch. Freundesfunktion bewertet (siehe unten).

## Datenmodell

- **Mahlzeit** (Tagebuch-Eintrag, `MealRecord`) – **Rezept** (`OwnRecipe`, mit Zutaten, Portionen, Vorrat) –
  **Favorit** (`FavoriteMeal`, Vorlage einer Mahlzeit). Drei getrennte Dinge: Eintragen aus Rezept oder Favorit legt
  immer eine Kopie im Tagebuch an.
- **Portionsanpassung** ändert nur den Tagebuch-Eintrag. Je Position steht die ursprüngliche Menge in
  `MealItem.plannedGrams` (JSON, optional – keine SwiftData-Migration); 100 % stellt den Ausgangszustand her.
  Nährwerte je 100 g bleiben, Summen ändern sich also genau proportional.

## Offene Grenzen

- **Homescreen-Widget:** geprüft, nicht umgesetzt – braucht eine App Group, die mit SideStore und kostenloser
  Apple-ID unsicher ist. Die Karten im Reiter zeigen dieselben Werte.
- **Freundesfunktion:** nicht umgesetzt (keine Konten, keine Personendaten beim Worker); Teilen per Code reicht für
  Nutzer derselben Installation. Personen mit eigenem Worker können keine Codes eines anderen Workers abrufen.
- **Erinnerungen:** lokale Mitteilungen werden beim Öffnen und bei Änderungen neu geplant; wird eine Mahlzeit auf
  einem anderen Gerät erfasst, weiß das iPhone es erst nach dem nächsten Öffnen.
- **Foto-Ergänzung:** Die KI schätzt Mengen; genannte Mengen werden übernommen, sonst bleiben es Schätzungen.
- Nicht auf einem Gerät getestet; Prüfpunkte in `docs/todo.md`.
