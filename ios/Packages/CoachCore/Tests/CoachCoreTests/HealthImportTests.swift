import Foundation
import Testing

@testable import CoachCore

struct HealthImportTests {
  let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

  func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = berlin
    return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .now
  }

  @Test func dayValuesAreCheckedAndConverted() {
    var values = HealthImport.DayValues(day: CalendarDay(year: 2026, month: 10, day: 20))
    values.restingHeartRate = 52
    values.hrvSDNN = 48
    values.steps = 9_876
    values.activeKilocalories = 640
    values.basalKilocalories = 1_750
    values.oxygenSaturation = 0.97
    values.vo2Max = 300
    let metrics = HealthImport.metrics(values, includeHRV: false)
    #expect(metrics.restingHeartRate == 52)
    #expect(metrics.hrvLastNightAverage == nil)
    #expect(metrics.totalKilocalories == 2_390)
    #expect(metrics.spo2Average == 97)
    #expect(metrics.vo2Max == nil)
    #expect(HealthImport.metrics(values, includeHRV: true).hrvLastNightAverage == 48)
  }

  @Test func garminValuesWin() {
    let day = CalendarDay(year: 2026, month: 10, day: 20)
    var garmin = DailyMetrics(day: day)
    garmin.restingHeartRate = 50
    var health = DailyMetrics(day: day)
    health.restingHeartRate = 55
    health.steps = 8_000
    let filled = HealthImport.fill(garmin, with: health)
    #expect(filled.restingHeartRate == 50)
    #expect(filled.steps == 8_000)
    #expect(HealthImport.fill(nil, with: health) == health)
  }

  @Test func sleepPrefersWatchStagesAndIgnoresNaps() {
    let watch = "com.apple.health.watch"
    let samples = [
      // iPhone: nur „im Bett“ und unspezifischer Schlaf
      HealthImport.SleepSample(start: date(20, 22, 30), end: date(21, 7), stage: .asleep, source: "iphone"),
      HealthImport.SleepSample(start: date(20, 23), end: date(21, 1), stage: .core, source: watch),
      HealthImport.SleepSample(start: date(21, 1), end: date(21, 2), stage: .deep, source: watch),
      HealthImport.SleepSample(start: date(21, 2), end: date(21, 2, 15), stage: .awake, source: watch),
      HealthImport.SleepSample(start: date(21, 2, 15), end: date(21, 5), stage: .core, source: watch),
      HealthImport.SleepSample(start: date(21, 5), end: date(21, 6, 30), stage: .rem, source: watch),
      // Nickerchen am Nachmittag
      HealthImport.SleepSample(start: date(21, 14), end: date(21, 15), stage: .core, source: watch),
    ]
    let nights = HealthImport.sleep(samples, timeZone: berlin)
    let night = nights[CalendarDay(year: 2026, month: 10, day: 21)]
    #expect(nights.count == 1)
    #expect(night?.sleepSeconds == 7 * 3_600 + 15 * 60)
    #expect(night?.deepSleepSeconds == 3_600)
    #expect(night?.remSleepSeconds == 5_400)
    #expect(night?.awakeSleepSeconds == 900)
    #expect(night?.sleepStartMinutes == 23 * 60)
    #expect(night?.sleepEndMinutes == 6 * 60 + 30)
  }

  @Test func overlappingSamplesCountOnce() {
    let samples = [
      HealthImport.SleepSample(start: date(20, 23), end: date(21, 3), stage: .asleep, source: "a"),
      HealthImport.SleepSample(start: date(21, 2), end: date(21, 6), stage: .asleep, source: "a"),
    ]
    #expect(HealthImport.asleepSeconds(samples) == 7 * 3_600)
  }

  @Test func workoutsAreDeduplicatedAgainstGarminAndOwnApp() {
    var garminRun = GarminActivity(id: 123)
    garminRun.typeKey = "running"
    garminRun.startLocal = "2026-10-20 18:02:00"
    garminRun.durationSeconds = 3_000
    let run = HealthImport.Workout(
      uuid: UUID(), typeKey: "running", start: date(20, 18), end: date(20, 18, 50), distanceMeters: 10_000,
      sourceName: "Garmin Connect", sourceBundle: "com.garmin.connect.mobile")
    let ride = HealthImport.Workout(
      uuid: UUID(), typeKey: "cycling", start: date(21, 7), end: date(21, 8), distanceMeters: 30_000,
      kilocalories: 600, averageHeartRate: 140, sourceName: "Apple Watch", sourceBundle: "com.apple.health")
    let gym = HealthImport.Workout(
      uuid: UUID(), typeKey: "strength_training", start: date(22, 18), end: date(22, 19), sourceName: "Coach",
      sourceBundle: "io.github.hkrb7p794w.coach")
    let result = HealthImport.newActivities(
      [run, ride, gym], existing: [garminRun], ownBundle: "io.github.hkrb7p794w.coach", timeZone: berlin)
    #expect(result.count == 1)
    let activity = result[0]
    #expect(activity.id < 0)
    #expect(activity.id == HealthImport.activityID(ride.uuid))
    #expect(activity.sport == .bike)
    #expect(activity.startLocal == "2026-10-21 07:00:00")
    #expect(activity.day == CalendarDay(year: 2026, month: 10, day: 21))
    #expect(activity.name == "Radfahren · Apple Watch")
    #expect(activity.averageSpeed.map { ($0 * 100).rounded() / 100 } == 8.33)
  }

  @Test func weightsKeepLastPerDayAndRankBelowGarmin() {
    let entries = HealthImport.weights(
      [(date(20, 7), 80.04), (date(20, 21), 81.0), (date(21, 7), 79.6)], timeZone: berlin)
    #expect(entries.map(\.kilograms) == [81, 79.6])
    let day = CalendarDay(year: 2026, month: 10, day: 21)
    let merged = WeightTrend.merged(entries + [WeightEntry(day: day, kilograms: 79.9, source: .garmin)])
    #expect(merged.last?.kilograms == 79.9)
  }
}
