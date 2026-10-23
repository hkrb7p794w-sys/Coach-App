import CoachCore
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

  func run(task: String, input: [String: JSONValue] = [:]) async throws -> AIResponse {
    guard let base = Self.normalizedURL(workerURL), let token = secrets.string(for: .aiAppToken) else {
      throw AIClientError.notConfigured
    }
    var request = URLRequest(url: base.appending(path: "v1/ai/generate"), timeoutInterval: 120)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(JSONValue.object(["task": .string(task), "input": .object(input)]))

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw AIClientError.network(error.localizedDescription)
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      if status == 401 { throw AIClientError.unauthorized }
      let message = (try? JSONDecoder().decode(AIErrorBody.self, from: data))?.error ?? "unbekannter Fehler"
      throw AIClientError.http(status, message)
    }
    return try JSONDecoder().decode(AIResponse.self, from: data)
  }
}
