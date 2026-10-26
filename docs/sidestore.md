# Coach auf dem iPhone installieren (SideStore, Windows)

Quelle: offizielle SideStore-Doku (<https://docs.sidestore.io>, Abschnitte „Prerequisites“ und „Install“).

## Einmalig: SideStore einrichten

Du brauchst: iPhone mit Code-Sperre, Windows-PC (64 Bit), USB-Kabel, WLAN, Apple-ID.

**Auf dem iPhone**
1. Im App Store **LocalDevVPN** installieren, öffnen, „Connect“ tippen und die VPN-Konfiguration erlauben.

**Auf dem Windows-PC**
2. **iTunes** direkt von Apple installieren: <https://www.apple.com/itunes/download/win64>
   (falls das nicht klappt: die App „Apple-Geräte“ aus dem Microsoft Store).
3. **iloader** installieren: <https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi>
4. iPhone per USB anschließen, auf dem iPhone „Vertrauen“ tippen und Code eingeben.
5. iloader öffnen, mit der Apple-ID anmelden (Groß-/Kleinschreibung beachten), iPhone auswählen,
   „Install SideStore (Stable)“ wählen.

**Wieder auf dem iPhone**
6. Einstellungen › Allgemein › VPN & Geräteverwaltung › unter „Entwickler-App“ deine Apple-ID ›
   „Vertrauen“ › „Erlauben & Neustarten“, Code eingeben.
7. Einstellungen › Datenschutz & Sicherheit › ganz unten **Entwicklermodus** einschalten (iPhone startet neu).
8. LocalDevVPN öffnen › „Connect“.
9. SideStore öffnen, mit derselben Apple-ID anmelden.
10. „My Apps“ › bei SideStore auf „7 DAYS“ tippen (erste Auffrischung). Fragt SideStore nach einem neuen
    Zertifikat: „Yes“ bzw. „Refresh Now“.

## Coach über die private Quelle installieren (einmalig) – danach Updates per Hinweis

Jeder Merge auf `main` baut automatisch eine neue Version (`vX.Y.<Build>`). Weil das Repo privat ist, liefert
der Cloudflare Worker `coach-ai` App und Quelle aus (Workers KV, `worker/src/sidestore.ts`). Der Link enthält
einen geheimen Pfad, den die App aus dem App-Token berechnet. SideStore prüft eingetragene Quellen im Hintergrund
und meldet neue Versionen („New Update Available“); installiert wird mit einem Tippen. Ganz ohne Tippen geht es
nicht: SideStore installiert Updates nicht von selbst, die Hintergrundprüfung schickt nur die Mitteilung
(SideStore-Quellcode `AppDelegate.performBackgroundFetch`, Stand 16.10.2026).

1. In Coach › Einstellungen › KI-Worker auf **SideStore-Quelle kopieren** tippen (erscheint, sobald
   Worker-Adresse und App-Token gespeichert sind).
2. LocalDevVPN verbinden.
3. SideStore › **Sources** › „+“ › Link einfügen. Eine alte Quelle „Coach (privat)“ mit `github.com`-Adresse
   vorher entfernen – sie funktioniert nicht mehr, seit das Repo privat ist.
4. In der Quelle „Coach (privat)“ › **Coach** › installieren bzw. aktualisieren. Die vorhandene App wird
   ersetzt, die Daten bleiben erhalten (gleiche App-ID).
5. SideStore › Settings: **Background Refresh** einschalten und Mitteilungen für SideStore erlauben.
6. Kommt die Mitteilung „New Update Available“: SideStore öffnen › „My Apps“ › bei Coach **Update**.

Den Link nur an Vertraute weitergeben: Wer ihn hat, kann die App laden (Garmin- und KI-Zugänge stecken nicht
darin, die gibt jeder in seiner App selbst ein).

## Gut zu wissen

- Mit kostenloser Apple-ID laufen Apps **7 Tage**. SideStore frischt sie auf, solange LocalDevVPN verbunden
  ist. Spätestens alle 7 Tage einmal SideStore öffnen und auffrischen.
- Höchstens **3 Apps** gleichzeitig (SideStore zählt mit) und **10 neue App-IDs pro Woche**.
- Nach einem iOS-Update kann die Pairing-Datei ungültig werden. Dann in iloader neu erzeugen
  (SideStore-Doku „Pairing File“).
