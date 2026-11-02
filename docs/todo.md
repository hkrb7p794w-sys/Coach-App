# To-do

## Testlauf auf dem iPhone (mit Alex)

Bisher nur in der CI gebaut und mit Beispieldaten geprüft; mit echten Daten noch offen. Gefundene Fehler direkt
hier notieren und als PR beheben.

- [ ] **Garmin-Übertragung der Krafteinheiten:** Einheit in IronLudi beenden → erscheint sie in Garmin Connect als
      Krafttraining mit Übungen, Wiederholungen und Gewicht? Doppelt, wenn die Uhr mitläuft?
- [ ] **Mahlzeit teilen:** Mahlzeit lange drücken › „Teilen …“ → Nachricht an die zweite Person; Link öffnet
      IronLudi mit Vorschau? „In mein Tagebuch“ legt einen neuen Eintrag an, Mengen und Nährwerte stimmen?
      „Freigabe zurückziehen“ → Code danach unbekannt?
- [ ] **Mahlzeiten-Erinnerungen:** Einstellungen › Ernährung: Mittagessen 12:30 an → Mitteilung kommt, außer das
      Mittagessen ist schon eingetragen? Zeit ändern → neue Zeit gilt? Zeitzone wechseln (Reise) → Ortszeit?
- [ ] **Übersicht anpassen:** Ernährung › „Übersicht anpassen“: Tagesübersicht einschalten, Karten verschieben –
      Reihenfolge bleibt nach Neustart?
- [ ] **Foto ergänzen:** Teller mit Reis, Gemüse und Hähnchen fotografieren → fehlt etwas? Unter „Fehlt etwas?“
      „noch 150 g Hähnchenbrust und 1 EL Olivenöl“ → zwei neue Positionen, die alten unverändert? Hinweis-Knöpfe
      („+ Bratöl“) sinnvoll?
- [ ] **Schnell erfassen und Portion:** „+“ › oben Zuletzt/Häufig/Rezepte/Favoriten – „+“ trägt sofort ein? Mahlzeit
      lange drücken › „Als Favorit merken“, erscheint unter Favoriten? Eingetragene Mahlzeit öffnen › Gegessen 75 % →
      kcal sinken auf 75 %, danach 100 % stellt alles wieder her? Rezept bleibt unverändert?
- [ ] **KI-Export und Prompts:** AI › Daten exportieren: nur Gym und Schlaf wählen → Datei enthält nur diese? JSON
      und CSV lassen sich teilen? AI › Prompt-Bibliothek › Trainingsanalyse kopieren und in ChatGPT/Gemini einfügen:
      Antwort in der Gliederung, fehlende Daten genannt? Eigenen Prompt anlegen und wieder öffnen.
- [ ] **Reiter „AI“:** Plan jetzt unter Training › Plan? Empfehlungen erscheinen (z. B. Stillstand im Gym), Wischen
      setzt „umgesetzt“/„verworfen“, Zahl am Reiter stimmt. „Alles analysieren“ liefert belegte Empfehlungen ohne
      Quellenangaben im Text; „Worauf beruht das?“ zeigt die Grundlage. Mit wenig Daten: fehlende Daten genannt?
- [ ] **KI-Stufen und Anbieter:** Einstellungen › KI: „Nur auf Anfrage“ → beim Öffnen von „Heute“ keine KI-Notiz,
      „Neu formulieren“ geht. „Aus“ → Mahlzeit beschreiben meldet „KI ist ausgeschaltet“, Export geht. „Datenschutz
      zuerst“ → Anbieter und Nutzung zeigt Workers AI. Nach dem Worker-Deploy: Workers AI als „eingerichtet“?
- [ ] **BLS-Nährwerte:** Mahlzeit beschreiben („2 Eier gekocht, Vollkornbrot mit Butter, Kaffee mit Milch“) →
      Positionen mit Quelle „BLS 4.0“ statt „geschätzt“? Passt der zugeordnete BLS-Eintrag (Position öffnen)?
      Falsche Zuordnungen hier notieren. Suche im Ernährungsreiter zeigt BLS-Treffer?
- [ ] **Apple Health:** Einstellungen › Apple Health einschalten, Berechtigungen erteilen → Schlaf mit Phasen,
      Ruhepuls, Schritte, Workouts und Gewicht sichtbar? Keine doppelten Aktivitäten neben Garmin?
- [ ] **GymBook-Import:** Backup auswählen → 174 Einheiten seit Februar 2024? Charts, 1RM und Rekorde je Übung
      plausibel? Zweiter Import legt nichts doppelt an?
- [ ] **Erinnerungen:** Trainingstag morgens, Schwimm-Ausrüstung am Vorabend um 18 Uhr, sonntags „Nächste Woche
      planen“ (Antippen öffnet die Wochenplanung). Nach einem erledigten Training: entfällt die Erinnerung?
- [ ] **„Heute“ nach dem Aufräumen:** Ist alles Wichtige oben, fehlt etwas unter „Diese Woche, Ziele und Verlauf“?
- [ ] **Garmin-Login und Tageswerte:** Werte vollständig (Gewicht, Schlafzeiten, HRV)? Fehler in der
      Garmin-Diagnose?
- [ ] **KI-Funktionen:** Coach-Notiz, Gym-Tipps, KI-Trainingsplan, Chat – Antworten sinnvoll, keine erfundenen
      Zahlen?
- [ ] **Gym im Training (Fokus-Karte):** Einheit starten → Satz erledigt springt richtig weiter, Ziffernblock und
      ± Knöpfe gut treffbar, Pause mit RIR-Frage, Rückgängig nach Ent-Haken, Beenden mit vergessenen Sätzen.
