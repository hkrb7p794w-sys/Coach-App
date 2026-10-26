import CoachCore
import SwiftUI

struct DiagnosticsView: View {
  @State private var viewModel = DiagnosticsViewModel()

  var body: some View {
    Form {
      Section {
        LabeledContent("Status") {
          Label(viewModel.healthDiagnosis.title, systemImage: statusSymbol)
            .foregroundStyle(statusColor)
        }
        Text(viewModel.healthDiagnosis.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button {
          Task { await viewModel.checkHealthKit() }
        } label: {
          if viewModel.isChecking {
            ProgressView()
          } else {
            Text("HealthKit prüfen")
          }
        }
        .disabled(viewModel.isChecking)
      } header: {
        Text("HealthKit")
      } footer: {
        Text("Fragt Lesezugriff auf Workouts, Schlaf und Herzfrequenz sowie Schreibzugriff für Workouts an.")
      }

      Section("App") {
        LabeledContent("Version", value: viewModel.versionText)
      }
    }
    .navigationTitle("HealthKit")
  }

  private var statusSymbol: String {
    switch viewModel.healthDiagnosis {
    case .working: "checkmark.circle.fill"
    case .notDetermined: "questionmark.circle"
    default: "exclamationmark.triangle.fill"
    }
  }

  private var statusColor: Color {
    switch viewModel.healthDiagnosis {
    case .working: .green
    case .notDetermined: .secondary
    default: .orange
    }
  }
}

#Preview {
  NavigationStack { DiagnosticsView() }
}
