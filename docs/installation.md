# Installation für Familie und Freunde (iPhone und Android)

Für Personen, denen du (Betreiber:in des Workers) die App gibst. Alles läuft über deinen Cloudflare Worker und die
dort hinterlegten Zugänge – niemand braucht ein eigenes Konto bei Cloudflare, GitHub oder einem KI-Anbieter.

| | iPhone: IronLudi (volle App) | Android: IronLudi Gym |
|---|---|---|
| Inhalt | Training, Ernährung, Gym, Garmin, KI-Coach, Widgets | Gym-Logging: Trainings, Pläne, 59 Übungen mit Anleitung, Steigerungsvorschläge, Pausentimer, Sicherung |
| Was du schickst | 1. SideStore-Link, 2. Einladungslink (Gastzugang für KI und Rangliste) | 1 Link zur Download-Seite |
| Wo du den Link findest | iPhone-App › Einstellungen › KI-Worker › „SideStore-Quelle teilen“; Einladung unter Einstellungen › Begleiter & Rangliste | iPhone-App › Einstellungen › KI-Worker › „Android-App teilen“ |
| Einmaliger Aufwand | ca. 30–45 min, braucht einmal einen Windows-PC oder Mac und eine eigene Apple-ID | ca. 3 min, nur das Handy |
| Laufend | alle 7 Tage in SideStore auffrischen (kostenlose Apple-ID) | nichts; Updates bei Bedarf über dieselbe Seite |
| Internet / Daten | Daten bleiben auf dem iPhone, KI über deinen Worker | komplett offline, Daten bleiben auf dem Handy |

Die Links sind **privat**: Wer sie hat, kann die App laden. Nur an Vertraute schicken, nicht öffentlich posten.

## Android (z. B. für deinen Bruder)

**Du:** In der iPhone-App unter Einstellungen › KI-Worker auf **„Android-App teilen“** tippen und den Link per
Messenger schicken. (Der Knopf erscheint nur mit deinem Haupt-Token, nicht bei Gästen.)

**Auf dem Android-Handy:**

1. Den Link im Browser (Chrome) öffnen › **„App herunterladen“**.
2. Die Datei öffnen (Benachrichtigung „Download abgeschlossen“ oder App „Dateien“ › Downloads).
3. Fragt Android: *„Aus Sicherheitsgründen ist die Installation unbekannter Apps aus dieser Quelle nicht
   zulässig“* › **Einstellungen** › „Dieser Quelle vertrauen“ bzw. „Zulassen“ einschalten › zurück ›
   **Installieren**.
4. Warnt **Google Play Protect** („App nicht geprüft“ bzw. „Unbekannter Entwickler“): **Weitere Details** ›
   **Trotzdem installieren**. Die App hat keine Internet-Berechtigung und liest keine anderen Daten.
5. **IronLudi Gym** öffnen › „Freies Training starten“ oder unter „Pläne“ einen Plan anlegen.

**Aktualisieren:** Denselben Link wieder öffnen und die neue Version genauso installieren. Die Trainings bleiben
erhalten. Die Version steht in der App unter Training › Zahnrad › Über.

**Sicherung:** Training › Zahnrad › **„Sicherung speichern“** (z. B. in Google Drive). Auf einem neuen Handy:
App installieren › „Sicherung einspielen“. Zusätzlich sichert Android die Daten automatisch im Google-Konto,
wenn in den Android-Einstellungen „Sicherung“ an ist.

**Wenn es hakt:**
- *„App nicht installiert“* beim Aktualisieren: Die neue Version ist anders signiert (sollte nicht vorkommen).
  Erst „Sicherung speichern“, dann alte App deinstallieren, neu installieren, „Sicherung einspielen“.
- *„Noch keine Android-Version hochgeladen“* auf der Seite: Der erste Build läuft noch oder der
  Signaturschlüssel fehlt in GitHub (siehe `docs/android.md`).

## iPhone

**Du schickst zwei Dinge:**
1. den **SideStore-Link** (iPhone-App › Einstellungen › KI-Worker › „SideStore-Quelle teilen“) und
2. einen **Einladungslink** für KI und Rangliste: Einstellungen › Begleiter & Rangliste › Rangliste erstellen (falls
   noch keine) › **„Einladungslink erstellen“** › teilen. **Für jede Person einen eigenen Link** – jeder enthält
   einen eigenen Gastzugang, nicht dein Token.

**Die Person macht (einmalig, mit PC oder Mac):**

1. SideStore einrichten wie in [`docs/sidestore.md`](sidestore.md), Abschnitt „Einmalig: SideStore einrichten“
   (LocalDevVPN, iloader, eigene Apple-ID, Entwicklermodus).
2. SideStore › **Sources** › „+“ › deinen SideStore-Link einfügen › „IronLudi (privat)“ › **IronLudi** installieren.
3. IronLudi öffnen und das Profil einrichten.
4. Deinen **Einladungslink** antippen (z. B. in WhatsApp/iMessage) › IronLudi öffnet sich, übernimmt Worker und
   Gastzugang und tritt der Rangliste bei. Damit funktionieren KI-Coach, Fotoanalyse und Rangliste.
5. Optional Garmin: eigener kostenloser Garmin-Key (Einstellungen › Garmin, Anleitung in `docs/einrichtung.md`,
   Schritt 1) – jeder nutzt sein eigenes Garmin-Konto.

**Laufend:** Spätestens alle 7 Tage SideStore öffnen (LocalDevVPN verbunden) und auffrischen, sonst startet die App
nicht mehr. Updates meldet SideStore („New Update Available“) und installiert sie mit einem Tippen.

## Wie vielen Leuten kann ich das geben?

| Begrenzung | Wert | Bedeutung |
|---|---|---|
| Android-Link | keine feste Grenze | Die App läuft offline; der Worker liefert nur die Datei aus. Kostenloser Cloudflare-Plan: 100.000 Aufrufe und 100.000 KV-Lesezugriffe am Tag – reicht für Hunderte Downloads täglich. |
| SideStore-Link (iPhone) | keine feste Grenze | Jede Person installiert mit **ihrer eigenen** Apple-ID (je 3 aktive Apps, 10 neue App-IDs pro Woche – betrifft nur ihr eigenes Gerät). |
| KI (iPhone) | **realistisch 5–10 aktive Personen** | Alle teilen deine kostenlosen KI-Kontingente (Gemini, Groq, Workers AI mit 10.000 Neurons am Tag). Bei mehr Nutzung kommen Fehlermeldungen „KI nicht verfügbar“, bis die Kontingente am nächsten Tag zurückgesetzt sind; es gibt noch keine Begrenzung je Person. |
| Rangliste | 20 Personen je Rangliste, rund 500 Abgleiche am Tag insgesamt | kostenlose Workers-KV-Grenzen (1.000 Schreib- und 1.000 List-Zugriffe am Tag) |
| Garmin | keine | jede Person nutzt ihren eigenen Garmin-Key |

**Kurz:** Den Android-Link und den SideStore-Link kannst du praktisch beliebig vielen Vertrauten geben. Die
Grenze ist die KI: Mit den kostenlosen Kontingenten bleibt es bei einer Handvoll Personen, die sie täglich
nutzen. Einen Gastzugang entziehst du über die Worker-Variable `REVOKED_GUESTS` oder indem du das Haupt-Token
wechselst (`docs/qualitaet-paket8.md`, Abschnitt 7).
