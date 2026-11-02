import CoachCore
import SwiftUI

/// Datenquellen: verbundene Anbieter mit Synchronisierungsstatus, primäres Gerät, bevorzugte Quelle je Datenart und
/// woher die Werte von heute stammen. Anbieter ohne eingebaute Anbindung werden ehrlich als solche gezeigt.
struct DataSourcesView: View {
  @Environment(AppModel.self) private var model
  @State private var syncing = false

  var body: some View {
    @Bindable var settings = model.settings
    let connected = model.connectedSources
    let states = model.sources.syncStates
    List {
      Section {
        ForEach(DataProvider.allCases) { provider in
          ProviderRow(provider: provider, connected: connected.contains(provider), state: states[provider])
        }
        Button {
          syncing = true
          Task {
            await model.syncNow()
            syncing = false
          }
        } label: {
          Label(syncing ? "Wird abgerufen …" : "Jetzt alle abrufen", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(syncing || connected.isEmpty)
      } header: {
        Text("Anbieter")
      } footer: {
        Text(
          "Automatisch beim Öffnen der App und im Hintergrund (iOS entscheidet wann). Nach Fehlern wartet der "
            + "automatische Abruf länger; „Jetzt abrufen“ geht immer und holt verpasste Tage nach.")
      }

      if connected.count > 1 {
        Section {
          Picker("Primäres Gerät", selection: $settings.sources.primary) {
            Text("Keins").tag(DataProvider?.none)
            ForEach(DataProvider.allCases.filter(connected.contains)) { provider in
              Text(provider.label).tag(DataProvider?.some(provider))
            }
          }
        } footer: {
          Text(
            "Das primäre Gerät gewinnt nur bei seinen Stärken (Garmin: Training, Belastung, Body Battery; WHOOP: "
              + "Schlaf, HRV, Recovery). Für alles andere gilt die bewährte Reihenfolge – oder deine Wahl unten.")
        }

        Section {
          ForEach(DataKind.allCases.filter { kind in
            connected.filter { $0.capabilities.contains(kind) }.count > 1
          }) { kind in
            KindPreferenceRow(kind: kind, connected: connected)
          }
        } header: {
          Text("Bevorzugte Quelle je Datenart")
        } footer: {
          Text(
            "Je Datenart zählt genau eine Quelle – keine doppelten Aktivitäten, Kalorien oder Belastungen und keine "
              + "gemischten Werte. Fehlen bei der bevorzugten Quelle Werte für einen Tag, springt die nächste ein.")
        }
      }

      let today = model.sources.sources(on: CalendarDay(date: .now))
      if !today.isEmpty {
        Section("Herkunft der Werte von heute") {
          ForEach(MetricsMerge.dailyKinds.filter { today[$0] != nil }, id: \.self) { kind in
            LabeledContent(kind.label, value: today[kind]?.label ?? "–")
          }
        }
      }

      Section {
        NavigationLink("Welche Anbieter gehen?") { IntegrationMatrixView() }
      }
    }
    .navigationTitle("Datenquellen")
    .onChange(of: settings.sources) { model.applySourcePreferences() }
  }
}

private struct ProviderRow: View {
  let provider: DataProvider
  let connected: Bool
  let state: ProviderSyncState?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(provider.label).font(.body.weight(.semibold))
        Spacer()
        Text(status).font(.caption).foregroundStyle(color)
      }
      if connected, let state {
        if let error = state.lastError {
          Text("Letzter Fehler: \(error)").font(.caption).foregroundStyle(.orange).lineLimit(2)
        }
        if let success = state.lastSuccess {
          Text("Zuletzt erfolgreich \(success.formatted(.relative(presentation: .named)))")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else if !connected {
        Text(provider.availabilityNote).font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
  }

  private var status: String {
    if connected { return state?.lastError == nil ? "verbunden" : "Fehler" }
    switch provider.availability {
    case .available: return "nicht verbunden"
    case .planned: return "noch nicht eingebaut"
    case .unavailable: return "nicht verfügbar"
    }
  }

  private var color: Color {
    if connected { return state?.lastError == nil ? .green : .orange }
    return .secondary
  }
}

private struct KindPreferenceRow: View {
  @Environment(AppModel.self) private var model
  let kind: DataKind
  let connected: Set<DataProvider>

  var body: some View {
    let automatic = SourcePreferences(primary: model.settings.sources.primary)
      .preferred(for: kind, connected: connected)
    Picker(
      kind.label,
      selection: Binding(
        get: { model.settings.sources.overrides[kind] },
        set: { model.settings.sources.overrides[kind] = $0 })
    ) {
      Text("Automatisch (\(automatic?.label ?? "–"))").tag(DataProvider?.none)
      ForEach(DataProvider.allCases.filter { connected.contains($0) && $0.capabilities.contains(kind) }) {
        Text($0.label).tag(DataProvider?.some($0))
      }
    }
  }
}

/// Integrationsmatrix: was die Anbieter offiziell anbieten und was davon in der App ist.
struct IntegrationMatrixView: View {
  var body: some View {
    List {
      ForEach(DataProvider.allCases) { provider in
        Section(provider.label) {
          Text(provider.availabilityNote)
          LabeledContent(
            "Datenarten",
            value: DataKind.allCases.filter(provider.capabilities.contains).map(\.label).joined(separator: ", "))
        }
      }
      Section {
        Text("Ausführlich mit Quellen: docs/integrationen.md im Repository.").foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Anbieter")
  }
}
