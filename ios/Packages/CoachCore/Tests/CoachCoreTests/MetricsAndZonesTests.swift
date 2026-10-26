import Foundation
import Testing

@testable import CoachCore

private func json(_ text: String) throws -> JSONValue {
  try JSONValue(data: Data(text.utf8))
}

private let today = CalendarDay(year: 2026, month: 10, day: 22)

private func activity(
  _ id: Int64, _ type: String, daysAgo: Int, maxHR: Double? = nil, averageHR: Double? = nil,
  minutes: Double = 45, km: Double = 10, zones: [Double]? = nil, vo2: Double? = nil
) -> GarminActivity {
  var activity = GarminActivity(id: id)
  activity.typeKey = type
  activity.startLocal = today.adding(days: -daysAgo).iso + " 07:00:00"
  activity.maxHeartRate = maxHR
  activity.averageHeartRate = averageHR
  activity.durationSeconds = minutes * 60
  activity.distanceMeters = km * 1000
  activity.secondsInZones = zones
  activity.vo2Max = vo2
  return activity
}

struct MoreGarminValuesTests {
  @Test func dailySummaryReadsSpo2RespirationAndBodyBatteryFlow() throws {
    let response = try json(
      """
      [{"calendarDate": "2026-10-22", "averageSpo2": 95, "lowestSpo2": 89, "avgWakingRespirationValue": 14.5,
        "bodyBatteryChargedValue": 62, "bodyBatteryDrainedValue": 48}]
      """)
    let metrics = try #require(GarminMetricsParser.dailySummaries(response)[today])
    #expect(metrics.spo2Average == 95)
    #expect(metrics.spo2Lowest == 89)
    #expect(metrics.respirationWaking == 14.5)
    #expect(metrics.bodyBatteryCharged == 62)
    #expect(metrics.bodyBatteryDrained == 48)
  }

  @Test func sleepReadsStagesAndNightValues() throws {
    let response = try json(
      """
      {"dailySleepDTO": {"calendarDate": "2026-10-22", "sleepTimeSeconds": 27000, "deepSleepSeconds": 5400,
        "lightSleepSeconds": 14400, "remSleepSeconds": 7200, "awakeSleepSeconds": 900,
        "averageRespirationValue": 13.2, "averageSpO2Value": 94, "lowestSpO2Value": 88, "avgSleepStress": 12}}
      """)
    let metrics = try #require(GarminMetricsParser.sleep(response)[today])
    #expect(metrics.deepSleepSeconds == 5400)
    #expect(metrics.remSleepSeconds == 7200)
    #expect(metrics.awakeSleepSeconds == 900)
    #expect(metrics.respirationSleep == 13.2)
    #expect(metrics.spo2Average == 94)
    #expect(metrics.sleepStress == 12)
    #expect(metrics.presentFields.contains("Schlafphasen"))
  }

