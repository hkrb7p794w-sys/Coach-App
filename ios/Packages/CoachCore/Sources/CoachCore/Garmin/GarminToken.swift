import Foundation

/// Bearer-Token der Personal API. Der API-Key wird per `POST` gegen ein Token getauscht,
/// das laut Garmins offiziellem Client 24 Stunden gilt; erneuert wird, wenn weniger als eine
/// Stunde Restlaufzeit bleibt.
public struct GarminBearerToken: Codable, Equatable, Sendable {
  public static let refreshWindow: TimeInterval = 3_600
  /// Fallback, wenn das Token kein lesbares JWT ist.
  public static let fallbackLifetime: TimeInterval = 23 * 3_600

  public let value: String
  public let expiresAt: Date

  public init(value: String, expiresAt: Date) {
    self.value = value
    self.expiresAt = expiresAt
  }

  /// Baut das Token aus der Antwort des Token-Endpunkts (reiner Text, ein JWT).
  public init?(responseBody: String, now: Date = .now) {
    let token = responseBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else { return nil }
    self.init(
      value: token,
      expiresAt: Self.jwtExpiration(token) ?? now.addingTimeInterval(Self.fallbackLifetime)
    )
  }

  public func needsRefresh(now: Date = .now) -> Bool {
    expiresAt.timeIntervalSince(now) <= Self.refreshWindow
  }

  /// Liest `exp` aus dem Payload eines JWT (ohne Signaturprüfung – nur für die Ablaufplanung).
  public static func jwtExpiration(_ token: String) -> Date? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    guard let data = Data(base64Encoded: base64),
      let payload = try? JSONValue(data: data),
      let exp = payload["exp"]?.doubleValue
    else { return nil }
    return Date(timeIntervalSince1970: exp)
  }
}

/// Fehlerbilder der Personal API in Klartext.
public enum GarminAPIError: Error, Equatable, Sendable {
  case missingKey
  /// 401/403 beim Token-Tausch: Key falsch, abgelaufen oder gelöscht.
  case keyRejected
  /// 401 bei einem Datenabruf trotz frischem Token.
  case unauthorized
  case rateLimited
  /// 400/500 ohne Inhalt, typischerweise ein zu großer Datumsbereich.
  case rejectedRequest(status: Int)
  case server(status: Int)
  case invalidResponse
  case network(String)

  public static func from(status: Int, isTokenExchange: Bool) -> GarminAPIError? {
    switch status {
    case 200..<300: nil
    case 401, 403: isTokenExchange ? .keyRejected : .unauthorized
    case 429: .rateLimited
    case 400, 404, 422: .rejectedRequest(status: status)
    default: .server(status: status)
    }
  }

  public var message: String {
    switch self {
    case .missingKey:
      "Kein Garmin-API-Key hinterlegt."
    case .keyRejected:
      "Garmin hat den API-Key abgelehnt. Er ist falsch, abgelaufen oder wurde gelöscht – bitte in Garmin Connect "
        + "einen neuen Key erzeugen."
    case .unauthorized:
      "Garmin hat die Anfrage nicht autorisiert."
    case .rateLimited:
      "Garmin begrenzt gerade die Anfragen. Bitte später erneut versuchen."
    case .rejectedRequest(let status):
      "Garmin hat die Anfrage abgelehnt (HTTP \(status))."
    case .server(let status):
      "Garmin-Server-Fehler (HTTP \(status))."
    case .invalidResponse:
      "Unerwartete Antwort von Garmin."
    case .network(let detail):
      "Netzwerkfehler: \(detail)"
    }
  }
}
