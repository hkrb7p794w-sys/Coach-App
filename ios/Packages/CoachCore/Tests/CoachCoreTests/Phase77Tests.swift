import Foundation
import Testing

@testable import CoachCore

/// Phase 77 (Audit): Tag und Ampel.
struct Phase77Tests {
  private let today = CalendarDay(year: 2026, month: 11, day: 9)
  private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

  private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlin
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .now
  }

  // MARK: - Ampel

  /// R2A-01: Nur Schritte sind keine Bewertung.
  @Test func stepsAloneGiveNoAmpel() {
    var metrics = DailyMetrics(day: today)
    metrics.steps = 8_000
    let state = RecoveryEvaluator.today(days: [metrics], form: [], today: today)
    #expect(!state.isKnown)
    #expect(state.level == nil)
  }

  @Test func restingPulseCountsOnlyWithAverage() {
    var metrics = DailyMetrics(day: today)
    metrics.restingHeartRate = 50
    #expect(!RecoveryEvaluator.today(days: [metrics], form: [], today: today).isKnown)
    let week = (1...7).map { offset -> DailyMetrics in
      var day = DailyMetrics(day: today.adding(days: -offset))
      day.restingHeartRate = 50
      return day
    }
    #expect(RecoveryEvaluator.today(days: [metrics] + week, form: [], today: today).level == .normal)
  }

  /// CORE2-06: Ohne Nachtwerte von heute gilt die letzte Nacht, in allen Ansichten gleich.
  @Test func todayFallsBackToLastNightWithInputs() {
    var morning = DailyMetrics(day: today)
    morning.steps = 300
    var night = DailyMetrics(day: today.adding(days: -1))
    night.sleepSeconds = 4 * 3_600
    let state = RecoveryEvaluator.today(days: [morning, night], form: [], today: today)
    #expect(state.metrics?.day == night.day)
    #expect(state.level == .pause)
  }

  @Test func morningReportUsesTheSameLevel() {
    var night = DailyMetrics(day: today)
    night.sleepSeconds = 8 * 3_600
    night.bodyBatteryAtWake = 20
    night.sleepScore = 40
    let report = MorningReport.make(days: [night], today: today, sleep: SleepSettings())
    #expect(report.level == RecoveryEvaluator.today(days: [night], form: [], today: today).level)
    #expect(report.level == .normal)
  }

  @Test func shortSleepTextIsNotRoundedUp() {
    var metrics = DailyMetrics(day: today)
    metrics.sleepSeconds = (4 * 60 + 57) * 60
    let result = RecoveryEvaluator.evaluate(metrics, restingHeartRate7DayAverage: nil)
    #expect(result.reasons.first == "nur 4,9 h Schlaf")
  }

  // MARK: - HRV (SCI-12)

  private func hrvDays(recent: Double, baseline: Double) -> [DailyMetrics] {
    (0..<40).map { offset in
      var day = DailyMetrics(day: today.adding(days: -offset))
      day.hrvLastNightAverage = offset < 7 ? recent : baseline + Double(offset % 3) * 2
      return day
    }
  }

  @Test func hrvWithoutStatusUsesWeeklyMean() {
    #expect(MorningReport.hrvTrend(hrvDays(recent: 40, baseline: 60), reference: today) == .below)
    #expect(MorningReport.hrvTrend(hrvDays(recent: 62, baseline: 60), reference: today) == .within)
  }

  @Test func oneLowNightDoesNotMoveTheWeeklyMean() {
    var days = hrvDays(recent: 62, baseline: 60)
    days[0].hrvLastNightAverage = 45
    #expect(MorningReport.hrvTrend(days, reference: today) == .within)
  }

  @Test func hrvTrendNeedsEnoughHistory() {
    let days = Array(hrvDays(recent: 40, baseline: 60).prefix(10))
    #expect(MorningReport.hrvTrend(days, reference: today) == nil)
  }

  // MARK: - Schlaf (R5A-01)

  @Test func daySleepAfterNightShiftCountsCompletely() {
    let watch = "com.apple.health.watch"
    let stages: [HealthImport.SleepStage] = [.core, .deep, .core, .rem, .core, .deep, .rem]
    let samples = (0..<7).map { index in
      HealthImport.SleepSample(
        start: date(21, 8 + index), end: date(21, 9 + index), stage: stages[index], source: watch)
    }
    let night = HealthImport.sleep(samples, timeZone: berlin)[CalendarDay(year: 2026, month: 10, day: 21)]
    #expect(night?.sleepSeconds == 25_200)
    #expect(night?.sleepEndMinutes == 900)
    if let night {
      #expect(RecoveryEvaluator.evaluate(night, restingHeartRate7DayAverage: nil).level != .pause)
    }
  }

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

  @Test func afternoonNapStaysANap() {
    let watch = "com.apple.health.watch"
    let samples = [
      HealthImport.SleepSample(start: date(20, 23), end: date(21, 7), stage: .core, source: watch),
      HealthImport.SleepSample(start: date(21, 14), end: date(21, 15), stage: .core, source: watch),
    ]
    let night = HealthImport.sleep(samples, timeZone: berlin)[CalendarDay(year: 2026, month: 10, day: 21)]
    #expect(night?.sleepSeconds == 28_800)
    #expect(night?.sleepEndMinutes == 420)
  }

  // MARK: - Widgets

  private func snapshot(gym: WidgetSnapshot.Gym?) -> WidgetSnapshot {
    WidgetSnapshot(
      createdAt: Date(timeIntervalSince1970: 1_800_000_000), day: today,
      today: .init(level: .normal, headline: "Normal trainieren"), nutrition: nil, gym: gym,
      health: [.init(metric: .sleep, value: "7,4 h", gauge: nil, status: .good, note: "Über deinem Bedarf")])
  }

  /// R3C-02
  @Test func healthOfPreviousSnapshotDayIsOldOnNextDay() {
    let next = snapshot(gym: nil).display(on: today.adding(days: 1))
    #expect(!next.isCurrent)
    #expect(next.healthIsOld)
    #expect(!snapshot(gym: nil).display(on: today).healthIsOld)
  }

  /// R3C-03: Die Einheit von gestern steht nicht mehr als nächstes Training da.
  @Test func dayBoundWorkoutIsClearedOnNextDay() {
    var gym = WidgetSnapshot.Gym(
      next: "Oberkörper", nextDetail: "Plan", running: false, runningTitle: nil, last: nil, weekDone: 1, weekPlanned: 3)
    gym.nextIsForDay = true
    let next = snapshot(gym: gym).display(on: today.adding(days: 1)).snapshot.gym
    #expect(next?.next == "App öffnen")
    #expect(next?.nextDetail == nil)
    gym.nextIsForDay = nil
    #expect(snapshot(gym: gym).display(on: today.adding(days: 1)).snapshot.gym?.next == "Oberkörper")
  }
}
