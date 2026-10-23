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
  }

  private struct CachedNote: Codable {
    let day: String
    let level: RecoveryLevel
    let points: [String]
    let source: String
  }

  static let noteKey = "coach.note"

  private(set) var snapshot: Snapshot?
  private(set) var notePoints: [String] = []
  private(set) var noteSource = ""
  private(set) var noteError: String?
  private(set) var isLoadingNote = false

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func update(days: [DailyMetrics], activities: [GarminActivity], settings: CoachSettings, now: Date = .now) {
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
    snapshot = Snapshot(
      metrics: metrics,
      isFromYesterday: byDay[today] == nil && yesterday != nil,
      recommendation: recommendation,
      plan: plan,
      week: week
    )
    showCachedOrFallback()
  }

  /// KI-Notiz holen. Ohne eingerichteten Worker bleibt die regelbasierte Notiz stehen.
  func loadNote(ai: AIClient, settings: CoachSettings, force: Bool = false) async {
    guard let snapshot, ai.isConfigured, !isLoadingNote else { return }
    if !force, let cached = cachedNote(for: snapshot), cached.source != Self.fallbackSource { return }
    isLoadingNote = true
    defer { isLoadingNote = false }
    let input = CoachingNote.input(
      recommendation: snapshot.recommendation,
      metrics: snapshot.metrics,
      plan: snapshot.plan,
      config: settings.season,
      week: snapshot.week,
      privacy: settings.privacy
    )
    do {
      let response = try await ai.run(task: "daily_note", input: input)
      let points = CoachingNote.points(from: response.output)
      guard !points.isEmpty else { throw AIClientError.http(200, "Leere KI-Antwort") }
      store(CachedNote(
        day: snapshot.plan.today.iso, level: snapshot.recommendation.level, points: points,
        source: "KI · \(response.model)"))
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
    } else {
      notePoints = CoachingNote.fallback(snapshot.recommendation, plan: snapshot.plan)
      noteSource = Self.fallbackSource
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
