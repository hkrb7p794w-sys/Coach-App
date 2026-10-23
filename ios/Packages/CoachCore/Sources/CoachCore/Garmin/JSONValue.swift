import Foundation

/// Beliebiges JSON, tolerant gelesen.
///
/// Die Antwortformate der Garmin Personal API sind nicht dokumentiert und können sich ändern.
/// Statt starrer `Decodable`-Strukturen werden Felder deshalb über mehrere mögliche Namen und in
/// verschachtelten Ebenen gesucht.
public enum JSONValue: Equatable, Sendable {
  case object([String: JSONValue])
  case array([JSONValue])
  case string(String)
  case number(Double)
  case bool(Bool)
  case null

  public init(data: Data) throws {
    self = try JSONDecoder().decode(JSONValue.self, from: data)
  }

  public subscript(key: String) -> JSONValue? {
    if case .object(let dictionary) = self { return dictionary[key] }
    return nil
  }

  public var objectValue: [String: JSONValue]? {
    if case .object(let dictionary) = self { return dictionary }
    return nil
  }

  public var arrayValue: [JSONValue]? {
    if case .array(let values) = self { return values }
    return nil
  }

  public var doubleValue: Double? {
    switch self {
    case .number(let value): value
    case .string(let text): Double(text)
    default: nil
    }
  }

  public var intValue: Int? {
    doubleValue.flatMap { $0.isFinite ? Int(exactly: $0.rounded()) : nil }
  }

  public var stringValue: String? {
    switch self {
    case .string(let text): text
    case .number(let value):
      value == value.rounded() && abs(value) < 9e15 ? String(Int64(value)) : String(value)
    default: nil
    }
  }

  /// Sucht den ersten Wert unter einem der Schlüssel, zuerst auf der obersten Ebene, dann
  /// in die Tiefe (Breitensuche). `null` zählt als nicht gefunden.
  public func firstValue(forAnyOf keys: [String]) -> JSONValue? {
    var queue: [JSONValue] = [self]
    var index = 0
    while index < queue.count {
      let current = queue[index]
      index += 1
      switch current {
      case .object(let dictionary):
        for key in keys {
          if let value = dictionary[key], value != .null { return value }
        }
        queue.append(contentsOf: dictionary.keys.sorted().compactMap { dictionary[$0] })
      case .array(let values):
        queue.append(contentsOf: values)
      default:
        break
      }
    }
    return nil
  }

  /// Alle Objekte im Baum, die den Schlüssel enthalten (äußerste zuerst, verschachtelte
  /// Treffer innerhalb eines Treffers werden nicht doppelt geliefert).
  public func objects(containingKey key: String) -> [[String: JSONValue]] {
    switch self {
    case .object(let dictionary):
      if dictionary[key] != nil { return [dictionary] }
      return dictionary.keys.sorted().flatMap { dictionary[$0]?.objects(containingKey: key) ?? [] }
    case .array(let values):
      return values.flatMap { $0.objects(containingKey: key) }
    default:
      return []
    }
  }

  /// Schlüsselpfade aller Blätter, z. B. `hrvSummary.status` oder `[].calendarDate`.
  /// Für die Diagnose: zeigt, welche Felder Garmin tatsächlich liefert.
  public func keyPaths(limit: Int = 200) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    func walk(_ value: JSONValue, _ path: String) {
      guard result.count < limit else { return }
      switch value {
      case .object(let dictionary):
        for key in dictionary.keys.sorted() {
          if let child = dictionary[key] { walk(child, path.isEmpty ? key : "\(path).\(key)") }
        }
      case .array(let values):
        for child in values.prefix(3) { walk(child, path + "[]") }
      default:
        if seen.insert(path).inserted { result.append(path) }
      }
    }
    walk(self, "")
    return result
  }
}

extension JSONValue: Decodable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }
}

extension Dictionary where Key == String, Value == JSONValue {
  /// Erster vorhandener Wert unter einem der Schlüssel, auch verschachtelt.
  func first(_ keys: String...) -> JSONValue? {
    JSONValue.object(self).firstValue(forAnyOf: keys)
  }
}
