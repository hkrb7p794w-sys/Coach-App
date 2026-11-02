import Foundation

/// Bereiche, nach denen die Gesundheitswerte gruppiert sind.
public enum HealthCategory: String, Codable, CaseIterable, Sendable {
  case health, sleep, recovery, load, performance

  public var label: String {
    switch self {
    case .health: "Gesundheit"
    case .sleep: "Schlaf"
    case .recovery: "Erholung"
    case .load: "Trainingsbelastung"
    case .performance: "Leistung"
    }
  }
}

/// Ein Widget im Gesundheitsbereich. Jedes zeigt einen gemessenen Wert; ohne Daten wird es nicht angeboten.
public enum HealthWidget: String, Codable, CaseIterable, Sendable, Identifiable {
  case bodyBattery, hrv, restingHeartRate, sleep, stress, vo2Max, trainingLoad, recoveryTime, readiness, steps
  case activeCalories, restingCalories, weight, heartRateRange, respiration, spo2

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .bodyBattery: "Body Battery"
    case .hrv: "HRV"
    case .restingHeartRate: "Ruhepuls"
    case .sleep: "Schlaf"
    case .stress: "Stress"
    case .vo2Max: "VO2max"
    case .trainingLoad: "Trainingsbelastung"
    case .recoveryTime: "Regenerationszeit"
    case .readiness: "Training Readiness"
    case .steps: "Schritte"
    case .activeCalories: "Aktivitätskalorien"
    case .restingCalories: "Ruhekalorien"
    case .weight: "Gewicht"
    case .heartRateRange: "Puls tief/hoch"
    case .respiration: "Atemfrequenz"
    case .spo2: "SpO2"
    }
  }

  public var unit: String {
    switch self {
    case .hrv: "ms"
    case .restingHeartRate, .heartRateRange: "bpm"
    case .sleep, .recoveryTime: "h"
    case .activeCalories, .restingCalories: "kcal"
    case .weight: "kg"
    case .respiration: "/min"
    case .spo2: "%"
    default: ""
    }
  }

  public var digits: Int {
    switch self {
    case .sleep, .vo2Max, .weight, .respiration: 1
    default: 0
    }
  }

  public var category: HealthCategory {
    switch self {
    case .restingHeartRate, .heartRateRange, .weight, .spo2, .respiration, .steps, .activeCalories, .restingCalories:
      .health
    case .sleep: .sleep
    case .bodyBattery, .hrv, .stress, .recoveryTime, .readiness: .recovery
    case .trainingLoad: .load
    case .vo2Max: .performance
    }
  }

  /// Höher ist besser (Farbe der Veränderung); `nil` = neutral.
  public var higherIsBetter: Bool? {
    switch self {
    case .bodyBattery, .readiness, .vo2Max, .steps: true
    case .restingHeartRate, .stress, .recoveryTime: false
    default: nil
    }
  }

  /// Wert eines Tages. Gewicht kommt aus den Wägungen, die Belastung ersatzweise aus den Aktivitäten (`extra`).
  public func value(_ metrics: DailyMetrics) -> Double? {
    switch self {
    case .bodyBattery: BodyBatteryAnalysis.wakeValue(metrics) ?? metrics.bodyBatteryHigh
    case .hrv: metrics.hrvLastNightAverage
    case .restingHeartRate: metrics.restingHeartRate
    case .sleep: metrics.sleepHours
    case .stress: metrics.stressAverage
    case .vo2Max: metrics.vo2Max
    case .trainingLoad: metrics.acuteLoad
    case .recoveryTime: metrics.recoveryHours
    case .readiness: metrics.trainingReadiness
    case .steps: metrics.steps
    case .activeCalories: metrics.activeKilocalories
    case .restingCalories: metrics.restingKilocalories
    case .weight: nil
    case .heartRateRange: metrics.maxHeartRate
    case .respiration: metrics.respirationWaking ?? metrics.respirationSleep
    case .spo2: metrics.spo2Average
    }
  }

  /// Woher der Wert kommen kann – für den Hinweis bei fehlenden Daten.
  public var sources: String {
    switch self {
    case .bodyBattery, .stress, .readiness, .recoveryTime: "nur Garmin"
    case .trainingLoad: "Garmin-Konto oder eigene Aktivitäten"
    case .weight: "Garmin, Apple Health oder eigene Wägungen"
    default: "Garmin oder Apple Health"
    }
  }
}

/// Darstellung eines Widgets.
public enum HealthWidgetStyle: String, Codable, CaseIterable, Sendable {
  case value, week, month

  public var label: String {
    switch self {
    case .value: "Nur Wert"
    case .week: "Verlauf 7 Tage"
    case .month: "Verlauf 30 Tage"
    }
  }

  public var days: Int {
    switch self {
    case .value, .week: 7
    case .month: 30
    }
  }
}

/// Aufbau des Gesundheitsbereichs: hinzugefügte Widgets in Reihenfolge, je mit Darstellung und Sichtbarkeit.
/// Ausgeblendete bleiben in der Liste (Reihenfolge und Darstellung bleiben erhalten), entfernte nicht.
public struct HealthDashboard: Codable, Equatable, Hashable, Sendable {
  public struct Entry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var kind: HealthWidget
    public var style: HealthWidgetStyle
    public var hidden: Bool
    public var id: String { kind.rawValue }

