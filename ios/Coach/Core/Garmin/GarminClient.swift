import CoachCore
import Foundation

/// Zugriff auf die Garmin Connect Personal API.
///
/// Der persönliche API-Key (aus Garmin Connect, Einstellungen › Personal API Key) wird gegen ein
/// Bearer-Token getauscht, das im Keychain zwischengespeichert und kurz vor Ablauf erneuert wird.
///
/// Ist das Garmin-Konto angemeldet (`GarminConnectSession`), kommen die Daten zuerst von dort; die Personal API
/// springt je Abruf ein, wenn das Konto scheitert (abgelaufen, blockiert, Endpunkt unbekannt).
final class GarminClient {
  enum Source: String {
    case connect = "Garmin-Konto"
    case personalAPI = "Personal API"
  }

  private let secrets: any SecretStore
  private let session: URLSession
  private var cachedToken: GarminBearerToken?
  let connect: GarminConnectSession?
  /// Wer die Abrufe seit dem letzten `resetSources()` beantwortet hat (für den Abrufbericht).
  private(set) var sources: [Source: Int] = [:]
  /// Letzter Fehler des Garmin-Kontos, wenn die Personal API einspringen musste.
  private(set) var lastConnectError: String?

  init(secrets: any SecretStore, session: URLSession = .shared, connect: GarminConnectSession? = nil) {
    self.secrets = secrets
    self.session = session
    self.connect = connect
  }

  var hasKey: Bool {
    !(secrets.string(for: .garminAPIKey) ?? "").isEmpty
  }

  /// Mindestens ein Zugang ist eingerichtet.
  var isConfigured: Bool {
    hasKey || (connect?.isLoggedIn ?? false)
  }

  func resetSources() {
    sources = [:]
    lastConnectError = nil
  }

  /// Neuer Key: altes Token verwerfen.
  func updateKey(_ key: String) throws {
    try secrets.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: .garminAPIKey)
    try secrets.set(nil, for: .garminBearerToken)
    cachedToken = nil
  }

  func json(_ endpoint: GarminEndpoint) async throws -> JSONValue {
    let data = try await data(endpoint)
    return data.isEmpty ? .null : try JSONValue(data: data)
  }

  func data(_ endpoint: GarminEndpoint) async throws -> Data {
    if let connect, connect.isLoggedIn, endpoint != .tokenExchange {
      do {
        let request = endpoint.request
        let data = try await connect.data(path: request.path, query: request.query, accept: request.accept)
        sources[.connect, default: 0] += 1
        return data
      } catch {
        lastConnectError = (error as? GarminAPIError)?.message ?? error.localizedDescription
        guard hasKey else { throw error }
      }
    }
    let data = try await personalData(endpoint)
    sources[.personalAPI, default: 0] += 1
    return data
  }

  /// Nur über das Garmin-Konto verfügbare Werte (Readiness, Trainingsstatus …).
  func json(_ endpoint: ConnectEndpoint) async throws -> JSONValue {
    guard let connect, connect.isLoggedIn else { throw GarminConnectError.needsLogin }
    let value = try await connect.json(endpoint)
    sources[.connect, default: 0] += 1
    return value
  }

  private func personalData(_ endpoint: GarminEndpoint) async throws -> Data {
    do {
      return try await authorizedData(endpoint, token: validToken())
    } catch GarminAPIError.unauthorized {
      // Token von Garmin vorzeitig verworfen: einmal neu tauschen.
      return try await authorizedData(endpoint, token: validToken(forceRefresh: true))
    }
  }

  func validToken(forceRefresh: Bool = false) async throws -> GarminBearerToken {
    if !forceRefresh, let token = cachedToken ?? storedToken(), !token.needsRefresh() {
      cachedToken = token
      return token
    }
    guard let key = secrets.string(for: .garminAPIKey), !key.isEmpty else { throw GarminAPIError.missingKey }

    let request = try urlRequest(GarminEndpoint.tokenExchange.request, authorization: "ApiKey \(key)")
    let (data, status) = try await send(request)
    if let error = GarminAPIError.from(status: status, isTokenExchange: true) { throw error }
    guard let token = GarminBearerToken(responseBody: String(decoding: data, as: UTF8.self)) else {
      throw GarminAPIError.invalidResponse
    }
    cachedToken = token
    if let encoded = try? JSONEncoder().encode(token) {
      try? secrets.set(String(decoding: encoded, as: UTF8.self), for: .garminBearerToken)
    }
    return token
  }

  private func storedToken() -> GarminBearerToken? {
    guard let text = secrets.string(for: .garminBearerToken) else { return nil }
    return try? JSONDecoder().decode(GarminBearerToken.self, from: Data(text.utf8))
  }

  private func authorizedData(_ endpoint: GarminEndpoint, token: GarminBearerToken) async throws -> Data {
    let request = try urlRequest(endpoint.request, authorization: "Bearer \(token.value)")
    let (data, status) = try await send(request)
    if let error = GarminAPIError.from(status: status, isTokenExchange: false) { throw error }
    return data
  }

  private func urlRequest(_ request: GarminRequest, authorization: String) throws -> URLRequest {
    guard let url = request.url() else { throw GarminAPIError.invalidResponse }
    var urlRequest = URLRequest(url: url, timeoutInterval: 30)
    urlRequest.httpMethod = request.method
    urlRequest.setValue(request.accept, forHTTPHeaderField: "Accept")
    urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
    return urlRequest
  }

  private func send(_ request: URLRequest) async throws -> (Data, Int) {
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { throw GarminAPIError.invalidResponse }
      return (data, http.statusCode)
    } catch let error as GarminAPIError {
      throw error
    } catch {
      throw GarminAPIError.network(error.localizedDescription)
    }
  }
}
