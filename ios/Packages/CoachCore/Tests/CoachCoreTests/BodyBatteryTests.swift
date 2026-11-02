import Foundation
import Testing

@testable import CoachCore

private func json(_ text: String) throws -> JSONValue {
  try JSONValue(data: Data(text.utf8))
}

private let april21 = CalendarDay(year: 2026, month: 4, day: 21)

struct BodyBatteryTests {
  /// Format laut python-garminconnect: Tag unter `date`, Zeitstempel in GMT.
  @Test func reportWithDateKeyGivesCurveInLocalTime() throws {
    let response = try json(
      """
      [{"date": "2026-04-21", "charged": 58, "drained": 32,
        "startTimestampGMT": "2026-04-20T22:00:00.0", "startTimestampLocal": "2026-04-21T00:00:00.0",
        "bodyBatteryValuesArray": [[1776722400000, 30], [1776744600000, 80], [1776745200000, 82],
          [1776783600000, 45], [1776783700000, -1]]}]
      """)
    let metrics = try #require(GarminMetricsParser.bodyBattery(response)[april21])
    #expect(metrics.bodyBatteryCharged == 58)
    #expect(metrics.bodyBatteryDrained == 32)
    #expect(metrics.bodyBatteryHigh == 82)
    #expect(metrics.bodyBatteryLow == 30)
    #expect(metrics.bodyBatteryLatest == 45)
    // 22:00 GMT = 0:00 Ortszeit (+2 h), 4:10 → Viertelstunde 6:00, 4:20 → 6:15, 15:00 → 17:00.
    #expect(
      metrics.bodyBatteryCurve == [
        BodyBatterySample(minute: 0, value: 30), BodyBatterySample(minute: 360, value: 80),
        BodyBatterySample(minute: 375, value: 82), BodyBatterySample(minute: 1020, value: 45),
      ])
  }

  @Test func descriptorListMovesValueIndex() throws {
    let response = try json(
      """
      [{"date": "2026-04-21",
        "bodyBatteryValueDescriptorDTOList": [
          {"bodyBatteryValueDescriptorIndex": 0, "bodyBatteryValueDescriptorKey": "timestamp"},
          {"bodyBatteryValueDescriptorIndex": 1, "bodyBatteryValueDescriptorKey": "bodyBatteryStatus"},
          {"bodyBatteryValueDescriptorIndex": 2, "bodyBatteryValueDescriptorKey": "bodyBatteryLevel"}],
        "bodyBatteryValuesArray": [[1776744600000, "MEASURED", 40], [1776783600000, "MEASURED", 70]]}]
      """)
    let utc = try #require(TimeZone(identifier: "UTC"))
    let metrics = try #require(GarminMetricsParser.bodyBattery(response, timeZone: utc)[april21])
    #expect(metrics.bodyBatteryCurve?.map(\.value) == [40, 70])
    #expect(metrics.bodyBatteryCurve?.map(\.minute) == [240, 900])
  }

  @Test func dailySummaryReadsWakeRestingCaloriesAndHeartRange() throws {
    let response = try json(
      """
      {"calendarDate": "2026-04-21", "bodyBatteryAtWakeTime": 74, "bmrKilocalories": 1720,
       "minHeartRate": 44, "maxHeartRate": 162}
      """)
    let metrics = try #require(GarminMetricsParser.dailySummaries(response)[april21])
    #expect(metrics.bodyBatteryAtWake == 74)
    #expect(metrics.restingKilocalories == 1720)
    #expect(metrics.minHeartRate == 44)
    #expect(metrics.maxHeartRate == 162)
  }

  @Test func readinessRecoveryTimeAndTrainingLoad() throws {
    let readiness = try json(#"[{"score": 60, "level": "MODERATE", "recoveryTime": 1260}]"#)
    #expect(GarminMetricsParser.trainingReadiness(readiness, day: april21)[april21]?.recoveryHours == 21)
    let recovered = try json(
      #"[{"score": 80, "recoveryTime": 900, "recoveryTimeChangePhrase": "REACHED_ZERO"}]"#)
    #expect(GarminMetricsParser.trainingReadiness(recovered, day: april21)[april21]?.recoveryHours == 0)

    let status = try json(
      """
      {"mostRecentTrainingStatus": {"latestTrainingStatusData": {"123": {
        "trainingStatusFeedbackPhrase": "PRODUCTIVE_3",
        "acuteTrainingLoadDTO": {"dailyTrainingLoadAcute": 512, "dailyTrainingLoadChronic": 430}}}}}
      """)
    let metrics = try #require(GarminMetricsParser.trainingStatus(status, day: april21)[april21])
    #expect(metrics.acuteLoad == 512)
    #expect(metrics.chronicLoad == 430)
  }

  @Test func healthImportKeepsRestingCalories() {
    var values = HealthImport.DayValues(day: april21)
    values.activeKilocalories = 600
    values.basalKilocalories = 1_700
    let metrics = HealthImport.metrics(values, includeHRV: false)
    #expect(metrics.restingKilocalories == 1_700)
    #expect(metrics.totalKilocalories == 2_300)
  }

  @Test func wakeValuePrefersGarminThenCurveAtWakeTime() {
    var metrics = DailyMetrics(day: april21)
    metrics.bodyBatteryCurve = [
      BodyBatterySample(minute: 300, value: 70), BodyBatterySample(minute: 405, value: 78),
      BodyBatterySample(minute: 600, value: 85),
    ]
    metrics.sleepEndMinutes = 410
    #expect(BodyBatteryAnalysis.wakeValue(metrics) == 78)
    metrics.sleepEndMinutes = nil
    #expect(BodyBatteryAnalysis.wakeValue(metrics) == 85)
    metrics.bodyBatteryAtWake = 76
    #expect(BodyBatteryAnalysis.wakeValue(metrics) == 76)
    #expect(BodyBatteryAnalysis.wakeValue(DailyMetrics(day: april21)) == nil)
  }

  @Test func summaryWithoutGarminIsEmpty() {
    var day = DailyMetrics(day: april21)
    day.restingHeartRate = 50
    let summary = BodyBatteryAnalysis.summary(days: [day], today: april21)
    #expect(!summary.hasData)
    #expect(summary.relations.isEmpty)
  }

  @Test func summaryHistoryNormAndRelations() {
    var days: [DailyMetrics] = []
    for offset in 0..<14 {
      var metrics = DailyMetrics(day: april21.adding(days: -offset))
      let long = offset % 2 == 0
      metrics.sleepSeconds = long ? 8 * 3_600 : 5.5 * 3_600
      metrics.bodyBatteryCharged = long ? 70 : 40
      metrics.stressAverage = long ? 20 : 45
      metrics.bodyBatteryDrained = long ? 50 : 75
      metrics.bodyBatteryHigh = long ? 90 : 60
      metrics.bodyBatteryAtWake = long ? 88 : 58
      days.append(metrics)
    }
    let summary = BodyBatteryAnalysis.summary(days: days, today: april21)
    #expect(summary.history.count == 14)
    #expect(summary.wake == 88)
    // 13 Vortage: 6 lange (88) und 7 kurze (58) Nächte.
    let norm = summary.wakeNorm
    #expect(norm?.count == 13)
    #expect((norm?.mean ?? 0) > 70 && (norm?.mean ?? 0) < 73)
    #expect(summary.relations.map(\.id) == ["sleep", "stress"])
    #expect(summary.relations[0].text.contains("um 70"))
    #expect(summary.relations[1].text.contains("75"))
  }

  @Test func relationsNeedEnoughDaysPerGroup() {
    let history = (0..<4).map { offset in
      BodyBatteryAnalysis.Day(
        day: april21.adding(days: -offset), high: 80, low: 20, wake: 70, charged: 60, drained: 50,
        sleepHours: 8, stress: 30)
    }
    #expect(BodyBatteryAnalysis.relations(history).isEmpty)
  }

  @Test func personalNormNeedsSevenDaysAndClassifies() {
    #expect(PersonalNorm.of([50, 51, 52]) == nil)
    let norm = PersonalNorm.of([48, 50, 52, 49, 51, 50, 50])
    #expect(norm?.mean == 50)
    #expect(norm?.position(44) == .below)
    #expect(norm?.position(50.5) == .within)
    #expect(norm?.position(56) == .above)
    // Heute zählt nicht mit.
    let days = (0..<8).map { offset -> DailyMetrics in
      var metrics = DailyMetrics(day: april21.adding(days: -offset))
      metrics.restingHeartRate = offset == 0 ? 80 : 50
      return metrics
    }
    #expect(PersonalNorm.of(days, today: april21) { $0.restingHeartRate }?.mean == 50)
  }
}