    public init(kind: HealthWidget, style: HealthWidgetStyle = .week, hidden: Bool = false) {
      self.kind = kind
      self.style = style
      self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey { case kind, style, hidden }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      kind = try container.decode(HealthWidget.self, forKey: .kind)
      style = (try? container.decodeIfPresent(HealthWidgetStyle.self, forKey: .style)) ?? .week
      hidden = (try? container.decodeIfPresent(Bool.self, forKey: .hidden)) ?? false
    }
  }

  public var entries: [Entry]

  public static let standard: [HealthWidget] = [
    .bodyBattery, .sleep, .hrv, .restingHeartRate, .stress, .trainingLoad, .recoveryTime, .steps,
  ]

  public init(entries: [Entry] = HealthDashboard.standard.map { Entry(kind: $0) }) {
    self.entries = Self.unique(entries)
  }

  private enum CodingKeys: String, CodingKey { case entries }

  /// Unbekannte Widgets (aus einer neueren Version) und Doppelte fallen weg statt alles zu verwerfen.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    var list = try container.nestedUnkeyedContainer(forKey: .entries)
    var entries: [Entry] = []
    while !list.isAtEnd {
      if let entry = try? list.decode(Entry.self) {
        entries.append(entry)
      } else {
        _ = try? list.decode(JSONValue.self)
      }
    }
    self.entries = Self.unique(entries)
  }

  private static func unique(_ entries: [Entry]) -> [Entry] {
    var seen = Set<HealthWidget>()
    return entries.filter { seen.insert($0.kind).inserted }
  }

  public func contains(_ kind: HealthWidget) -> Bool { entries.contains { $0.kind == kind } }

  public mutating func add(_ kind: HealthWidget, style: HealthWidgetStyle = .week) {
    guard !contains(kind) else {
      setHidden(kind, false)
      return
    }
    entries.append(Entry(kind: kind, style: style))
  }

  public mutating func remove(_ kind: HealthWidget) {
    entries.removeAll { $0.kind == kind }
  }

  public mutating func setHidden(_ kind: HealthWidget, _ hidden: Bool) {
    guard let index = entries.firstIndex(where: { $0.kind == kind }) else { return }
    entries[index].hidden = hidden
  }

  public mutating func setStyle(_ kind: HealthWidget, _ style: HealthWidgetStyle) {
    guard let index = entries.firstIndex(where: { $0.kind == kind }) else { return }
    entries[index].style = style
  }

  /// Wie `move(fromOffsets:toOffset:)` in SwiftUI-Listen: `destination` zählt in der Liste vor dem Verschieben.
  public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
    let moving = source.filter { $0 < entries.count }.map { entries[$0] }
    let before = source.filter { $0 < destination }.count
    var rest = entries.enumerated().filter { !source.contains($0.offset) }.map(\.element)
    rest.insert(contentsOf: moving, at: min(max(destination - before, 0), rest.count))
    entries = rest
  }

  /// Angezeigt: nicht ausgeblendet und mit Daten.
  public func visible(available: Set<HealthWidget>) -> [Entry] {
    entries.filter { !$0.hidden && available.contains($0.kind) }
  }

  /// Zum Hinzufügen: noch nicht in der Liste und mit Daten.
  public func addable(available: Set<HealthWidget>) -> [HealthWidget] {
    HealthWidget.allCases.filter { !contains($0) && available.contains($0) }
  }

  /// Widgets, für die in den letzten `days` Tagen mindestens ein Wert vorliegt.
  public static func available(
    days: [DailyMetrics], extra: [HealthWidget: [DayValue]] = [:], today: CalendarDay, window: Int = 30
  ) -> Set<HealthWidget> {
    let start = today.adding(days: -(window - 1))
    let recent = days.filter { $0.day >= start && $0.day <= today }
    var result = Set<HealthWidget>()
    for kind in HealthWidget.allCases {
      let fromDays = recent.contains { kind.value($0) != nil }
      let fromExtra = (extra[kind] ?? []).contains { $0.day >= start && $0.day <= today }
      if fromDays || fromExtra { result.insert(kind) }
    }
    return result
  }

  /// Werte eines Widgets für die letzten `days` Tage (Tageswerte vor Ersatzquellen).
  public static func series(
    _ kind: HealthWidget, days: [DailyMetrics], extra: [HealthWidget: [DayValue]] = [:], today: CalendarDay,
    window: Int
  ) -> [DayValue] {
    let start = today.adding(days: -(window - 1))
    var byDay: [CalendarDay: Double] = [:]
    for value in extra[kind] ?? [] where value.day >= start && value.day <= today {
      byDay[value.day] = value.value
    }
    for metrics in days where metrics.day >= start && metrics.day <= today {
      if let value = kind.value(metrics) { byDay[metrics.day] = value }
    }
    return byDay.keys.sorted().map { DayValue(day: $0, value: byDay[$0] ?? 0) }
  }
}
