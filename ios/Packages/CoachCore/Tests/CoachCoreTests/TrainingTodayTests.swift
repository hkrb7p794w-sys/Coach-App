import Foundation
import Testing

@testable import CoachCore

struct TrainingTodayTests {
  /// Mittwoch, 28.10.2026.
  let today = CalendarDay(year: 2026, month: 10, day: 28)
  let monday = CalendarDay(year: 2026, month: 10, day: 26)
  let utc = TimeZone(identifier: "UTC") ?? .current

  func activity(
    _ id: Int64, _ typeKey: String, day: CalendarDay, minutes: Double, load: Double? = nil, name: String? = nil
  ) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.durationSeconds = minutes * 60
    activity.trainingLoad = load
    activity.name = name
    return activity
  }

  /// Di intensiv, Do intensiv, Sa lang.
  var profile: UserProfile {
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run, .hard)], on: .tuesday)
    schedule.set([SessionSlot(.run, .hard)], on: .thursday)
    schedule.set([SessionSlot(.run, .long)], on: .saturday)
    return UserProfile(sports: [.run], schedule: schedule)
  }

  func warning(increase: Double = 0.6) -> WeekLoad.Result {
    WeekLoad.Result(
      last: 160, baseline: 100, bySport: [:], estimatedShare: 0, increase: increase, warning: "Zu viel Belastung.")
  }

  // MARK: - Wochenbelastung und Form

  @Test func weeklyLoadAcrossSports() {
    let earlier = (0..<3).map { activity(Int64($0), "running", day: today.adding(days: -10 - 7 * $0), minutes: 60, load: 100) }
    let recent = [
      activity(10, "running", day: today, minutes: 60, load: 100),
      activity(11, "cycling", day: today.adding(days: -2), minutes: 60, load: 100),
      activity(12, "running", day: today.adding(days: -3), minutes: 60),
    ]
    let gym = ActivityFeed.GymItem(
      id: UUID(), title: "Push", start: Date(timeIntervalSince1970: 1_793_095_200), minutes: 50, sets: 12,
      volumeKg: 3_000)
    let result = WeekLoad.check(activities: earlier + recent, gym: [gym], today: today, timeZone: utc)
    #expect(result.baseline == 100)
    #expect(result.last == 310)
    #expect(result.bySport[.strength] == 50)
    #expect(result.bySport[.bike] == 100)
    #expect(result.increase == 2.1)
    #expect(result.warning?.contains("210 % mehr") == true)
    #expect(abs(result.estimatedShare - 110.0 / 310) < 0.001)
  }

  @Test func noWarningWithoutHistoryOrSmallDifference() {
    let recent = [activity(1, "running", day: today, minutes: 60, load: 100)]
    #expect(WeekLoad.check(activities: recent, today: today).warning == nil)
    let earlier = (0..<3).map { activity(Int64(10 + $0), "running", day: today.adding(days: -10 - 7 * $0), minutes: 30, load: 40) }
    let small = [activity(1, "running", day: today, minutes: 60, load: 80)]
    #expect(WeekLoad.check(activities: earlier + small, today: today).warning == nil)
  }

  @Test func estimatedLoadUsesIntensity() {
    #expect(WeekLoad.load(activity(1, "running", day: today, minutes: 40)).value == 40)
    #expect(WeekLoad.load(activity(1, "running", day: today, minutes: 40, name: "Intervalle")).value == 80)
    let measured = WeekLoad.load(activity(1, "running", day: today, minutes: 40, load: 55))
    #expect(measured.value == 55)
    #expect(!measured.estimated)
  }

  func formPoints(count: Int, percent: Double) -> [FitnessForm.Point] {
    (0..<count).map {
      FitnessForm.Point(
        day: today.adding(days: $0 - count + 1), load: 50, fitness: 50, fatigue: 50 - percent / 2,
        form: percent / 2)
    }
  }

  @Test func veryNegativeFormLimitsAmpelToEasy() {
    let normal = Recommendation(level: .normal, reasons: ["HRV-Status ausgeglichen"])
    let limited = normal.limited(byForm: formPoints(count: 42, percent: -40))
    #expect(limited.level == .locker)
    #expect(limited.isLimitedByForm)
    #expect(limited.evidenceIDs.contains("load.fitness-form"))
    let pause = Recommendation(level: .pause, reasons: ["HRV-Status niedrig"]).limited(
      byForm: formPoints(count: 42, percent: -40))
    #expect(pause.level == .pause)
    #expect(normal.limited(byForm: formPoints(count: 41, percent: -40)) == normal)
    #expect(normal.limited(byForm: formPoints(count: 42, percent: -20)) == normal)
    #expect(!normal.evidenceIDs.contains("load.fitness-form"))
  }

  // MARK: - Vorschläge

  @Test func loadSuggestionEasesNextHardDay() throws {
    let suggestion = try #require(
      PlanSuggestion.load(warning(), profile: profile, adjustments: PlanAdjustments(), today: today))
    #expect(suggestion.source == .load)
    #expect(suggestion.changes.map(\.text) == ["Do: Qualitätslauf (Tempo oder Intervalle) → Lockerer Lauf"])
    #expect(suggestion.unchanged == ["Di: Qualitätslauf (Tempo oder Intervalle) bleibt", "Sa: Langer Lauf bleibt"])
    #expect(suggestion.adjustments.schedule(profile.schedule, inWeekOf: today).slots(on: .thursday) == [SessionSlot(.run)])
    #expect(suggestion.conflicts.isEmpty)
    #expect(suggestion.week == monday)
    #expect(PlanSuggestion.load(warning(), profile: profile, adjustments: PlanAdjustments(), today: today.adding(days: 3)) == nil)
  }

  @Test func suggestionShowsNewRuleConflicts() throws {
    var after = profile.schedule
    after.set([SessionSlot(.run, .hard)], on: .wednesday)
    let suggestion = try #require(
      PlanSuggestion.make(
        id: "test", source: .recovery, title: "Test", reason: "", profile: profile, adjustments: PlanAdjustments(),
        week: today
      ) { $0.setWeekPlan(after, base: profile.schedule, inWeekOf: today) })
    #expect(suggestion.changes.map(\.weekday) == [.wednesday])
    #expect(suggestion.conflicts.contains { $0.id.hasPrefix("back-to-back") })
    #expect(
      PlanSuggestion.make(
        id: "none", source: .recovery, title: "", reason: "", profile: profile, adjustments: PlanAdjustments(),
        week: today
      ) { _ in } == nil)
  }

  @Test func recoveryAndNextWeekSuggestions() throws {
    let thursday = today.adding(days: 1)
    let advice = ScheduleAdvice(
      mode: .rest, headline: "Heute frei", detail: "HRV niedrig", move: .friday, plannedTitles: [], evidenceIDs: [])
    let move = try #require(
      PlanSuggestion.recovery(advice: advice, profile: profile, adjustments: PlanAdjustments(), today: thursday))
    #expect(move.changes.map(\.weekday) == [.thursday, .friday])
    #expect(move.adjustments.note(for: .thursday, inWeekOf: thursday) == "verschoben auf Freitag")

    let next = try #require(
      PlanSuggestion.nextWeek(load: warning(), profile: profile, adjustments: PlanAdjustments(), today: today))
    #expect(next.week == monday.adding(days: 7))
    #expect(next.changes.map(\.weekday) == [.tuesday])
    #expect(next.reason.hasPrefix("Diese Woche lag die Belastung 60 %"))
    var noWarning = warning()
    noWarning.warning = nil
    #expect(PlanSuggestion.nextWeek(load: noWarning, profile: profile, adjustments: PlanAdjustments(), today: today) == nil)
  }

  // MARK: - Jetzt dran

  @Test func progressText() {
    let progress = TodayFocus.Progress(sessionsDone: 3, sessionsPlanned: 5, minutesDone: 140, minutesPlanned: 210)
    #expect(progress.text == "3/5 Einheiten · 140/210 min")
    #expect(abs(progress.fraction - 140.0 / 210) < 0.001)
    #expect(TodayFocus.Progress(sessionsDone: 2, sessionsPlanned: 4, minutesDone: 90, minutesPlanned: nil).text
      == "2/4 Einheiten · 90 min")
  }

  @Test func conflictBetweenRuleAndPlan() {
    let reasons = ["HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline"]
    #expect(
      TodayFocus.conflict(level: .locker, reasons: reasons, planned: ["Qualitätslauf"])
        == "Regel: locker (HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline) · geplant: "
        + "Qualitätslauf. Es gilt die Regel.")
    #expect(TodayFocus.conflict(level: .normal, reasons: reasons, planned: ["Qualitätslauf"]) == nil)
    #expect(TodayFocus.conflict(level: .pause, reasons: [], planned: []) == nil)
    #expect(TodayFocus.why(["HRV-Status ausgeglichen"]) == nil)
  }

  @Test func personalFocusShowsTodayWithTarget() throws {
    let thursday = today.adding(days: 1)
    let planned = SessionMatcher.planned(schedule: profile.schedule, monday: monday)
    let runs = [activity(1, "running", day: monday.adding(days: 1), minutes: 50, name: "Intervalle")]
    let week = SessionMatcher.match(planned: planned, activities: runs, today: thursday)
    let advice = ScheduleAdvice(
      mode: .lighter, headline: "Locker statt intensiv", detail: "", move: nil, plannedTitles: [], evidenceIDs: [])
    let focus = TodayFocus.personal(
      advice: advice, recommendation: Recommendation(level: .locker, reasons: ["kurzer Schlaf (5,5 h)"]), week: week,
      activities: runs, today: thursday)
    let item = try #require(focus.items.first)
    #expect(item.target == "Soll 50 min · Intensiv")
    #expect(item.demanding)
    #expect(focus.conflict?.hasPrefix("Regel: locker (kurzer Schlaf (5,5 h))") == true)
    #expect(focus.progress.sessionsDone == 1)
    #expect(focus.progress.sessionsPlanned == 3)
    #expect(focus.progress.minutesDone == 50)
    #expect(focus.progress.minutesPlanned == 50 + 50 + 90)
  }

  // MARK: - Verlauf, Trends, Rückblick

  @Test func feedFilter() {
    let activities = [
      activity(1, "running", day: today, minutes: 40),
      activity(2, "running", day: today.adding(days: -1), minutes: 50, name: "Intervalle 4x4"),
      activity(3, "cycling", day: today.adding(days: -2), minutes: 60),
      activity(4, "running", day: today.adding(days: -60), minutes: 30),
    ]
    let entries = ActivityFeed.entries(activities: activities, gym: [], timeZone: utc)
    #expect(ActivityFeed.Filter(sport: .run).apply(entries, today: today).count == 3)
    #expect(ActivityFeed.Filter(onlyHard: true).apply(entries, today: today).map(\.id) == ["a2"])
    #expect(ActivityFeed.Filter(search: "interv").apply(entries, today: today).map(\.id) == ["a2"])
    #expect(ActivityFeed.Filter(period: .weeks4).apply(entries, today: today).count == 3)
    #expect(ActivityFeed.Filter(onlyPlanned: true).apply(entries, today: today).isEmpty)
    #expect(!ActivityFeed.Filter(period: .year).narrows)
  }

  @Test func weeklyMinutesStacked() {
    let activities = [
      activity(1, "running", day: today, minutes: 30),
      activity(2, "cycling", day: today.adding(days: -7), minutes: 60),
    ]
    let gym = ActivityFeed.GymItem(
      id: UUID(), title: "Push", start: Date(timeIntervalSince1970: 1_793_095_200), minutes: 40, sets: 10,
      volumeKg: 2_000)
    let minutes = TrainingTrends.weeklyMinutes(activities: activities, gym: [gym], today: today, weeks: 2, timeZone: utc)
    #expect(minutes.map(\.sport) == [.bike, .run, .strength])
    #expect(minutes.map(\.minutes) == [60, 30, 40])
    #expect(minutes.first?.monday == monday.adding(days: -7))
  }

  @Test func aerobicEfficiencyOfEasyRuns() {
    var easy = activity(1, "running", day: today, minutes: 25)
    easy.distanceMeters = 5_000
    easy.averageHeartRate = 150
    var short = activity(2, "running", day: today, minutes: 10)
    short.distanceMeters = 2_000
    short.averageHeartRate = 140
    let values = TrainingTrends.aerobicEfficiency(activities: [easy, short])
    #expect(values == [DayValue(day: today, value: 1.33)])
  }

  @Test func weeklyReviewHighlights() {
    var run = activity(1, "running", day: today, minutes: 70)
    run.distanceMeters = 12_500
    let progress = TodayFocus.Progress(sessionsDone: 3, sessionsPlanned: 3, minutesDone: 150, minutesPlanned: 140)
    let review = WeeklyReview.make(progress: progress, week: nil, activities: [run], today: today.adding(days: 4))
    #expect(review.highlights.contains("Alle 3 geplanten Einheiten geschafft."))
    #expect(review.highlights.contains("Längster Lauf: 12,5 km"))
    #expect(WeeklyReview.isDue(today.adding(days: 4)))
    #expect(!WeeklyReview.isDue(today))
  }
}
