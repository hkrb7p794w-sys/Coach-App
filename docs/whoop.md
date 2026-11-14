# WHOOP verbinden

Die App liest Erholung (Recovery), HRV, Ruhepuls, Schlaf mit Phasen, Tageskalorien, Schritte, Workouts und
Körperwerte über die **offizielle WHOOP-API (v2)**. Wie bei Garmin ruft die App die Daten selbst ab; der Worker
tauscht nur die Anmeldung (OAuth), weil WHOOP dafür ein Client-Secret verlangt, das nicht in die App gehört.

Einmalig nötig: eine eigene „App“ im WHOOP-Developer-Dashboard (kostenlos, mit dem eigenen WHOOP-Konto).

## 1. WHOOP-App anlegen

1. <https://developer-dashboard.whoop.com> öffnen und mit dem WHOOP-Konto anmelden (beim ersten Mal ein „Team“
   anlegen, Name beliebig).
2. **Create App**:
   - **Name:** z. B. `IronLudi`
   - **Scopes:** alle Häkchen setzen – `read:recovery`, `read:cycles`, `read:workout`, `read:sleep`,
     `read:profile`, `read:body_measurement` (`offline` fordert die App selbst an).
   - **Redirect URL:** die Worker-Adresse mit `/w/whoop`, z. B.
     `https://coach-ai.<deine-subdomain>.workers.dev/w/whoop` (dieselbe Adresse wie in der App unter
     Einstellungen › KI-Worker, ohne Schrägstrich am Ende).
3. Nach dem Speichern **Client ID** und **Client Secret** kopieren.

## 2. In GitHub hinterlegen

Im Repo **Coach-App › Settings › Secrets and variables › Actions › New repository secret**:

| Name | Wert |
|---|---|
| `WHOOP_CLIENT_ID` | Client ID aus Schritt 1 |
| `WHOOP_CLIENT_SECRET` | Client Secret aus Schritt 1 |

Danach **Actions › Worker › Run workflow** (oder nächster Merge auf `main`). Der Health-Check des Workers
(`/v1/health`) zeigt dann `"whoop": true`.

## 3. In der App verbinden

Einstellungen › Training und Fitness › **WHOOP** › „Mit WHOOP verbinden“. WHOOP fragt im Browser nach der Freigabe
und leitet zurück in die App. Ab dann holt die App die WHOOP-Daten bei jedem Abruf mit (beim ersten Mal 90 Tage).
Welche Quelle bei Schlaf, HRV usw. zählt, steht unter Einstellungen › Datenquellen und Vorrang.

## Hinweise

- Ohne Developer-App gibt es keinen anderen offiziellen Weg; WHOOP schreibt aber Schlaf, Ruhepuls und Workouts nach
  Apple Health (ohne HRV und Recovery).
- Grenzen der API: 100 Anfragen je Minute, 10 000 je Tag (pro Developer-App). Ein Abruf braucht wenige Anfragen.
- Trennen in der App widerruft den Zugriff bei WHOOP und löscht die Tokens auf dem Gerät.
