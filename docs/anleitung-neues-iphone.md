# AIronLudi auf einem anderen iPhone einrichten

Schritt für Schritt, einmal mit **Windows-PC** und einmal mit **Mac**. Die App kommt nicht aus dem App Store, sondern
über **SideStore** (kostenlose Apple-ID). Das iPhone braucht dafür einmal einen Computer; danach läuft alles am Handy.

**Vorher bereitlegen**
- das iPhone mit Code-Sperre, iOS 18 oder neuer
- ein USB-Kabel
- WLAN
- eine **eigene Apple-ID** der Person (E-Mail und Passwort; bei Zwei-Faktor-Anmeldung muss ein Gerät den Code anzeigen)
- vom Betreiber zwei Links: **SideStore-Link** (Quelle) und **Einladungslink** (KI, Rangliste, Konto)

Dauer: etwa 30 bis 45 Minuten. Reihenfolge: Teil A (Computer, je nach System) › Teil B (am iPhone, für alle gleich) ›
Teil C (App einrichten).

---

## Teil A1 – Windows-PC

1. **Am iPhone:** im App Store **LocalDevVPN** installieren. Öffnen, **Connect** tippen, VPN-Konfiguration erlauben.
2. **Am PC: iTunes** direkt von Apple installieren: <https://www.apple.com/itunes/download/win64>. Klappt das nicht,
   stattdessen die App **Apple-Geräte** aus dem Microsoft Store. (Wichtig: nicht die Microsoft-Store-Version von iTunes
   mit der Apple-Version mischen.)
3. **Am PC: iloader** laden und installieren:
   <https://github.com/nab138/iloader/releases/latest/download/iloader-windows-x64.msi>
4. iPhone per USB an den PC anschließen. Am iPhone **„Diesem Computer vertrauen“ › Vertrauen**, Code eingeben.
5. **iloader** öffnen › mit der Apple-ID der Person anmelden (Groß-/Kleinschreibung beachten, ggf. Code für die
   Zwei-Faktor-Anmeldung eingeben).
6. In iloader das iPhone auswählen › **Install SideStore (Stable)**. Warten, bis „Success“ erscheint.
7. Weiter mit **Teil B**. Das Kabel kann ab jetzt ab.

## Teil A2 – Mac

Auf dem Mac ist **kein iTunes nötig** (der Finder erkennt das iPhone).

1. **Am iPhone:** im App Store **LocalDevVPN** installieren. Öffnen, **Connect** tippen, VPN-Konfiguration erlauben.
2. **Am Mac: iloader** laden: <https://github.com/nab138/iloader/releases/latest>, dort die Datei für macOS wählen
   (`.dmg`, Name enthält „darwin“ oder „macos“; auf Apple-Silicon- und Intel-Macs jeweils die passende bzw. die
   „universal“-Version). Die `.dmg` öffnen und **iloader** in den Ordner **Programme** ziehen.
3. iPhone per USB an den Mac anschließen. Am iPhone **„Diesem Computer vertrauen“ › Vertrauen**, Code eingeben.
4. **iloader** öffnen. Blockiert macOS die App („nicht überprüfter Entwickler“): Rechtsklick auf iloader › **Öffnen** ›
   **Öffnen**, oder Systemeinstellungen › Datenschutz & Sicherheit › unten **Trotzdem öffnen**.
5. In iloader mit der Apple-ID der Person anmelden (ggf. Zwei-Faktor-Code eingeben).
6. In iloader das iPhone auswählen › **Install SideStore (Stable)**. Warten, bis „Success“ erscheint.
7. Weiter mit **Teil B**. Das Kabel kann ab jetzt ab.

---

## Teil B – am iPhone (für Windows und Mac gleich)

1. **Einstellungen › Allgemein › VPN & Geräteverwaltung** › unter „Entwickler-App“ die eigene Apple-ID antippen ›
   **Vertrauen** › **Erlauben & Neustarten**, Code eingeben.
2. **Einstellungen › Datenschutz & Sicherheit** › ganz unten **Entwicklermodus** einschalten. Das iPhone startet neu;
   nach dem Neustart die Nachfrage mit **Einschalten** bestätigen.
