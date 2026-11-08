# Design-Skills aus GitHub-Repositories (Paket 11)

Stand: 08.11.2026. Frage: Lohnt es sich, GitHub-Repositories als Design-Skill für die Arbeit an der App einzubinden?

**Ergebnis: Nein, vorerst kein Repository einbinden.** Geändert wurde deshalb nichts unter `.claude/`.

## Wie Claude-Code-Skills funktionieren

Ein Skill ist ein Ordner mit einer `SKILL.md` (Beschreibung im Kopf, Anweisungen darunter), für ein Projekt unter
`.claude/skills/<name>/`. Immer im Kontext ist nur die Beschreibung, der Rest wird erst bei Bedarf geladen. Die
[Dokumentation](https://code.claude.com/docs/en/skills) legt keinen Vorrang zwischen Skill und `CLAUDE.md` fest. Ein
Skill kann den Projektregeln also widersprechen, und niemand entscheidet das zuverlässig.

## Direkt einbinden oder lokal aufbereiten

- **Ein Repository-Link allein reicht nicht.** Claude Code liest keine fremden Repositories als Skill, sie müssen als
  Dateien oder Plugin installiert werden.
- **Direkt übernehmen** heißt: fremder Text wird zu Anweisungen für einen Agenten, der pushen und mergen darf. Änderungen
  am Original kämen ungeprüft dazu, wenn man sie automatisch nachzieht.
- **Lokal aufbereiten** (Datei kopieren, auf die Projektregeln kürzen, Commit-Stand notieren, Lizenz mitführen) wäre der
  einzig vertretbare Weg, falls später ein konkreter Bedarf entsteht.

## Geprüfte Repositories

Lizenz, Sterne und letzter Push direkt über die GitHub-API am 08.11.2026. Der Inhalt wurde nicht im Einzelnen geprüft
und nicht ausprobiert, die Beschreibung stammt aus der Websuche.

| Repository | Lizenz | Sterne | Letzter Push | Inhalt |
|---|---|---|---|---|
| wshobson/agents (mobile-ios-design) | MIT | 42.311 | 08.11.2026 | große Sammlung, darin ein Skill zu HIG und SwiftUI |
| Prisma-Labs-Dev/apple-skills (früher vabole) | MIT | 356 | 26.09.2026 | iOS-Design und UI-Handwerk, iOS 26 |
| Wholiver/swiftui-design-skill | MIT | 208 | 01.05.2026 | eigenständige SwiftUI-Oberflächen |
| SwiftyJourney/swiftui-expert-skill | MIT | 3 | 10.08.2026 | SwiftUI schreiben und prüfen |
| Spacebody/apple-developer-skills | MIT | 0 | 03.11.2026 | u. a. HIG-Prüfung |

## Warum nicht einbinden

- **Wenig Zusatznutzen:** Die App hat feste Regeln (`CLAUDE.md`, Komponenten in `ios/Coach`). Allgemeines zu HIG, Safe
  Areas und Dynamic Type deckt das in dieser Arbeitsumgebung verfügbare Plugin `mobile-app-design` bereits ab
  (`ios-screens`, `ios-review`, `ios-flows`).
- **Risiko:** Mögliche Konflikte mit den Projektregeln (deutsche Texte, Liquid Glass ab iOS 26 bei Zielsystem iOS 18).
- **Wartung:** Die kleineren Repositories werden kaum genutzt, die große Sammlung ändert sich täglich.
- **Kein Beleg:** Ob einer dieser Skills bessere Oberflächen für diese App ergibt, ist nicht gemessen.

Sinnvoller ist ein eigener kurzer Skill, sobald sich Design-Fehler wiederholen. Er enthielte dann die tatsächlichen
Regeln dieser App und würde `CLAUDE.md` ausdrücklich nachgeordnet.
