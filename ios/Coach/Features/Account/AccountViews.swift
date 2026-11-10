import CoachCore
import SwiftUI

/// Abschnitt „Konto“ in den Einstellungen. Das Anmelde-Fenster zeigt der Aufrufer außerhalb der Liste (`authMode`):
/// Hängt es an der Zeile, schließt SwiftUI es, sobald sich der Abschnitt ändert – etwa wenn der Server die Sitzung
/// meldet und „Anmelden“ durch den Kontonamen ersetzt wird, noch bevor das Fenster fertig ist.
struct AccountSettingsSection: View {
  @Environment(AppModel.self) private var model
  @Binding var authMode: AccountAuthView.Mode?

  var body: some View {
    let account = model.account
    Section {
      if account.isSignedIn, let info = account.account {
        NavigationLink {
          AccountDetailView()
        } label: {
          LabeledContent {
            Text("@\(info.username)")
          } label: {
            Label(info.displayName, systemImage: "person.crop.circle.fill")
          }
        }
      } else {
        if let notice = account.notice {
          Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        Button("Anmelden") { authMode = .login }
        Button("Konto erstellen") { authMode = .register }
      }
    } header: {
      Text("Konto")
    } footer: {
      if !account.isSignedIn {
        Text(
          "Mit einem eigenen Konto findest du Freunde über den Benutzernamen. Nur du kennst dein Passwort; "
            + "deine Gesundheitsdaten bleiben auf diesem Gerät.")
      }
    }
  }
}

/// Anmelden, Registrieren oder Passwort mit dem Wiederherstellungscode zurücksetzen.
struct AccountAuthView: View {
  enum Mode: String, CaseIterable, Identifiable {
    case login, register, recover
    var id: Self { self }
    var title: String {
      switch self {
      case .login: "Anmelden"
      case .register: "Registrieren"
      case .recover: "Vergessen"
      }
    }
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var mode: Mode
  @State private var server: String
  @State private var username = ""
  @State private var displayName = ""
  @State private var password = ""
  @State private var repeated = ""
  @State private var inviteCode: String
  @State private var recoveryInput = ""
  @State private var isWorking = false
  @State private var error: String?
  @State private var recoveryCode: String?
  @FocusState private var focused: Bool

  private let invite: AccountInvite?

  init(initialMode: Mode, invite: AccountInvite?) {
    self.invite = invite
    _mode = State(initialValue: invite == nil ? initialMode : .register)
    _server = State(initialValue: invite?.workerURL ?? "")
    _inviteCode = State(initialValue: invite?.code ?? "")
  }

  private var account: AccountService { model.account }

  /// Server-Feld nur, wenn keiner gespeichert ist oder die Einladung einen anderen nennt.
  private var showsServer: Bool {
    guard let saved = AIClient.normalizedURL(account.workerURL) else { return true }
    guard let invite, let host = invite.host else { return false }
    return saved.host()?.lowercased() != host
  }

  private var serverURL: String { showsServer ? server : account.workerURL }
  private var needsInvite: Bool { mode == .register && (account.needsInviteCode || showsServer) }

  private var usernameHint: String? {
    username.isEmpty || mode == .login ? nil : AccountRules.usernameProblem(username)
  }

  private var passwordHint: String? {
    guard mode != .login, !password.isEmpty else { return nil }
    if let problem = AccountRules.passwordProblem(password, username: username) { return problem }
    if !repeated.isEmpty, repeated != password { return "Die Passwörter stimmen nicht überein." }
    return nil
  }

  private var canSubmit: Bool {
    guard !isWorking, AIClient.normalizedURL(serverURL) != nil, !username.isEmpty, !password.isEmpty else {
      return false
    }
    switch mode {
    case .login: return true
    case .register:
      return AccountRules.usernameProblem(username) == nil
        && AccountRules.passwordProblem(password, username: username) == nil && repeated == password
        && AccountRules.displayName(displayName) != nil
        && (!needsInvite || AccountRules.normalizeCode(inviteCode).count == 10)
    case .recover:
      return AccountRules.passwordProblem(password, username: username) == nil && repeated == password
        && AccountRules.normalizeCode(recoveryInput).count == 16
    }
  }

  var body: some View {
    NavigationStack {
      if let recoveryCode {
        RecoveryCodeView(code: recoveryCode) { dismiss() }
      } else {
        form
      }
    }
  }

