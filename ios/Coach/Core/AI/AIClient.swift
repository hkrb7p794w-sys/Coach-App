import CoachCore
import CryptoKit
import Foundation

nonisolated struct AIResponse: Decodable, Equatable {
  let output: JSONValue
  let model: String
  let provider: String
  let usage: Usage?

  struct Usage: Decodable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let listPriceUsd: Double?
  }
}

private nonisolated struct AIErrorBody: Decodable {
  let error: String
}

enum AIClientError: Error, LocalizedError, Equatable {
  case notConfigured
  case invalidURL
  case unauthorized
  case http(Int, String)
  case network(String)
  /// Die KI-Stufe in den Einstellungen erlaubt diese Anfrage nicht.
  case disabled(String)

  var errorDescription: String? {
    switch self {
    case .notConfigured: "KI-Worker ist nicht eingerichtet (Adresse und App-Token in den Einstellungen)."
    case .invalidURL: "Die Worker-Adresse muss mit https:// beginnen."
    case .unauthorized: "Der Worker hat das App-Token abgelehnt."
    case .http(let status, let message): "KI-Worker HTTP \(status): \(message)"
    case .network(let detail): "Netzwerkfehler: \(detail)"
    case .disabled(let message): message
    }
  }
}

/// Spricht mit dem Cloudflare Worker, der die KI-Anfragen weiterreicht. Die KI-Keys liegen nur dort;
/// die App kennt nur die Worker-Adresse und ein eigenes App-Token (im Keychain).
final class AIClient {
  static let urlKey = "ai.workerURL"
  private let secrets: any SecretStore
  private let defaults: UserDefaults
  private let session: URLSession
  /// Eigene Quellen aus den Einstellungen; gehen bei jeder passenden Aufgabe als belegte Regeln mit.
  var userSources: () -> [UserSource] = { [] }
  /// KI-Stufe und Anbieter (aus den Einstellungen); gilt für jede Aufgabe.
  var settings: () -> AISettings = { AISettings() }
  /// Meldet jede Anfrage für das interne Nutzungsprotokoll (ohne Inhalte).
  var onUsage: (AIUsageEntry) -> Void = { _ in }

  init(secrets: any SecretStore, defaults: UserDefaults = .standard, session: URLSession = .shared) {
    self.secrets = secrets
    self.defaults = defaults
    self.session = session
  }

  var workerURL: String {
    defaults.string(forKey: Self.urlKey) ?? ""
  }

  var hasToken: Bool {
    !(secrets.string(for: .aiAppToken) ?? "").isEmpty
  }

  var isConfigured: Bool {
    Self.normalizedURL(workerURL) != nil && hasToken
  }

  /// Private SideStore-Quelle des Workers (`worker/src/sidestore.ts`): Pfad aus SHA-256("sidestore:" + Token).
  /// Nur mit dem Haupt-Token: Ein Gast-Token öffnet die Quelle nicht (`worker/src/auth.ts`).
  var sideStoreSourceURL: URL? {
    guard let base = Self.normalizedURL(workerURL), let token = secrets.string(for: .aiAppToken), !token.isEmpty,
      !GuestToken.isGuest(token)
    else { return nil }
    return base.appending(path: "sidestore/\(Self.sideStoreKey(token: token))/source.json")
  }

  static func sideStoreKey(token: String) -> String {
    let digest = SHA256.hash(data: Data("sidestore:\(token)".utf8))
    return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
  }

  /// Speichert Adresse und (falls angegeben) Token. Ein leeres Token-Feld lässt das gespeicherte stehen.
  func configure(url: String, token: String) throws {
    guard let normalized = Self.normalizedURL(url) else { throw AIClientError.invalidURL }
    defaults.set(normalized.absoluteString, forKey: Self.urlKey)
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { try secrets.set(trimmed, for: .aiAppToken) }
  }

  static func normalizedURL(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    guard let url = URL(string: trimmed), url.scheme == "https", url.host() != nil else { return nil }
    return url
  }

  /// Bild für KI-Aufgaben (JPEG, bereits verkleinert).
  struct Image {
    let mimeType: String
    let data: Data
  }

