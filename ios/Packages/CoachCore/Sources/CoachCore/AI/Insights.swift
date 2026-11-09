import Foundation

/// Thema einer Empfehlung im Reiter „AI“.
public enum InsightTopic: String, Codable, CaseIterable, Sendable {
  case training
  case planning = "plan"
  case performance = "leistung"
  case recovery = "erholung"
  case nutrition = "ernaehrung"
  case progress = "fortschritt"
  case stagnation
  case action = "handlung"

  public var label: String {
    switch self {
    case .training: "Training"
    case .planning: "Trainingsplan"
    case .performance: "Leistung"
    case .recovery: "Erholung"
    case .nutrition: "Ernährung"
    case .progress: "Fortschritt"
    case .stagnation: "Stagnation"
    case .action: "Nächste Schritte"
    }
  }

  public var symbol: String {
    switch self {
    case .training: "figure.run"
    case .planning: "calendar"
    case .performance: "chart.line.uptrend.xyaxis"
    case .recovery: "bed.double"
    case .nutrition: "fork.knife"
    case .progress: "arrow.up.right"
    case .stagnation: "pause.circle"
    case .action: "checklist"
    }
  }
}

/// Bereich einer Empfehlung für die Filter. Wird aus Thema und Inhalt abgeleitet, gespeicherte Empfehlungen bleiben
/// damit unverändert gültig; ein neuer Bereich braucht nur einen Fall und seine Stichwörter.
public enum InsightCategory: String, CaseIterable, Sendable {
  case strength, endurance, nutrition, recovery, health, bodyComposition, general

  public var label: String {
    switch self {
    case .strength: "Training und Kraftaufbau"
    case .endurance: "Ausdauer und Leistung"
    case .nutrition: "Ernährung"
    case .recovery: "Schlaf und Regeneration"
    case .health: "Gesundheit und Belastung"
    case .bodyComposition: "Körperzusammensetzung"
    case .general: "Allgemeine Fitness"
    }
  }

  public var symbol: String {
    switch self {
    case .strength: "dumbbell"
    case .endurance: "figure.run"
    case .nutrition: "fork.knife"
    case .recovery: "bed.double"
    case .health: "heart.text.square"
    case .bodyComposition: "scalemass"
    case .general: "figure.mixed.cardio"
    }
  }

  /// Das Thema, das die KI-Analyse für diesen Bereich bekommt.
  public var analysisTopic: InsightTopic? {
    switch self {
    case .strength: .training
    case .endurance: .performance
    case .nutrition, .bodyComposition: .nutrition
    case .recovery, .health: .recovery
    case .general: nil
    }
  }

  fileprivate var keywords: [String] {
    switch self {
    case .strength:
      [
        "bankdr", "kniebeug", "kreuzheb", "schulterdr", "klimmz", "rudern", "kraft", "gym", "satz", "saetze", "sätze",
        "volumen", "progression", "deload", "muskel",
      ]
    case .endurance:
      ["lauf", "rennrad", "radfahr", "rad-", "schwimm", "pace", "ausdauer", "tempo", "intervall", "zone"]
    case .nutrition: ["protein", "kalorien", "kcal", "ernaehr", "ernähr", "mahlzeit", "kohlenhydr", "fett", "essen"]
    case .recovery: ["schlaf", "erhol", "regener", "hrv", "muedigkeit", "müdigkeit", "ruhetag"]
    case .health: ["schmerz", "krank", "verletz", "ruhepuls", "ueberlast", "überlast", "belastung", "beschwerd"]
    case .bodyComposition: ["koerper", "körper", "gewicht", "abnehm", "zunehm", "taille"]
    case .general: []
    }
  }

  /// Das Thema entscheidet zuerst, innerhalb davon der Inhalt. So bleibt „Schlaf für mehr Kraft“ bei der Regeneration.
  static func of(topic: InsightTopic, content: String) -> InsightCategory {
    let lower = content.lowercased()
    func has(_ category: InsightCategory) -> Bool { category.keywords.contains { lower.contains($0) } }
    switch topic {
    case .recovery: return has(.health) ? .health : .recovery
    case .nutrition: return has(.bodyComposition) ? .bodyComposition : .nutrition
    default:
      let order: [InsightCategory] = [.health, .bodyComposition, .recovery, .nutrition, .strength, .endurance]
      return order.first(where: has) ?? .general
    }
  }
}

