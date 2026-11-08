import Foundation
import Testing

@testable import CoachCore

/// Runde 5 (R5A): Schichtarbeit und Menstruationszyklus.
struct AuditR5ATests {
  let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

  func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlin
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .now
  }

  /// R5A-01: Die Nickerchen-Regel (Beginn 10–18 Uhr) prüft jede einzelne Schlafphase statt der ganzen
  /// Schlafepisode (HealthImport.swift:100–102). Tagschlaf nach der Nachtschicht (8–15 Uhr, Apple Watch schreibt
  /// stündliche Phasen) zählt nur 8–10 Uhr = 2 h; die Tagesampel springt deshalb auf „Pause“ (< 5 h).
  @Test func daySleepAfterNightShiftCountsCompletely() {
    let watch = "com.apple.health.watch"
    let stages: [HealthImport.SleepStage] = [.core, .deep, .core, .rem, .core, .deep, .rem]
    let samples = (0..<7).map { index in
      HealthImport.SleepSample(
        start: date(21, 8 + index), end: date(21, 9 + index), stage: stages[index], source: watch)
    }
    let nights = HealthImport.sleep(samples, timeZone: berlin)
    let night = nights[CalendarDay(year: 2026, month: 10, day: 21)]
    #expect(night?.sleepSeconds == 25_200)
    #expect(night?.sleepEndMinutes == 900)
    if let night {
      #expect(RecoveryEvaluator.evaluate(night, restingHeartRate7DayAverage: nil).level != .pause)
    }
  }

  /// R5A-01 (auch ohne Schichtarbeit): Ausschlafen bis 10:30 Uhr – die Phasen ab 10 Uhr fallen weg.
  @Test func sleepingInPastTenIsNotCutOff() {
    let watch = "com.apple.health.watch"
    let samples = [
      HealthImport.SleepSample(start: date(20, 23, 30), end: date(21, 4), stage: .core, source: watch),
      HealthImport.SleepSample(start: date(21, 4), end: date(21, 10), stage: .core, source: watch),
      HealthImport.SleepSample(start: date(21, 10), end: date(21, 10, 30), stage: .rem, source: watch),
    ]
    let night = HealthImport.sleep(samples, timeZone: berlin)[CalendarDay(year: 2026, month: 10, day: 21)]
    #expect(night?.sleepSeconds == 39_600)
    #expect(night?.sleepEndMinutes == 630)
  }

  /// Gewichtsstabile Frau, zyklische Wassereinlagerung ±0,5 kg (Periode 28 Tage, Annahme), tägliche Wägung.
  func cyclingWeights(base: CalendarDay, days: Int) -> [WeightEntry] {
    (0..<days).map { offset in
      let raw = 70 + 0.5 * sin(2 * Double.pi * Double(offset) / 28)
      return WeightEntry(day: base.adding(days: offset), kilograms: (raw * 10).rounded() / 10, source: .manual)
    }
  }

  /// R5A-02: Die lineare Regression über genau 28 Tage (WeightTrend.swift:62–80) macht aus der zyklischen
  /// Wassereinlagerung je nach Phase bis zu ±0,35 % pro Woche „Trend“ (Toleranz 0,25 %). Beim Ziel „halten“
  /// schlägt die App dann „+250 kcal“ bzw. „−250 kcal“ vor, obwohl sich das Gewicht nicht ändert.
  @Test func menstrualWaterRetentionIsNoWeightTrend() throws {
    let base = CalendarDay(year: 2026, month: 9, day: 1)
    let today = base.adding(days: 55)
    let result = try #require(WeightTrend.trend(cyclingWeights(base: base, days: 56), today: today))
    #expect(abs(result.weeklyPercent) <= WeightTrend.tolerancePercent)
    let advice = WeightTrend.advice(result: result, plannedPercent: nil, currentAdjustment: 0)
    #expect(advice.kind == .onTrack)
  }

  /// R5A-02: Gleiches Muster im gemessenen Verbrauch (Expenditure.swift:39–43): 2.000 kcal gegessen, Gewicht
  /// stabil, trotzdem „Verbrauch 2.270 kcal“ und Vorschlag „Tagesziele um +250 kcal anpassen“.
  @Test func menstrualWaterRetentionDoesNotChangeExpenditure() throws {
    let base = CalendarDay(year: 2026, month: 9, day: 1)
    let today = base.adding(days: 56)
    var intake: [CalendarDay: Double] = [:]
    for offset in 0..<56 { intake[base.adding(days: offset)] = 2_000 }
    let result = try #require(
      Expenditure.estimate(
        intake: intake, weights: cyclingWeights(base: base, days: 56), today: today, basalMetabolicRate: 1_400))
    #expect(abs(result.kilocalories - 2_000) < Expenditure.minimumDifference)
    #expect(Expenditure.adjustment(result, formulaMaintenance: 2_000, current: 0) == nil)
  }
}
