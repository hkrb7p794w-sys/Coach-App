import Foundation
import Testing

@testable import CoachCore

struct SessionMatchTests {
  /// Mittwoch, 28.10.2026.
  let today = CalendarDay(year: 2026, month: 10, day: 28)
  var monday: CalendarDay { CalendarDay(year: 2026, month: 10, day: 26) }

  func activity(_ id: Int64, _ typeKey: String, day: CalendarDay, minutes: Double, name: String? = nil)
    -> GarminActivity
  {
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.durationSeconds = minutes * 60
    activity.name = name
    return activity
  }

  var schedule: WeekSchedule {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .hard)], on: .monday)
    schedule.set([SessionSlot(.strength, .hard)], on: .tuesday)
    schedule.set([SessionSlot(.run, .easy)], on: .wednesday)
    schedule.set([SessionSlot(.run, .long)], on: .saturday)
    return schedule
  }

  @Test func walkDoesNotTickOffIntervals() {
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    let walk = activity(1, "walking", day: monday, minutes: 40)
    let week = SessionMatcher.match(planned: planned, activities: [walk], today: today)
    #expect(week.results(on: monday).first?.status == .missed)
    #expect(week.extraIDs == [1])
  }

  @Test func statusesForTheWeek() {
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday, runMinutes: [.saturday: [100]])
    #expect(planned.last?.targetMinutes == 100)
    let activities = [
      activity(1, "cycling", day: monday, minutes: 60),
      activity(2, "running", day: today, minutes: 20),
    ]
    let week = SessionMatcher.match(
      planned: planned, activities: activities, gymDays: [monday.adding(days: 1)], today: today)
    let statuses = week.results.map(\.status)
    #expect(statuses == [.substituted, .done, .partial, .planned])
    #expect(week.results[2].compareText == "Soll 45 min · Ist 20 min")
    #expect(week.results[0].intensityNote == "locker statt intensiv")
    #expect(week.allCounted(on: today))
    #expect(!week.allCounted(on: monday.adding(days: 5)))

    let totals = SessionMatcher.totals(planned: planned, activities: activities, monday: monday)
    let run = totals.first { $0.sport == .run }
    #expect(run?.planned == 50 + 45 + 100)
    #expect(run?.actual == 20)
  }

  @Test func missedAndMakeUp() throws {
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    let week = SessionMatcher.match(planned: planned, activities: [], today: today)
    let missed = MissedSessions.open(week, handled: [])
    #expect(missed.map(\.planned.day) == [monday.adding(days: 1), monday])
    #expect(MissedSessions.open(week, handled: [missed[0].id]).count == 1)

    // Intervalllauf vom Montag nachholen: nicht Fr (vor dem langen Lauf am Sa), sondern Do.
    let session = try #require(week.results.first?.planned)
    let profile = UserProfile.personalDraft(from: SeasonConfig())
    let day = MissedSessions.makeUpDay(
      for: session, schedule: schedule, profile: profile, today: today, makeUpsThisWeek: 0)
    #expect(day == .thursday)
    #expect(
      MissedSessions.makeUpDay(for: session, schedule: schedule, profile: profile, today: today, makeUpsThisWeek: 1)
        == nil)
  }

  @Test func illnessCapsRecovery() {
    let sick = today.adding(days: -1)
    #expect(MissedSessions.cappedRecovery(.normal, sickDay: sick, today: today) == .locker)
    #expect(MissedSessions.cappedRecovery(.pause, sickDay: sick, today: today) == .pause)
    #expect(MissedSessions.cappedRecovery(.normal, sickDay: today.adding(days: -3), today: today) == .normal)
    #expect(MissedSessions.cappedRecovery(nil, sickDay: sick, today: today) == .locker)
  }

  @Test func manualEntry() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let swim = ManualActivity.make(sport: .swim, start: start, minutes: 40, effort: 6, timeZone: .gmt)
    #expect(ManualActivity.isManual(swim.id))
    #expect(!ManualActivity.isManual(HealthImport.activityID(UUID())))
    #expect(swim.sport == .swim)
    #expect(swim.durationSeconds == 2_400)
    #expect(swim.trainingLoad == 60)
    #expect(swim.name == "Schwimmen (nachgetragen)")
    #expect(swim.day == CalendarDay(date: start, timeZone: .gmt))
  }
}