3. **LocalDevVPN** öffnen › **Connect**. (Muss bei allen folgenden SideStore-Schritten verbunden sein.)
4. **SideStore** öffnen und mit derselben Apple-ID anmelden.
5. **My Apps** › bei SideStore auf **7 DAYS** tippen (erste Auffrischung). Fragt SideStore nach einem neuen
   Zertifikat: **Yes** bzw. **Refresh Now**.
6. **AIronLudi laden:** SideStore › **Sources** › **+** › den **SideStore-Link** einfügen › Quelle „AIronLudi (privat)“
   öffnen › bei **AIronLudi** auf **Free** bzw. **Installieren** tippen. Warten, bis die App auf dem Homescreen liegt.
7. **SideStore › Settings:** **Background Refresh** einschalten und Mitteilungen für SideStore erlauben.

## Teil C – AIronLudi einrichten

1. **AIronLudi** öffnen und das Profil einrichten (Ziel, Sportarten, Körperdaten). Bei Apple Health „Erlauben“ wählen,
   wenn die Uhr-Daten genutzt werden sollen; ohne geht die App auch.
2. **Einladungslink** antippen (WhatsApp/iMessage) › AIronLudi öffnet sich und übernimmt KI-Zugang und Rangliste.
3. **Konto anlegen:** Einstellungen › Konto › **Konto erstellen** (Benutzername, Anzeigename, Passwort; Wiederherstellungscode
   notieren). So finden sich Freunde und der Feed, die Wettkämpfe und die Serie funktionieren.
4. *Optional* **Garmin:** Einstellungen › Garmin, mit dem eigenen Garmin-Konto bzw. -Key (Anleitung in
   [`einrichtung.md`](einrichtung.md), Schritt 1).
5. *Empfohlen* **Datensicherung:** Einstellungen › Datensicherung › Ordner in iCloud Drive wählen. Nach einer
   Neuinstallation: erster Bildschirm › oben rechts **Sicherung einspielen**.
6. *Optional* Widgets: Homescreen lange drücken › **+** › AIronLudi. Sperrbildschirm-Karte für Mahlzeiten:
   Einstellungen › Ernährung › „Mahlzeiten auf dem Sperrbildschirm“.

---

## Laufend

- Mit kostenloser Apple-ID läuft eine App **7 Tage**. **Mindestens einmal pro Woche** SideStore öffnen (LocalDevVPN
  verbunden) und **Refresh All** tippen, sonst startet AIronLudi nicht mehr. Mit Background Refresh geschieht das oft von
  selbst, verlass dich aber nicht darauf.
- Neue Versionen meldet SideStore („New Update Available“): SideStore › My Apps › bei AIronLudi **Update**. Die Daten
  bleiben erhalten.
- Es sind höchstens **3 Apps** gleichzeitig möglich (SideStore zählt mit) und 10 neue App-IDs pro Woche.

## Wenn etwas hakt

| Problem | Lösung |
|---|---|
| iloader sieht das iPhone nicht | anderes Kabel/USB-Anschluss, iPhone entsperren, „Vertrauen“ erneut bestätigen. Windows: iTunes bzw. „Apple-Geräte“ installiert? |
| Anmeldung mit Apple-ID schlägt fehl | Passwort in <https://account.apple.com> prüfen; ggf. ein **App-spezifisches Passwort** erzeugen und das verwenden |
| „Entwicklermodus“ fehlt | erst Teil A fertigstellen; der Eintrag erscheint erst nach der SideStore-Installation |
| SideStore meldet „Pairing file“ / lässt sich nicht verbinden | LocalDevVPN verbunden? Sonst in iloader die Pairing-Datei neu erzeugen (SideStore-Doku „Pairing File“); nach einem iOS-Update nötig |
| AIronLudi öffnet nicht mehr („nicht verfügbar“) | 7 Tage abgelaufen: LocalDevVPN verbinden › SideStore › My Apps › Refresh |
| Link des Betreibers lässt sich nicht einfügen | SideStore › Sources › **+** funktioniert nur mit dem vollständigen Link (mit `https://`) |

Quellen: offizielle SideStore-Doku <https://docs.sidestore.io> (Prerequisites, Install); technische Details und Updates
siehe [`sidestore.md`](sidestore.md) und [`installation.md`](installation.md).
