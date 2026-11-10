import Foundation
import Testing

@testable import CoachCore

struct HealthRecordingTests {
  /// 20 Minuten Lauf mit 3 m/s: Distanz in 3-s-Stücken, Puls alle 5 s.
  private func run(pause: HealthRecording.Interval? = nil) -> HealthRecording.Input {
    var input = HealthRecording.Input(start: 1_000, end: 2_200)
    var time = 1_000.0
    while time < 2_200 {
      let paused = pause.map { $0.start <= time && time < $0.end } ?? false
      if !paused { input.distance.append(HealthRecording.Amount(start: time, end: time + 3, value: 9)) }
      time += 3
    }
    input.heartRate = stride(from: 1_000.0, through: 2_200, by: 5).map {
      HealthRecording.Sample(time: $0, value: $0 < 1_600 ? 140 : 150)
    }
    if let pause { input.pauses = [pause] }
    return input
  }

  @Test func buildsRecordsOnAFiveSecondGrid() throws {
    let fit = HealthRecording.fit(run())
    #expect(fit.records.count == 241)
    #expect(fit.records.first?.distance == 0)
    let last = try #require(fit.records.last)
    #expect(abs((last.distance ?? 0) - 3_600) < 1)
    #expect(fit.records[10].heartRate == 140)
    #expect(fit.records[200].heartRate == 150)
    #expect(fit.records.dropFirst().allSatisfy { abs(($0.speed ?? 0) - 3) < 0.01 })
  }

  @Test func reportWorksLikeForAGarminFile() {
    var activity = GarminActivity(id: -7)
    activity.typeKey = "running"
    activity.name = "Laufen"
    activity.startLocal = "2026-11-09 07:00:00"
    activity.durationSeconds = 1_200
    let report = ActivityReportBuilder.build(activity, fit: HealthRecording.fit(run()))
    #expect(report.splits.count == 4)
    #expect(report.splits.prefix(3).allSatisfy { abs($0.seconds - 333) <= 6 })
    #expect(report.halves.speedChangePercent == 0)
    #expect((report.halves.heartRateChangePercent ?? 0) > 5)
    #expect(report.byDistance)
    #expect(ActivityFindings.findings(report).contains { $0.id == "drift" && $0.tone == .attention })
  }

  @Test func pausesLeaveAGapAndCountAsStandingTime() {
    let pause = HealthRecording.Interval(start: 1_300, end: 1_600)
    let fit = HealthRecording.fit(run(pause: pause))
    #expect(!fit.records.contains { $0.timestamp >= 1_300 && $0.timestamp < 1_600 })
    var activity = GarminActivity(id: -8)
    activity.typeKey = "running"
    activity.durationSeconds = 1_200
    let report = ActivityReportBuilder.build(activity, fit: fit)
    #expect(abs(report.pausedSeconds - 300) <= 10)
    #expect(abs(report.movingSeconds - 900) <= 10)
  }

  @Test func lapsGetTimeDistanceAndPulse() throws {
    var input = run()
    input.laps = [
      HealthRecording.Interval(start: 1_000, end: 1_600), HealthRecording.Interval(start: 1_600, end: 2_200),
    ]
    let laps = HealthRecording.fit(input).laps
    #expect(laps.count == 2)
    #expect(laps[0].timerSeconds == 600)
    #expect(abs((laps[0].distanceMeters ?? 0) - 1_800) < 1)
    #expect(abs((laps[0].averageSpeed ?? 0) - 3) < 0.01)
    #expect((laps[0].averageHeartRate ?? 0) < 141)
    #expect(laps[1].maxHeartRate == 150)
  }

  @Test func locationsAndStaleValues() {
    var input = HealthRecording.Input(start: 0, end: 120)
    input.heartRate = [HealthRecording.Sample(time: 0, value: 120)]
    input.locations = [
      HealthRecording.Location(time: 0, latitude: 52.37, longitude: 5.22, altitude: 3),
      HealthRecording.Location(time: 100, latitude: 52.38, longitude: 5.23, altitude: 4),
    ]
    let fit = HealthRecording.fit(input)
    #expect(fit.records.count == 25)
    #expect(fit.records[2].heartRate == 120)
    // Nach 30 s ohne neuen Wert bleibt die Stelle leer statt einen alten Puls fortzuschreiben.
    #expect(fit.records[10].heartRate == nil)
    #expect(fit.records[0].latitude == 52.37)
    #expect(fit.records[10].latitude == nil)
    #expect(fit.records[20].altitude == 4)
    #expect(fit.records[0].distance == nil)
    #expect(HealthRecording.fit(HealthRecording.Input(start: 5, end: 5)).records.isEmpty)
  }
}
