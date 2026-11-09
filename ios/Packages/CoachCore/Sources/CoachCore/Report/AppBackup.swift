import Foundation

/// Datensicherung der iPhone-App als eine JSON-Datei: Einstellungen (UserDefaults), Krafteinheiten, Mahlzeiten und
/// eigene Lebensmittel. Nicht enthalten: Zugangsdaten aus dem Schlüsselbund (Garmin, App-Token) und Garmin-/Health-
/// Daten, die beim nächsten Abruf ohnehin wiederkommen. Einspielen führt zusammen: Vorhandenes bleibt, Fehlendes
/// kommt dazu; Einstellungen werden ersetzt.
public struct AppBackup: Codable, Equatable, Sendable {
  public static let currentVersion = 1
  public static let fileName = "IronLudi-Sicherung.json"
  public static let previousFileName = "IronLudi-Sicherung-vorher.json"
  /// Automatische Sicherung höchstens so oft.
  public static let autoInterval: TimeInterval = 20 * 3_600

  public enum Value: Codable, Equatable, Sendable {
    case data(Data)
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      switch try container.decode(String.self, forKey: .type) {
      case "data": self = .data(try container.decode(Data.self, forKey: .value))
      case "string": self = .string(try container.decode(String.self, forKey: .value))
      case "bool": self = .bool(try container.decode(Bool.self, forKey: .value))
      case "int": self = .int(try container.decode(Int.self, forKey: .value))
      case "double": self = .double(try container.decode(Double.self, forKey: .value))
      case let other:
        throw DecodingError.dataCorruptedError(
          forKey: .type, in: container, debugDescription: "Unbekannter Typ \(other)")
      }
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .data(let value):
        try container.encode("data", forKey: .type)
        try container.encode(value, forKey: .value)
      case .string(let value):
        try container.encode("string", forKey: .type)
        try container.encode(value, forKey: .value)
      case .bool(let value):
        try container.encode("bool", forKey: .type)
        try container.encode(value, forKey: .value)
      case .int(let value):
        try container.encode("int", forKey: .type)
        try container.encode(value, forKey: .value)
      case .double(let value):
        try container.encode("double", forKey: .type)
        try container.encode(value, forKey: .value)
      }
    }
  }

  public struct Gym: Codable, Equatable, Sendable {
    public var id: UUID
    /// `GymSession` als JSON, unverändert aus der Datenbank.
    public var payload: Data
    public var savedToHealth: Bool
    public var uploadedToGarmin: Bool

    public init(id: UUID, payload: Data, savedToHealth: Bool, uploadedToGarmin: Bool) {
      self.id = id
      self.payload = payload
      self.savedToHealth = savedToHealth
      self.uploadedToGarmin = uploadedToGarmin
    }
  }

  public struct Meal: Codable, Equatable, Sendable {
    public var id: UUID
    public var dayKey: String
    public var createdAt: Date
    public var category: String
    public var title: String
    public var hint: String
    /// `[MealItem]` als JSON.
    public var items: Data

    public init(
      id: UUID, dayKey: String, createdAt: Date, category: String, title: String, hint: String, items: Data
    ) {
      self.id = id
      self.dayKey = dayKey
      self.createdAt = createdAt
      self.category = category
      self.title = title
      self.hint = hint
      self.items = items
    }
  }

  public struct Food: Codable, Equatable, Sendable {
    public var key: String
    public var name: String
    /// `MealItem` als JSON.
    public var payload: Data
    public var lastUsed: Date
    public var useCount: Int

    public init(key: String, name: String, payload: Data, lastUsed: Date, useCount: Int) {
      self.key = key
      self.name = name
      self.payload = payload
      self.lastUsed = lastUsed
      self.useCount = useCount
    }
  }

  public enum Failure: Error, Equatable, LocalizedError {
    case unreadable
    case newerVersion(Int)

    public var errorDescription: String? {
      switch self {
      case .unreadable: "Die Datei ist keine IronLudi-Sicherung oder beschädigt."
      case .newerVersion(let version):
        "Die Sicherung stammt aus einer neueren App-Version (Format \(version)). Bitte erst IronLudi aktualisieren."
      }
    }
  }

  public var version: Int
  public var createdAt: Date
  public var settings: [String: Value]
  public var gym: [Gym]
  public var meals: [Meal]
  public var foods: [Food]

  public init(
    version: Int = AppBackup.currentVersion, createdAt: Date, settings: [String: Value], gym: [Gym], meals: [Meal],
    foods: [Food]
  ) {
    self.version = version
    self.createdAt = createdAt
    self.settings = settings
    self.gym = gym
    self.meals = meals
    self.foods = foods
  }

  /// Gesichert werden die App-Einstellungen (`coach.…`) und die Worker-Adresse. Nicht: Abrufstände von Garmin und
  /// Health (sonst fehlten nach dem Einspielen ältere Aktivitäten), der laufende Wecker und die gerade offene
  /// Krafteinheit.
  public static func isBackedUp(key: String) -> Bool {
    if key == "ai.workerURL" { return true }
    return key.hasPrefix("coach.") && !excludedKeys.contains(key)
  }

  static let excludedKeys: Set<String> = ["coach.wakeAlarm"]

  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }

  public static func decode(_ data: Data) throws -> AppBackup {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    struct Header: Decodable { var version: Int }
    guard let header = try? decoder.decode(Header.self, from: data) else { throw Failure.unreadable }
    guard header.version <= currentVersion else { throw Failure.newerVersion(header.version) }
    guard let backup = try? decoder.decode(AppBackup.self, from: data) else { throw Failure.unreadable }
    return backup
  }

  /// Kurzbeschreibung für die Bestätigung vor dem Einspielen.
  public var summary: String {
    "\(gym.count) Krafteinheiten, \(meals.count) Mahlzeiten, \(foods.count) eigene Lebensmittel, "
      + "\(settings.count) Einstellungen"
  }

  /// Automatische Sicherung fällig (nie gesichert oder länger als `autoInterval` her).
  public static func isDue(last: Date?, now: Date) -> Bool {
    guard let last else { return true }
    return now.timeIntervalSince(last) >= autoInterval || last > now
  }

  /// Was beim Zusammenführen dazukommt: nur Einträge, deren Schlüssel noch fehlt, ohne Doppelte in der Datei.
  public static func missing<Item, Key: Hashable>(
    _ items: [Item], key: (Item) -> Key, existing: Set<Key>
  ) -> [Item] {
    var seen = existing
    var result: [Item] = []
    for item in items where !seen.contains(key(item)) {
      seen.insert(key(item))
      result.append(item)
    }
    return result
  }
}
