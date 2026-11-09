import CoachCore
import Foundation
import Observation
import UIKit

/// Eigenes Konto am Worker (`worker/src/accounts.ts`): Registrieren mit Einladung, Anmelden, Sitzungen.
/// Das Sitzungs-Token liegt nur im Keychain dieses Geräts; Benutzername und Anzeigename zusätzlich in den
/// Einstellungen, damit die App sie auch offline zeigt. Gesundheitsdaten gehen dabei nicht an den Worker.
@Observable
final class AccountService {
  struct Account: Codable, Equatable {
    var id: String
    var username: String
    var displayName: String
    var isAdmin: Bool
  }

  struct Session: Decodable, Equatable, Identifiable {
    var device: String
    var createdAt: String
    var lastUsed: String
    var current: Bool
    var id: String { "\(device)-\(createdAt)" }
  }

  struct Invite: Decodable, Equatable, Identifiable {
    var code: String
    var expiresAt: String
    var id: String { code }
  }

  static let accountKey = "account.profile"

  private(set) var account: Account?
  private(set) var sessions: [Session] = []
  private(set) var invites: [Invite] = []
  /// Hinweis, wenn die Sitzung vom Worker abgelehnt wurde.
  private(set) var notice: String?

  private let ai: AIClient
  private let defaults: UserDefaults

  init(ai: AIClient, defaults: UserDefaults = .standard) {
    self.ai = ai
    self.defaults = defaults
    if ai.hasSession, let data = defaults.data(forKey: Self.accountKey) {
      account = try? JSONDecoder().decode(Account.self, from: data)
    }
    ai.onSessionRejected = { [weak self] in
      Task { @MainActor in self?.signedOutByServer() }
    }
  }

  var isSignedIn: Bool { account != nil && ai.hasSession }

  /// Ohne App-Token braucht die Registrierung einen Einladungscode.
  var needsInviteCode: Bool { ai.appToken == nil }

  var workerURL: String { ai.workerURL }

  private var device: String {
    "\(UIDevice.current.model) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))"
  }

  // MARK: - Anmelden

  private struct AuthResponse: Decodable {
    let token: String
    let account: Account
    let recoveryCode: String?
  }

  /// Server-Adresse übernehmen, falls noch keine gespeichert ist oder eine Einladung eine andere nennt.
  func useServer(_ url: String) throws {
    guard let normalized = AIClient.normalizedURL(url) else { throw AIClientError.invalidURL }
    if AIClient.normalizedURL(ai.workerURL) != normalized {
      try ai.configure(url: normalized.absoluteString, token: "")
    }
  }

  /// Neues Konto; liefert den Wiederherstellungscode (nur einmal anzeigen).
  func register(username: String, displayName: String, password: String, invite: String) async throws -> String {
    let body: [String: String] = [
      "username": AccountRules.normalizeUsername(username),
      "displayName": AccountRules.displayName(displayName) ?? "",
      "password": password,
      "invite": AccountRules.normalizeCode(invite),
      "device": device,
    ]
    let data = try await ai.send(
      path: "v1/account/register", method: "POST", body: try JSONEncoder().encode(body),
      auth: ai.appToken == nil ? .none : .appToken)
    let response = try JSONDecoder().decode(AuthResponse.self, from: data)
    try store(response)
    return response.recoveryCode ?? ""
  }

  func login(username: String, password: String) async throws {
    let body = ["username": AccountRules.normalizeUsername(username), "password": password, "device": device]
    let data = try await ai.send(
      path: "v1/account/login", method: "POST", body: try JSONEncoder().encode(body), auth: .none)
    try store(try JSONDecoder().decode(AuthResponse.self, from: data))
  }

