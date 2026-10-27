import Foundation
import Testing

@testable import CoachCore

struct ReminderExtrasTests {
  /// Montag, 26.10.2026: In dieser Woche braucht die Schwimmeinheit einen Pull-Buoy.
  let monday = CalendarDay(year: 2026, month: 10, day: 26)

  @Test func swimEquipmentComesTheEveningBefore() throws {
    let schedule = try #require(SeasonSchedule.load())
    let notes = ReminderPlanner.swimEquipment(
      schedule: schedule, config: .standard, decisions: [:], today: monday, minutesNow: 600, days: 7)
    #expect(notes.map(\.day) == [monday, monday.adding(days: 2)])
    #expect(notes.allSatisfy { $0.hour == 18 && $0.minute == 0 && $0.kind == .equipment })
    #expect(notes.first?.title == "Morgen Schwimmen: Pull-Buoy einpacken")
    #expect(notes.first?.id == "coach.reminder.equipment.2026-10-26")

    // Nach 18 Uhr kommt die Erinnerung für heute Abend nicht mehr.
    let late = ReminderPlanner.swimEquipment(
      schedule: schedule, config: .standard, decisions: [:], today: monday, minutesNow: 19 * 60, days: 7)
    #expect(late.map(\.day) == [monday.adding(days: 2)])
  }

  @Test func weekPlanningOnSundays() {
    let notes = ReminderPlanner.weekPlanning(
      mode: .personal, today: monday, minutesNow: 600, hour: 18, minute: 0, days: 14)
    #expect(notes.map(\.day) == [monday.adding(days: 6), monday.adding(days: 13)])
    #expect(notes.first?.title == "Nächste Woche planen")
    let sunday = monday.adding(days: 6)
    let lateSunday = ReminderPlanner.weekPlanning(
      mode: .season, today: sunday, minutesNow: 19 * 60, hour: 18, minute: 0, days: 7)
    #expect(lateSunday.isEmpty)
  }

  @Test func weekPlanReplacesScheduleForThatWeekOnly() throws {
    var base = WeekSchedule()
    base.set([SessionSlot(.run)], on: .tuesday)
    var next = base
    next.set([], on: .tuesday)
    next.set([SessionSlot(.swim)], on: .wednesday)
    var adjustments = PlanAdjustments()
    adjustments.skip(.tuesday, inWeekOf: monday.adding(days: 7))
    adjustments.setWeekPlan(next, base: base, inWeekOf: monday.adding(days: 7))
    #expect(adjustments.changes.isEmpty)
    #expect(adjustments.schedule(base, inWeekOf: monday.adding(days: 9)) == next)
    #expect(adjustments.schedule(base, inWeekOf: monday) == base)

    // Gleich dem Wochenplan: nichts gespeichert.
    adjustments.setWeekPlan(base, base: base, inWeekOf: monday.adding(days: 7))
    #expect(adjustments.weekPlans.isEmpty)

    // Ältere gespeicherte Ausnahmen ohne Wochenpläne bleiben lesbar.
    let old = #"{"changes":[{"week":{"year":2026,"month":10,"day":26},"from":1}]}"#
    let decoded = try JSONDecoder().decode(PlanAdjustments.self, from: Data(old.utf8))
    #expect(decoded.changes.count == 1)
    #expect(decoded.weekPlans.isEmpty)
  }

  @Test func germanList() {
    #expect(ListFormat.german(["Pull-Buoy"]) == "Pull-Buoy")
    #expect(ListFormat.german(["Pull-Buoy", "Paddles", "Flossen"]) == "Pull-Buoy, Paddles und Flossen")
  }
}
