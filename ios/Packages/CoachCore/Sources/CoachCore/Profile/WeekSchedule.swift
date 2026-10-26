import Foundation

public enum Weekday: Int, CaseIterable, Codable, Sendable, Identifiable {
  case monday = 0, tuesday, wednesday, thursday, friday, saturday, sunday

  public var id: Int { rawValue }

  public init(day: CalendarDay) {
    self = Weekday(rawValue: day.weekdayIndex) ?? .monday
  }

  public var short: String {
    ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][rawValue]
  }

  public var long: String {
    ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][rawValue]
  }

  /// Der folgende Tag; auf den Sonntag folgt der Montag.
  public var next: Weekday {
    Self.allCases[(rawValue + 1) % 7]
  }

  public var previous: Weekday {
    Self.allCases[(rawValue + 6) % 7]
  }

  public func adding(_ days: Int) -> Weekday {
    Self.allCases[((rawValue + days) % 7 + 7) % 7]
  }
}

/// Wie fordernd eine Einheit ist. Die meisten Einheiten sollen locker sein (Seiler 2006).
public enum SessionIntensity: String, Codable, CaseIterable, Sendable, Identifiable {
  case easy, hard, long

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .easy: "Locker"
    case .hard: "Intensiv"
    case .long: "Lang"
    }
  }

  /// Fordernd für die Erholung: intensive und lange Einheiten.
  public var isDemanding: Bool { self != .easy }
}

/// Eine Einheit an einem Tag: Sportart plus Intensität.
public struct SessionSlot: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var sport: TrainingSport
  public var intensity: SessionIntensity

  public init(_ sport: TrainingSport, _ intensity: SessionIntensity = .easy) {
    self.sport = sport
    self.intensity = intensity
  }

  public var id: String { "\(sport.rawValue)-\(intensity.rawValue)" }

  /// Kurzer Name der Einheit.
  public var title: String {
    switch (sport, intensity) {
    case (.run, .easy): "Lockerer Lauf"
    case (.run, .hard): "Qualitätslauf (Tempo oder Intervalle)"
    case (.run, .long): "Langer Lauf"
    case (.bike, .easy): "Lockere Radfahrt"
    case (.bike, .hard): "Intensive Radeinheit"
    case (.bike, .long): "Lange Radfahrt"
    case (.swim, .easy): "Lockeres Schwimmen"
    case (.swim, .hard): "Intensives Schwimmen"
    case (.swim, .long): "Langes Schwimmen"
    case (.strength, .easy): "Kraft leicht (Technik, Mobilität)"
    case (.strength, .hard): "Krafttraining"
    case (.strength, .long): "Krafttraining"
    case (.other, _): "Yoga / Beweglichkeit / Wandern"
    }
  }

  /// Kurze Anleitung, wie die Einheit gemeint ist (allgemein, ohne Zahlen aus einem Trainingsplan).
  public var guide: String {
    switch (sport, intensity) {
    case (.run, .easy), (.bike, .easy), (.swim, .easy):
      "So locker, dass du dich dabei noch unterhalten kannst. Lieber etwas kürzer als zu hart."
    case (.run, .hard):
      "Nach etwa 10 Minuten Einlaufen zügig laufen (Tempo oder Intervalle), danach locker auslaufen. "
        + "Nur wenn du dich erholt fühlst."
    case (.bike, .hard), (.swim, .hard):
      "Nach dem Einrollen bzw. Einschwimmen zügige Intervalle, danach locker ausklingen lassen."
    case (.run, .long), (.bike, .long), (.swim, .long):
      "Die längste Einheit der Woche, ruhig und gleichmäßig."
    case (.strength, .easy):
      "Leichte Gewichte, saubere Technik und Beweglichkeit."
    case (.strength, _):
      "Ganzkörper oder Ober-/Unterkörper, mehrere Sätze je Übung mit sauberer Technik."
    case (.other, _):
      "Locker, beweglich bleiben und erholen."
    }
  }

  /// Ausdauereinheit mit hoher Belastung. Krafttraining zählt hier nicht: Es belastet andere Strukturen.
  public var isDemandingEndurance: Bool {
    sport.isEndurance && intensity.isDemanding
  }

  /// Text für den Tagestyp der Ernährung: Lange und intensive Einheiten brauchen mehr Kohlenhydrate.
  var nutritionText: String {
    intensity.isDemanding && sport.isEndurance ? "\(title) intensiv lange" : title
  }
}

/// Der Wochenplan: sieben Tage, an jedem keine, eine oder mehrere Einheiten.
public struct WeekSchedule: Codable, Equatable, Hashable, Sendable {
  public private(set) var days: [[SessionSlot]]

  public init(days: [[SessionSlot]] = []) {
    self.days = Self.normalized(days)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    days = Self.normalized((try? container.decode([[SessionSlot]].self)) ?? [])
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(days)
  }

  private static func normalized(_ days: [[SessionSlot]]) -> [[SessionSlot]] {
    var result = Array(days.prefix(7))
    while result.count < 7 { result.append([]) }
    return result
  }

  public func slots(on weekday: Weekday) -> [SessionSlot] {
    days[weekday.rawValue]
  }

  public mutating func set(_ slots: [SessionSlot], on weekday: Weekday) {
    days[weekday.rawValue] = slots
  }

  public var trainingDays: [Weekday] {
    Weekday.allCases.filter { !slots(on: $0).isEmpty }
  }

  public var restDays: [Weekday] {
    Weekday.allCases.filter { slots(on: $0).isEmpty }
  }

  public var sessionCount: Int {
    days.reduce(0) { $0 + $1.count }
  }

  public var isEmpty: Bool { sessionCount == 0 }

  public func count(of sport: TrainingSport) -> Int {
    days.reduce(0) { $0 + $1.filter { $0.sport == sport }.count }
  }

  /// Tage mit mindestens einer intensiven oder langen Ausdauereinheit.
  public var demandingEnduranceDays: [Weekday] {
    Weekday.allCases.filter { weekday in slots(on: weekday).contains { $0.isDemandingEndurance } }
  }

  /// Nächster freier Tag innerhalb von `within` Tagen nach `weekday` (der Plan ist zyklisch).
  public func nextRestDay(after weekday: Weekday, within: Int) -> Weekday? {
    guard within > 0 else { return nil }
    for offset in 1...within {
      let candidate = weekday.adding(offset)
      if slots(on: candidate).isEmpty { return candidate }
    }
    return nil
  }

  /// Längste Folge aufeinanderfolgender Trainingstage (zyklisch: Sonntag und Montag hängen zusammen).
  public var longestStreak: Int {
    let trainingDays = Weekday.allCases.map { !slots(on: $0).isEmpty }
    guard trainingDays.contains(false) else { return 7 }
    var longest = 0
    var current = 0
    // Zweimal durchlaufen, damit Folgen über die Wochengrenze mitzählen.
    for index in 0..<14 {
      if trainingDays[index % 7] {
        current += 1
        longest = max(longest, current)
      } else {
        current = 0
      }
    }
    return min(longest, 7)
  }

  /// Einträge für die Tagestyp-Erkennung der Ernährung (`NutritionPlanner.plannedDayType`).
  public func templateItems(on weekday: Weekday) -> [TemplateItem] {
    slots(on: weekday).map { slot in
      let kind: TemplateItem.Kind =
        switch slot.sport {
        case .run: .run
        case .bike: .bike
        case .swim: .swimOrLegs
        case .strength: .strength
        case .other: .optional
        }
      return TemplateItem(kind: kind, text: slot.nutritionText)
    }
  }
}