/// Bearbeitungsstand aus Sicht der Person.
public enum InsightStatus: String, Codable, Sendable {
  case new = "neu"
  case read = "gelesen"
  case done = "umgesetzt"
  case dismissed = "verworfen"
}

/// Woher eine Empfehlung kommt. Regeln haben Vorrang vor der KI.
public enum InsightOrigin: String, Codable, Sendable {
  case rules = "regeln"
  case ai = "ki"
}

/// Wohin eine Empfehlung zielt – zwei Empfehlungen zum selben Betreff mit anderer Richtung widersprechen sich.
public enum InsightDirection: String, Codable, Sendable {
  case more = "mehr"
  case less = "weniger"
  case keep = "halten"
  case change = "aendern"
  case check = "pruefen"
}

/// Eine Empfehlung im Reiter „AI“. `basis`, `origin` und `model` sind intern (Nachvollziehbarkeit), die Ansicht zeigt
/// nur Titel und Text.
public struct Insight: Codable, Equatable, Sendable, Identifiable {
  /// Thema + Betreff: dieselbe Frage hat immer dieselbe ID.
  public var id: String { "\(topic.rawValue).\(subject)" }
  public var topic: InsightTopic
  /// Worum es geht, z. B. „bankdruecken“, „schlaf“, „protein“ (klein, ohne Leerzeichen).
  public var subject: String
  public var title: String
  public var text: String
  public var direction: InsightDirection
  /// 1 = wichtig, 3 = nebenbei.
  public var priority: Int
  public var origin: InsightOrigin
  public var created: Date
  public var validUntil: Date
  /// Belegende Fakten in Klartext (intern, nicht in der normalen Ansicht).
  public var basis: [String]
  /// Modell bei KI-Empfehlungen (intern).
  public var model: String?
  /// `niedrig`, wenn Daten fehlen oder knapp sind – wird in der Ansicht genannt, nicht verschleiert.
  public var uncertain: Bool
  public var status: InsightStatus
  public var statusChanged: Date?

  public init(
    topic: InsightTopic, subject: String, title: String, text: String, direction: InsightDirection,
    priority: Int = 2, origin: InsightOrigin, created: Date, validUntil: Date, basis: [String] = [],
    model: String? = nil, uncertain: Bool = false
  ) {
    self.topic = topic
    self.subject = Self.normalizedSubject(subject)
    self.title = title
    self.text = text
    self.direction = direction
    self.priority = min(max(priority, 1), 3)
    self.origin = origin
    self.created = created
    self.validUntil = validUntil
    self.basis = basis
    self.model = model
    self.uncertain = uncertain
    status = .new
  }

  public func isCurrent(at date: Date) -> Bool { validUntil > date }

  public var category: InsightCategory {
    InsightCategory.of(topic: topic, content: "\(subject) \(title) \(text)")
  }

  /// Titel zu Schlaf und Gesundheit können Rohwerte enthalten; sie gehen nur bei vollem Datenschutzmodus an die KI.
  public var hasRawHealthValue: Bool {
    (category == .recovery || category == .health) && title.contains(where: \.isNumber)
  }

  /// Widerspruch: gleicher Betreff mit anderer Richtung, oder „mehr“ gegen „weniger“ zum selben Hauptwort im Bereich.
  func contradicts(_ other: Insight) -> Bool {
    if subject == other.subject { return direction != other.direction }
    let opposite = Set([direction, other.direction]) == [.more, .less]
    return opposite && category == other.category
      && subject.split(separator: "-").first == other.subject.split(separator: "-").first
  }

  static func normalizedSubject(_ text: String) -> String {
    let words = FoodSearch.normalized(text).split { !$0.isLetter && !$0.isNumber }
    return words.prefix(4).joined(separator: "-")
  }
}

