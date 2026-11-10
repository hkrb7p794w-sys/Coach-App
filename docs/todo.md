# To-do

## Testlauf auf dem iPhone (mit Alex)

Bisher nur in der CI gebaut und mit Beispieldaten geprüft; mit echten Daten noch offen. Gefundene Fehler direkt
hier notieren und als PR beheben.

- [ ] **Paket 9:** Erfassen: Kamera, Foto, Barcode, Manuell, Nur kcal ohne Scrollen sichtbar, Vorschläge darunter. Rezeptideen: Woche
      erstellt alle Tage. Kochen planen: Freigabe auf beiden iPhones, Link öffnen, „Für uns beide“, Teller und Gesamtmengen plausibel,
      Zutat ändern rechnet neu, Freigabe zurückziehen löscht beim anderen Gerät beim nächsten Abruf.
- [ ] **Paket 10 (Gym):** Training beenden: Ergebnis statt weißem Bildschirm. Aufwärmsätze vorschlagen und ändern, zählen nicht ins Volumen. Pausenton und
      Vibration: einmal, pünktlich, nach Abbruch keiner. Sperrbildschirm zeigt Pause und nächsten Satz. KI-Plan: Zusammenfassung vor dem Senden.
- [ ] **Paket 11 (Einstellungen):** Bereiche übersichtlich? Schlaf: Bundesland wählen, freie Tage und Feiertag zeigen eine andere Schlafenszeit, gestellter Wecker
      (iOS 26) ändert sie. Pause: Übungswert, Planwert, Einstellung; Anzeige, Timer und Mitteilung gleich.
- [ ] **Paket 12 (Chat):** „Wie hat sich mein Bankdrücken entwickelt?“, „Wie viel Protein fehlt mir heute noch?“, „Sollte ich heute schwer trainieren?“, danach
      „Und was bedeutet das für mein Training morgen?“: stimmen die Antworten mit deinen echten Daten? KI aus oder offline: verständliche Meldung? AI-Reiter: Filter nach Bereichen.
