import Foundation

/// Eigene wissenschaftliche Quellen der Person (Einstellungen › Coach › Eigene Quellen). Sie gehen als zusätzliche
/// „belegte Regeln“ an die KI (Gemini Flash im Worker) und dürfen dort zitiert werden. Die Entscheidungen der App
/// (Tagesampel, Ziele, Progression, Schutzgrenzen) ändern sie nicht – „Regeln entscheiden, KI formuliert“.
public struct UserSource: Codable, Equatable, Hashable, Sendable, Identifiable {
  public enum Topic: String, Codable, CaseIterable, Sendable, Identifiable {
    case endurance, strength, nutrition, recovery, general

    public var id: String { rawValue }

    public var label: String {
      switch self {
      case .endurance: "Ausdauer"
      case .strength: "Krafttraining"
      case .nutrition: "Ernährung"
      case .recovery: "Schlaf und Erholung"
      case .general: "Allgemein"
      }
    }
  }

  public var id: UUID
  /// Kurzbeleg, z. B. „Schoenfeld et al. 2017“.
  public var citation: String
  /// DOI, PMID oder Link.
  public var reference: String
  /// Kernaussage in eigenen Worten, so wie die KI sie verwenden soll.
  public var statement: String
  public var topics: Set<Topic>

  public init(
    id: UUID = UUID(), citation: String, reference: String = "", statement: String, topics: Set<Topic> = [.general]
  ) {
    self.id = id
    self.citation = citation
    self.reference = reference
    self.statement = statement
    self.topics = topics
  }

  /// Kennung für die KI und die Quellenangabe in ihrer Antwort.
  public var evidenceID: String { "eigen.\(id.uuidString.prefix(8).lowercased())" }

  public var isValid: Bool {
    !citation.trimmingCharacters(in: .whitespaces).isEmpty
      && statement.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
  }

  /// Link aus DOI, PMID oder URL.
  public var url: URL? {
    let text = reference.trimmingCharacters(in: .whitespaces)
    if text.lowercased().hasPrefix("http") { return URL(string: text) }
    if text.hasPrefix("10.") { return URL(string: "https://doi.org/\(text)") }
    let digits = text.lowercased().replacingOccurrences(of: "pmid", with: "")
      .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
    return URL(string: "https://pubmed.ncbi.nlm.nih.gov/\(digits)/")
  }
}

public enum UserSources {
  public static let maxPerRequest = 8
  public static let maxStatementLength = 300

  /// Themen, die zu einer Worker-Aufgabe passen; `nil` = alle (Chat).
  static func topics(for task: String) -> Set<UserSource.Topic>? {
    switch task {
    case "daily_note": [.endurance, .recovery, .general]
    case "gym_hints", "gym_plan": [.strength, .recovery, .general]
    case "nutrition_review", "weekly_recipes": [.nutrition, .general]
    case "coach_chat": nil
    default: []
    }
  }

  /// Hängt passende eigene Quellen an `evidence` der Eingabe an (nach den Regeln der App, damit diese Vorrang haben).
  public static func inject(
    _ sources: [UserSource], into input: [String: JSONValue], task: String
  ) -> [String: JSONValue] {
    let wanted = topics(for: task)
    if let wanted, wanted.isEmpty { return input }
    let relevant = sources.filter { source in
      source.isValid && (wanted.map { !source.topics.isDisjoint(with: $0) } ?? true)
    }.prefix(maxPerRequest)
    guard !relevant.isEmpty else { return input }
    var result = input
    let existing = input["evidence"]?.arrayValue ?? []
    let extra = relevant.map { source -> JSONValue in
      let trimmed = source.statement.trimmingCharacters(in: .whitespacesAndNewlines)
      let statement = String(trimmed.prefix(maxStatementLength))
      return .object([
        "id": .string(source.evidenceID),
        "statement": .string("\(statement) (eigene Quelle: \(source.citation))"),
      ])
    }
    result["evidence"] = .array(Array(existing.prefix(20 - extra.count)) + extra)
    return result
  }

  public static func isUserID(_ id: String) -> Bool { id.hasPrefix("eigen.") }
}
