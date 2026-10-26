import Foundation

/// Ein Messwert an einem Tag – Grundlage der Verlaufsgrafiken.
public struct DayValue: Equatable, Sendable, Identifiable {
  public var day: CalendarDay
  public var value: Double
  public var id: String { day.iso }

  public init(day: CalendarDay, value: Double) {
    self.day = day
    self.value = value
  }
}

/// Verlauf eines Werts über einen Zeitraum, wie die Karte `coach-trend` im Altbestand:
/// aktueller Wert, Schnitt des Zeitraums und Veränderung gegenüber dem Zeitraum davor.
public struct MetricTrend: Equatable, Sendable {
  public var points: [DayValue]
  public var latest: DayValue?
  public var average: Double?
  public var previousAverage: Double?

  /// Veränderung des Schnitts gegenüber dem vorherigen gleich langen Zeitraum.
  public var change: Double? {
    guard let average, let previousAverage else { return nil }
    return average - previousAverage
  }

  /// - Parameters:
  ///   - values: alle bekannten Werte (beliebige Reihenfolge, Tage ohne Wert fehlen einfach).
  ///   - days: Länge des Zeitraums bis einschließlich `today`.
  public init(values: [DayValue], days: Int, today: CalendarDay) {
    let start = today.adding(days: -(days - 1))
    let previousStart = start.adding(days: -days)
    let sorted = values.sorted { $0.day < $1.day }
    points = sorted.filter { start <= $0.day && $0.day <= today }
    latest = points.last
    average = Self.mean(points)
    previousAverage = Self.mean(sorted.filter { previousStart <= $0.day && $0.day < start })
  }

  static func mean(_ values: [DayValue]) -> Double? {
    values.isEmpty ? nil : values.map(\.value).reduce(0, +) / Double(values.count)
  }

  /// Werte eines Felds aus den Tageswerten.
  public static func values(_ days: [DailyMetrics], _ field: (DailyMetrics) -> Double?) -> [DayValue] {
    days.compactMap { metrics in field(metrics).map { DayValue(day: metrics.day, value: $0) } }
  }
}

/// Kilometer und Einheiten je Woche und Sportart für die Wochenbalken.
public struct WeekVolume: Equatable, Sendable, Identifiable {
  public var monday: CalendarDay
  public var volume: WeeklyVolume
  public var id: String { monday.iso }

  /// Die letzten `weeks` Wochen bis einschließlich der Woche von `today`, älteste zuerst.
  public static func history(activities: [GarminActivity], today: CalendarDay, weeks: Int) -> [WeekVolume] {
    let thisMonday = today.adding(days: -today.weekdayIndex)
    return (0..<weeks).reversed().map { offset in
      let monday = thisMonday.adding(days: -7 * offset)
      return WeekVolume(monday: monday, volume: WeeklyVolume(activities: activities, weekContaining: monday))
    }
  }
}

/// VO2max-Werte aus Aktivitäten (Garmin schreibt sie nur nach qualifizierenden Einheiten) und dem Profil.
public enum VO2MaxHistory {
  /// Je Tag der höchste Wert aus Lauf- bzw. Radeinheiten.
  public static func values(activities: [GarminActivity], sport: GarminActivity.Sport) -> [DayValue] {
    var best: [CalendarDay: Double] = [:]
    for activity in activities where activity.sport == sport {
      guard let day = activity.day, let value = activity.vo2Max, value > 10 else { continue }
      best[day] = max(best[day] ?? 0, value)
    }
    return best.map { DayValue(day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
  }
}
