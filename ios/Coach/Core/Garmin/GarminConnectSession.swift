import CoachCore
import Foundation

enum GarminConnectError: Error, LocalizedError, Equatable {
  case invalidCredentials
  case blocked(String)
  case needsLogin
  case codeRejected
  case unexpected(String)

  var errorDescription: String? {
    switch self {
    case .invalidCredentials: "E-Mail oder Passwort falsch."
    case .blocked(let detail): "Garmin blockiert die Anmeldung gerade (\(detail)). Bitte später erneut versuchen."
    case .needsLogin: "Garmin-Anmeldung abgelaufen. Bitte in den Einstellungen neu anmelden."
    case .codeRejected: "Der Bestätigungscode wurde nicht akzeptiert."
    case .unexpected(let detail): "Garmin-Anmeldung fehlgeschlagen: \(detail)"
    }
  }
}

/// Inoffizieller Garmin-Connect-Zugang (Ablauf in `CoachCore/GarminConnect`). Das Passwort wird nie
/// gespeichert, nur das Token (Schlüsselbund) und die E-Mail-Adresse (zur Anzeige).
final class GarminConnectSession {
  enum LoginState: Equatable {
    case loggedIn
    case needsCode(method: String)
  }

  static let emailKey = "garminConnect.email"
  static let displayNameKey = "garminConnect.displayName"

  private let secrets: any SecretStore
  private let defaults: UserDefaults
  private let makeSession: () -> URLSession
  /// Für Token-Erneuerung und API-Abrufe (ohne Anmelde-Cookies).
  private let apiSession: URLSession
  /// Pause zwischen Anmeldeseite und Absenden (wie die App; sonst antwortet Cloudflare mit 429).
  var pause: () async -> Void = { try? await Task.sleep(for: .seconds(Double.random(in: 2...5))) }
  private var cachedToken: GarminConnect.Token?
  /// Sitzung mit den Cookies der laufenden Anmeldung (für den Bestätigungscode).
  private var loginSession: URLSession?
  private var pendingMethod: String?

  init(
    secrets: any SecretStore, defaults: UserDefaults = .standard,
    makeSession: @escaping () -> URLSession = { URLSession(configuration: .ephemeral) }
  ) {
    self.secrets = secrets
    self.defaults = defaults
    self.makeSession = makeSession
    apiSession = makeSession()
  }

  var isLoggedIn: Bool { storedToken() != nil }
  var email: String? { defaults.string(forKey: Self.emailKey) }
  var displayName: String? { defaults.string(forKey: Self.displayNameKey) }

  // MARK: - Anmeldung

  func login(email: String, password: String) async throws -> LoginState {
    let session = makeSession()
    loginSession = session
    pendingMethod = nil
    let (_, pageStatus) = try await send(GarminConnect.signInPage, session: session)
    if pageStatus == 429 || pageStatus == 427 || pageStatus == 403 {
      throw GarminConnectError.blocked("Anmeldeseite HTTP \(pageStatus)")
    }
    await pause()
    let request = GarminConnect.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
    let (body, status) = try await send(request, session: session)
    defaults.set(email.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.emailKey)
    return try await handle(GarminConnect.loginResult(status: status, body: body), session: session)
  }

  func submitCode(_ code: String) async throws -> LoginState {
    guard let session = loginSession, let method = pendingMethod else { throw GarminConnectError.needsLogin }
    let request = GarminConnect.verifyCode(code.trimmingCharacters(in: .whitespacesAndNewlines), method: method)
    let (body, status) = try await send(request, session: session)
    let result = GarminConnect.loginResult(status: status, body: body)
    if case .unexpected = result { throw GarminConnectError.codeRejected }
    return try await handle(result, session: session)
  }

  func logout() {
    try? secrets.set(nil, for: .garminConnectToken)
    cachedToken = nil
    loginSession = nil
    pendingMethod = nil
    defaults.removeObject(forKey: Self.displayNameKey)
  }

  private func handle(_ result: GarminConnect.LoginResult, session: URLSession) async throws -> LoginState {
    switch result {
    case .ticket(let ticket):
      try await exchange(ticket: ticket, session: session)
      loginSession = nil
      pendingMethod = nil
      return .loggedIn
    case .needsCode(let method):
      pendingMethod = method
      return .needsCode(method: method)
    case .invalidCredentials:
      throw GarminConnectError.invalidCredentials
    case .blocked(let detail):
      throw GarminConnectError.blocked(detail)
    case .unexpected(let detail):
      throw GarminConnectError.unexpected(detail)
    }
  }

