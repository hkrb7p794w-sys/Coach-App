import Foundation
import Testing

@testable import CoachCore

struct ActivityReportTests {
  let today = CalendarDay(year: 2026, month: 11, day: 10)

  private func run(id: Int64 = 1, seconds: Double = 3_000) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.name = "Morgenlauf"
    activity.startLocal = "2026-11-09 07:00:00"
    activity.durationSeconds = seconds
    activity.secondsInZones = [300, 1_500, 900, 300, 0]
    return activity
  }

  /// Ein Messpunkt pro Sekunde; `speed` und `heartRate` je Sekunde.
  private func fit(
    seconds: Int, speed: (Int) -> Double, heartRate: (Int) -> Double, laps: [FitLap] = []
  ) -> FitActivity {
    var activity = FitActivity()
    var distance = 0.0
    for second in 0...seconds {
      let current = speed(second)
      if second > 0 { distance += current }
      var record = FitRecord(
        timestamp: Double(second), heartRate: heartRate(second), speed: current, distance: distance)
      record.altitude = 100
      record.cadence = 86
      activity.records.append(record)
    }
    activity.laps = laps
    return activity
  }

  @Test func steadyRunHasEvenSplitsAndStablePulse() {
    let file = fit(seconds: 3_000, speed: { _ in 10.0 / 3 }, heartRate: { _ in 145 })
    let report = ActivityReportBuilder.build(run(), fit: file)
    #expect(report.splits.count == 10)
    #expect(report.splits.allSatisfy { abs($0.seconds - 300) <= 1 })
    #expect(report.splits[0].averageHeartRate == 145)
    #expect(report.halves.speedChangePercent == 0)
    #expect(report.pausedSeconds < 5)
    #expect(report.averageCadence == 172)
    #expect(report.highZonePercent == 10)
    #expect(report.samples.count <= 151)
    let texts = ActivityFindings.findings(report).map(\.text)
    #expect(texts.contains("Tempo über die ganze Einheit gleichmäßig."))
    #expect(texts.contains("Puls blieb bei gleichem Tempo stabil."))
    #expect(texts.contains("10 % der Zeit in Zone 4–5."))
  }

  @Test func fadingAndNegativeSplit() {
    let fading = ActivityReportBuilder.build(
      run(), fit: fit(seconds: 3_000, speed: { $0 < 1_500 ? 3.6 : 3.2 }, heartRate: { _ in 150 }))
    #expect((fading.halves.speedChangePercent ?? 0) < -10)
    #expect(ActivityFindings.findings(fading).first?.tone == .attention)
    #expect(ActivityFindings.findings(fading).first?.text.contains("zu schnell begonnen") == true)

    let negative = ActivityReportBuilder.build(
      run(), fit: fit(seconds: 3_000, speed: { $0 < 1_500 ? 3.2 : 3.4 }, heartRate: { _ in 150 }))
    #expect(ActivityFindings.findings(negative).first?.text.contains("gut eingeteilt") == true)
    let splits = ActivityFindings.findings(negative).first { $0.id == "splits" }
    #expect(splits?.text.contains("Schnellster Kilometer") == true)
  }

  @Test func heartRateDriftAtSteadyPace() {
    let report = ActivityReportBuilder.build(
      run(), fit: fit(seconds: 3_600, speed: { _ in 3.0 }, heartRate: { $0 < 1_800 ? 140 : 152 }))
    #expect(report.halves.heartRateChangePercent == 8.6)
    let drift = ActivityFindings.findings(report).first { $0.id == "drift" }
    #expect(drift?.tone == .attention)
    #expect(drift?.text.contains("8,6 %") == true)
  }

  @Test func pausesCountAsStandingTime() {
    // 10 Minuten laufen, 5 Minuten stehen, 10 Minuten laufen.
    let file = fit(seconds: 1_500, speed: { (600..<900).contains($0) ? 0 : 3 }, heartRate: { _ in 140 })
    let report = ActivityReportBuilder.build(run(seconds: 1_500), fit: file)
    #expect(abs(report.pausedSeconds - 300) <= 2)
    #expect(abs(report.movingSeconds - 1_200) <= 2)
    #expect(ActivityFindings.findings(report).contains { $0.id == "pause" && $0.text.hasPrefix("5 min Standzeit") })
  }

  @Test func intervalsCompareFirstAndLast() {
    func lap(_ speed: Double, _ intensity: FitLap.Intensity, heartRate: Double) -> FitLap {
      var lap = FitLap(
        timerSeconds: 240, distanceMeters: speed * 240, averageHeartRate: heartRate, intensity: intensity)
      lap.averageSpeed = speed
      return lap
    }
    let laps = [
      lap(2.8, .warmup, heartRate: 130), lap(4.2, .interval, heartRate: 168), lap(2.5, .recovery, heartRate: 140),
      lap(4.1, .interval, heartRate: 172), lap(2.5, .recovery, heartRate: 142), lap(3.9, .interval, heartRate: 175),
    ]
    let report = ActivityReportBuilder.build(
      run(), fit: fit(seconds: 1_440, speed: { _ in 3.3 }, heartRate: { _ in 150 }, laps: laps))
    let findings = ActivityFindings.findings(report)
    #expect(findings.first?.text.hasPrefix("3 Intervalle") == true)
    #expect(findings.contains { $0.id == "fade" && $0.tone == .attention })
    // Im Modus „reduziert“ gehen keine Pulswerte in Schlägen an die KI.
    let reduced = ActivityFindings.contextLine(report, full: false)
    #expect(reduced?.contains("Schläge") == false)
    #expect(ActivityFindings.contextLine(report, full: true)?.contains("175 Schläge") == true)
    #expect(reduced?.hasPrefix("Morgenlauf (09.11.2026): ") == true)
  }

  @Test func reportSurvivesStorage() throws {
    let report = ActivityReportBuilder.build(
      run(), fit: fit(seconds: 1_200, speed: { _ in 3 }, heartRate: { _ in 140 }))
    let decoded = try JSONDecoder().decode(ActivityReport.self, from: JSONEncoder().encode(report))
    #expect(decoded == report)
  }

  @Test func plannerTakesEveryRecentGarminActivityOnce() {
    var old = run(id: 2)
    old.startLocal = "2026-08-01 07:00:00"
    var short = run(id: 3, seconds: 120)
    short.startLocal = "2026-11-08 07:00:00"
    var health = run(id: -5)
    health.startLocal = "2026-11-08 09:00:00"
    var strength = run(id: 4)
    strength.typeKey = "strength_training"
    strength.startLocal = "2026-11-10 06:00:00"
    let all = [run(), old, short, health, strength]
    #expect(ActivityReportPlanner.pending(all, known: [:], today: today).map(\.id) == [4, 1])
    let known = [Int64(1): ActivityReportBuilder.build(run(), fit: FitActivity())]
    #expect(ActivityReportPlanner.pending(all, known: known, today: today).map(\.id) == [4])
    #expect(ActivityReportPlanner.pending(all, known: known, failed: [4], today: today).isEmpty)
  }
}
