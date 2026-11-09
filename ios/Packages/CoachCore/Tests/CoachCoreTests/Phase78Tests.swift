import Foundation
import Testing

@testable import CoachCore

/// Phase 78 (Audit): Soll/Ist und Trainingstage.
struct Phase78Tests {
  private let monday = CalendarDay(year: 2026, month: 11, day: 9)

  private func run(_ id: Int64, day: CalendarDay, kilometers: Double, minutes: Double) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.distanceMeters = kilometers * 1_000
    activity.durationSeconds = minutes * 60
    return activity
  }

  private func settings() -> NutritionSettings {
    var settings = NutritionSettings()
    settings.weightKilograms = 80
    settings.heightCentimeters = 180
    settings.age = 35
    settings.isFemale = false
    return settings
  }

  private func targets(_ slot: SessionSlot, recovery: RecoveryLevel?) -> NutritionTargets {
    var schedule = WeekSchedule()
    schedule.set([slot], on: Weekday(day: monday))
    return NutritionPlanner.compute(
      activities: [], planItems: schedule.templateItems(on: Weekday(day: monday)), settings: settings(),
      garminProfile: nil, day: monday, hasGarminData: true, recovery: recovery)
  }

  // MARK: - Geplanter Tag (R2D-01, R2D-10)

  @Test func onlyLongSessionsAreHardDays() {
    #expect(targets(SessionSlot(.run, .long), recovery: nil).dayType == .hard)
    #expect(targets(SessionSlot(.run, .hard), recovery: nil).dayType == .moderate)
    #expect(targets(SessionSlot(.run, .easy), recovery: nil).dayType == .light)
  }

  @Test func plannedEnergyUsesTheSessionMinutes() {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .easy)], on: Weekday(day: monday))
    let weekday = Weekday(day: monday)
    func energy(_ minutes: [Int]) -> Double {
      NutritionPlanner.compute(
        activities: [], planItems: schedule.templateItems(on: weekday, runMinutes: minutes), settings: settings(),
        garminProfile: nil, day: monday, hasGarminData: true
      ).exerciseKilocalories
    }
    #expect(energy([30]) < energy([60]))
    #expect(energy([30]) == 240)
  }

  @Test func pauseIgnoresThePlannedSession() {
    let result = targets(SessionSlot(.run, .long), recovery: .pause)
    #expect(result.dayType == .restDay)
    #expect(result.source != .planned)
  }

  @Test func easyDayCapsThePlannedSession() {
    #expect(targets(SessionSlot(.run, .long), recovery: .locker).dayType == .light)
  }

  // MARK: - Rangliste (R4B-06)

  @Test func walksAreNoTrainingUnlessPlanned() {
    var walk = GarminActivity(id: 1)
    walk.typeKey = "walking"
    walk.durationSeconds = 1_500
    #expect(!ScoreRules.countsAsTraining(walk, otherIsPlanned: false))
    #expect(ScoreRules.countsAsTraining(walk, otherIsPlanned: true))
    #expect(ScoreRules.countsAsTraining(run(2, day: monday, kilometers: 5, minutes: 30), otherIsPlanned: false))
    #expect(!ScoreRules.countsAsTraining(run(3, day: monday, kilometers: 1, minutes: 10), otherIsPlanned: false))
  }

  // MARK: - Laufbelastung (SCI-04)

  @Test func warnsAfterARunFarBeyondTheLongest() {
    let runs = [
      run(1, day: monday.adding(days: -12), kilometers: 10, minutes: 60),
      run(2, day: monday.adding(days: -1), kilometers: 12, minutes: 72),
    ]
    #expect(LoadCheck.running(activities: runs, today: monday).warning?.contains("längster") == true)
  }

  @Test func noWarningWithinTenPercent() {
    let runs = [
      run(1, day: monday.adding(days: -12), kilometers: 10, minutes: 60),
      run(2, day: monday.adding(days: -1), kilometers: 11, minutes: 66),
    ]
    #expect(LoadCheck.singleRunWarning(activities: runs, today: monday) == nil)
  }

  @Test func oldRunsDoNotTriggerTheWarning() {
    let runs = [
      run(1, day: monday.adding(days: -12), kilometers: 10, minutes: 60),
      run(2, day: monday.adding(days: -6), kilometers: 14, minutes: 84),
    ]
    #expect(LoadCheck.singleRunWarning(activities: runs, today: monday) == nil)
  }

  @Test func plannedRunStaysNearTheLongestRecentRun() throws {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .easy)], on: .saturday)
    var profile = UserProfile(sports: [.run], goal: .improveFitness, schedule: schedule)
    profile.setLevel(.advanced, for: .run)
    let runs = (0..<8).map { run(Int64($0), day: monday.adding(days: -2 - $0 * 3), kilometers: 10, minutes: 60) }
    let week = try #require(RunPlanner.week(profile: profile, schedule: schedule, monday: monday, activities: runs))
    #expect((week.sessions.first?.minutes ?? 0) <= 66)
  }
}