  /// Ticket gegen ein Token tauschen (Client-Kennungen der Reihe nach) und mit einem Abruf prüfen.
  private func exchange(ticket: String, session: URLSession) async throws {
    for clientID in GarminConnect.diClientIDs {
      let (body, status) = try await send(GarminConnect.exchange(ticket: ticket, clientID: clientID), session: session)
      if status == 429 { throw GarminConnectError.blocked("Token-Tausch HTTP 429") }
      guard (200..<300).contains(status), let token = GarminConnect.Token(response: body, clientID: clientID) else {
        continue
      }
      store(token)
      let profile = try await json(.socialProfile)
      if let name = profile["displayName"]?.stringValue { defaults.set(name, forKey: Self.displayNameKey) }
      return
    }
    throw GarminConnectError.unexpected("Token-Tausch fehlgeschlagen")
  }

  // MARK: - Token

  func validToken(forceRefresh: Bool = false) async throws -> GarminConnect.Token {
    guard let token = cachedToken ?? storedToken() else { throw GarminConnectError.needsLogin }
    guard forceRefresh || token.needsRefresh() else { return token }
    guard let request = GarminConnect.refresh(token) else { throw GarminConnectError.needsLogin }
    let (body, status) = try await send(request, session: apiSession)
    guard (200..<300).contains(status), var fresh = GarminConnect.Token(response: body, clientID: token.clientID)
    else {
      // Abgelehnt: neu anmelden. Netz- oder Serverfehler: altes Token behalten, solange es gilt.
      if status == 400 || status == 401 { logout() }
      if token.expiresAt > .now, status >= 500 { return token }
      throw GarminConnectError.needsLogin
    }
    if fresh.refreshToken == nil { fresh.refreshToken = token.refreshToken }
    store(fresh)
    return fresh
  }

  private func store(_ token: GarminConnect.Token) {
    cachedToken = token
    if let data = try? JSONEncoder().encode(token) {
      try? secrets.set(String(decoding: data, as: UTF8.self), for: .garminConnectToken)
    }
  }

  private func storedToken() -> GarminConnect.Token? {
    if let cachedToken { return cachedToken }
    guard let text = secrets.string(for: .garminConnectToken) else { return nil }
    return try? JSONDecoder().decode(GarminConnect.Token.self, from: Data(text.utf8))
  }

  // MARK: - Abrufe

  /// GET auf connectapi; bei 401 einmal das Token erneuern.
  func data(path: String, query: [GarminRequest.QueryItem] = [], accept: String = "application/json") async throws
    -> Data
  {
    var token = try await validToken()
    for attempt in 0..<2 {
      let request = GarminConnect.apiRequest(path: path, query: query, token: token, accept: accept)
      let (body, status) = try await send(request, session: apiSession)
      if status == 401, attempt == 0 {
        token = try await validToken(forceRefresh: true)
        continue
      }
      if let error = GarminAPIError.from(status: status, isTokenExchange: false) { throw error }
      return body
    }
    throw GarminAPIError.unauthorized
  }

  /// Lädt eine FIT-Datei als Aktivität hoch. `true` = neu angelegt, `false` = war schon vorhanden (409).
  func upload(fit: Data, fileName: String) async throws -> Bool {
    var token = try await validToken()
    for attempt in 0..<2 {
      let request = GarminConnect.uploadRequest(
        fit: fit, fileName: fileName, token: token, boundary: "coach-\(UUID().uuidString)")
      let (_, status) = try await send(request, session: apiSession)
      if status == 401, attempt == 0 {
        token = try await validToken(forceRefresh: true)
        continue
      }
      if status == 409 { return false }
      if let error = GarminAPIError.from(status: status, isTokenExchange: false) { throw error }
      return true
    }
    throw GarminAPIError.unauthorized
  }

  func json(_ endpoint: ConnectEndpoint) async throws -> JSONValue {
    let body = try await data(path: endpoint.path, query: endpoint.query)
    return body.isEmpty ? .null : try JSONValue(data: body)
  }

  private func send(_ request: GarminConnect.Request, session: URLSession) async throws -> (Data, Int) {
    var urlRequest = URLRequest(url: request.url, timeoutInterval: 30)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
    do {
      let (data, response) = try await session.data(for: urlRequest)
      guard let http = response as? HTTPURLResponse else { throw GarminAPIError.invalidResponse }
      return (data, http.statusCode)
    } catch let error as GarminAPIError {
      throw error
    } catch {
      throw GarminAPIError.network(error.localizedDescription)
    }
  }
}