  /// Neues Passwort mit dem Wiederherstellungscode; liefert den neuen Code.
  func recover(username: String, recoveryCode: String, newPassword: String) async throws -> String {
    let body = [
      "username": AccountRules.normalizeUsername(username), "recoveryCode": recoveryCode,
      "newPassword": newPassword, "device": device,
    ]
    let data = try await ai.send(
      path: "v1/account/recover", method: "POST", body: try JSONEncoder().encode(body), auth: .none)
    let response = try JSONDecoder().decode(AuthResponse.self, from: data)
    try store(response)
    return response.recoveryCode ?? ""
  }

  private func store(_ response: AuthResponse) throws {
    try ai.setSession(response.token)
    account = response.account
    notice = nil
    defaults.set(try JSONEncoder().encode(response.account), forKey: Self.accountKey)
  }

  private func clearLocal() {
    try? ai.setSession(nil)
    account = nil
    sessions = []
    invites = []
    defaults.removeObject(forKey: Self.accountKey)
  }

  private func signedOutByServer() {
    guard account != nil else { return }
    clearLocal()
    notice = "Du wurdest abgemeldet (Passwort geändert, auf einem anderen Gerät abgemeldet oder lange nicht genutzt)."
  }

  // MARK: - Konto verwalten

  private struct MeResponse: Decodable {
    let account: Account
    let sessions: [Session]
  }

  func refresh() async throws {
    guard isSignedIn else { return }
    let data = try await ai.send(path: "v1/account/me", method: "GET", auth: .session)
    let response = try JSONDecoder().decode(MeResponse.self, from: data)
    account = response.account
    sessions = response.sessions
    defaults.set(try JSONEncoder().encode(response.account), forKey: Self.accountKey)
    try await loadInvites()
  }

  func logout(everywhere: Bool = false) async {
    let body = try? JSONEncoder().encode(["all": everywhere])
    _ = try? await ai.send(path: "v1/account/logout", method: "POST", body: body, auth: .session)
    clearLocal()
  }

  func changePassword(old: String, new: String) async throws {
    let body = try JSONEncoder().encode(["oldPassword": old, "newPassword": new])
    _ = try await ai.send(path: "v1/account/password", method: "POST", body: body, auth: .session)
    try await refresh()
  }

  func updateDisplayName(_ name: String) async throws {
    struct Response: Decodable { let account: Account }
    let body = try JSONEncoder().encode(["displayName": AccountRules.displayName(name) ?? name])
    let data = try await ai.send(path: "v1/account/profile", method: "PATCH", body: body, auth: .session)
    let updated = try JSONDecoder().decode(Response.self, from: data).account
    account = updated
    defaults.set(try JSONEncoder().encode(updated), forKey: Self.accountKey)
  }

  func deleteAccount(password: String) async throws {
    let body = try JSONEncoder().encode(["password": password])
    _ = try await ai.send(path: "v1/account/delete", method: "POST", body: body, auth: .session)
    clearLocal()
  }

  // MARK: - Einladungen

  func loadInvites() async throws {
    struct Response: Decodable { let invites: [Invite] }
    let data = try await ai.send(path: "v1/account/invites", method: "GET", auth: .session)
    invites = try JSONDecoder().decode(Response.self, from: data).invites
  }

  /// Neue Einladung als Link zur Einladungsseite des Workers.
  func createInvite() async throws -> AccountInvite {
    let data = try await ai.send(path: "v1/account/invites", method: "POST", body: Data("{}".utf8), auth: .session)
    let invite = try JSONDecoder().decode(Invite.self, from: data)
    try? await loadInvites()
    guard let base = AIClient.normalizedURL(ai.workerURL) else { throw AIClientError.notConfigured }
    return AccountInvite(workerURL: base.absoluteString, code: invite.code)
  }

  func deleteInvite(_ code: String) async {
    _ = try? await ai.send(path: "v1/account/invites/\(code)", method: "DELETE", auth: .session)
    try? await loadInvites()
  }

  func inviteLink(for code: String) -> AccountInvite? {
    guard let base = AIClient.normalizedURL(ai.workerURL) else { return nil }
    return AccountInvite(workerURL: base.absoluteString, code: code)
  }
}
