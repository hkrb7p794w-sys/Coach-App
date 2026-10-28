import Foundation
import Testing

@testable import CoachCore

struct ActivityFeedTests {
  let day = CalendarDay(year: 2026, month: 10, day: 28)

  func activity(_ id: Int64, _ typeKey: String, time: String = "07:00:00", minutes: Double = 45) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey
    activity.startLocal = "\(day.iso) \(time)"
    activity.durationSeconds = minutes * 60
    return activity
  }

  /// 28.10.2026, volle Stunde in UTC.
  func date(_ hour: Int) -> Date {
    Date(timeIntervalSince1970: 1_793_145_600 + Double(hour) * 3_600)
  }

  @Test func mergesGymWithGarminStrength() {
    let garmin = activity(5, "strength_training", time: "18:10:00", minutes: 50)
    let run = activity(6, "running", time: "07:00:00")
    let gym = ActivityFeed.GymItem(id: UUID(), title: "Push", start: date(18), minutes: 55, sets: 18, volumeKg: 4_230)
    let other = ActivityFeed.GymItem(id: UUID(), title: "Pull", start: date(10), minutes: nil, sets: 12, volumeKg: 0)
    let entries = ActivityFeed.entries(activities: [garmin, run], gym: [gym, other], timeZone: .gmt)
    #expect(entries.map(\.title) == ["Push", "Pull", "running"])
    #expect(entries[0].sources == [.app, .garmin])
    #expect(entries[0].values == ["50:00", "18 Sätze", "4230 kg"])
    #expect(entries[1].sources == [.app])
    #expect(entries[1].values == ["12 Sätze"])
    #expect(entries[2].intensity == .easy)
  }

  @Test func sourcesAndPlanLink() {
    #expect(ActivitySource.of(1) == .garmin)
    #expect(ActivitySource.of(HealthImport.activityID(UUID())) == .health)
    let manual = ManualActivity.make(sport: .run, start: date(7), minutes: 30, effort: 5, timeZone: .gmt)
    #expect(ActivitySource.of(manual.id) == .manual)

    let run = activity(6, "running")
    let planned = PlannedSession(day: day, slot: SessionSlot(.run, .easy))
    let result = SessionResult(
      planned: planned, status: .done, activityID: 6, actualMinutes: 45, intensityNote: nil)
    let entries = ActivityFeed.entries(activities: [run], gym: [], results: [result], timeZone: .gmt)
    #expect(entries.first?.planned?.status == .done)
  }

  @Test func paceZonesAndMissing() {
    var run = activity(1, "running", minutes: 50)
    run.distanceMeters = 10_000
    #expect(ActivityFeed.pace(run) == "5:00 /km")
    var swim = activity(2, "lap_swimming", minutes: 30)
    swim.distanceMeters = 1_500
    #expect(ActivityFeed.pace(swim) == "2:00 /100 m")
    var bike = activity(3, "cycling", minutes: 60)
    bike.distanceMeters = 30_000
    #expect(ActivityFeed.pace(bike) == "30 km/h")

    run.secondsInZones = [600, 1_200, 600, 300, 300]
    #expect(ActivityFeed.zoneShares(run) == [0.2, 0.4, 0.2, 0.1, 0.1])

    let bare = activity(4, "running")
    let notes = ActivityFeed.missing(bare)
    #expect(notes.contains { $0.hasPrefix("Keine Herzfrequenz") })
    #expect(notes.contains { $0.hasPrefix("Keine Strecke") })
    #expect(notes.contains { $0.hasPrefix("Keine Trainingsbelastung") })
    let manual = ManualActivity.make(sport: .swim, start: date(7), minutes: 30, effort: 5, timeZone: .gmt)
    #expect(ActivityFeed.missing(manual).count == 1)
  }
}

struct PostWorkoutTests {
  let today = CalendarDay(year: 2026, month: 10, day: 28)

  @Test func hardEasyRunSoftensTomorrow() {
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.startLocal = "\(today.iso) 07:00:00"
    run.durationSeconds = 45 * 60
    let planned = SessionResult(
      planned: PlannedSession(day: today, slot: SessionSlot(.run, .easy)), status: .done, activityID: 1,
      actualMinutes: 45, intensityNote: nil)
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .hard), SessionSlot(.strength, .hard)], on: .thursday)
    let review = PostWorkout.review(
      activity: run, effort: 8, planned: planned, tomorrow: today.adding(days: 1), tomorrowSchedule: schedule)
    #expect(review.headline == "Wie geplant")
    #expect(review.points.contains { $0.hasPrefix("Für eine lockere Einheit war das hart") })
    #expect(review.points.last == "Anstrengung 8/10 × 45 min ≈ Belastung 90 (session RPE).")
    #expect(review.evidenceIDs == ["intensity.distribution", "load.rpe"])
    let tomorrow = review.tomorrow?.schedule.slots(on: .thursday)
    #expect(tomorrow == [SessionSlot(.run, .easy), SessionSlot(.strength, .hard)])

    let easy = PostWorkout.review(
      activity: run, effort: 3, planned: planned, tomorrow: today.adding(days: 1), tomorrowSchedule: schedule)
    #expect(easy.tomorrow == nil)
    #expect(easy.points.count == 2)
  }

  @Test func unplannedAndPartial() {
    var bike = GarminActivity(id: 2)
    bike.typeKey = "cycling"
    bike.durationSeconds = 20 * 60
    let free = PostWorkout.review(
      activity: bike, effort: nil, planned: nil, tomorrow: today.adding(days: 1), tomorrowSchedule: nil)
    #expect(free.headline == "Außerplanmäßig")
    let partial = SessionResult(
      planned: PlannedSession(day: today, slot: SessionSlot(.bike, .easy)), status: .partial, activityID: 2,
      actualMinutes: 20, intensityNote: nil)
    let short = PostWorkout.review(
      activity: bike, effort: nil, planned: partial, tomorrow: today.adding(days: 1), tomorrowSchedule: nil)
    #expect(short.headline == "Kürzer als geplant")
    #expect(short.points.first?.hasPrefix("Soll 45 min · Ist 20 min") == true)
  }
}

struct PersonalNoteTests {
  @Test func inputHasNoSeasonValues() {
    let today = CalendarDay(year: 2026, month: 10, day: 28)
    let profile = UserProfile(sports: [.run, .strength], goal: .improveFitness)
    let advice = ScheduleAdvice(
      mode: .asPlanned, headline: "Lockerer Lauf", detail: "Wie geplant.", move: nil, plannedTitles: [],
      evidenceIDs: [])
    let planned = [PlannedSession(day: today, slot: SessionSlot(.run, .easy))]
    let week = SessionMatcher.match(planned: planned, activities: [], today: today)
    let input = PersonalNote.input(
      profile: profile, advice: advice, recommendation: nil, metrics: nil, week: week, today: today,
      privacy: .reduced)
    #expect(input["raceName"] == nil)
    #expect(input["testValues"] == nil)
    #expect(input["todayItems"] == .array([.string("Lockerer Lauf (heute)")]))
    #expect(input["weekPlanned"] == .number(1))
    let fallback = PersonalNote.fallback(advice: advice, recommendation: nil, week: week)
    #expect(fallback == ["Lockerer Lauf: Wie geplant.", "Diese Woche: 0 von 1 Einheiten geschafft."])
  }
}
