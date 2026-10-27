import Foundation

/// Tatsächlicher Energieverbrauch aus erfasster Ernährung und Gewichtsverlauf (Intake-Balance-Methode):
/// Verbrauch = mittlere Zufuhr − Änderung der Körperreserven. Mit Gewichtsdaten lag die Methode nah an der
/// tatsächlichen Zufuhr (Gilmore et al. 2014; Sanghvi et al. 2015). Sie ist nur so gut wie die Erfassung:
/// Selbstauskünfte unterschätzen die Zufuhr oft deutlich (Lichtman et al. 1992). Tage mit offensichtlich
/// unvollständiger Erfassung zählen deshalb nicht, und unplausible Ergebnisse werden nicht verwendet.
public enum Expenditure {
  public static let windowDays = 28
  public static let minimumLoggedDays = 14
  /// Tage unter diesem Anteil des Medians gelten als unvollständig erfasst.
  public static let incompleteShare = 0.5
  /// Ab dieser Abweichung von der Formel schlägt die App eine Anpassung vor (kcal pro Tag).
  public static let minimumDifference = 150.0

  public struct Result: Equatable, Sendable {
    /// Geschätzter Verbrauch in kcal pro Tag (auf 10 gerundet).
    public var kilocalories: Double
    public var averageIntake: Double
    public var loggedDays: Int
    public var excludedDays: Int
    /// Gewichtsänderung laut Trend in kg pro Woche.
    public var kilogramsPerWeek: Double
    /// `false`, wenn das Ergebnis außerhalb von 1,1–3,5 × Grundumsatz liegt (meist Lücken beim Erfassen).
    public var plausible: Bool
  }

  /// `intake`: erfasste kcal je Tag (Tage ohne Eintrag fehlen). Der heutige Tag zählt nicht, er ist noch offen.
  public static func estimate(
    intake: [CalendarDay: Double], weights: [WeightEntry], today: CalendarDay, basalMetabolicRate: Double
  ) -> Result? {
    let start = today.adding(days: -windowDays)
    let days = intake.filter { $0.key >= start && $0.key < today && $0.value > 0 }
    guard !days.isEmpty else { return nil }
    let sorted = days.values.sorted()
    let median = sorted[sorted.count / 2]
    let included = days.values.filter { $0 >= incompleteShare * median }
    guard included.count >= minimumLoggedDays,
      let trend = WeightTrend.trend(weights, today: today.adding(days: -1))
    else { return nil }
    let average = included.reduce(0, +) / Double(included.count)
    let perWeek = trend.weeklyPercent / 100 * trend.trendKilograms
    let kilocalories = average - perWeek / 7 * 7_700
    let plausible = (1.1 * basalMetabolicRate...3.5 * basalMetabolicRate).contains(kilocalories)
    return Result(
      kilocalories: (kilocalories / 10).rounded() * 10, averageIntake: average.rounded(),
      loggedDays: included.count, excludedDays: days.count - included.count,
      kilogramsPerWeek: (perWeek * 100).rounded() / 100, plausible: plausible)
  }

  /// Vorschlag für die gesamte Anpassung der Tagesenergie: Unterschied zwischen gemessenem Verbrauch und dem
  /// Bedarf laut Formel (`formulaMaintenance`, ohne Ziel und Anpassung), auf 50 gerundet und auf ±500 begrenzt.
  /// `nil`, wenn das Ergebnis unplausibel ist oder sich kaum etwas ändern würde.
  public static func adjustment(_ result: Result, formulaMaintenance: Double, current: Double) -> Double? {
    guard result.plausible else { return nil }
    let difference = result.kilocalories - formulaMaintenance
    guard abs(difference) >= minimumDifference else { return current == 0 ? nil : 0 }
    let limit = WeightTrend.maxTotalKilocalories
    let proposal = (min(max(difference, -limit), limit) / 50).rounded() * 50
    return abs(proposal - current) >= 100 ? proposal : nil
  }
}
