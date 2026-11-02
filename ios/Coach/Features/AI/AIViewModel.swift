import CoachCore
import Foundation

/// Sammelt die Empfehlungen der Regeln und startet die KI-Analyse. Beides landet im selben Eingang
/// (`InsightInbox`), der Doppeltes und Widersprüche aussortiert.
@Observable
final class AIViewModel {
  private(set) var isAnalyzing = false
  private(set) var error: String?
  private(set) var note: String?
  private(set) var missing: [String] = []
  /// Gleiche Tagesbewertung wie unter „Heute“ (für Regeln, Chat und Fakten).
  private(set) var snapshot: TodayViewModel.Snapshot?
  private let today = TodayViewModel()

  /// Regeln neu auswerten. Was eine Regel nicht mehr meldet, gilt ab jetzt als „nicht mehr aktuell“.
  func refreshRules(
    model: AppModel, metrics: [DailyMetrics], activities: [GarminActivity], meals: [MealRecord], gym: [GymSession],
    now: Date = .now
  ) {
    let settings = model.settings
    today.update(
      days: metrics, activities: activities, settings: settings, gymDays: gym.map(\.day),
      gym: gym.map(ActivityFeed.GymItem.init), now: now)
    snapshot = today.snapshot
    let day = CalendarDay(date: now)
    let input = InsightRules.Input(
      now: now,
      recommendation: metrics.contains { $0.day >= day.adding(days: -1) } ? snapshot?.recommendation : nil,
      sleep: SleepCoach.report(days: metrics, settings: settings.sleep, goal: settings.profile.goal, today: day),
      gymObservations: GymCoach.observations(sessions: gym, today: day),
      nutritionGaps: RecipeViewModel.gaps(
        meals: meals, settings: settings, garminProfile: model.sync.profile, today: day),
      planSuggestions: planSuggestions(settings: settings).filter {
        !settings.dismissedSuggestions.contains($0.id)
      })
    let rules = InsightRules.build(input)
    var inbox = InsightInbox.retireRules(settings.insights, keeping: Set(rules.map(\.id)), now: now)
    inbox = InsightInbox.merge(inbox, with: rules, now: now)
    if inbox != settings.insights { settings.insights = inbox }
    missing = CoachFacts.missing(
      metrics: metrics, activities: activities, meals: meals, gym: gym, weights: model.allWeights.count, now: now)
  }

  func mark(_ status: InsightStatus, _ insight: Insight, model: AppModel, onlyIfNew: Bool = false) {
    if onlyIfNew && insight.status != .new { return }
    model.settings.insights = InsightInbox.setStatus(status, id: insight.id, in: model.settings.insights, now: .now)
  }

  /// KI-Analyse auf Anfrage: Fakten der App, fehlende Daten und die Regeln gehen an den Worker; zurück kommen nur
  /// geprüfte Empfehlungen mit Belegen.
  func analyze(
    topic: InsightTopic?, model: AppModel, metrics: [DailyMetrics], activities: [GarminActivity],
    meals: [MealRecord], gym: [GymSession], now: Date = .now
  ) async {
    guard !isAnalyzing else { return }
    isAnalyzing = true
    error = nil
    note = nil
    defer { isAnalyzing = false }
    let facts = InsightAnalysis.facts(
      CoachFacts.analysis(
        model: model, snapshot: snapshot, metrics: metrics, activities: activities, meals: meals, gym: gym,
        now: now))
    guard !facts.isEmpty else {
      error = "Noch zu wenige Daten für eine Analyse."
      return
    }
    let rules = model.settings.insights.filter { $0.origin == .rules && $0.isCurrent(at: now) }
    let input = InsightAnalysis.input(topic: topic, facts: facts, missing: missing, ruleInsights: rules)
    do {
      let response = try await model.ai.run(task: "ai_insights", input: input)
      let insights = InsightAnalysis.insights(from: response.output, facts: facts, model: response.model, now: now)
      let before = model.settings.insights.count
      model.settings.insights = InsightInbox.merge(model.settings.insights, with: insights, now: now)
      let added = model.settings.insights.count - before
      note =
        added > 0
        ? "\(added) neue Empfehlung\(added == 1 ? "" : "en")."
        : "Keine neuen Empfehlungen – die bisherigen gelten weiter."
    } catch {
      self.error = error.localizedDescription
    }
  }

  /// Planvorschläge wie unter „Heute“ (nur eigener Wochenplan).
  private func planSuggestions(settings: CoachSettings) -> [PlanSuggestion] {
    guard settings.profile.mode == .personal, let snapshot else { return [] }
    let day = snapshot.plan.today
    var list: [PlanSuggestion] = []
    if let advice = snapshot.advice,
      let suggestion = PlanSuggestion.recovery(
        advice: advice, profile: settings.profile, adjustments: settings.planAdjustments, today: day)
    {
      list.append(suggestion)
    }
    if let load = snapshot.load {
      if let suggestion = PlanSuggestion.load(
        load, profile: settings.profile, adjustments: settings.planAdjustments, today: day)
      {
        list.append(suggestion)
      }
      if let suggestion = PlanSuggestion.nextWeek(
        load: load, profile: settings.profile, adjustments: settings.planAdjustments, today: day)
      {
        list.append(suggestion)
      }
    }
    return list
  }
}
