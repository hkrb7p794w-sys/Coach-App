import Foundation
import Testing

@testable import CoachCore

struct AuditWeightAndRunTests {
  /// CORE1-11: Zu schnelles Abnehmen bei ausgeschöpfter Anpassung (+500): `step` liefert 0, die Meldung sagt
  /// „Iss täglich etwa 0 kcal mehr“ (WeightTrend.swift:103–110).
  @Test func tooFastAdviceNeverSaysZeroKilocalories() {
    let result = WeightTrend.Result(trendKilograms: 80, weeklyPercent: -1.5, entries: 10, spanDays: 20)
    let advice = WeightTrend.advice(result: result, plannedPercent: -0.5, currentAdjustment: 500)
    #expect(advice.kind == .tooFast)
    #expect(!advice.message.contains("etwa 0 kcal"))
  }

  /// CORE1-12: Mindestdauer 20 min je Lauf (RunPlan.swift:147) hebelt die 10-%-Grenze aus. Vier Wochen mit je
  /// 15 min (3 × 5 min) → Basis 15, Ziel 16,5 min; drei Laufeinheiten à 20 min = 60 min (+300 %).
  @Test func minimumSessionLengthRespectsTenPercentRule() throws {
    let monday = CalendarDay(year: 2026, month: 11, day: 9)
    var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .improveFitness)
    profile.setLevel(.beginner, for: .run)
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run)], on: .tuesday)
    schedule.set([SessionSlot(.run, .hard)], on: .thursday)
    schedule.set([SessionSlot(.run, .long)], on: .sunday)
    let history = (1...28).compactMap { back -> GarminActivity? in
      guard back % 7 == 1 || back % 7 == 4 || back % 7 == 6 else { return nil }
      var activity = GarminActivity(id: Int64(back))
      activity.typeKey = "running"
      activity.startLocal = "\(monday.adding(days: -back).iso) 07:00:00"
      activity.durationSeconds = 5 * 60
      return activity
    }
    let week = try #require(
      RunPlanner.week(profile: profile, schedule: schedule, monday: monday, activities: history))
    #expect(week.phase == .build)
    #expect(week.baselineMinutes == 15)
    #expect(Double(week.totalMinutes) <= Double(week.baselineMinutes) * 1.10 + 10)
  }
}