- [ ] **Phase 75:** Einladungslink: Server wird vor dem Beitreten angezeigt? Worker-Adresse auf einen anderen Server ändern, ohne Token einzugeben: altes Token weg?
- [ ] **Phase 77:** App über Mitternacht offen lassen, um 00:05 eine Mahlzeit eintragen: landet am neuen Tag? Ältere Mahlzeit von 100 auf 150 g ändern: Ring und Widget gleich? Ohne Uhr: graue Ampel statt grün? Heute, Gym, Ernährung und Morning Report zeigen dieselbe Stufe? Nachtschicht oder Ausschlafen bis nach 10 Uhr: Schlaf vollständig?
- [ ] **Phase 78:** Krafteinheit in der App mit Garmin-Upload: nur eine Einheit abgehakt? Spaziergang füllt weder Wochenbalken noch Rangliste? Bei roter Ampel sinkt das Ernährungsziel? Zwei nachgetragene Einheiten um 18 Uhr bleiben beide erhalten?
- [ ] **Schutzgrenzen (Phase 74):** Profil mit „Schwanger“ oder „Essstörung“: Gewichtsverlauf ohne Kalorienvorschläge, Chat und
      Rezepte ohne „Abnehmen“. Wägung unter BMI 18,5 eintragen: Ziel auf „halten“. Zielgewicht erreichen: Hinweis und kein
      Defizit mehr. Einstellungen zeigen „Ernährung: …“ passend.
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
- [ ] **Dunkelmodus:** Einstellungen › Darstellung „Dunkel“ → alle Reiter, Sheets und Daisy gut lesbar; zurück auf „Wie System“ folgt sofort dem iPhone.
- [ ] **Einladung (Paket 8):** Begleiter & Rangliste › „Einladungslink erstellen“ › teilen → zweites iPhone tritt bei, Rangliste zeigt beide; dort keine SideStore-Quelle und kein Einladungsknopf, nur der Code. **Falls früher schon Links verschickt:** Haupt-Token wechseln (`docs/qualitaet-paket8.md`, Abschnitt 7).
- [ ] **Android (IronLudi Gym):** Zuerst die Secrets `ANDROID_KEYSTORE_PASSWORD`/`ANDROID_KEYSTORE_B64` setzen (`docs/android.md`). Dann iPhone › Einstellungen › KI-Worker › „Android-App teilen“ → Link auf Android öffnen, installieren; Training mit Plan, Satz abhaken (Pause vibriert), beenden → Verlauf; nach zweitem Training „Erhöhen auf …“-Vorschlag; Sicherung speichern/einspielen; ein Update über denselben Link behält die Daten.
- [ ] **Android Ernährung:** iPhone › „Android-Link erstellen“ → auf Android „In der App verbinden“ → „KI-Zugang verbunden“. Ernährung › Zahnrad: Körperwerte, Wochentage. Erfassen: Text „2 Eier, 1 Scheibe Vollkornbrot“ → Entwurf mit BLS-Werten; Foto (Kamera/Galerie); Barcode scannen (Joghurt) → Produkt; Suche „Haferflocken“; Speichern → Ringe/Balken; „Wie gestern“ am nächsten Tag; Wasser +250 ml; Portion 50 %; Favorit.
- [ ] **Android Ernährung Teil 2:** Mahlzeit ⋮ › „Als Rezept speichern“ → Rezepte & Woche: Portionen/gekochtes Gewicht, „Gekocht“ → Vorrat, „1 Portion eintragen“ zählt herunter. „Was esse ich jetzt?“ → 3 Gerichte, Tippen = Entwurf. Wochenplan erstellen (Allergene wählen) → Einkaufsliste nach Abteilung abhaken. „Tag auswerten“. Gewicht eintragen (nach 2 Wochen Trend). ⋮ › Teilen → Link auf dem iPhone öffnen. Erinnerung Mittag 12:30 → kommt nur ohne Eintrag. Flugmodus + Foto → „ohne Netz gespeichert“ → online „Jetzt auswerten“.
- [ ] **Mahlzeiten-Widget und Wasser (iPhone):** Erfassen › blauer Knopf zeigt Kamera-Symbol. Kaffee und Suppe eintragen → Wasser steigt, „davon … aus Essen“. Sperrbildschirm › Widgets › IronLudi „Mahlzeiten“ → vier Werte; Homescreen mittelgroß → „+“ bei Mittag öffnet Erfassen mit „Mittagessen“ vorgewählt.
- [ ] **Schnellaktionen (Paket 7 A):** Nach dem ersten Öffnen lange aufs App-Icon drücken → „Training starten“,
      „Mahlzeit erfassen“, „Health öffnen“, „KI-Analyse starten“. Jede springt in den richtigen Reiter, auch bei
      geschlossener App. Spotlight/Kurzbefehle-App: „Training starten in IronLudi“. Funktionieren Einladungs- und
      Mahlzeit-Links weiter?

- [ ] **Homescreen-Widgets (Paket 7 B):** Installiert SideStore die App mit App Group? (Sonst bricht SideStore mit
      einem App-Group-Fehler ab → melden.) Widgets „Heute“, „Ernährung“, „Health“, „Gym“ hinzufügen und per „Widget
      bearbeiten“ umstellen; Werte wie in der App? „+250 ml“ im mittleren Ernährungs-Widget zählt sofort, nach dem
      Öffnen der App steht der Eintrag im Tagebuch (genau einmal). Sperrbildschirm: kcal-Ring, Body Battery. Am
      nächsten Morgen ohne Öffnen: 0 kcal, „Neuer Tag – App öffnen“.
- [ ] **GitHub-Models-Token erneuern (spätestens Nov. 2027):** Fine-grained Token `coach-models` läuft nach 366 Tagen
      ab. Neuen Token mit „Models: Read-only“ anlegen und das Secret `GH_MODELS_TOKEN` ersetzen, dann Actions › Worker
      › Run workflow (`docs/einrichtung.md`, Schritt 2).

- [ ] **Datensicherung (PR 97):** Einstellungen › Datensicherung › „Ordner wählen“ → iCloud Drive › neuen Ordner
      „IronLudi“ → erste Sicherung erscheint dort als `IronLudi-Sicherung.json`. App schließen → am nächsten Tag
      liegt eine neue Sicherung dort, die alte als „…-vorher.json“. Test Einspielen: Mahlzeit löschen, Sicherung
      einspielen → Mahlzeit ist wieder da, nichts doppelt.

- [ ] **Beschwerden und Urlaub (PR 100):** Gesundheit › Mobility › Beschwerden „Knie“ an → Mobility-Einheit nennt
      „Beschwerden: Knie“; im Training zeigt die Kniebeuge den orangen Hinweis. Einstellungen › Urlaub oder Pause für
      die nächsten Tage → keine Erinnerung, „Jetzt dran“ zeigt die Pause, nach der Pause keine „verpasst“-Karte für
      diese Tage.

