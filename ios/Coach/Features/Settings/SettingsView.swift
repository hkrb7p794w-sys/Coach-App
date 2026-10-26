import SwiftUI

struct SettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    SettingsForm(viewModel: SettingsViewModel(model: model))
  }
}

private struct SettingsForm: View {
  @State var viewModel: SettingsViewModel
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        garminSection
        aiSection
        Section("Coach") {
          NavigationLink("Saison & Ziele") { SeasonSettingsView() }
          NavigationLink("Ernährung") { NutritionSettingsView() }
          NavigationLink("Wissenschaftliche Grundlagen") { EvidenceLibraryView() }
        }
        Section("Diagnose") {
          NavigationLink("Garmin-Diagnose") { GarminDiagnosticsView() }
          NavigationLink("HealthKit") { DiagnosticsView() }
        }
      }
      .navigationTitle("Einstellungen")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
      .disabled(viewModel.isBusy)
      .overlay {
        if viewModel.isBusy { ProgressView() }
      }
    }
  }

  private var garminSection: some View {
    Section {
      if viewModel.hasGarminKey {
        Label("Key hinterlegt", systemImage: "checkmark.seal")
          .foregroundStyle(.green)
      }
      if let warning = viewModel.expiryWarning {
        Label(warning, systemImage: "clock.badge.exclamationmark")
          .foregroundStyle(.orange)
      }
      SecureField(viewModel.hasGarminKey ? "Neuen Key einfügen" : "Personal API Key", text: $viewModel.garminKeyInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      DatePicker("Gültig bis", selection: $viewModel.keyExpiry, displayedComponents: .date)
        .onChange(of: viewModel.keyExpiry) { viewModel.saveExpiry() }
      Button("Speichern und verbinden") {
        Task { await viewModel.saveGarminKey() }
      }
      if viewModel.hasGarminKey {
        Button("Jetzt abrufen") {
          Task { await model.syncNow() }
        }
        Button("Key entfernen", role: .destructive) { viewModel.removeGarminKey() }
      }
      if let status = viewModel.garminStatus {
        Text(status).font(.footnote).foregroundStyle(.secondary)
      }
    } header: {
      Text("Garmin")
    } footer: {
      Text(
        "Key erzeugen: Garmin Connect im Browser › Einstellungen › Personal API Key (Laufzeit 1 Jahr). "
          + "Der Key bleibt nur im Schlüsselbund dieses iPhones."
      )
    }
  }

  private var aiSection: some View {
    Section {
      TextField("https://coach-ai.<name>.workers.dev", text: $viewModel.workerURLInput)
        .keyboardType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      SecureField(viewModel.hasAIToken ? "App-Token (gespeichert)" : "App-Token", text: $viewModel.appTokenInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Speichern und testen") {
        Task { await viewModel.saveAndTestAI() }
      }
      if let status = viewModel.aiStatus {
        Text(status).font(.footnote).foregroundStyle(.secondary)
      }
      if let source = model.ai.sideStoreSourceURL {
        ShareLink(item: source) {
          Label("SideStore-Quelle teilen", systemImage: "square.and.arrow.up")
        }
        Button {
          UIPasteboard.general.url = source
        } label: {
          Label("SideStore-Quelle kopieren", systemImage: "doc.on.doc")
        }
      }
    } header: {
      Text("KI-Worker")
    } footer: {
      Text(
        "Adresse und App-Token aus der Einrichtung des Cloudflare Workers (siehe docs/einrichtung.md). "
          + "Die SideStore-Quelle ist privat: Wer den Link hat, kann die App laden – nur an Vertraute weitergeben."
      )
    }
  }
}
