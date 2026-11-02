import CoachCore
import Foundation

/// Fakten aus den Regeln der App für Chat und KI-Analyse – überall dieselben, damit sich Antworten nicht
/// widersprechen. Im Datenschutzmodus „reduziert“ ohne Rohwerte (siehe `ChatContext`).
enum CoachFacts {
  static func chat(
    model: AppModel, snapshot: TodayViewModel.Snapshot?, metrics: [DailyMetrics],
    activities allActivities: [GarminActivity], meals: [MealRecord], gymDays: [CalendarDay], now: Date = .now
  ) -> ChatContext.Facts {
    let settings = model.settings
    let today = CalendarDay(date: now)
    var facts = ChatContext.Facts(profile: settings.profile, privacy: settings.privacy)
    if let snapshot {
      facts.recommendation = snapshot.recommendation.label
      facts.reasons = snapshot.recommendation.reasons
      if let advice = snapshot.advice {
        facts.todaySessions = [advice.headline]
      } else if let plan = snapshot.today {
        facts.todaySessions = plan.items.map(\.title)
      }
    }
    if settings.profile.mode == .personal {
      let schedule = settings.schedule(inWeekOf: today)
      facts.runWeek = RunPlanner.week(
        profile: settings.profile, schedule: schedule, monday: PlanAdjustments.monday(of: today),
        activities: allActivities)
      if facts.todaySessions.isEmpty {
        facts.todaySessions = schedule.slots(on: Weekday(day: today)).map(\.title)
      }
    }
    facts.sleep = SleepCoach.report(days: metrics, settings: settings.sleep, goal: settings.profile.goal, today: today)
    facts.targets = NutritionPlanner.compute(
      activities: allActivities.filter { $0.day == today }, planItems: [], settings: settings.nutrition,
      garminProfile: model.sync.profile, day: today, hasGarminData: !metrics.isEmpty)
    let eaten = meals.filter { $0.dayKey == today.iso }.flatMap(\.items)
    if !eaten.isEmpty { facts.eatenKilocalories = NutritionSummary.totals(eaten)[.kcal] }
    facts.weightTrend = WeightTrend.trend(WeightTrend.merged(model.allWeights), today: today)
    let form = FitnessForm.series(activities: allActivities, today: today)
    if FitnessForm.isReliable(form), let percent = form.last?.formPercent {
      facts.formZone = FitnessForm.Zone.of(percent)
    }
    facts.weekHighlights =
      WeeklyReport.lastWeek(
        activities: allActivities, days: metrics, gymDays: gymDays, today: today
      ).highlights
    return facts
  }

  /// Fakten für die KI-Analyse: Chat-Fakten plus Krafttraining, Ernährungslücken und Gewicht.
  static func analysis(
    model: AppModel, snapshot: TodayViewModel.Snapshot?, metrics: [DailyMetrics], activities: [GarminActivity],
    meals: [MealRecord], gym: [GymSession], now: Date = .now
  ) -> [String] {
    let today = CalendarDay(date: now)
    let facts = chat(
      model: model, snapshot: snapshot, metrics: metrics, activities: activities, meals: meals,
      gymDays: gym.map(\.day), now: now)
    var lines = ChatContext.lines(facts)
    lines += GymCoach.observations(sessions: gym, today: today).map { "Krafttraining: \($0)" }
    let recentGym = gym.filter { $0.day >= today.adding(days: -28) }
    if !recentGym.isEmpty {
      lines.append("Krafteinheiten in den letzten 4 Wochen: \(recentGym.count)")
    }
    let recentActivities = activities.filter { $0.day >= today.adding(days: -28) && $0.day <= today }
    if !recentActivities.isEmpty {
      let minutes = recentActivities.compactMap(\.durationSeconds).reduce(0, +) / 60
      lines.append(
        "Ausdaueraktivitäten in den letzten 4 Wochen: \(recentActivities.count), zusammen \(Int(minutes)) Minuten")
    }
    lines += RecipeViewModel.gaps(
      meals: meals, settings: model.settings, garminProfile: model.sync.profile, today: today
    ).map { "Ernährung 14 Tage: \($0)" }
    return lines
  }

  /// Was fehlt – geht an die KI, damit sie nichts ergänzt, und wird in der Ansicht genannt.
  static func missing(
    metrics: [DailyMetrics], activities: [GarminActivity], meals: [MealRecord], gym: [GymSession],
    weights: Int, now: Date = .now
  ) -> [String] {
    let today = CalendarDay(date: now)
    var result: [String] = []
    if !metrics.contains(where: { $0.day >= today.adding(days: -7) }) {
      result.append("Keine Erholungsdaten (Ruhepuls, HRV, Schlaf) der letzten 7 Tage")
    } else if !metrics.contains(where: { $0.day >= today.adding(days: -7) && ($0.sleepSeconds ?? 0) > 0 }) {
      result.append("Keine Schlafdaten der letzten 7 Tage")
    }
    if !activities.contains(where: { $0.day >= today.adding(days: -14) }) {
      result.append("Keine Ausdaueraktivitäten in den letzten 2 Wochen")
    }
    if !gym.contains(where: { $0.day >= today.adding(days: -42) }) {
      result.append("Keine Krafteinheiten in den letzten 6 Wochen")
    }
    let mealDays = Set(meals.filter { $0.dayKey >= today.adding(days: -14).iso }.map(\.dayKey)).count
    if mealDays < 3 { result.append("Kaum erfasste Mahlzeiten (\(mealDays) Tage in 2 Wochen)") }
    if weights == 0 { result.append("Kein Gewichtsverlauf") }
    return result
  }
}