  /// Darf die Aufgabe laufen? Für Knöpfe und automatische Abläufe, bevor sie die KI fragen.
  func allows(_ task: String, trigger: AITrigger = .user) -> Bool {
    isConfigured && AIPolicy.allows(settings().mode, task: task, trigger: trigger)
  }

  /// `trigger: .automatic` für alles, was ohne Antippen startet (z. B. Notiz beim Öffnen).
  func run(
    task: String, input: [String: JSONValue] = [:], images: [Image] = [], trigger: AITrigger = .user
  ) async throws -> AIResponse {
    let settings = settings()
    guard AIPolicy.allows(settings.mode, task: task, trigger: trigger) else {
      throw AIClientError.disabled(AIPolicy.blockedMessage(settings.mode))
    }
    let started = Date()
    do {
      let response = try await generate(task: task, input: input, images: images, provider: settings.provider)
      onUsage(
        AIUsageEntry(
          date: started, task: task, trigger: trigger, provider: response.provider, model: response.model, ok: true,
          inputTokens: response.usage?.inputTokens, outputTokens: response.usage?.outputTokens,
          listPriceUsd: response.usage?.listPriceUsd, milliseconds: Self.milliseconds(since: started)))
      return response
    } catch {
      if error as? AIClientError != .notConfigured {
        onUsage(
          AIUsageEntry(
            date: started, task: task, trigger: trigger, provider: nil, model: nil, ok: false,
            milliseconds: Self.milliseconds(since: started), error: error.localizedDescription))
      }
      throw error
    }
  }

  private static func milliseconds(since start: Date) -> Int {
    Int(Date().timeIntervalSince(start) * 1000)
  }

  private func generate(
    task: String, input: [String: JSONValue], images: [Image], provider: AIProviderChoice
  ) async throws -> AIResponse {
    let input = UserSources.inject(userSources(), into: input, task: task)
    var body: [String: JSONValue] = [
      "task": .string(task), "input": .object(input), "provider": .string(provider.rawValue),
    ]
    if !images.isEmpty {
      body["images"] = .array(
        images.map {
          .object(["mimeType": .string($0.mimeType), "data": .string($0.data.base64EncodedString())])
        })
    }
    let data = try await send(
      path: "v1/ai/generate", method: "POST", body: try JSONEncoder().encode(JSONValue.object(body)), timeout: 120)
    return try JSONDecoder().decode(AIResponse.self, from: data)
  }

  /// App-Token für die Anmeldung am Worker.
  var appToken: String? {
    secrets.string(for: .aiAppToken).flatMap { $0.isEmpty ? nil : $0 }
  }

  /// Eingeladen (Gast-Token) statt Betreiber:in des Workers.
  var isGuest: Bool { appToken.map(GuestToken.isGuest) ?? false }

  /// Neues Gast-Token für eine Einladung (nur mit dem Haupt-Token).
  func createGuestToken() async throws -> String {
    struct Invite: Decodable { let token: String }
    let data = try await send(path: "v1/invite", method: "POST")
    return try JSONDecoder().decode(Invite.self, from: data).token
  }

  /// Anfrage an den Worker mit App-Token; liefert den Antwortkörper bei Status 2xx.
  func send(
    path: String, method: String, body: Data? = nil, query: [URLQueryItem] = [], timeout: TimeInterval = 30
  ) async throws -> Data {
    guard let base = Self.normalizedURL(workerURL), let token = appToken else {
      throw AIClientError.notConfigured
    }
    var url = base.appending(path: path)
    if !query.isEmpty { url.append(queryItems: query) }
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = body

    let result: (Data, URLResponse)
    do {
      result = try await session.data(for: request)
    } catch {
      throw AIClientError.network(error.localizedDescription)
    }
    let (data, response) = result
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if status == 401 { throw AIClientError.unauthorized }
      let message = (try? JSONDecoder().decode(AIErrorBody.self, from: data))?.error ?? "unbekannter Fehler"
      throw AIClientError.http(status, message)
    }
    return data
  }
}