/// Sammelt Empfehlungen aus Regeln und KI: keine Doppelten, keine Widersprüche, Bearbeitungsstand bleibt erhalten.
public enum InsightInbox {
  /// Erledigte und verworfene Empfehlungen bleiben so lange sichtbar (Verlauf), danach fallen sie weg.
  public static let keepClosedDays = 30
  /// Abgelaufene Empfehlungen bleiben so lange als „nicht mehr aktuell“.
  public static let keepExpiredDays = 14

  /// Neue Empfehlungen einsortieren.
  /// - Gleiche ID: Text wird aktualisiert; der Stand bleibt, außer der Inhalt hat sich geändert (dann wieder „neu“).
  ///   Verworfenes bleibt verworfen, solange es noch gilt und die Richtung gleich ist.
  /// - Gleicher Betreff, andere Richtung (Widerspruch): Regeln schlagen KI; sonst ersetzt die neuere die ältere.
  /// - Gleicher Titel unter anderem Betreff: doppelt, die ältere bleibt.
  public static func merge(_ existing: [Insight], with incoming: [Insight], now: Date) -> [Insight] {
    var result = existing
    for candidate in incoming where candidate.isCurrent(at: now) {
      if let index = result.firstIndex(where: { $0.id == candidate.id }) {
        let current = result[index]
        if current.origin == .rules, candidate.origin == .ai, current.isCurrent(at: now) { continue }
        var updated = candidate
        let sameContent = current.text == candidate.text && current.direction == candidate.direction
        if sameContent || (current.status == .dismissed && current.direction == candidate.direction) {
          updated.status = current.status
          updated.statusChanged = current.statusChanged
          updated.created = current.created
        }
        result[index] = updated
        continue
      }
      let conflicts = result.indices.filter {
        result[$0].contradicts(candidate) && result[$0].isCurrent(at: now) && result[$0].status != .dismissed
      }
      if conflicts.contains(where: { result[$0].origin == .rules }) && candidate.origin == .ai { continue }
      let replaced = Set(conflicts.map { result[$0].id })
      result.removeAll { replaced.contains($0.id) }
      let title = FoodSearch.normalized(candidate.title)
      if result.contains(where: { FoodSearch.normalized($0.title) == title && $0.isCurrent(at: now) }) { continue }
      result.append(candidate)
    }
    return prune(result, now: now)
  }

  /// Regel-Empfehlungen, die nicht mehr zutreffen, gelten ab jetzt als abgelaufen (die Regel hat sie zurückgezogen).
  public static func retireRules(_ insights: [Insight], keeping current: Set<String>, now: Date) -> [Insight] {
    insights.map { insight in
      guard insight.origin == .rules, !current.contains(insight.id), insight.isCurrent(at: now) else { return insight }
      var retired = insight
      retired.validUntil = now
      return retired
    }
  }

  public static func setStatus(_ status: InsightStatus, id: String, in insights: [Insight], now: Date) -> [Insight] {
    insights.map { insight in
      guard insight.id == id else { return insight }
      var changed = insight
      changed.status = status
      changed.statusChanged = now
      return changed
    }
  }

  static func prune(_ insights: [Insight], now: Date) -> [Insight] {
    insights.filter { insight in
      if insight.status == .done || insight.status == .dismissed {
        return (insight.statusChanged ?? insight.created) > now.addingTimeInterval(-Double(keepClosedDays) * 86_400)
      }
      return insight.validUntil > now.addingTimeInterval(-Double(keepExpiredDays) * 86_400)
    }
  }

  /// Gruppen für die Ansicht.
  public struct Groups: Equatable, Sendable {
    public var new: [Insight] = []
    public var open: [Insight] = []
    public var closed: [Insight] = []
    public var expired: [Insight] = []
  }

