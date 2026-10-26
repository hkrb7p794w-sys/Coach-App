import Foundation
import Testing

@testable import CoachCore

/// Montag, 26.10.2026.
private let monday = CalendarDay(year: 2026, month: 10, day: 26)

/// Di Lauf intensiv, Do Lauf locker, Fr Kraft, So langer Lauf.
private func runnerProfile() -> UserProfile {
  var profile = UserProfile(sports: [.run, .strength], goal: .improveFitness)
  profile.setLevel(.intermediate, for: .run)
  profile.setLevel(.intermediate, for: .strength)
  var schedule = WeekSchedule()
  schedule.set([SessionSlot(.run, .hard)], on: .tuesday)
  schedule.set([SessionSlot(.run)], on: .thursday)
  schedule.set([SessionSlot(.strength, .hard)], on: .friday)
  schedule.set([SessionSlot(.run, .long)], on: .sunday)
  profile.schedule = schedule
  return profile
}

struct PlanAdjustmentsTests {
  @Test func skipRemovesOnlyThisWeek() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.skip(.tuesday, inWeekOf: monday.adding(days: 1))
    let thisWeek = adjustments.schedule(profile.schedule, inWeekOf: monday.adding(days: 3))
    #expect(thisWeek.slots(on: .tuesday).isEmpty)
    #expect(thisWeek.slots(on: .thursday) == [SessionSlot(.run)])
    let nextWeek = adjustments.schedule(profile.schedule, inWeekOf: monday.adding(days: 8))
    #expect(nextWeek == profile.schedule)
    #expect(adjustments.note(for: .tuesday, inWeekOf: monday) == "diese Woche ausgelassen")
  }

  @Test func moveAddsToTargetDay() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.move(.tuesday, to: .wednesday, inWeekOf: monday)
    let week = adjustments.schedule(profile.schedule, inWeekOf: monday)
    #expect(week.slots(on: .tuesday).isEmpty)
    #expect(week.slots(on: .wednesday) == [SessionSlot(.run, .hard)])
    #expect(adjustments.note(for: .tuesday, inWeekOf: monday) == "verschoben auf Mittwoch")
    #expect(adjustments.note(for: .wednesday, inWeekOf: monday) == "von Dienstag verschoben")
    #expect(adjustments.note(for: .monday, inWeekOf: monday) == nil)
  }

  @Test func movesChainInOrder() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.move(.tuesday, to: .wednesday, inWeekOf: monday)
    adjustments.move(.wednesday, to: .saturday, inWeekOf: monday)
    adjustments.move(.monday, to: .friday, inWeekOf: monday)  // Montag ist frei: nichts passiert
    adjustments.move(.thursday, to: .thursday, inWeekOf: monday)  // gleicher Tag wird ignoriert
    let week = adjustments.schedule(profile.schedule, inWeekOf: monday)
    #expect(week.slots(on: .saturday) == [SessionSlot(.run, .hard)])
    #expect(week.slots(on: .friday) == [SessionSlot(.strength, .hard)])
    #expect(week.sessionCount == profile.schedule.sessionCount)
    #expect(adjustments.changes.count == 3)
  }

  @Test func undoRestoresDay() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.move(.tuesday, to: .wednesday, inWeekOf: monday)
    adjustments.skip(.friday, inWeekOf: monday)
    adjustments.undo(.wednesday, inWeekOf: monday)
    let week = adjustments.schedule(profile.schedule, inWeekOf: monday)
    #expect(week.slots(on: .tuesday) == [SessionSlot(.run, .hard)])
    #expect(week.slots(on: .friday).isEmpty)
    #expect(adjustments.changes.count == 1)
  }

  @Test func resetAndPrune() throws {
    var adjustments = PlanAdjustments()
    adjustments.skip(.tuesday, inWeekOf: monday)
    adjustments.skip(.friday, inWeekOf: monday.adding(days: 7))
    adjustments.reset(weekOf: monday.adding(days: 9))
    #expect(adjustments.changes.count == 1)
    adjustments.prune(before: monday.adding(days: 7))
    #expect(adjustments.changes.isEmpty)

    adjustments.skip(.sunday, inWeekOf: monday)
    let data = try JSONEncoder().encode(adjustments)
    #expect(try JSONDecoder().decode(PlanAdjustments.self, from: data) == adjustments)
  }

  @Test func moveOptionsAvoidBackToBackHardDays() {
    let profile = runnerProfile()
    // Dienstag (intensiv) verschieben, heute ist Dienstag.
    let options = PlanMoveAdvisor.options(
      for: .tuesday, schedule: profile.schedule, profile: profile, today: monday.adding(days: 1))
    #expect(!options.isEmpty)
    #expect(options.allSatisfy { $0.rawValue > Weekday.tuesday.rawValue })
    // Samstag liegt direkt vor dem langen Lauf am Sonntag und kommt nicht zuerst.
    #expect(options.first != .saturday)
    #expect(options.first == .wednesday)
  }

  @Test func moveOptionsEmptyOnSundayOrRestDay() {
    let profile = runnerProfile()
    #expect(
      PlanMoveAdvisor.options(for: .sunday, schedule: profile.schedule, profile: profile, today: monday.adding(days: 6))
        .isEmpty)
    #expect(PlanMoveAdvisor.options(for: .monday, schedule: profile.schedule, profile: profile, today: monday).isEmpty)
  }

  @Test func adviceUsesAdjustedSchedule() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.skip(.tuesday, inWeekOf: monday)
    let tuesday = monday.adding(days: 1)
    let advice = ScheduleAdvisor.advice(
      profile: profile, schedule: adjustments.schedule(profile.schedule, inWeekOf: tuesday), day: tuesday,
      recovery: .normal, trainedToday: false)
    #expect(advice.mode == .restDay)
    let unchanged = ScheduleAdvisor.advice(profile: profile, day: tuesday, recovery: .normal, trainedToday: false)
    #expect(unchanged.mode == .asPlanned)
  }
}

