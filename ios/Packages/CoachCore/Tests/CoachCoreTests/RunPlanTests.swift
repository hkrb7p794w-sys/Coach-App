import Foundation
import Testing

@testable import CoachCore

struct RunPlanTests {
  /// Montag, 9.11.2026: Aufbauwoche; 2.11. ist eine Entlastungswoche (jede vierte ab 5.1.2026).
  private let buildMonday = CalendarDay(year: 2026, month: 11, day: 9)
  private let deloadMonday = CalendarDay(year: 2026, month: 11, day: 2)

  private var profile: UserProfile {
    var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .improveFitness)
    profile.setLevel(.intermediate, for: .run)
    return profile
  }

  private var schedule: WeekSchedule {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run)], on: .tuesday)
    schedule.set([SessionSlot(.run, .hard)], on: .thursday)
    schedule.set([SessionSlot(.run, .long)], on: .sunday)
    return schedule
  }

  /// Vier Wochen mit je 150 Minuten Laufen vor `monday`.
  private func history(before monday: CalendarDay, minutesPerWeek: Double = 150) -> [GarminActivity] {
    (1...28).compactMap { back -> GarminActivity? in
      guard back % 7 == 1 || back % 7 == 4 || back % 7 == 6 else { return nil }
      var activity = GarminActivity(id: Int64(back))
      activity.typeKey = "running"
      activity.startLocal = "\(monday.adding(days: -back).iso) 07:00:00"
      activity.durationSeconds = minutesPerWeek / 3 * 60
      return activity
    }
  }

  @Test func buildWeekGrowsAtMostTenPercent() throws {
    let week = try #require(
      RunPlanner.week(
        profile: profile, schedule: schedule, monday: buildMonday, activities: history(before: buildMonday)))
    #expect(week.phase == .build)
    #expect(week.baselineMinutes == 150)
    // Rundung auf 5 Minuten je Einheit: kleine Abweichung erlaubt.
    #expect(Double(week.totalMinutes) <= 150 * 1.10 + 10)
    #expect(week.totalMinutes > 150)
    let long = try #require(week.sessions.first { $0.slot.intensity == .long })
    let easy = try #require(week.sessions.first { $0.slot.intensity == .easy })
    #expect(long.minutes > easy.minutes)
    let hard = try #require(week.sessions.first { $0.slot.intensity == .hard })
    #expect(hard.detail.contains("Minuten"))
  }

  @Test func adaptsToWhatWasActuallyRun() throws {
    // Nur 60 Minuten pro Woche geschafft: Der Plan startet von dort, nicht vom Wunsch.
    let week = try #require(
      RunPlanner.week(
        profile: profile, schedule: schedule, monday: buildMonday,
        activities: history(before: buildMonday, minutesPerWeek: 60)))
    #expect(week.baselineMinutes == 60)
    #expect(week.totalMinutes <= 80)
  }

  @Test func deloadAndTaper() throws {
    let deload = try #require(
      RunPlanner.week(
        profile: profile, schedule: schedule, monday: deloadMonday, activities: history(before: deloadMonday)))
    #expect(deload.phase == .deload)
    #expect(Double(deload.totalMinutes) <= 150 * 0.7 + 10)

    var racer = profile
    racer.event = EventGoal(name: "10 km", date: buildMonday.adding(days: 6), kind: .run10k)
    let race = try #require(
      RunPlanner.week(
        profile: racer, schedule: schedule, monday: buildMonday, activities: history(before: buildMonday)))
    #expect(race.phase == .race)
    #expect(race.sessions.contains { $0.detail.contains("Wettkampf") })
    #expect(RunPlanner.phase(monday: buildMonday.adding(days: -7), event: racer.event) == .taper)
  }

  @Test func withoutHistoryUsesLevelStartAndNoRunsMeansNoPlan() throws {
    var beginner = profile
    beginner.setLevel(.beginner, for: .run)
    let week = try #require(
      RunPlanner.week(profile: beginner, schedule: schedule, monday: buildMonday, activities: []))
    #expect(week.baselineMinutes == 60)
    #expect(week.sessions.allSatisfy { $0.minutes >= RunPlanner.minimumSessionMinutes })
    var noRuns = WeekSchedule()
    noRuns.set([SessionSlot(.strength, .hard)], on: .monday)
    #expect(RunPlanner.week(profile: profile, schedule: noRuns, monday: buildMonday, activities: []) == nil)
  }
}
