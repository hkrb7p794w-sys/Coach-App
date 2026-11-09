import Foundation

/// Regeln für Konten, gleich wie im Worker (`worker/src/accounts.ts`), damit die App Fehler schon beim Tippen zeigt.
/// Entscheidend bleibt der Worker.
public enum AccountRules {
  public static let minPasswordLength = 10
  public static let maxPasswordLength = 128
  static let reserved: Set<String> = [
    "admin", "administrator", "coach", "ironludi", "support", "system", "root", "owner",
  ]

  public static func normalizeUsername(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// `nil`, wenn der Benutzername passt; sonst der Hinweis für die Anzeige.
  public static func usernameProblem(_ raw: String) -> String? {
    let username = normalizeUsername(raw)
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
    let startAllowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
    guard (3...20).contains(username.count), username.allSatisfy(allowed.contains),
      let first = username.first, startAllowed.contains(first)
    else {
      return
        "Benutzername: 3–20 Zeichen, nur a–z, 0–9, Punkt und Unterstrich, am Anfang ein Buchstabe oder eine Ziffer."
    }
    if reserved.contains(username) { return "Dieser Benutzername ist reserviert." }
    return nil
  }

  public static func passwordProblem(_ password: String, username: String) -> String? {
    if password.count < minPasswordLength { return "Das Passwort braucht mindestens 10 Zeichen." }
    if password.count > maxPasswordLength { return "Das Passwort darf höchstens 128 Zeichen haben." }
    let name = normalizeUsername(username)
    if !name.isEmpty, password.lowercased().contains(name) {
      return "Das Passwort darf den Benutzernamen nicht enthalten."
    }
    if Set(password).count < 4 { return "Das Passwort ist zu einfach." }
    return nil
  }

  /// Anzeigename: 1–40 Zeichen, mehrfache Leerzeichen zusammengefasst; leer = Benutzername.
  public static func displayName(_ raw: String) -> String? {
    let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if collapsed.isEmpty { return "" }
    return collapsed.count <= 40 ? collapsed : nil
  }

  /// Einladungs- bzw. Wiederherstellungscode vereinheitlichen: Großbuchstaben, ohne Leer- und Bindestriche.
  public static func normalizeCode(_ text: String) -> String {
    text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
  }
}

/// Einladung zu einem Konto: Server und einmaliger Code, als Link `coach://account?worker=…&invite=…`.
/// Kommt über die Einladungsseite des Workers (`/i/<code>`), die iPhone- und Android-Link anbietet.
public struct AccountInvite: Equatable, Sendable, Identifiable {
  public var workerURL: String
  public var code: String
  public var id: String { code }

  public init(workerURL: String, code: String) {
    self.workerURL = workerURL
    self.code = AccountRules.normalizeCode(code)
  }

  public init?(url: URL) {
    guard url.scheme == LeagueInvite.scheme, url.host() == "account",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }
    func value(_ name: String) -> String { items.first { $0.name == name }?.value ?? "" }
    let worker = value("worker")
    let code = AccountRules.normalizeCode(value("invite"))
    guard worker.hasPrefix("https://"), URL(string: worker)?.host() != nil, code.count == 10 else { return nil }
    self.init(workerURL: worker, code: code)
  }

  public var host: String? { URL(string: workerURL)?.host()?.lowercased() }

  public var url: URL? {
    var components = URLComponents()
    components.scheme = LeagueInvite.scheme
    components.host = "account"
    components.queryItems = [URLQueryItem(name: "worker", value: workerURL), URLQueryItem(name: "invite", value: code)]
    return components.url
  }

  /// Link zum Weitergeben: Seite des Workers, funktioniert in jeder Nachrichten-App und auf Android.
  public var shareURL: URL? {
    guard var base = URL(string: workerURL) else { return nil }
    base.append(path: "i/\(code)")
    return base
  }
}
