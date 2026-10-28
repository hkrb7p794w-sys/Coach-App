import CoachCore
import Foundation
import Observation

/// Berechnet Tagesampel, Wochen-Soll/Ist und Rennvorbereitung aus den gespeicherten Garmin-Daten und
/// holt die KI-Notiz (einmal je Tag und Ampelstufe, zwischengespeichert).
@Observable
final class TodayViewModel {
  struct Snapshot: Equatable {
    let metrics: DailyMetrics?
    /// true, wenn für heute noch keine Werte vorliegen und die von gestern gezeigt werden.
    let isFromYesterday: Bool
    let recommendation: Recommendation
    let plan: PlanState
    let week: WeeklyVolume
    /// Einheiten des Tages mit Hinweisen (Portierung von `coach_today()`).
    let today: TodayPlan?
    /// Empfehlung aus dem eigenen Wochenplan (nur bei persönlichem Profil).
    let advice: ScheduleAdvice?
    /// Soll/Ist je Einheit dieser Woche (nur bei persönlichem Profil).
    var sessions: SessionMatcher.Week?
  }

  private struct CachedNote: Codable {
    let day: String
    let level: RecoveryLevel
    let points: [String]
    let source: String
    /// Von der KI genannte Regeln (fehlt in älteren Einträgen).
    var sources: [String]?
  }

  static let noteKey = "coach.note"

  private(set) var snapshot: Snapshot?
  private(set) var notePoints: [String] = []
  private(set) var noteSource = ""
  /// Regeln hinter Tagesampel und Notiz.
  private(set) var noteEvidence: [String] = []
  private(set) var noteError: String?
  private(set) var isLoadingNote = false

  private let defaults: UserDefaults
  private let schedule: SeasonSchedule?

  init(defaults: UserDefaults = .standard, schedule: SeasonSchedule? = .load()) {
    self.defaults = defaults
    self.schedule = schedule
  }

  func update(
    days: [DailyMetrics], activities: [GarminActivity], settings: CoachSettings, gymDays: [CalendarDay] = [],
    now: Date = .now
  ) {
    let today = CalendarDay(date: now)
    let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
    let yesterday = byDay[today.adding(days: -1)]
    let metrics = byDay[today] ?? yesterday
    let referenceDay = metrics?.day ?? today

    let recommendation = RecoveryEvaluator.evaluate(
      metrics ?? DailyMetrics(day: today),
      restingHeartRate7DayAverage: RecoveryEvaluator.average(
        \.restingHeartRate, in: days, daysBefore: 1...7, today: referenceDay)
    )
    let week = WeeklyVolume(activities: activities, weekContaining: today)
    let plan = SeasonPlan.state(today: today, config: settings.season, week: week)
    let todayPlan = schedule.map {
      Self.todayPlan(
        schedule: $0, activities: activities, gymDays: gymDays, settings: settings, today: today,
        recommendation: recommendation, hasMetrics: metrics != nil)
    }
    var advice: ScheduleAdvice?
    var sessions: SessionMatcher.Week?
    if settings.profile.mode == .personal {
      // „Geschafft“ nur, wenn die geplanten Einheiten wirklich gemacht sind (Sportart, Dauer), nicht bei irgendeiner
      // Aktivität.
      let week = Self.sessionWeek(settings: settings, activities: activities, gymDays: gymDays, today: today)
      sessions = week
      let recovery = MissedSessions.cappedRecovery(
        metrics == nil ? nil : recommendation.level, sickDay: settings.illnessDay, today: today)
      advice = ScheduleAdvisor.advice(
        profile: settings.profile, schedule: settings.schedule(inWeekOf: today), day: today,
        recovery: recovery, trainedToday: week.allCounted(on: today))
    }
    snapshot = Snapshot(
      metrics: metrics,
      isFromYesterday: byDay[today] == nil && yesterday != nil,
      recommendation: recommendation,
      plan: plan,
      week: week,
      today: todayPlan,
      advice: advice,
      sessions: sessions
    )
    showCachedOrFallback()
  }