- [ ] **Satzarten und Supersätze:** Aufwärmsätze einfügen (zählen nicht für Volumen/Rekorde), Supersatz A1/A2 ohne
      Pause dazwischen, Später/Ersetzen/Reihenfolge, Klimmzug mit Unterstützung, Rückfrage bei 625 kg.
- [ ] **Start und Auswertung:** Karte „Nächste Einheit“ schlägt die richtige Routine vor; Abschluss mit Vergleich und
      „Nächstes Mal“; Auswertung mit Kalender und Serie.
- [ ] **Ernährung schnell eintragen:** Vorschläge zur Tageszeit und „wie gestern“ mit einem Tipp, Suche, gestern
      nachtragen, Rest-Ring, nur Kalorien, Wasser-Knopf, Rückgängig.
- [ ] **Ernährung Entwurf:** Portionen (Scheibe, Riegel), ± je Zeile, „danach … übrig“, Rezept über den Entwurf,
      Foto + Text in einem Schritt, unbekannter Barcode (Etikett fotografieren).
- [ ] **Ernährung Planung:** „Was esse ich jetzt?“, Meal-Prep mit Vorrat, ohne Netz (Flugmodus) und danach
      automatisch ausgewertet, Woche, Einkaufsliste nach Abteilung mit „Habe ich da“, großes „+“ unten.
- [ ] **Training Soll/Ist:** Plan-Reiter zeigt je Einheit „erledigt/teilweise/anders gemacht/verpasst“ mit Soll/Ist,
      Summen je Sportart, Wischen (auslassen/verschieben); Karte „Verpasst“ auf Heute; Training nachtragen und löschen.
- [ ] **Gym-Einstellungen:** Pausen je Übung und Standard, „Pause starten“ ohne Automatik, Aufwärm-Vorschlag
      abschaltbar, Abhaken nach Eingabe; Einstellungen › Disziplinen (Gym, Laufen, Rad, Schwimmen, Ernährung, Schlaf).
- [ ] **Training Verlauf:** Aktivitäten zeigt Gym-App + Garmin-Kraft einmal; Karte „Nach dem Training“ (1–10,
      „Übernehmen“ ändert morgen auf locker, „Rückgängig“); „Warum?“ im persönlichen Profil; Zonenbalken im Detail.
- [ ] **Gym Stoppuhr:** Plank: Start, Zeit läuft gegen das Ziel, Stopp übernimmt und startet die Pause, ±1/±5 s
      korrigieren; Pausenkarte einklappen und wieder groß machen.
- [ ] **Training Heute:** „Jetzt dran“ oben (Einheit mit Soll, Ampel, Widerspruch bei gelber Ampel und hartem Plan),
      Vorschlag „Übernehmen“/„Rückgängig“/„Anpassen“/„Verwerfen“, Wochenbalken, Chips; sonntags Wochenrückblick;
      Training › Trends (Zoom); Aktivitäten filtern und suchen. Stimmen Wochenbelastung und Form mit Garmin überein?
- [ ] **Mahlzeit diktieren:** Erfassen › „Sprechen“: Erlaubnis-Abfragen, Text erscheint live, „Fertig gesprochen“,
      vorhandener Text bleibt davor; Hinweis „auf dem iPhone“ oder „Apple“; danach Analysieren.
- [ ] **Gym Ablauf (Paket 1 A):** letzter Satz → Blatt „Plan geschafft“ (beenden/fortsetzen/Übung dazu); Pausen-
      Mitteilung „Weiter mit …“; Karte „Danach“; Überspringen und Nachholen; während des Trainings keine
      Trainingserinnerung; Gewicht eines Satzes ändern lässt die anderen Sätze unverändert; Ziffernblock ersetzt den
      alten Wert; „Zuletzt“ mit 5 Einheiten; Sperrbildschirm: Gewicht/Wdh. −/+ ohne Entsperren; Kabel-Crunch zeigt
      „65 kg“ statt „+65 kg Zusatz“.
- [ ] **Gym Muskeln (Paket 1 B):** Gym › „Trainingspläne“ oben; Plan bearbeiten: „Reihenfolge ändern“ (ziehen),
      Heatmap des Plans; Übungen: Muskel-Chips filtern, Körperkarte in der Übung; nach dem Speichern Heatmap der
      Einheit; Auswertung › Muskeln: 7 Tage / Ø 4 Wochen / Erholung. Passt die Zuordnung der eigenen Übungen?
- [ ] **Gym und Garmin (Paket 1 C):** Einheit mit Uhr aufzeichnen und in der App loggen → nach dem Speichern bzw.
      nächsten Abruf in Garmin Connect *eine* Aktivität mit Kalorien, Puls und Sätzen; Einheit › „Garmin Connect“
      zeigt den Status; „Ursprüngliche Sätze wiederherstellen“; ohne Uhr nach 3 h eigene Aktivität. Werden die
      Übungsnamen in Connect richtig angezeigt? Alte Doppelte zählen in Verlauf und Kalorien nur einmal.
- [ ] **Live-Aktivität:** Installiert SideStore die App mit Widget-Erweiterung (2 App-IDs)? Pause auf dem
      Sperrbildschirm, „Satz erledigt“ ohne Entsperren, endet nach dem Beenden.

- [ ] **Garmin-Übungsnamen:** Einheit › Garmin Connect › „Sätze erneut übertragen“ → in Garmin Connect Übungen statt
      „Unbekannt“, Satzdauer realistisch. Welche eigenen Übungen landen noch falsch?

## Gestrichen

- Watch-App fürs Gym (Entscheidung von Alex, 27.10.2026).