  /// `focus`: Themen in der Reihenfolge der Prioritäten der Person; bei gleicher Dringlichkeit zuerst.
  public static func groups(
    _ insights: [Insight], topic: InsightTopic? = nil, category: InsightCategory? = nil, focus: [InsightTopic] = [],
    now: Date
  ) -> Groups {
    var groups = Groups()
    func rank(_ topic: InsightTopic) -> Int { focus.firstIndex(of: topic) ?? focus.count }
    let sorted = insights.filter { (topic == nil || $0.topic == topic) && (category == nil || $0.category == category) }
      .sorted { ($0.priority, rank($0.topic), $1.created) < ($1.priority, rank($1.topic), $0.created) }
    for insight in sorted {
      switch insight.status {
      case .done, .dismissed: groups.closed.append(insight)
      case .new where insight.isCurrent(at: now): groups.new.append(insight)
      case .read where insight.isCurrent(at: now): groups.open.append(insight)
      default: groups.expired.append(insight)
      }
    }
    return groups
  }

  public static func unreadCount(_ insights: [Insight], now: Date) -> Int {
    insights.filter { $0.status == .new && $0.isCurrent(at: now) }.count
  }
}

/// Empfehlungen aus den Regeln der App (ohne KI): Erholung, Schlaf, Stillstand und Volumen im Krafttraining,
/// Ernährungslücken und Planvorschläge. Jede Regel ist dieselbe wie an ihrem Ort in der App.
public enum InsightRules {
  public struct Input: Sendable {
    public var now: Date
    public var recommendation: Recommendation?
    public var sleep: SleepCoach.Report?
    public var gymObservations: [String]
    public var nutritionGaps: [String]
    public var planSuggestions: [PlanSuggestion]

    public init(
      now: Date, recommendation: Recommendation? = nil, sleep: SleepCoach.Report? = nil,
      gymObservations: [String] = [], nutritionGaps: [String] = [], planSuggestions: [PlanSuggestion] = []
    ) {
      self.now = now
      self.recommendation = recommendation
      self.sleep = sleep
      self.gymObservations = gymObservations
      self.nutritionGaps = nutritionGaps
      self.planSuggestions = planSuggestions
    }
  }

  public static func build(_ input: Input) -> [Insight] {
    let now = input.now
    let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
    let inAWeek = now.addingTimeInterval(7 * 86_400)
    var result: [Insight] = []

    if let recommendation = input.recommendation, recommendation.level != .normal {
      result.append(
        Insight(
          topic: .recovery, subject: "tagesform", title: recommendation.label, text: recommendation.advice,
          direction: .less, priority: 1, origin: .rules, created: now, validUntil: endOfDay,
          basis: recommendation.reasons))
    }

    if let sleep = input.sleep, sleep.nights >= 3, sleep.debtHours >= 3 {
      result.append(
        Insight(
          topic: .recovery, subject: "schlaf", title: "Schlaf nachholen",
          text: "In den letzten Nächten fehlen dir rund \(GermanFormat.decimal(sleep.debtHours)) Stunden Schlaf. "
            + "Plane heute etwas mehr Zeit im Bett ein.",
          direction: .more, priority: 2, origin: .rules, created: now, validUntil: endOfDay,
          basis: ["\(sleep.nights) Nächte, Ø \(GermanFormat.decimal(sleep.averageHours)) h"]))
    }

    for observation in input.gymObservations {
      let parts = observation.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard parts.count == 2 else { continue }
      let stalled = observation.contains("Stillstand")
      let tooMuch = observation.contains("mehr als")
      result.append(
        Insight(
          topic: stalled ? .stagnation : .training, subject: parts[0],
          title: stalled ? "\(parts[0]): Stillstand" : parts[0], text: parts[1],
          direction: stalled ? .change : (tooMuch ? .less : .more), priority: stalled ? 1 : 2, origin: .rules,
          created: now, validUntil: inAWeek, basis: [observation]))
    }

    for gap in input.nutritionGaps {
      let name = gap.split(separator: ":").first.map(String.init) ?? gap
      result.append(
        Insight(
          topic: .nutrition, subject: name, title: "Mehr \(name)",
          text: "\(gap.replacingOccurrences(of: "\(name): ", with: "Du kommst ")) – in den letzten zwei Wochen "
            + "unter 80 % deines Ziels.",
          direction: .more, priority: 2, origin: .rules, created: now, validUntil: inAWeek, basis: [gap]))
    }

    for suggestion in input.planSuggestions {
      result.append(
        Insight(
          topic: .planning, subject: "plan-\(suggestion.id)", title: suggestion.title,
          text: suggestion.reason + " Übernehmen kannst du den Vorschlag im Reiter Training.",
          direction: .change, priority: 2, origin: .rules, created: now,
          validUntil: suggestion.week.adding(days: 7).referenceDate, basis: suggestion.changes.map(\.text)))
    }
    return result
  }
}

