import Foundation

/// Fokus während einer Krafteinheit. iOS lässt Apps den Fokus nicht selbst schalten; der offizielle Weg sind
/// Kurzbefehle: Die App startet über `shortcuts://x-callback-url/run-shortcut` zwei Kurzbefehle der Person
/// (Aktion „Fokus festlegen“) und kehrt danach über `coach://` zurück.
/// Quelle: <https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios>
public enum WorkoutFocus {
  public static let onShortcut = "IronLudi Training an"
  public static let offShortcut = "IronLudi Training aus"
  public static let returnURL = "coach://gym"

  public static func url(turningOn: Bool) -> URL? {
    var components = URLComponents()
    components.scheme = "shortcuts"
    components.host = "x-callback-url"
    components.path = "/run-shortcut"
    components.queryItems = [
      URLQueryItem(name: "name", value: turningOn ? onShortcut : offShortcut),
      URLQueryItem(name: "x-success", value: returnURL),
      URLQueryItem(name: "x-cancel", value: returnURL),
      URLQueryItem(name: "x-error", value: returnURL),
    ]
    return components.url
  }
}