  @Test func fitnessAgeAndSpo2Endpoints() throws {
    let fitness = try json(#"{"chronologicalAge": 36, "fitnessAge": 29.4, "components": {"vo2Max": 54.0}}"#)
    let metrics = try #require(GarminMetricsParser.fitnessAge(fitness, day: today)[today])
    #expect(metrics.fitnessAge == 29.4)
    #expect(metrics.vo2Max == 54)
    let empty = try json("{}")
    #expect(GarminMetricsParser.fitnessAge(empty, day: today).isEmpty)

    let spo2 = try json(#"{"calendarDate": "2026-10-22", "averageSpO2": 96, "lowestSpO2": 90}"#)
    #expect(GarminMetricsParser.spo2(spo2)[today]?.spo2Average == 96)
    #expect(GarminEndpoint.spo2(today).request.path == "/wellness-service/wellness/daily/spo2acclimation/2026-10-22")
    #expect(GarminEndpoint.fitnessAge(today).request.path == "/fitnessage-service/fitnessage/v2/2026-10-22")
  }

  @Test func activityReadsTimeInZones() throws {
    let response = try json(
      """
      [{"activityId": 1, "activityType": {"typeKey": "running"}, "hrTimeInZone_1": 300, "hrTimeInZone_2": 1800,
        "hrTimeInZone_3": 600, "hrTimeInZone_4": 0, "hrTimeInZone_5": 0},
       {"activityId": 2, "activityType": {"typeKey": "running"}, "hrTimeInZone_1": 300}]
      """)
    let activities = GarminActivityParser.activities(response)
    #expect(activities[0].secondsInZones == [300, 1800, 600, 0, 0])
    #expect(activities[1].secondsInZones == nil)
  }
}

struct HeartRateZoneTests {
  /// Erwartungswerte von Hand mit `friel_zones(170, "run", 190)` aus dem Altbestand nachgerechnet.
  @Test func frielZonesMatchLegacy() {
    let zones = HeartRateZoneCalculator.frielZones(threshold: 170, sport: .run, maxHeartRate: 190)
    #expect(zones.map(\.name) == ["Z1", "Z2", "Z3", "Z4", "Z5a", "Z5b", "Z5c"])
    #expect(zones.map(\.low) == [nil, 145, 153, 162, 170, 176, 181])
    #expect(zones.map(\.high) == [144, 152, 161, 169, 175, 180, 190])
    let coach = CoachZones(
      sport: .run, lactateThreshold: 170, source: "", isApproximate: false, zones: zones)
    #expect(coach.easyLimit == 152)
    #expect(coach.fiveZones.last == HeartRateZone(name: "Z5", use: "Schwelle+", low: 170, high: 190))
  }

  @Test func watchZonesFromGarmin() throws {
    let response = try json(
      """
      [{"trainingMethod": "HR_MAX", "sport": "DEFAULT", "zone1Floor": 95, "zone2Floor": 114, "zone3Floor": 133,
        "zone4Floor": 152, "zone5Floor": 171, "maxHeartRateUsed": 190, "restingHeartRateUsed": 48,
        "lactateThresholdHeartRateUsed": 168},
       {"sport": "CYCLING", "zone1Floor": 90}]
      """)
    let zones = HeartRateZoneCalculator.watchZones(response)
    #expect(zones.count == 1)
    #expect(zones[0].maxHeartRate == 190)
    #expect(zones[0].lactateThreshold == 168)
    #expect(zones[0].zones.map(\.high) == [113, 132, 151, 170, 190])
    #expect(zones[0].methodText == "% HFmax")
  }

  @Test func observedMaxNeedsConfirmation() {
    let activities = [
      activity(1, "running", daysAgo: 3, maxHR: 201),  // Ausreißer
      activity(2, "running", daysAgo: 10, maxHR: 186),
      activity(3, "road_biking", daysAgo: 20, maxHR: 184),
      activity(4, "strength_training", daysAgo: 1, maxHR: 199),  // zählt nicht
      activity(5, "running", daysAgo: 400, maxHR: 195),  // zu alt
    ]
    let observed = HeartRateZoneCalculator.observedMax(activities: activities, today: today)
    #expect(observed.confirmed == 186)
    #expect(observed.peak == 201)
    #expect(observed.count == 3)
  }

  @Test func reportPrefersOwnValuesThenGarmin() {
    var profile = GarminProfile()
    profile.lactateThresholdHeartRate = 168
    let activities = [
      activity(1, "running", daysAgo: 3, maxHR: 188), activity(2, "running", daysAgo: 5, maxHR: 187),
    ]
    let automatic = HeartRateZoneCalculator.report(
      activities: activities, watchZonesJSON: nil, profile: profile, overrides: HeartRateOverrides(), today: today)
    #expect(automatic.maxHeartRate == 188)
    #expect(automatic.maxHeartRateSource == "bestätigter Messwert (12 Monate)")
    #expect(automatic.run.lactateThreshold == 168)
    #expect(automatic.run.source == "Garmin (Laktatschwelle)")
    #expect(automatic.bike.isApproximate)
    #expect(automatic.hints.contains { $0.hasPrefix("Für das Rad") })

    let own = HeartRateZoneCalculator.report(
      activities: activities, watchZonesJSON: nil, profile: profile,
      overrides: HeartRateOverrides(maxHeartRate: 192, thresholdRun: 0, thresholdBike: 160), today: today)
    #expect(own.maxHeartRate == 192)
    #expect(own.run.lactateThreshold == 168)
    #expect(own.bike.lactateThreshold == 160)
    #expect(!own.bike.isApproximate)
  }

  @Test func estimateWithoutAnyThreshold() {
    let report = HeartRateZoneCalculator.report(
      activities: [], watchZonesJSON: nil, profile: nil, overrides: HeartRateOverrides(maxHeartRate: 190),
      today: today)
    #expect(report.run.lactateThreshold == 171)
    #expect(report.run.isApproximate)
    #expect(report.run.source == "Schätzung (90 % HFmax)")
  }

  @Test func distributionAndEasyShareHint() {
    let hard: [Double] = [0, 600, 1800, 600, 0]
    let activities = (0..<6).map {
      activity(Int64($0), "running", daysAgo: $0 * 3, averageHR: 160, minutes: 50, zones: hard)
    }
    let distribution = HeartRateZoneCalculator.distribution(activities: activities, today: today)
    #expect(distribution.run?.easyPercent == 20)
    #expect(distribution.run?.moderatePercent == 60)
    #expect(distribution.run?.hardPercent == 20)
    #expect(distribution.bike == nil)
    #expect(!distribution.perWeek.isEmpty)

    let report = HeartRateZoneCalculator.report(
      activities: activities, watchZonesJSON: nil, profile: nil,
      overrides: HeartRateOverrides(maxHeartRate: 190, thresholdRun: 170), today: today)
    #expect(report.hints.contains { $0.hasPrefix("Laufen: 0 % der Zeit") })
  }
}

struct TrendTests {
  @Test func trendComparesWithPreviousPeriod() {
    let values = (0..<14).map { DayValue(day: today.adding(days: -$0), value: $0 < 7 ? 60 : 50) }
    let trend = MetricTrend(values: values, days: 7, today: today)
    #expect(trend.points.count == 7)
    #expect(trend.latest?.day == today)
    #expect(trend.average == 60)
    #expect(trend.previousAverage == 50)
    #expect(trend.change == 10)
    #expect(MetricTrend(values: [], days: 7, today: today).change == nil)
  }

  @Test func weekVolumeHistoryAndVO2Max() {
    let activities = [
      activity(1, "running", daysAgo: 0, km: 10, vo2: 52),
      activity(2, "running", daysAgo: 1, km: 8, vo2: 53),
      activity(3, "running", daysAgo: 14, km: 12),
      activity(4, "virtual_ride", daysAgo: 7, km: 30, vo2: 55),
    ]
    let history = WeekVolume.history(activities: activities, today: today, weeks: 4)
    #expect(history.count == 4)
    #expect(history.last?.monday == today.adding(days: -today.weekdayIndex))
    #expect(history.map { $0.volume.kilometers[.run] ?? 0 } == [0, 12, 0, 18])
    #expect(VO2MaxHistory.values(activities: activities, sport: .run).map(\.value) == [53, 52])
    #expect(VO2MaxHistory.values(activities: activities, sport: .bike).count == 1)
  }
}
