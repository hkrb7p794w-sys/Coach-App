import Foundation
import Testing

@testable import CoachCore

/// Beispielantworten im Format der Garmin-Connect-Endpunkte (Feldnamen aus python-garminconnect und
/// dem Altbestand). Die echten Antworten der Personal API werden nach dem ersten Abruf in der App
/// geprüft (Diagnose-Ansicht) und die Fixtures bei Bedarf angepasst.
private func json(_ text: String) throws -> JSONValue {
  try JSONValue(data: Data(text.utf8))
}

private let day = CalendarDay(year: 2026, month: 10, day: 22)

struct GarminParsingTests {
  @Test func dailySummariesReadsRecoveryFields() throws {
    let response = try json(
      """
      {"data": [
        {"calendarDate": "2026-10-22", "totalSteps": 10234, "restingHeartRate": 48,
         "averageStressLevel": 27, "bodyBatteryHighestValue": 88, "bodyBatteryLowestValue": 21,
         "bodyBatteryMostRecentValue": 35, "activeKilocalories": 812, "totalKilocalories": 2650},
        {"calendarDate": "2026-10-21", "totalSteps": 8000, "restingHeartRate": 50, "averageStressLevel": -1}
      ]}
      """)

    let map = GarminMetricsParser.dailySummaries(response)

    #expect(map.count == 2)
    let today = try #require(map[day])
    #expect(today.restingHeartRate == 48)
    #expect(today.steps == 10234)
    #expect(today.stressAverage == 27)
    #expect(today.bodyBatteryHigh == 88)
    #expect(today.bodyBatteryLow == 21)
    #expect(today.bodyBatteryLatest == 35)
    #expect(today.activeKilocalories == 812)
    #expect(map[day.adding(days: -1)]?.stressAverage == nil)
  }

  @Test func hrvDayReadsSummaryAndBaseline() throws {
    let response = try json(
      """
      {"userProfilePk": 1, "hrvSummary": {"calendarDate": "2026-10-22", "weeklyAvg": 62, "lastNightAvg": 58,
       "status": "balanced", "baseline": {"lowUpper": 50, "balancedLow": 55, "balancedUpper": 70}},
       "hrvReadings": [{"hrvValue": 57, "readingTimeGMT": "2026-10-22T01:00:00.0"}]}
      """)

    let metrics = try #require(GarminMetricsParser.hrv(response)[day])

    #expect(metrics.hrvLastNightAverage == 58)
    #expect(metrics.hrvWeeklyAverage == 62)
    #expect(metrics.hrvStatus == "BALANCED")
    #expect(metrics.hrvBaselineLow == 55)
    #expect(metrics.hrvBaselineHigh == 70)
  }

  @Test func hrvSummariesReadsSeveralDays() throws {
    let response = try json(
      """
      {"hrvSummaries": [
        {"calendarDate": "2026-10-21", "weeklyAvg": 60, "lastNightAvg": 61, "status": "UNBALANCED",
         "baseline": {"balancedLow": 55, "balancedUpper": 70}},
        {"calendarDate": "2026-10-22", "weeklyAvg": 62, "lastNightAvg": 58, "status": "BALANCED"}
      ]}
      """)

    let map = GarminMetricsParser.hrv(response)

    #expect(map.count == 2)
    #expect(map[day.adding(days: -1)]?.hrvStatus == "UNBALANCED")
    #expect(map[day]?.hrvBaselineLow == nil)
  }

  @Test func sleepReadsDurationAndScore() throws {
    let response = try json(
      """
      {"dailySleepDTO": {"calendarDate": "2026-10-22", "sleepTimeSeconds": 26100,
        "sleepScores": {"overall": {"value": 81, "qualifierKey": "GOOD"}}},
       "restingHeartRate": 47}
      """)

    let metrics = try #require(GarminMetricsParser.sleep(response)[day])

    #expect(metrics.sleepSeconds == 26100)
    #expect(metrics.sleepHours == 7.3)
    #expect(metrics.sleepScore == 81)
  }

