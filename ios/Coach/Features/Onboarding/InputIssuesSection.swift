import CoachCore
import SwiftUI

/// Hinweise zu den Eingaben: unplausible Werte, widersprüchliche Ziele und Zielzeiten im Vergleich zur Prognose.
struct InputIssuesSection: View {
  let issues: [InputIssue]
  var title = "Deine Angaben im Check"

  var body: some View {
    if !issues.isEmpty {
      Section {
        ForEach(issues) { issue in
          Label {
            Text(issue.message).font(.subheadline)
          } icon: {
            Image(systemName: symbol(issue.severity)).foregroundStyle(color(issue.severity))
          }
        }
        let ids = issues.flatMap(\.evidenceIDs)
        if !ids.isEmpty { EvidenceDisclosure(ruleIDs: ids) }
      } header: {
        Text(title)
      }
    }
  }

  private func symbol(_ severity: InputIssue.Severity) -> String {
    switch severity {
    case .warning: "exclamationmark.triangle.fill"
    case .tip: "lightbulb.fill"
    case .info: "checkmark.circle.fill"
    }
  }

  private func color(_ severity: InputIssue.Severity) -> Color {
    switch severity {
    case .warning: .orange
    case .tip: .yellow
    case .info: .green
    }
  }
}
