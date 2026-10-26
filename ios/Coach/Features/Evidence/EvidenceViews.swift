import CoachCore
import SwiftUI

/// „Grundlage“ unter einer Empfehlung: die Regeln mit Einstufung und Studien (Link auf DOI bzw. PubMed).
struct EvidenceDisclosure: View {
  let ruleIDs: [String]
  var title = "Wissenschaftliche Grundlage"

  var body: some View {
    var seen = Set<String>()
    let rules = Evidence.rules(ruleIDs.filter { seen.insert($0).inserted })
    if !rules.isEmpty {
      DisclosureGroup {
        ForEach(rules) { rule in
          EvidenceRuleRow(rule: rule)
        }
      } label: {
        Label(title, systemImage: "book.closed")
          .font(.subheadline)
      }
    }
  }
}

struct EvidenceRuleRow: View {
  let rule: EvidenceRule

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(rule.title).font(.subheadline.bold())
        Spacer()
        StrengthBadge(strength: rule.strength)
      }
      Text(rule.statement).font(.footnote)
      ForEach(rule.studies) { study in
        if let url = study.url {
          Link(destination: url) {
            Text("\(study.citation) · \(study.kind.rawValue)")
              .font(.caption)
              .multilineTextAlignment(.leading)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

struct StrengthBadge: View {
  let strength: EvidenceRule.Strength

  private var color: Color {
    switch strength {
    case .strong: .green
    case .moderate: .blue
    case .practice: .orange
    }
  }

  var body: some View {
    Text(strength.rawValue)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.15), in: Capsule())
      .foregroundStyle(color)
  }
}

/// Alle Regeln der App mit ihren Quellen (Einstellungen › Wissenschaftliche Grundlagen).
struct EvidenceLibraryView: View {
  var body: some View {
    List {
      Section {
        Text(
          "Die App entscheidet nach festen Regeln; die KI formuliert nur. Jede Regel nennt ihre Quellen. "
            + "„Praxisregel“ heißt: vorsichtig gewählt, aber ohne direkte Studie für genau diesen Wert.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      ForEach(Evidence.rules) { rule in
        Section { EvidenceRuleRow(rule: rule) }
      }
      Section("Kontrolle der KI") {
        Text(
          "Die KI bekommt nur die Fakten der App und diese Regeln. Der Worker prüft jede Antwort: Zahlen, die nicht "
            + "in den Fakten stehen, und unbekannte Quellen werden verworfen. Ist nichts belegt, zeigt die App die "
            + "regelbasierte Notiz.")
          .font(.footnote)
      }
    }
    .navigationTitle("Wissenschaftliche Grundlagen")
  }
}
