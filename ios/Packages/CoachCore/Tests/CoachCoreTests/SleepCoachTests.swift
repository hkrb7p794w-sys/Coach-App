import Foundation
import Testing

@testable import CoachCore

struct SleepCoachTests {
  private let today = CalendarDay(year: 2026, month: 11, day: 10)

  private func nights(_ hours: [Double], starts: [Double]? = nil) -> [DailyMetrics] {
    hours.enumerated().map { index, value in
      var metrics = DailyMetrics(day: today.adding(days: -index))
      metrics.sleepSeconds = value * 3_600
      metrics.sleepStartMinutes = starts?[index]
      return metrics
    }
  }

  @Test func enoughSleepKeepsTheRoutine() throws {
    let report = try #require(
      SleepCoach.report(days: nights([8, 8.2, 7.9, 8.1, 8]), settings: SleepSettings(), goal: nil, today: today))
    #expect(report.tonightMinutes == 480)
    // Aufstehen 6:30, 8 Stunden Schlaf, 15 Minuten Einschlafen → 22:15.
    #expect(SleepCoach.clock(report.bedtimeMinutes) == "22:15")
    #expect(report.tips.map(\.id) == ["good"])
  }

  @Test func shortNightsMoveBedtimeEarlier() throws {
    let report = try #require(
      SleepCoach.report(
        days: nights([6, 6.5, 6, 6.2, 6.4, 6, 6.3]), settings: SleepSettings(), goal: .loseWeight, today: today))
    #expect(report.averageHours < 7)
    #expect(report.shortNights == 7)
    // Defizit über 10 Stunden → höchstens 60 Minuten extra.
    #expect(report.tonightMinutes == 540)
    #expect(SleepCoach.clock(report.bedtimeMinutes) == "21:15")
    #expect(report.tips.map(\.id) == ["short", "weight"])
  }

  @Test func irregularBedtimesAreReported() throws {
    // Einschlafzeiten zwischen 22:00 und 1:30.
    let starts: [Double] = [1_320, 90, 1_350, 60, 1_330, 45]
    let report = try #require(
      SleepCoach.report(
        days: nights([8, 8, 8, 8, 8, 8], starts: starts), settings: SleepSettings(), goal: nil, today: today))
    let spread = try #require(report.bedtimeSpreadMinutes)
    #expect(spread > SleepCoach.irregularMinutes)
    #expect(report.tips.contains { $0.id == "regular" })
  }

  @Test func needsThreeNightsAndClampsSettings() throws {
    #expect(SleepCoach.report(days: nights([8, 8]), settings: SleepSettings(), goal: nil, today: today) == nil)
    let decoded = try JSONDecoder().decode(
      SleepSettings.self, from: Data(#"{"targetHours": 12, "wakeHour": 30}"#.utf8))
    #expect(decoded.targetHours == 9)
    #expect(decoded.wakeHour == 23)
  }

  @Test func parsesSleepTimesFromConnect() {
    // 2026-11-10 23:15 Ortszeit als UTC-kodierte Millisekunden.
    let start = 1_794_352_500_000.0
    let json = JSONValue.object([
      "dailySleepDTO": .object([
        "calendarDate": .string("2026-11-11"), "sleepTimeSeconds": .number(27_000),
        "sleepStartTimestampLocal": .number(start), "sleepEndTimestampLocal": .number(start + 27_000_000),
      ])
    ])
    let metrics = GarminMetricsParser.sleep(json)[CalendarDay(year: 2026, month: 11, day: 11)]
    #expect(metrics?.sleepStartMinutes == 1_395)
    #expect(metrics?.sleepEndMinutes == 1_395 + 450 - 1_440)
  }
}
