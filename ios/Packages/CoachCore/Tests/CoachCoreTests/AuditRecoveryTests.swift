import Foundation
import Testing

@testable import CoachCore

/// Audit CORE2-05: Die Schlafregel der Tagesampel („unter 5 h rot, unter 6 h gelb“) prüft gegen
/// `DailyMetrics.sleepHours`, das bereits auf 0,1 h gerundet ist. 4:57 h werden so zu „5 h“ (nur „locker“ statt
/// „Pause“), 5:57 h zu „6 h“ („normal“ statt „locker“). Die Schwelle muss gegen die ungerundeten Sekunden laufen.
struct AuditRecoveryTests {
  private let day = CalendarDay(year: 2026, month: 11, day: 3)

  private func metrics(sleepMinutes: Double) -> DailyMetrics {
    var metrics = DailyMetrics(day: day)
    metrics.sleepSeconds = sleepMinutes * 60
    return metrics
  }

  @Test func sleepJustUnderFiveHoursIsPause() {
    let result = RecoveryEvaluator.evaluate(metrics(sleepMinutes: 4 * 60 + 57), restingHeartRate7DayAverage: nil)
    #expect(result.level == .pause)
  }

  @Test func sleepJustUnderSixHoursIsEasy() {
    let result = RecoveryEvaluator.evaluate(metrics(sleepMinutes: 5 * 60 + 57), restingHeartRate7DayAverage: nil)
    #expect(result.level == .locker)
  }

  @Test func exactlyFiveHoursStaysEasy() {
    // Gegenprobe: genau 5:00 h ist nicht „unter 5 h“.
    let result = RecoveryEvaluator.evaluate(metrics(sleepMinutes: 5 * 60), restingHeartRate7DayAverage: nil)
    #expect(result.level == .locker)
  }
}