  @Test func bodyBatteryDerivesHighLowLatestFromValues() throws {
    let response = try json(
      """
      [{"calendarDate": "2026-10-22", "charged": 60, "drained": 55,
        "bodyBatteryValuesArray": [[1761091200000, 30], [1761105600000, 92], [1761148800000, 41], [1761150000000, -1]]}]
      """)

    let metrics = try #require(GarminMetricsParser.bodyBattery(response)[day])

    #expect(metrics.bodyBatteryHigh == 92)
    #expect(metrics.bodyBatteryLow == 30)
    #expect(metrics.bodyBatteryLatest == 41)
  }

  @Test func mergeKeepsValuesFromAllSources() throws {
    var summary = DailyMetrics(day: day)
    summary.restingHeartRate = 48
    var hrv = DailyMetrics(day: day)
    hrv.hrvStatus = "LOW"
    var sleep = DailyMetrics(day: day)
    sleep.sleepSeconds = 20000
    sleep.restingHeartRate = nil

    let merged = try #require(GarminMetricsParser.merge([[day: summary], [day: hrv], [day: sleep]])[day])

    #expect(merged.restingHeartRate == 48)
    #expect(merged.hrvStatus == "LOW")
    #expect(merged.sleepSeconds == 20000)
    #expect(merged.presentFields == ["Ruhepuls", "HRV-Status", "Schlafdauer"])
  }

  @Test func unknownShapeYieldsNoRecords() throws {
    #expect(GarminMetricsParser.dailySummaries(try json(#"{"message": "nope"}"#)).isEmpty)
    #expect(GarminMetricsParser.sleep(.null).isEmpty)
  }

  @Test func activitiesFromSearch() throws {
    let response = try json(
      """
      [{"activityId": 21000000001, "activityName": "Lauf am Morgen", "startTimeLocal": "2026-10-22 06:30:00",
        "activityType": {"typeKey": "running", "typeId": 1}, "distance": 10012.5, "duration": 3120.4,
        "averageHR": 142, "maxHR": 171, "calories": 690, "activityTrainingLoad": 118.3,
        "aerobicTrainingEffect": 3.1, "anaerobicTrainingEffect": 0.8, "vO2MaxValue": 52},
       {"activityId": 21000000002, "activityType": {"typeKey": "strength_training"},
        "startTimeLocal": "2026-10-21 18:00:00", "duration": 2700},
       {"activityName": "ohne ID"}]
      """)

    let activities = GarminActivityParser.activities(response)

    #expect(activities.count == 2)
    let run = activities[0]
    #expect(run.id == 21_000_000_001)
    #expect(run.sport == .run)
    #expect(run.day == day)
    #expect(run.distanceMeters == 10012.5)
    #expect(run.trainingLoad == 118.3)
    #expect(run.vo2Max == 52)
    #expect(activities[1].sport == .strength)
  }

  @Test(arguments: [
    ("lap_swimming", GarminActivity.Sport.swim),
    ("road_biking", .bike),
    ("indoor_cycling", .bike),
    ("trail_running", .run),
    ("treadmill_running", .run),
    ("strength_training", .strength),
    ("yoga", .other),
  ])
  func sportMapping(typeKey: String, expected: GarminActivity.Sport) {
    var activity = GarminActivity(id: 1)
    activity.typeKey = typeKey
    #expect(activity.sport == expected)
  }

  @Test func profileFromSettings() throws {
    let response = try json(
      """
      {"id": 1, "userData": {"gender": "male", "weight": 78400.0, "height": 182.0,
       "birthDate": "1990-05-17", "vo2MaxRunning": 52.0, "lactateThresholdHeartRate": 168}}
      """)

    let profile = GarminProfile(settings: response)

    #expect(profile.weightKilograms == 78.4)
    #expect(profile.heightCentimeters == 182)
    #expect(profile.gender == "MALE")
    #expect(profile.age(on: day) == 36)
    #expect(profile.age(on: CalendarDay(year: 2026, month: 5, day: 16)) == 35)
  }

  @Test func keyPathsListLeafFields() throws {
    let response = try json(#"{"a": {"b": 1, "c": [{"d": true}, {"d": false}]}, "e": null}"#)
    #expect(response.keyPaths() == ["a.b", "a.c[].d", "e"])
  }
}
