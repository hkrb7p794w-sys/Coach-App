# Einrichtung: Garmin, KI-Worker und App

Einmalig, etwa 30 Minuten. Reihenfolge einhalten. Keys und Tokens **nie** in Chats, Issues oder Dateien im
Repo kopieren – nur in die genannten Felder.

Vorher: Coach ist per SideStore installiert (siehe [sidestore.md](sidestore.md)).

## 1. Garmin Personal API Key (am besten direkt auf dem iPhone)

1. Auf dem iPhone in Safari <https://connect.garmin.com/app/settings/personalApiToken> öffnen und mit dem
   Garmin-Konto anmelden.
2. **Create** bzw. „Key erstellen“, Bedingungen bestätigen, Laufzeit **1 Jahr** wählen.
3. Den Key kopieren – er wird **nur einmal** angezeigt.
4. Coach öffnen › **Einstellungen** › Abschnitt **Garmin** › Key einfügen, „Gültig bis“ auf das angezeigte
   Ablaufdatum setzen › **Speichern und verbinden**.
5. Nach einigen Sekunden steht dort „Abgerufen: … Tage, … Aktivitäten“. Im Tab **Heute** erscheinen die Werte.

Geht etwas schief: **Einstellungen › Garmin-Diagnose** zeigt, welche Endpunkte Daten geliefert haben. Die
Feldliste einer Antwort lässt sich über „Teilen“ weitergeben (sie enthält nur Feldnamen, keine Werte).

## 2. KI-Keys

**Gemini** (kostenloses Kontingent, keine Kreditkarte):

1. <https://aistudio.google.com> › **Get API key** › **Create API key**. Den Key aus dem alten Home-Assistant-
   Add-on kannst du weiterverwenden.

**Groq** (Ausweichstufe, kostenloses Kontingent):

1. <https://console.groq.com/keys> › anmelden › **Create API Key** › Namen „coach“ › Key kopieren.

Hinweis Datenschutz: Im kostenlosen Gemini-Kontingent darf Google Eingaben zur Produktverbesserung nutzen. Die
App schickt deshalb standardmäßig nur Einordnungen („HRV ausgeglichen“), keine Rohwerte.

## 3. Cloudflare-Konto und API-Token

1. Kostenloses Konto anlegen: <https://dash.cloudflare.com/sign-up>.
2. Im Dashboard links **Workers & Pages** öffnen. Beim ersten Besuch fragt Cloudflare nach einer
   `workers.dev`-Subdomain – einen Namen wählen (er wird Teil der Worker-Adresse).
3. **Account ID** kopieren: auf der Seite **Workers & Pages** rechts unter „Account details“ bzw. im Menü neben
   dem Kontonamen › „Copy account ID“.
4. API-Token: Profil-Symbol › **API Tokens** (bzw. „Account API tokens“) › **Create Token** › bei der Vorlage
   **Edit Cloudflare Workers** auf **Use template** › bei „Account Resources“ nur dein Konto auswählen ›
   **Continue to summary** › **Create Token** › Token kopieren (wird nur einmal angezeigt).

Quelle: Cloudflare-Doku „GitHub Actions“ (Workers › CI/CD).

## 4. App-Token erzeugen

Ein langes Zufallspasswort, mit dem sich die App beim Worker anmeldet. Am Windows-PC in **PowerShell**:

```powershell
$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ([BitConverter]::ToString($b) -replace '-','').ToLower()
```

Alternativ auf dem iPhone in der Passwörter-App ein starkes Passwort erzeugen (mindestens 32 Zeichen).

## 5. GitHub-Secrets anlegen

Im Repo **Settings › Secrets and variables › Actions › New repository secret**, je einmal:

| Name | Wert |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Token aus Schritt 3.4 |
| `CLOUDFLARE_ACCOUNT_ID` | Account ID aus Schritt 3.3 |
| `GEMINI_API_KEY` | Gemini-Key aus Schritt 2 |
| `GROQ_API_KEY` | Groq-Key aus Schritt 2 |
| `COACH_APP_TOKEN` | App-Token aus Schritt 4 |

## 6. Worker bereitstellen

1. Im Repo **Actions › Worker › Run workflow** (Branch `main`) › **Run workflow**.
   (Nach dem Merge einer PR, die `worker/` ändert, passiert das automatisch.)
2. Nach etwa einer Minute den Lauf öffnen › Job **deploy** › **Summary**: Dort steht die **Adresse für die
   App**, z. B. `https://coach-ai.<deine-subdomain>.workers.dev`, und die Antwort des Health-Checks
   (`"providers": {"gemini": true, "groq": true}`).

Fehlt ein Secret, endet der Lauf grün mit dem Hinweis „Deploy übersprungen – fehlende Secrets: …“.

## 7. App mit dem Worker verbinden

1. Coach › **Einstellungen** › **KI-Worker**: Adresse aus Schritt 6 und App-Token aus Schritt 4 eintragen.
2. **Speichern und testen** – darunter erscheint ein kurzer Gruß der KI mit Anbieter und Modell.

## Später

- **Garmin-Key läuft ab** (spätestens nach einem Jahr): Garmin schickt eine E-Mail, die App warnt 14 Tage
  vorher. Neuen Key wie in Schritt 1 erzeugen und eintragen.
- **KI-Key wechseln**: GitHub-Secret ändern und Schritt 6.1 wiederholen. In der App ändert sich nichts.
- **App-Token wechseln**: Secret `COACH_APP_TOKEN` ändern, Schritt 6.1 wiederholen und das neue Token in der
  App eintragen.