  private var form: some View {
    Form {
      Section {
        Picker("Art", selection: $mode) {
          ForEach(Mode.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(invite != nil)
      } footer: {
        if invite != nil {
          Text("Du wurdest eingeladen. Lege dein eigenes Konto an – nur du kennst dein Passwort.")
        }
      }

      if showsServer {
        Section("Server") {
          TextField("https://coach-ai.<name>.workers.dev", text: $server)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }

      Section {
        TextField("Benutzername", text: $username)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .focused($focused)
        if mode == .register {
          TextField("Anzeigename (z. B. Vorname)", text: $displayName)
            .textContentType(.givenName)
        }
        if mode == .recover {
          TextField("Wiederherstellungscode", text: $recoveryInput)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        }
        SecureField(mode == .recover ? "Neues Passwort" : "Passwort", text: $password)
          .textContentType(mode == .login ? .password : .newPassword)
        if mode != .login {
          SecureField("Passwort wiederholen", text: $repeated)
            .textContentType(.newPassword)
        }
        if needsInvite {
          TextField("Einladungscode", text: $inviteCode)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        }
      } footer: {
        VStack(alignment: .leading, spacing: 4) {
          if let usernameHint { Text(usernameHint) }
          if let passwordHint { Text(passwordHint) }
          if mode == .register && usernameHint == nil && passwordHint == nil {
            Text("Freunde finden dich über den Benutzernamen. Passwort: mindestens 10 Zeichen.")
          }
          if mode == .recover {
            Text(
              "Den Wiederherstellungscode hast du bei der Registrierung erhalten. Ohne Code kann die Person, die den "
                + "Server betreibt, dir einen neuen ausstellen.")
          }
        }
      }

      Section {
        Button {
          Task { await submit() }
        } label: {
          HStack {
            Text(mode == .login ? "Anmelden" : mode == .register ? "Konto erstellen" : "Passwort zurücksetzen")
            Spacer()
            if isWorking { ProgressView() }
          }
        }
        .disabled(!canSubmit)
      } footer: {
        if let error { Text(error).foregroundStyle(.red) }
      }
    }
    .navigationTitle(mode == .login ? "Anmelden" : mode == .register ? "Konto erstellen" : "Passwort vergessen")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
    }
    .onAppear { focused = true }
    .onChange(of: mode) { error = nil }
  }

  private func submit() async {
    isWorking = true
    defer { isWorking = false }
    error = nil
    do {
      if showsServer { try account.useServer(server) }
      switch mode {
      case .login:
        try await account.login(username: username, password: password)
        dismiss()
      case .register:
        recoveryCode = try await account.register(
          username: username, displayName: displayName, password: password, invite: inviteCode)
      case .recover:
        recoveryCode = try await account.recover(
          username: username, recoveryCode: recoveryInput, newPassword: password)
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}

/// Wiederherstellungscode einmalig zeigen; erst nach Bestätigung schließen.
struct RecoveryCodeView: View {
  let code: String
  let onDone: () -> Void
  @State private var saved = false
  @State private var copied = false

  var body: some View {
    Form {
      Section {
        Text(code)
          .font(.title2.monospaced().weight(.semibold))
          .frame(maxWidth: .infinity)
          .textSelection(.enabled)
          .accessibilityLabel("Wiederherstellungscode \(code.map(String.init).joined(separator: " "))")
        Button {
          UIPasteboard.general.string = code
          copied = true
        } label: {
          Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
      } header: {
        Text("Dein Wiederherstellungscode")
      } footer: {
        Text(
          "Mit diesem Code setzt du dein Passwort zurück, falls du es vergisst. Er wird nur jetzt angezeigt. Bewahre "
            + "ihn sicher auf, z. B. im Passwort-Manager, und gib ihn niemandem.")
      }
      Section {
        Toggle("Ich habe den Code sicher aufbewahrt", isOn: $saved)
        Button("Fertig", action: onDone).disabled(!saved)
      }
    }
    .navigationTitle("Konto bereit")
    .navigationBarTitleDisplayMode(.inline)
    .interactiveDismissDisabled(!saved)
  }
}

/// Konto verwalten: Anzeigename, Einladungen, Geräte, Passwort, Abmelden, Löschen.
struct AccountDetailView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var displayName = ""
  @State private var error: String?
  @State private var newInvite: AccountInvite?
  @State private var confirmLogoutAll = false
  @State private var deleting = false
  @State private var deletePassword = ""
  @State private var isWorking = false

  private var account: AccountService { model.account }

  var body: some View {
    Form {
      if let info = account.account {
        Section {
          LabeledContent("Benutzername", value: "@\(info.username)")
          TextField("Anzeigename", text: $displayName)
            .onSubmit { Task { await saveName() } }
          if displayName != info.displayName, AccountRules.displayName(displayName) != nil {
            Button("Anzeigenamen speichern") { Task { await saveName() } }
          }
        } header: {
          Text("Profil")
        } footer: {
          Text("Freunde sehen Benutzernamen und Anzeigenamen.")
        }
      }

      Section {
        Button {
          Task { await invite() }
        } label: {
          Label("Neue Einladung erstellen", systemImage: "person.badge.plus")
        }
        .disabled(isWorking)
        if let newInvite, let url = newInvite.shareURL {
          ShareLink(
            item: url,
            message: Text("Komm zu AIronLudi! Mit diesem Link legst du dein Konto an (14 Tage gültig, einmalig).")
          ) {
            Label("Einladung \(newInvite.code) teilen", systemImage: "square.and.arrow.up")
          }
        }
        ForEach(account.invites) { item in
          LabeledContent(item.code) {
            Text("bis \(Self.shortDate(item.expiresAt))")
          }
          .font(.body.monospaced())
          .swipeActions {
            Button("Löschen", role: .destructive) { Task { await account.deleteInvite(item.code) } }
          }
        }
      } header: {
        Text("Freunde und Familie einladen")
      } footer: {
        Text("Jede Einladung gilt einmal und 14 Tage. Höchstens 5 offene Einladungen.")
      }

      Section("Angemeldete Geräte") {
        ForEach(account.sessions) { session in
          VStack(alignment: .leading) {
            Text(session.device + (session.current ? " · dieses Gerät" : ""))
            Text("Zuletzt aktiv \(Self.shortDate(session.lastUsed))").font(.caption).foregroundStyle(.secondary)
          }
        }
        Button("Auf allen Geräten abmelden", role: .destructive) { confirmLogoutAll = true }
      }

      Section("Sicherheit") {
        NavigationLink("Passwort ändern") { ChangePasswordView() }
        Button("Auf diesem Gerät abmelden") {
          Task {
            await account.logout()
            dismiss()
          }
        }
        Button("Konto löschen", role: .destructive) { deleting = true }
      }

      if let error {
        Section { Text(error).foregroundStyle(.red) }
      }
    }
    .navigationTitle("Konto")
    .task {
      displayName = account.account?.displayName ?? ""
      do { try await account.refresh() } catch { self.error = error.localizedDescription }
      if !account.isSignedIn { dismiss() }
    }
    .confirmationDialog("Auf allen Geräten abmelden?", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
      Button("Überall abmelden", role: .destructive) {
        Task {
          await account.logout(everywhere: true)
          dismiss()
        }
      }
    } message: {
      Text("Du musst dich danach auf jedem Gerät neu anmelden.")
    }
    .alert("Konto löschen?", isPresented: $deleting) {
      SecureField("Passwort", text: $deletePassword)
      Button("Endgültig löschen", role: .destructive) { Task { await delete() } }
      Button("Abbrechen", role: .cancel) { deletePassword = "" }
    } message: {
      Text(
        "Konto, Anmeldungen und offene Einladungen werden auf dem Server gelöscht. Deine Daten auf diesem iPhone "
          + "bleiben.")
    }
  }

  private func saveName() async {
    do { try await account.updateDisplayName(displayName) } catch { self.error = error.localizedDescription }
  }

  private func invite() async {
    isWorking = true
    defer { isWorking = false }
    do { newInvite = try await account.createInvite() } catch { self.error = error.localizedDescription }
  }

  private func delete() async {
    let password = deletePassword
    deletePassword = ""
    do {
      try await account.deleteAccount(password: password)
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }

  static func shortDate(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter.withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    else { return iso }
    return date.formatted(date: .abbreviated, time: .omitted)
  }
}

extension ISO8601DateFormatter {
  /// Zeiten des Workers (`toISOString()`, mit Millisekunden).
  static var withFraction: ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }
}

struct ChangePasswordView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var old = ""
  @State private var new = ""
  @State private var repeated = ""
  @State private var error: String?
  @State private var isWorking = false

  var body: some View {
    let username = model.account.account?.username ?? ""
    let hint =
      new.isEmpty
      ? nil
      : AccountRules.passwordProblem(new, username: username)
        ?? (repeated.isEmpty || repeated == new ? nil : "Die Passwörter stimmen nicht überein.")
    Form {
      Section {
        SecureField("Bisheriges Passwort", text: $old).textContentType(.password)
        SecureField("Neues Passwort", text: $new).textContentType(.newPassword)
        SecureField("Neues Passwort wiederholen", text: $repeated).textContentType(.newPassword)
      } footer: {
        Text(hint ?? "Andere Geräte werden danach abgemeldet.")
      }
      Section {
        Button("Passwort ändern") {
          Task {
            isWorking = true
            defer { isWorking = false }
            do {
              try await model.account.changePassword(old: old, new: new)
              dismiss()
            } catch {
              self.error = error.localizedDescription
            }
          }
        }
        .disabled(isWorking || old.isEmpty || hint != nil || repeated != new || new.isEmpty)
      } footer: {
        if let error { Text(error).foregroundStyle(.red) }
      }
    }
    .navigationTitle("Passwort ändern")
  }
}

/// Einladungslink geöffnet, obwohl schon ein Konto angemeldet ist.
struct AlreadySignedInSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ContentUnavailableView(
        "Schon angemeldet", systemImage: "person.crop.circle.badge.checkmark",
        description: Text(
          "Die Einladung ist für eine Person ohne Konto. Gib den Link an die Person weiter, für die er gedacht ist.")
      )
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
  }
}