struct ReminderPlannerTests {
  @Test func remindersFollowAdjustments() {
    let profile = runnerProfile()
    var adjustments = PlanAdjustments()
    adjustments.skip(.thursday, inWeekOf: monday)
    adjustments.move(.friday, to: .saturday, inWeekOf: monday)
    let reminders = ReminderPlanner.personal(
      profile: profile, adjustments: adjustments, today: monday, includeToday: true)
    let days = reminders.map(\.day)
    // Woche 1: Di, Sa (verschoben), So; Woche 2: Di, Do, Fr, So.
    #expect(
      days == [1, 5, 6, 8, 10, 11, 13].map { monday.adding(days: $0) })
    #expect(reminders.first?.title == "Heute: Qualitätslauf (Tempo oder Intervalle)")
    #expect(reminders.allSatisfy { $0.canAdjust })
    #expect(reminders.first?.id == "coach.reminder.2026-10-27")
  }

  @Test func todayOnlyWhenRequested() {
    let profile = runnerProfile()
    let tuesday = monday.adding(days: 1)
    let with = ReminderPlanner.personal(
      profile: profile, adjustments: PlanAdjustments(), today: tuesday, includeToday: true, days: 1)
    let without = ReminderPlanner.personal(
      profile: profile, adjustments: PlanAdjustments(), today: tuesday, includeToday: false, days: 1)
    #expect(with.count == 1)
    #expect(without.isEmpty)
  }

  @Test func seasonRemindersUseFixedDays() throws {
    let schedule = try #require(SeasonSchedule.load())
    let reminders = ReminderPlanner.season(
      schedule: schedule, config: .standard, decisions: [:], today: monday, includeToday: true, days: 7)
    #expect(!reminders.isEmpty)
    #expect(reminders.allSatisfy { !$0.canAdjust && !$0.titles.isEmpty })
    #expect(!reminders.contains { $0.titles.contains("Ruhetag") })
  }

  @Test func bodyMentionsCompanion() {
    let reminder = TrainingReminder(day: monday, titles: ["Lockerer Lauf"], canAdjust: true)
    #expect(ReminderPlanner.body(for: reminder).contains("verschieben"))
    #expect(ReminderPlanner.body(for: reminder, companion: "Daisy").hasPrefix("Daisy"))
    let season = TrainingReminder(day: monday, titles: ["Push"], canAdjust: false)
    #expect(!ReminderPlanner.body(for: season).contains("verschieben"))
  }
}
