import Foundation
import Testing

@testable import CoachCore

/// Audit Runde 4 (R4A): Plan, Soll/Ist-Abgleich und Planvorschlag im persönlichen Profil.
/// Alle Tests schlagen mit dem Stand 07cf563 fehl und werden nach dem jeweiligen Fix grün.
struct AuditR4APlanTests {
  /// Montag, 26.10.2026.
  let monday = CalendarDay(year: 2026, month: 10, day: 26)

  func activity(_ id: Int64, _ typeKey: String, day: CalendarDay, minutes: Double) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.durationSeconds = minutes * 60
    return activity
  }

  func profile(
    sports: [TrainingSport], goal: FitnessGoal = .improveFitness, levels: [TrainingSport: ExperienceLevel],
    event: EventGoal? = nil, schedule: WeekSchedule = WeekSchedule()
  ) -> UserProfile {
    var profile = UserProfile(sports: sports, goal: goal, event: event, schedule: schedule)
    for (sport, level) in levels { profile.setLevel(level, for: sport) }
    return profile
  }

  // MARK: R4A-01 – App-Einheit + Uhr-Aufzeichnung am Krafttag hakt eine zweite Kraft-Einheit ab

  @Test func gymSessionWithWatchRecordingOnPlannedDayCountsOnce() {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.strength, .hard)], on: .monday)
    schedule.set([SessionSlot(.strength, .hard)], on: .thursday)
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    // Montag: Einheit in der App, nach Garmin hochgeladen – kommt als Krafttraining zurück.
    let watch = activity(1, "strength_training", day: monday, minutes: 55)
    let week = SessionMatcher.match(
      planned: planned, activities: [watch], gymDays: [monday], today: monday.adding(days: 2))
    // Nur eine Einheit gemacht; Donnerstag ist noch offen.
    #expect(week.results.filter(\.status.counts).count == 1)
    #expect(week.results(on: monday.adding(days: 3)).first?.status == .planned)
  }

  // MARK: R4A-02 – „Außerplanmäßig“ enthält Aktivitäten aus allen früheren Wochen

  @Test func extrasOnlyFromTheMatchedWeek() {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .easy)], on: .tuesday)
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    let oldWalk = activity(10, "walking", day: monday.adding(days: -21), minutes: 40)
    let thisWeekWalk = activity(11, "walking", day: monday, minutes: 40)
    let week = SessionMatcher.match(
      planned: planned, activities: [oldWalk, thisWeekWalk], today: monday.adding(days: 2))
    #expect(week.extraIDs == [11])
  }

  // MARK: R4A-03 – Tagesampel schlägt Verschieben auf einen vergangenen Tag vor

  @Test func recoveryMoveStaysInTheFutureOfThisWeek() {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .long)], on: .saturday)
    schedule.set([SessionSlot(.run, .easy)], on: .sunday)
    let person = profile(sports: [.run], levels: [.run: .intermediate], schedule: schedule)
    let saturday = monday.adding(days: 5)
    let advice = ScheduleAdvisor.advice(
      profile: person, day: saturday, recovery: .pause, trainedToday: false)
    // Montag liegt (für diese Woche) in der Vergangenheit.
    #expect(advice.move.map { $0.rawValue > Weekday.saturday.rawValue } ?? true)
    let suggestion = PlanSuggestion.recovery(
      advice: advice, profile: person, adjustments: PlanAdjustments(), today: saturday)
    #expect(suggestion?.changes.allSatisfy { $0.weekday.rawValue >= Weekday.saturday.rawValue } ?? true)
  }

  // MARK: R4A-04 – Planvorschlag kürzt Wettkampfsportarten komplett weg

  @Test func marathonOnTwoDaysStillGetsRuns() {
    let event = EventGoal(name: "Marathon", date: monday.adding(days: 150), kind: .marathon)
    let person = profile(
      sports: [.run, .strength], levels: [.run: .intermediate, .strength: .intermediate], event: event)
    let result = SchedulePlanner.suggest(profile: person, availableDays: [.saturday, .sunday])
    // Heute: leerer Vorschlag (Lauf unter Untergrenze 3 → ganze Sportart gestrichen).
    #expect(result.sessionCount == 2)
    #expect(result.count(of: .run) >= 1)
  }

  @Test func triathlonOnThreeDaysKeepsAllDisciplines() {
    let event = EventGoal(name: "Sprint", date: monday.adding(days: 90), kind: .triathlon)
    let person = profile(
      sports: [.swim, .bike, .run, .strength],
      levels: [.swim: .intermediate, .bike: .intermediate, .run: .intermediate, .strength: .intermediate],
      event: event)
    let result = SchedulePlanner.suggest(profile: person, availableDays: [.tuesday, .thursday, .saturday])
    #expect(result.sessionCount == 3)
    for sport in [TrainingSport.swim, .bike, .run] { #expect(result.count(of: sport) == 1) }
  }

  // MARK: R4A-05 – Lauf-Einsteiger:in mit Kraft-Erfahrung bekommt Intervalle

  @Test func runningBeginnerWithStrengthExperienceRunsEasy() {
    let person = profile(
      sports: [.run, .strength], goal: .loseWeight, levels: [.run: .beginner, .strength: .advanced])
    let result = SchedulePlanner.suggest(profile: person, availableDays: [.monday, .wednesday, .friday, .saturday])
    let runs = result.days.flatMap { $0 }.filter { $0.sport == .run }
    #expect(!runs.isEmpty)
    #expect(runs.allSatisfy { $0.intensity == .easy })
    // Die Wochenprüfung soll die Einsteiger-Regel ebenfalls anwenden.
    var hard = WeekSchedule()
    hard.set([SessionSlot(.run, .hard)], on: .tuesday)
    hard.set([SessionSlot(.run, .hard)], on: .friday)
    #expect(ScheduleCheck.hints(schedule: hard, profile: person).contains { $0.id == "beginner-hard" })
  }

  // MARK: R4A-06 – Wochenfortschritt: Minuten statt Einheiten

  @Test func appGymSessionsFillTheWeekProgress() {
    var schedule = WeekSchedule()
    for day in [Weekday.monday, .wednesday, .friday] { schedule.set([SessionSlot(.strength, .hard)], on: day) }
    let person = profile(sports: [.strength], goal: .buildMuscle, levels: [.strength: .intermediate], schedule: schedule)
    let thursday = monday.adding(days: 3)
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    let week = SessionMatcher.match(
      planned: planned, activities: [], gymDays: [monday, monday.adding(days: 2)], today: thursday)
    let advice = ScheduleAdvisor.advice(profile: person, day: thursday, recovery: nil, trainedToday: false)
    let focus = TodayFocus.personal(
      advice: advice, recommendation: nil, week: week, activities: [], today: thursday)
    #expect(focus.progress.sessionsDone == 2)
    // 2 von 3 Krafteinheiten gemacht – der Balken darf nicht leer sein.
    #expect(focus.progress.fraction >= 0.5)
  }

  @Test func walksDoNotFillTheWeekProgress() {
    var schedule = WeekSchedule()
    for day in [Weekday.monday, .wednesday, .friday] { schedule.set([SessionSlot(.run, .easy)], on: day) }
    let person = profile(sports: [.run], levels: [.run: .intermediate], schedule: schedule)
    let thursday = monday.adding(days: 3)
    let walks = (0..<3).map { activity(Int64(20 + $0), "walking", day: monday.adding(days: $0), minutes: 60) }
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday)
    let week = SessionMatcher.match(planned: planned, activities: walks, today: thursday)
    let advice = ScheduleAdvisor.advice(profile: person, day: thursday, recovery: nil, trainedToday: false)
    let focus = TodayFocus.personal(
      advice: advice, recommendation: nil, week: week, activities: walks, today: thursday)
    #expect(focus.progress.sessionsDone == 0)
    // Kein Lauf gemacht – „Woche geschafft“ (grüner, voller Balken) wäre falsch.
    #expect(focus.progress.fraction < 0.5)
  }

  // MARK: R4A-07 – Zwei nachgetragene Einheiten mit gleicher Startzeit überschreiben sich

  @Test func manualEntriesAtTheSameStartGetDistinctIDs() {
    let start = Date(timeIntervalSince1970: 1_793_000_000)
    let run = ManualActivity.make(sport: .run, start: start, minutes: 45, effort: 5)
    let strength = ManualActivity.make(sport: .strength, start: start, minutes: 45, effort: 6)
    #expect(run.id != strength.id)
    #expect(ManualActivity.isManual(run.id) && ManualActivity.isManual(strength.id))
  }
}
