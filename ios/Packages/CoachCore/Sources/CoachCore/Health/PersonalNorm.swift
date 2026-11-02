import Foundation

/// Persönlicher Normalbereich eines Werts: Mittelwert ± eine Standardabweichung der letzten Wochen (heute nicht
/// mitgezählt). Rund zwei Drittel der eigenen Tage liegen darin – ein Wert außerhalb ist für diese Person
/// auffällig, auch wenn er allgemein „normal“ wäre (Plews et al. 2013 für HRV; dasselbe Prinzip für Ruhepuls,
/// Schlaf und Body Battery).
public struct PersonalNorm: Equatable, Sendable {
  public enum Position: String, Equatable, Sendable {
    case below, within, above
  }

  public var mean: Double
  public var low: Double
  public var high: Double
  /// Anzahl Tage, aus denen der Bereich stammt.
  public var count: Int

  /// Mindestens so viele Tage, sonst gibt es keinen persönlichen Bereich (dann gilt nur der allgemeine Richtwert).
  public static let minimumDays = 7
  public static let windowDays = 30

  public init(mean: Double, low: Double, high: Double, count: Int) {
    self.mean = mean
    self.low = low
    self.high = high
    self.count = count
  }

  /// Bereich aus den Tagen vor `today` (bis `window` Tage zurück).
  public static func of(
    _ days: [DailyMetrics], today: CalendarDay, window: Int = windowDays, _ field: (DailyMetrics) -> Double?
  ) -> PersonalNorm? {
    let start = today.adding(days: -window)
    let values = days.filter { $0.day >= start && $0.day < today }.compactMap(field)
    return of(values)
  }

  public static func of(_ values: [Double]) -> PersonalNorm? {
    guard values.count >= minimumDays else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
    // Untergrenze für die Spanne, damit ein sehr gleichmäßiger Verlauf nicht jede Kleinigkeit meldet.
    let spread = max(variance.squareRoot(), abs(mean) * 0.03)
    func round(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    return PersonalNorm(mean: round(mean), low: round(mean - spread), high: round(mean + spread), count: values.count)
  }

  public func position(_ value: Double) -> Position {
    if value < low { return .below }
    if value > high { return .above }
    return .within
  }
}
