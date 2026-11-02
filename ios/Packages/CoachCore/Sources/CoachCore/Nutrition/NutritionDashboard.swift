import Foundation

/// Karten im Ernährungsreiter: Reihenfolge und Sichtbarkeit wählt die Person selbst.
public struct NutritionDashboard: Codable, Equatable, Hashable, Sendable {
  public enum Card: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Kalorienring (übrig) und Protein/KH/Fett.
    case budget
    /// Kennzahlen: gegessen, Ziel, verbleibend, Fortschritt, Zahl der Mahlzeiten.
    case summary
    case water
    /// „Was esse ich jetzt?“
    case ideas
    /// Schnell-Leiste (häufig, wie gestern, Rezepte mit Vorrat).
    case quick
    case meals
    /// Alle Nährstoffe mit Ziel.
    case nutrients

    public var id: String { rawValue }

    public var label: String {
      switch self {
      case .budget: "Kalorien und Makros"
      case .summary: "Tagesübersicht"
      case .water: "Wasser"
      case .ideas: "Was esse ich jetzt?"
      case .quick: "Schnell eintragen"
      case .meals: "Mahlzeiten"
      case .nutrients: "Alle Nährstoffe"
      }
    }

    public var symbol: String {
      switch self {
      case .budget: "chart.pie"
      case .summary: "square.grid.2x2"
      case .water: "drop"
      case .ideas: "sparkles"
      case .quick: "bolt"
      case .meals: "list.bullet"
      case .nutrients: "list.bullet.rectangle"
      }
    }
  }

  /// Alle Karten in der gewählten Reihenfolge (auch ausgeblendete).
  public var order: [Card]
  public var hidden: Set<Card>

  public static let standardOrder: [Card] = [.budget, .summary, .water, .ideas, .quick, .meals, .nutrients]

  public init(order: [Card] = standardOrder, hidden: Set<Card> = [.summary]) {
    self.order = Self.complete(order)
    self.hidden = hidden
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = (try? container.decode([String].self, forKey: .order)) ?? []
    order = Self.complete(raw.compactMap(Card.init(rawValue:)))
    hidden = Set(((try? container.decode([String].self, forKey: .hidden)) ?? []).compactMap(Card.init(rawValue:)))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(order.map(\.rawValue), forKey: .order)
    try container.encode(hidden.map(\.rawValue).sorted(), forKey: .hidden)
  }

  enum CodingKeys: String, CodingKey { case order, hidden }

  /// Unbekannte entfernen, Doppelte entfernen, neue Karten hinten anhängen.
  static func complete(_ order: [Card]) -> [Card] {
    var seen = Set<Card>()
    let known = order.filter { seen.insert($0).inserted }
    return known + Card.allCases.filter { !seen.contains($0) }
  }

  public var visible: [Card] { order.filter { !hidden.contains($0) } }

  public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    var items = order
    let moving = source.sorted().map { items[$0] }
    for index in source.sorted(by: >) { items.remove(at: index) }
    let target = destination - source.filter { $0 < destination }.count
    items.insert(contentsOf: moving, at: min(max(target, 0), items.count))
    order = items
  }

  public mutating func set(_ card: Card, visible: Bool) {
    if visible { hidden.remove(card) } else { hidden.insert(card) }
  }
}

/// Kennzahlen der Tagesübersicht.
public struct NutritionDaySummary: Equatable, Sendable {
  public var eaten: Double
  public var goal: Double?
  public var meals: Int

  public init(eaten: Double, goal: Double?, meals: Int) {
    self.eaten = eaten
    self.goal = goal
    self.meals = meals
  }

  public var remaining: Double? { goal.map { $0 - eaten } }
  /// Anteil des Ziels in Prozent (gerundet).
  public var percent: Int? {
    guard let goal, goal > 0 else { return nil }
    return Int((eaten / goal * 100).rounded())
  }
}
