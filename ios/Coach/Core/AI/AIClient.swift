import CoachCore
import CryptoKit
import Foundation

nonisolated struct AIResponse: Decodable, Equatable {
  let output: JSONValue
  let model: String
  let provider: String
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

  var errorDescription: String? {
    switch self {
    case .notConfigured: "KI-Worker ist nicht eingerichtet (Adresse und App-Token in den Einstellungen)."
    case .invalidURL: "Die Worker-Adresse muss mit https:// beginnen."
    case .unauthorized: "Der Worker hat das App-Token abgelehnt."
    case .http(let status, let message): "KI-Worker HTTP \(status): \(message)"
    case .network(let detail): "Netzwerkfehler: \(detail)"
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
  var sideStoreSourceURL: URL? {
    guard let base = Self.normalizedURL(workerURL), let token = secrets.string(for: .aiAppToken), !token.isEmpty
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

  func run(task: String, input: [String: JSONValue] = [:], images: [Image] = []) async throws -> AIResponse {
    var body: [String: JSONValue] = ["task": .string(task), "input": .object(input)]
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

  /// App-Token für den Einladungslink der Rangliste.
  var appToken: String? {
    secrets.string(for: .aiAppToken).flatMap { $0.isEmpty ? nil : $0 }
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