- [ ] **An die Uhr senden (PR 101):** Heute › „Jetzt dran“ › Laufeinheit › „An die Uhr senden“ › Tag › Senden →
      erscheint im Garmin-Connect-Kalender, nach dem Uhren-Sync als Training auf der Uhr (Schritte wie in der
      Vorschau, Pace als Notiz). Nochmals senden → kein doppeltes Workout. Schwimmeinheiten des Saisonplans zeigen
      keinen Knopf (macht weiter das Add-on).

- [ ] **Nutzung je Person:** Nach dem Deploy `curl -H "Authorization: Bearer <HAUPT-TOKEN>" https://<worker>/v1/usage/all`
      → zeigt die Nutzung der letzten Tage. Mit `AI_GUEST_DAILY_LIMIT=2` testweise: dritte Anfrage eines Gastes zeigt
      in der App „Dein KI-Tageslimit (2 Anfragen) ist erreicht“.

- [ ] **Konten (PR 91):** Einstellungen › Konto › „Konto erstellen“ (mit App-Token ohne Code) → Wiederherstellungscode
      erscheint einmal. „Neue Einladung erstellen“ › an ein zweites Gerät schicken › Link öffnen › „Auf dem iPhone“
      bzw. „Auf Android öffnen“ → Registrieren mit vorausgefülltem Code. Falsches Passwort 5× → „15 Minuten“.
      Passwort ändern → anderes Gerät ist abgemeldet und zeigt das in den Einstellungen.

- [ ] **Freunde (PR 92):** Zwei Konten: A sucht B über „@b…“ › Hinzufügen; B nimmt an. A teilt nach dem Gym
      „Mit Freunden teilen“ → B sieht es im Feed, reagiert mit 🔥 und kommentiert. A teilt eine Mahlzeit → B
      „In mein Tagebuch übernehmen“. Freundschaft beenden → Beiträge verschwinden bei B.

- [ ] **Wettkampf (PR 93):** Heute zeigt „Fortschritt“ mit Serie und Stufe. Freunde › Wettkampf › „Neue Challenge“
      (Trainingsminuten, diese Woche, Freund einladen) → Freund sieht die Einladung, tippt „Mitmachen“. Nach einem
      Training und dem Öffnen von Heute steigen Minuten und Rangliste; 3 Stunden Training zählen als 90 Minuten.

- [ ] **Aufzeichnungen vollständig (PR 94):** Nach dem Abruf steht in der Meldung „… mit Runden und Verlauf“. Eine
      Aktivität im Flugmodus öffnen → Auswertung, Diagramme, Runden und Kilometer-Splits sind da. Coach fragen „Wie
      war mein letzter Lauf?“ → Antwort nennt Tempo-Einteilung bzw. Puls-Drift. Mit Garmin Connect vergleichen:
      Rundenzeiten und Kilometer-Splits stimmen überein.

- [ ] **Apple Watch (PR 95):** Mit der Apple Watch ein Outdoor-Training aufzeichnen › App öffnen › iOS fragt einmal
      nach „Trainingsrouten“ und Leistung › erlauben. Aktivität öffnen → Karte, Diagramme (Puls, Tempo, Höhe),
      Kilometer-Splits und Auswertung sind da; Splits mit der Fitness-App vergleichen. Workout mit Pause → Standzeit
      stimmt.

- [ ] **Widgets im neuen Stil (PR 96):** Mahlzeiten-Widget (mittel) hinzufügen → Kopfzeile mit Flamme und Serie,
      vier Ringe mit „+“ bzw. Haken, Snacks abgesetzt; „+“ öffnet das Erfassen der Mahlzeit. Heute-, Ernährungs-,
      Health- und Gym-Widget sehen gleich aus; in Hell und Dunkel und mit getöntem Homescreen lesbar.

- [ ] **Mahlzeiten auf dem Sperrbildschirm (PR 111):** Einstellungen › Ernährung › „Mahlzeiten auf dem
      Sperrbildschirm“ einschalten › iPhone sperren → farbige Karte in voller Breite mit Flamme und vier Ringen; „+“
      öffnet das Erfassen der Mahlzeit. Mahlzeit eintragen, App verlassen → Ring und Haken stimmen. Am nächsten
      Morgen vor dem Öffnen: Karte ist leer oder weg, nach dem Öffnen wieder aktuell.

## Gestrichen

- Watch-App fürs Gym (Entscheidung von Alex, 27.10.2026).
