import Foundation
import Testing

@testable import CoachCore

private let today = CalendarDay(year: 2026, month: 11, day: 2)

/// 14 unauffällige Vortage mit leichter Streuung.
private func history() -> [DailyMetrics] {
  (1...14).map { offset in
    var metrics = DailyMetrics(day: today.adding(days: -offset))
    let wobble = Double(offset % 3) - 1
    metrics.sleepSeconds = (7.8 + wobble * 0.2) * 3_600
    metrics.restingHeartRate = 48 + wobble
    metrics.hrvLastNightAverage = 60 + wobble * 3
    metrics.stressAverage = 25 + wobble * 3
    metrics.bodyBatteryAtWake = 80 + wobble * 4
    metrics.deepSleepSeconds = 5_400 + wobble * 300
    return metrics
  }
}

struct MorningReportTests {
  @Test func badNightIsExplainedWithPersonalRanges() {
    var night = DailyMetrics(day: today)
    night.sleepSeconds = 6.2 * 3_600
    night.sleepScore = 55
    night.restingHeartRate = 54
    night.hrvLastNightAverage = 48
    night.bodyBatteryAtWake = 52
    let sessions = [MorningReport.Session(id: "1", title: "Intervalle", target: "Soll 60 min", demanding: true)]
    let report = MorningReport.make(
      days: history() + [night], today: today, sleep: SleepSettings(), sessions: sessions)

    #expect(report.level == .locker)
    #expect(report.headline == "Heute eher locker")
    #expect(report.findings.contains { $0.hasPrefix("Schlaf war") && $0.contains("kürzer als dein Bedarf") })
    #expect(report.findings.contains("HRV liegt unter deinem Normalbereich."))
    #expect(report.findings.contains("Body Battery ist vergleichsweise niedrig."))
    #expect(report.findings.contains { $0.hasPrefix("Ruhepuls") })
    #expect(report.recommendation.contains("lockere Trainingseinheit"))
    #expect(report.recommendation.contains("„Intervalle“"))
    #expect(report.sleepAdvice?.contains("ins Bett") == true)
    #expect(!report.isFromYesterday)
  }

  @Test func goodNightKeepsPlan() {
    var night = DailyMetrics(day: today)
    night.sleepSeconds = 8.1 * 3_600
    night.sleepScore = 86
    night.restingHeartRate = 48
    night.hrvLastNightAverage = 61
    night.hrvStatus = "BALANCED"
    night.bodyBatteryAtWake = 82
    let sessions = [MorningReport.Session(id: "1", title: "Lauf", target: "45 min", demanding: false)]
    let report = MorningReport.make(days: history() + [night], today: today, sleep: SleepSettings(), sessions: sessions)
    #expect(report.level == .normal)
    #expect(report.findings.isEmpty)
    #expect(report.recommendation == "Empfehlung: Training wie geplant.")
    #expect(report.items.first { $0.metric == .sleepDuration }?.status == .good)
    #expect(report.items.first { $0.metric == .hrv }?.status == .good)
  }

  @Test func singleDeviationDoesNotDowngrade() {
    var night = DailyMetrics(day: today)
    night.sleepSeconds = 8 * 3_600
    night.restingHeartRate = 48
    night.bodyBatteryAtWake = 60
    let report = MorningReport.make(days: history() + [night], today: today, sleep: SleepSettings())
    #expect(report.findings == ["Body Battery ist vergleichsweise niedrig."])
    #expect(report.level == .normal)
  }

  @Test func withoutDataTheReportSaysSo() {
    let report = MorningReport.make(days: [], today: today, sleep: SleepSettings())
    #expect(report.level == nil)
    #expect(report.headline == "Zu wenig Daten für eine Einschätzung")
    #expect(report.recommendation.contains("Gefühl"))
    #expect(report.missing.contains("Schlafdauer"))
    #expect(report.missing.contains("Body Battery"))
    #expect(report.items.allSatisfy { $0.status == .missing })
    #expect(report.sleepAdvice == nil)
  }

  @Test func partialDataWorksWithoutPersonalRanges() {
    var night = DailyMetrics(day: today)
    night.sleepSeconds = 7.5 * 3_600
    night.restingHeartRate = 52
    let report = MorningReport.make(days: [night], today: today, sleep: SleepSettings())
    #expect(report.level == .normal)
    #expect(report.items.first { $0.metric == .restingHeartRate }?.note.contains("ab 7 Tagen") == true)
    #expect(report.missing.contains("HRV"))
    #expect(!report.missing.contains("Ruhepuls"))
  }

  @Test func fallsBackToYesterdayBeforeSync() {
    var yesterday = DailyMetrics(day: today.adding(days: -1))
    yesterday.sleepSeconds = 7 * 3_600
    yesterday.restingHeartRate = 50
    let report = MorningReport.make(days: [yesterday], today: today, sleep: SleepSettings())
    #expect(report.isFromYesterday)
    #expect(report.dataDay == today.adding(days: -1))
  }

  @Test func loadUsesWatchRatio() {
    var metrics = DailyMetrics(day: today)
    metrics.acuteLoad = 900
    metrics.chronicLoad = 500
    #expect(MorningReport.load(metrics, form: nil).status == .attention)
    metrics.acuteLoad = 520
    #expect(MorningReport.load(metrics, form: nil).status == .normal)
    #expect(MorningReport.load(nil, form: nil).status == .missing)
  }

  @Test func hrvStatusOverridesNightValue() {
    var metrics = DailyMetrics(day: today)
    metrics.hrvStatus = "LOW"
    metrics.hrvLastNightAverage = 70
    #expect(MorningReport.hrv(metrics, norm: nil).status == .attention)
    metrics.hrvStatus = nil
    #expect(MorningReport.hrv(metrics, norm: PersonalNorm(mean: 60, low: 55, high: 65, count: 10)).status == .good)
  }
}