  /// Soll/Ist der Woche: Plan mit Ausnahmen, Laufminuten aus dem Laufplan, Aktivitäten und Krafteinheiten.
  static func sessionWeek(
    settings: CoachSettings, activities: [GarminActivity], gymDays: [CalendarDay], today: CalendarDay
  ) -> SessionMatcher.Week {
    let monday = PlanAdjustments.monday(of: today)
    let schedule = settings.schedule(inWeekOf: today)
    let runWeek = RunPlanner.week(
      profile: settings.profile, schedule: schedule, monday: monday, activities: activities)
    let runMinutes = Dictionary(grouping: runWeek?.sessions ?? [], by: \.weekday).mapValues { $0.map(\.minutes) }
    let planned = SessionMatcher.planned(schedule: schedule, monday: monday, runMinutes: runMinutes)
    return SessionMatcher.match(planned: planned, activities: activities, gymDays: Set(gymDays), today: today)
  }

  /// Erledigtes der Woche: Garmin-Aktivitäten (Rad nur mit Distanz) und Krafteinheiten aus Garmin und App.
  static func todayPlan(
    schedule: SeasonSchedule, activities: [GarminActivity], gymDays: [CalendarDay], settings: CoachSettings,
    today: CalendarDay, recommendation: Recommendation, hasMetrics: Bool
  ) -> TodayPlan {
    let monday = today.adding(days: -today.weekdayIndex)
    let progress = TodayPlan.done(activities: activities, gymDays: gymDays, weekOf: today, upTo: today)
    let strengthDays = progress.strengthDays
    let done = progress.done
    let zones = HeartRateZoneCalculator.distribution(activities: activities, today: today, weeks: 1)
      .perWeek.first { $0.monday == monday }?.run
    return TodayPlan(
      schedule: schedule, config: settings.season, decisions: settings.competitionDecisions, today: today,
      level: hasMetrics ? recommendation.level : nil, advice: recommendation.advice, done: done,
      gymDays: strengthDays, runZones: zones)
  }

  /// KI-Notiz holen. Ohne eingerichteten Worker bleibt die regelbasierte Notiz stehen.
  func loadNote(ai: AIClient, settings: CoachSettings, force: Bool = false) async {
    guard let snapshot, ai.isConfigured, !isLoadingNote else { return }
    if !force, let cached = cachedNote(for: snapshot), cached.source != Self.fallbackSource { return }
    isLoadingNote = true
    defer { isLoadingNote = false }
    var input = CoachingNote.input(
      recommendation: snapshot.recommendation,
      metrics: snapshot.metrics,
      plan: snapshot.plan,
      config: settings.season,
      week: snapshot.week,
      privacy: settings.privacy
    )
    // Gleiche Einheiten und Hinweise wie in der Ansicht – Karte und Notiz widersprechen sich nicht.
    if let today = snapshot.today {
      input["todayItems"] = .array(
        today.items.map { .string(CoachingNote.line($0.title, $0.caption, done: $0.done, chip: $0.chip)) })
      input["openItems"] = .array(
        today.open.map { .string(CoachingNote.line($0.title, $0.caption, done: false, chip: $0.chip)) })
    }
    do {
      let response = try await ai.run(task: "daily_note", input: input)
      let points = CoachingNote.points(from: response.output)
      guard !points.isEmpty else { throw AIClientError.http(200, "Leere KI-Antwort") }
      store(
        CachedNote(
          day: snapshot.plan.today.iso, level: snapshot.recommendation.level, points: points,
          source: "KI · \(response.model)", sources: CoachingNote.sources(from: response.output)))
      noteError = nil
    } catch {
      noteError = error.localizedDescription
    }
    showCachedOrFallback()
  }

  private static let fallbackSource = "Regeln (ohne KI)"

  private func showCachedOrFallback() {
    guard let snapshot else { return }
    if let cached = cachedNote(for: snapshot) {
      notePoints = cached.points
      noteSource = cached.source
      noteEvidence = snapshot.recommendation.evidenceIDs + (cached.sources ?? [])
    } else {
      notePoints = CoachingNote.fallback(snapshot.recommendation, plan: snapshot.plan)
      noteSource = Self.fallbackSource
      noteEvidence = snapshot.recommendation.evidenceIDs
    }
  }

  private func cachedNote(for snapshot: Snapshot) -> CachedNote? {
    guard let data = defaults.data(forKey: Self.noteKey),
      let cached = try? JSONDecoder().decode(CachedNote.self, from: data),
      cached.day == snapshot.plan.today.iso, cached.level == snapshot.recommendation.level
    else { return nil }
    return cached
  }

  private func store(_ note: CachedNote) {
    if let data = try? JSONEncoder().encode(note) { defaults.set(data, forKey: Self.noteKey) }
  }
}
