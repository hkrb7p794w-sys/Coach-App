import CoachCore
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
  @State private var profileEditor: ProfileEditor?

  private enum ProfileEditor: Identifiable {
    case edit, switchToPersonal
    var id: Self { self }
  }

  var body: some View {
    NavigationStack {
      Form {
        profileSection
        connectSection
        garminSection
        aiSection
        Section("Coach") {
          if model.settings.profile.mode == .season {
            NavigationLink("Saison & Ziele") { SeasonSettingsView() }
          }
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
      .fullScreenCover(item: $profileEditor) { editor in
        OnboardingView(
          isEditing: true,
          initial: editor == .edit ? model.settings.profile : UserProfile.personalDraft(from: model.settings.season))
      }
      .disabled(viewModel.isBusy)
      .overlay {
        if viewModel.isBusy { ProgressView() }
      }
    }
  }

  private var profileSection: some View {
    Section {
      if model.settings.profile.mode == .season {
        Label("Du nutzt den Saisonplan (\(model.settings.season.mainRaceName)).", systemImage: "flag.checkered")
        Button("Zu persönlichem Profil wechseln") { profileEditor = .switchToPersonal }
      } else {
        let profile = model.settings.profile
        Label(profile.goal.label, systemImage: profile.goal.symbol)
        Label(profile.sports.map(\.shortLabel).joined(separator: ", "), systemImage: "figure.mixed.cardio")
        Button("Sportarten, Ziel, Körperdaten ändern") { profileEditor = .edit }
      }
    } header: {
      Text("Profil")
    } footer: {
      if model.settings.profile.mode == .season {
        Text(
          "Mit einem persönlichen Profil wählst du Sportarten, Ziel und Wochenplan selbst; der Saisonplan "
            + "wird dann nicht mehr verwendet. Garmin-Daten, Gym-Einheiten und Mahlzeiten bleiben erhalten.")
      } else {
        Text("Plan, Ernährung und Empfehlungen passen sich an dein Profil an.")
      }
    }
  }

  private var connectSection: some View {
    Section {
      if viewModel.connectLoggedIn {
        Label(model.garmin.connect?.email ?? "Angemeldet", systemImage: "person.crop.circle.badge.checkmark")
          .foregroundStyle(.green)
        Button("Jetzt abrufen") {
          Task { await model.syncNow() }
        }
        Button("Abmelden", role: .destructive) { viewModel.logoutConnect() }
      } else if viewModel.awaitingCodeVia != nil {
        TextField("Bestätigungscode", text: $viewModel.connectCode)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
        Button("Code bestätigen") {
          Task { await viewModel.submitConnectCode() }
        }
        .disabled(viewModel.connectCode.count < 4)
      } else {
        TextField("E-Mail", text: $viewModel.connectEmail)
          .keyboardType(.emailAddress)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        SecureField("Passwort", text: $viewModel.connectPassword)
          .textContentType(.password)
        Button("Anmelden") {
          Task { await viewModel.loginConnect() }
        }
      }
      if let status = viewModel.connectStatus {
        Text(status).font(.footnote).foregroundStyle(.secondary)
      }
      if let problem = model.lastReport?.connectProblem, viewModel.connectLoggedIn {
        Label("Personal API ist eingesprungen: \(problem)", systemImage: "arrow.triangle.branch")
          .font(.footnote)
          .foregroundStyle(.orange)
      }
    } header: {
      Text("Garmin-Konto")
    } footer: {
      Text(
        "Inoffizieller Zugang wie die Garmin-Connect-App: mehr Werte (Training Readiness, Trainingsstatus, "
          + "Endurance Score, Wettkampfprognosen). Das Passwort wird nicht gespeichert, nur das Anmelde-Token im "
          + "Schlüsselbund. Fällt der Zugang aus, springt die Personal API ein, sofern ein Key hinterlegt ist."
      )
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
      Text("Garmin Personal API (Rückfall)")
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
