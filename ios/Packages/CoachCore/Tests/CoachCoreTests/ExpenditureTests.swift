import Foundation
import Testing

@testable import CoachCore

struct ExpenditureTests {
  private let today = CalendarDay(year: 2026, month: 11, day: 30)

  /// Tägliche Wägungen: `perWeek` kg pro Woche, leichtes Rauschen.
  private func weights(start: Double, perWeek: Double) -> [WeightEntry] {
    (1...28).map { back in
      let day = today.adding(days: -back)
      let offset = Double(28 - back)
      let noise = back.isMultiple(of: 2) ? 0.2 : -0.2
      return WeightEntry(day: day, kilograms: start + perWeek * offset / 7 + noise, source: .manual)
    }
  }

  private func intake(_ kilocalories: Double, days: Int = 28) -> [CalendarDay: Double] {
    Dictionary(uniqueKeysWithValues: (1...days).map { (today.adding(days: -$0), kilocalories) })
  }

  @Test func deficitShowsHigherExpenditure() throws {
    // 2.000 kcal gegessen, 0,5 kg pro Woche abgenommen → etwa 2.000 + 0,5 × 7.700 / 7 = 2.550 kcal.
    let result = try #require(
      Expenditure.estimate(
        intake: intake(2_000), weights: weights(start: 80, perWeek: -0.5), today: today, basalMetabolicRate: 1_700))
    #expect(abs(result.kilocalories - 2_550) <= 40)
    #expect(result.plausible)
    #expect(result.loggedDays == 28)
  }

  @Test func incompleteDaysAreExcluded() throws {
    var days = intake(2_400)
    for back in [3, 9, 15] { days[today.adding(days: -back)] = 600 }
    let result = try #require(
      Expenditure.estimate(
        intake: days, weights: weights(start: 70, perWeek: 0), today: today, basalMetabolicRate: 1_500))
    #expect(result.excludedDays == 3)
    #expect(abs(result.averageIntake - 2_400) < 1)
  }

  @Test func needsEnoughLoggedDaysAndWeights() {
    #expect(
      Expenditure.estimate(
        intake: intake(2_000, days: 10), weights: weights(start: 80, perWeek: -0.5), today: today,
        basalMetabolicRate: 1_700) == nil)
    #expect(
      Expenditure.estimate(intake: intake(2_000), weights: [], today: today, basalMetabolicRate: 1_700) == nil)
  }

  @Test func implausibleResultGivesNoAdjustment() throws {
    // 900 kcal erfasst bei gleichem Gewicht: fast sicher Lücken beim Erfassen.
    let result = try #require(
      Expenditure.estimate(
        intake: intake(900), weights: weights(start: 80, perWeek: 0), today: today, basalMetabolicRate: 1_700))
    #expect(!result.plausible)
    #expect(Expenditure.adjustment(result, formulaMaintenance: 2_400, current: 0) == nil)
  }

  @Test func adjustmentIsRoundedAndLimited() {
    func result(_ kilocalories: Double) -> Expenditure.Result {
      Expenditure.Result(
        kilocalories: kilocalories, averageIntake: kilocalories, loggedDays: 20, excludedDays: 0,
        kilogramsPerWeek: 0, plausible: true)
    }
    #expect(Expenditure.adjustment(result(2_730), formulaMaintenance: 2_500, current: 0) == 250)
    #expect(Expenditure.adjustment(result(3_400), formulaMaintenance: 2_500, current: 0) == 500)
    #expect(Expenditure.adjustment(result(2_560), formulaMaintenance: 2_500, current: 0) == nil)
    // Schon übernommen: kein erneuter Vorschlag.
    #expect(Expenditure.adjustment(result(2_730), formulaMaintenance: 2_500, current: 250) == nil)
    // Abweichung verschwunden: Anpassung zurücknehmen.
    #expect(Expenditure.adjustment(result(2_520), formulaMaintenance: 2_500, current: 300) == 0)
  }
}