/// KI-Analyse im Reiter „AI“ (Worker-Aufgabe `ai_insights`): Die App schickt nummerierte Fakten, fehlende Daten und
/// die Empfehlungen der Regeln; die KI darf nur daraus folgern und muss je Empfehlung Fakten nennen.
public enum InsightAnalysis {
  public struct Fact: Equatable, Sendable {
    public var id: String
    public var text: String
  }

  /// Fakten mit IDs (`f1`, `f2` …) aus Klartextzeilen.
  public static func facts(_ lines: [String]) -> [Fact] {
    lines.filter { !$0.isEmpty }.prefix(60).enumerated().map { Fact(id: "f\($0.offset + 1)", text: $0.element) }
  }

  public static func input(
    topic: InsightTopic?, facts: [Fact], missing: [String], ruleInsights: [Insight], closed: [Insight] = []
  ) -> [String: JSONValue] {
    [
      // Umgesetztes und Verworfenes: nicht erneut vorschlagen, bei Umgesetztem die Wirkung bewerten.
      "bearbeitet": .array(
        closed.filter { ($0.status == .done || $0.status == .dismissed) && !$0.hasRawHealthValue }.prefix(20).map {
          .object(["titel": .string($0.title), "betreff": .string($0.subject), "stand": .string($0.status.rawValue)])
        }),
      "thema": .string(topic?.rawValue ?? "alle"),
      "fakten": .array(facts.map { .object(["id": .string($0.id), "text": .string($0.text)]) }),
      "fehlend": .array(missing.map { .string($0) }),
      "regeln": .array(
        ruleInsights.map {
          .object([
            "betreff": .string($0.subject), "titel": .string($0.title), "richtung": .string($0.direction.rawValue),
          ])
        }),
      "themen": .array(InsightTopic.allCases.map { .string($0.rawValue) }),
    ]
  }

  /// Liest die geprüfte Antwort des Workers. Fakten-IDs werden zu Klartext (intern), unbekannte Themen verworfen.
  public static func insights(from output: JSONValue, facts: [Fact], model: String, now: Date) -> [Insight] {
    let byID = Dictionary(facts.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
    return (output["empfehlungen"]?.arrayValue ?? []).compactMap { item -> Insight? in
      guard let topic = item["thema"]?.stringValue.flatMap(InsightTopic.init(rawValue:)),
        let title = item["titel"]?.stringValue, !title.isEmpty,
        let text = item["text"]?.stringValue, !text.isEmpty
      else { return nil }
      let basis = (item["belege"]?.arrayValue ?? []).compactMap(\.stringValue).compactMap { byID[$0] }
      guard !basis.isEmpty else { return nil }
      let days = item["gueltig_tage"]?.clampedInt(1...14) ?? 7
      return Insight(
        topic: topic, subject: item["betreff"]?.stringValue ?? title, title: String(title.prefix(80)),
        text: String(text.prefix(400)),
        direction: item["richtung"]?.stringValue.flatMap(InsightDirection.init(rawValue:)) ?? .check,
        priority: item["prioritaet"]?.clampedInt(1...3) ?? 2, origin: .ai, created: now,
        validUntil: now.addingTimeInterval(Double(days) * 86_400), basis: basis, model: model,
        uncertain: item["sicherheit"]?.stringValue == "niedrig")
    }
  }
}
