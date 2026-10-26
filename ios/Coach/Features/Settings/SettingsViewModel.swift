import CoachCore
import Foundation
import Observation

@Observable
final class SettingsViewModel {
  static let keyExpiryKey = "garmin.keyExpiry"
  /// Ab so vielen Tagen vor Ablauf des Garmin-Keys warnt die App.
  static let expiryWarningDays = 14

  var garminKeyInput = ""
  var keyExpiry: Date
  var workerURLInput: String
  var appTokenInput = ""
  var connectEmail: String
  var connectPassword = ""
  var connectCode = ""
  /// Garmin wartet auf einen Bestätigungscode (Methode, z. B. `email`).
  private(set) var awaitingCodeVia: String?
  private(set) var connectLoggedIn: Bool
  private(set) var connectStatus: String?

  private(set) var garminStatus: String?
  private(set) var aiStatus: String?
  private(set) var isBusy = false

  private let model: AppModel
  private let defaults: UserDefaults

  init(model: AppModel, defaults: UserDefaults = .standard) {
    self.model = model
    self.defaults = defaults
    keyExpiry =
      defaults.object(forKey: Self.keyExpiryKey) as? Date
      ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
    workerURLInput = model.ai.workerURL
    connectEmail = model.garmin.connect?.email ?? ""
    connectLoggedIn = model.garmin.connect?.isLoggedIn ?? false
  }

  var hasGarminKey: Bool { model.garmin.hasKey }
  var hasAIToken: Bool { model.ai.hasToken }

  /// Warnung, wenn der Garmin-Key bald abläuft (Garmin erlaubt höchstens ein Jahr).
  var expiryWarning: String? {
    guard hasGarminKey, defaults.object(forKey: Self.keyExpiryKey) != nil else { return nil }
    let days = Calendar.current.dateComponents([.day], from: .now, to: keyExpiry).day ?? 0
    if days < 0 { return "Der Garmin-Key ist abgelaufen. Bitte in Garmin Connect einen neuen erzeugen." }
    if days <= Self.expiryWarningDays { return "Der Garmin-Key läuft in \(days) Tagen ab." }
    return nil
  }

  func saveGarminKey() async {
    let key = garminKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else {
      garminStatus = "Bitte den Key einfügen."
      return
    }
    isBusy = true
    defer { isBusy = false }
    do {
      try model.garmin.updateKey(key)
      defaults.set(keyExpiry, forKey: Self.keyExpiryKey)
      _ = try await model.garmin.validToken(forceRefresh: true)
      garminKeyInput = ""
      garminStatus = "Verbunden. Daten werden abgerufen …"
      await model.syncNow()
      garminStatus = model.lastError ?? model.lastReport.map { "Abgerufen: \($0.summary)" } ?? "Verbunden."
    } catch let error as GarminAPIError {
      garminStatus = error.message
    } catch {
      garminStatus = error.localizedDescription
    }
  }

  // MARK: - Garmin-Konto

  func loginConnect() async {
    guard let connect = model.garmin.connect else { return }
    guard !connectEmail.isEmpty, !connectPassword.isEmpty else {
      connectStatus = "Bitte E-Mail und Passwort eingeben."
      return
    }
    isBusy = true
    defer { isBusy = false }
    connectStatus = "Anmeldung läuft …"
    do {
      let state = try await connect.login(email: connectEmail, password: connectPassword)
      connectPassword = ""
      await finish(state)
    } catch {
      connectPassword = ""
      connectStatus = error.localizedDescription
    }
  }

  func submitConnectCode() async {
    guard let connect = model.garmin.connect else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let state = try await connect.submitCode(connectCode)
      connectCode = ""
      await finish(state)
    } catch {
      connectStatus = error.localizedDescription
    }
  }

  private func finish(_ state: GarminConnectSession.LoginState) async {
    switch state {
    case .needsCode(let method):
      awaitingCodeVia = method
      connectStatus =
        method.lowercased() == "email"
        ? "Garmin hat dir einen Code per E-Mail geschickt." : "Garmin hat dir einen Code geschickt (\(method))."
    case .loggedIn:
      awaitingCodeVia = nil
      connectLoggedIn = true
      connectStatus = "Angemeldet. Daten werden abgerufen …"
      await model.syncNow()
      connectStatus = model.lastError ?? model.lastReport.map { "Abgerufen: \($0.summary)" } ?? "Angemeldet."
    }
  }

  func logoutConnect() {
    model.garmin.connect?.logout()
    connectLoggedIn = false
    awaitingCodeVia = nil
    connectStatus = "Abgemeldet."
  }

  func saveExpiry() {
    defaults.set(keyExpiry, forKey: Self.keyExpiryKey)
  }

  func removeGarminKey() {
    try? model.garmin.updateKey("")
    defaults.removeObject(forKey: Self.keyExpiryKey)
    garminStatus = "Key entfernt."
  }

  func saveAndTestAI() async {
    isBusy = true
    defer { isBusy = false }
    do {
      try model.ai.configure(url: workerURLInput, token: appTokenInput)
      appTokenInput = ""
      workerURLInput = model.ai.workerURL
      let response = try await model.ai.run(task: "ping")
      let greeting = response.output["gruss"]?.stringValue ?? "ok"
      aiStatus = "\(greeting) (\(response.provider), \(response.model))"
    } catch {
      aiStatus = error.localizedDescription
    }
  }
}
