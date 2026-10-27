import Foundation

/// Prognose beim Abnehmen: erwartetes Gewicht nach 4, 8 und 12 Wochen und bis zum Zielgewicht, mit dem dafür
/// geschätzten Kaloriendefizit. Gesund und nachhaltig heißt: das Tempo aus `GoalRules` (Standard 0,5 %, höchstens
/// 1 % des Körpergewichts pro Woche), ein Defizit von höchstens 25 % des Bedarfs (wie in `NutritionPlanner`) und
/// nie unter BMI 18,5. 7.700 kcal je kg sind eine Näherung; der Körper passt sich an (Hall et al. 2011), deshalb
/// steuert die App anhand der Waage nach.
public enum WeightForecast {
  public static let kilocaloriesPerKilogram = 7_700.0
  public static let maximumDeficitShare = 0.25
  public static let horizons = [4, 8, 12]

  public struct Point: Equatable, Sendable, Identifiable {
    public var weeks: Int
    public var day: CalendarDay
    public var kilograms: Double
    public var id: Int { weeks }
  }

  public struct Result: Equatable, Sendable {
    /// Geplantes Tempo in % pro Woche (positiv = Abnahme).
    public var weeklyPercent: Double
    public var weeklyKilograms: Double
    /// Geschätztes Defizit pro Tag in kcal.
    public var dailyDeficit: Double
    /// Defizit wurde auf 25 % des Bedarfs begrenzt.
    public var deficitCapped: Bool
    public var points: [Point]
    public var target: Double?
    public var weeksToTarget: Int?
    public var targetDay: CalendarDay?
    /// Untergrenze (BMI 18,5).
    public var floorKilograms: Double
  }

  /// - Parameters:
  ///   - weeklyChangePercent: geplante Änderung pro Woche (negativ = abnehmen), z. B. `-0.5`.
  ///   - maintenanceKilocalories: geschätzter Tagesbedarf ohne Ziel, für die 25-%-Grenze.
  public static func compute(
    currentKilograms: Double, weeklyChangePercent: Double, heightCentimeters: Double,
    maintenanceKilocalories: Double?, target: Double?, today: CalendarDay
  ) -> Result? {
    guard currentKilograms > 0, weeklyChangePercent < 0 else { return nil }
    let meters = heightCentimeters / 100
    let floor = meters > 0 ? (GoalRules.minimumBMI * meters * meters * 10).rounded(.up) / 10 : 0
    var percent = min(-weeklyChangePercent, GoalRules.maxLossPercentPerWeek)
    var deficit = percent / 100 * currentKilograms * kilocaloriesPerKilogram / 7
    var capped = false
    if let maintenance = maintenanceKilocalories, maintenance > 0, deficit > maintenance * maximumDeficitShare {
      deficit = maintenance * maximumDeficitShare
      percent = deficit * 7 / kilocaloriesPerKilogram / currentKilograms * 100
      capped = true
    }
    let goal = target.map { max($0, floor) }
    func weight(after weeks: Int) -> Double {
      // Tempo in % des jeweils aktuellen Gewichts: wer leichter wird, verliert pro Woche etwas weniger.
      let projected = currentKilograms * pow(1 - percent / 100, Double(weeks))
      return max(projected, goal ?? floor, floor)
    }
    let points = horizons.map { weeks in
      Point(weeks: weeks, day: today.adding(days: weeks * 7), kilograms: (weight(after: weeks) * 10).rounded() / 10)
    }
    var weeksToTarget: Int?
    if let goal, goal < currentKilograms, percent > 0 {
      let weeks = log(goal / currentKilograms) / log(1 - percent / 100)
      weeksToTarget = Int(weeks.rounded(.up))
    }
    return Result(
      weeklyPercent: (percent * 100).rounded() / 100,
      weeklyKilograms: (currentKilograms * percent / 100 * 100).rounded() / 100,
      dailyDeficit: (deficit / 10).rounded() * 10, deficitCapped: capped, points: points, target: goal,
      weeksToTarget: weeksToTarget, targetDay: weeksToTarget.map { today.adding(days: $0 * 7) },
      floorKilograms: floor)
  }
}
