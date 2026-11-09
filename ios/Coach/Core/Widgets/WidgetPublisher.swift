import CoachCore
import Foundation
import SwiftData
import WidgetKit

/// Homescreen-Widgets: schreibt den Stand der App in die App Group und übernimmt Wasser, das im Widget getippt
/// wurde. Ohne App Group (z. B. wenn SideStore sie nicht angelegt hat) passiert nichts – die App bleibt unberührt.
enum WidgetPublisher {
  /// Wasser aus dem Widget als Einträge speichern (beim Öffnen, vor dem ersten Bild).
  static func takeQueuedActions(model: AppModel, now: Date = .now) {
    guard WidgetStore.isAvailable, !model.isDemo else { return }
    let pending = WidgetStore.loadQueue().pending(today: CalendarDay(date: now))
    let context = model.container.mainContext
    for entry in pending {
      context.insert(
        MealRecord(
          day: entry.day, category: NutritionViewModel.category(at: entry.at), title: "Wasser", hint: "",
          items: [.water(milliliters: entry.waterMilliliters)], at: entry.at))
    }
    try? context.save()
    // Auch verfallene Einträge entfernen, damit die Datei nicht wächst.
    let today = CalendarDay(date: now)
    WidgetStore.updateQueue { queue in
      let taken = Set(pending.map(\.id))
      let expired = Set(queue.entries.filter { $0.day < today.adding(days: -WidgetActionQueue.maxAgeDays) }.map(\.id))
      queue.remove(taken.union(expired))
    }
  }

  /// Stand schreiben und die Widgets neu laden. Günstig: rechnet dieselben Regeln wie die Reiter, ohne KI.
  static func publish(model: AppModel, now: Date = .now) {
    guard WidgetStore.isAvailable, !model.isDemo, model.settings.profile.onboardingDone else { return }
    WidgetStore.save(snapshot(model: model, now: now))
    WidgetCenter.shared.reloadAllTimelines()
  }

  static func snapshot(model: AppModel, now: Date = .now) -> WidgetSnapshot {
    let context = model.container.mainContext
    let settings = model.settings
    let today = CalendarDay(date: now)
    let since = today.adding(days: -120).iso
    let todayKey = today.iso
    let days =
      ((try? context.fetch(
        FetchDescriptor<DailyMetricsRecord>(
          predicate: #Predicate { $0.dayKey >= since }, sortBy: [SortDescriptor(\.dayKey)]))) ?? [])
      .compactMap(\.metrics)
    let activities =
      ((try? context.fetch(
        FetchDescriptor<ActivityRecord>(
          predicate: #Predicate { $0.dayKey >= since }, sortBy: [SortDescriptor(\.startLocal)]))) ?? [])
      .compactMap(\.activity)
    let gymSessions =
      ((try? context.fetch(FetchDescriptor<GymSessionRecord>(sortBy: [SortDescriptor(\.start, order: .reverse)])))
      ?? []).compactMap(\.session)
    let meals =
      (try? context.fetch(
        FetchDescriptor<MealRecord>(
          predicate: #Predicate { $0.dayKey == todayKey }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []

    // Heute: dieselbe Rechnung wie im Reiter (laufende Einheit mit Satz zählt mit).
    let gym = GymViewModel.shared
    let running = gym.active != nil && gym.sessionState(now: now).countsAsTrained
    var gymDays = gymSessions.map(\.day)
    if running, let active = gym.active { gymDays.append(active.day) }
    let todayModel = TodayViewModel()
    todayModel.update(
      days: days, activities: activities, settings: settings, gymDays: gymDays,
      gym: gymSessions.map(ActivityFeed.GymItem.init), now: now)
    let focus = todayModel.snapshot?.focus
    let report = MorningReportBuilder.make(model: model, days: days, activities: activities, focus: focus, now: now)

    let todayPart = WidgetSnapshot.Today(
      level: focus?.level ?? report.level, headline: focus?.headline ?? report.headline,
      sessions: (focus?.items ?? []).filter { $0.sport != nil }.map { item in
        WidgetSnapshot.Session(
          title: item.title, target: item.target, done: item.status == .done,
          symbol: item.sport?.symbol ?? "figure.mixed.cardio")
      }, week: focus?.progress.text, weekFraction: focus?.progress.fraction)

    // Ernährung: Ziele wie im Reiter, Summen ohne Schätzung.
    let targets = NutritionViewModel.targets(
      for: today, activities: activities, settings: settings, profile: model.sync.profile,
      hasGarminData: !days.isEmpty, recovery: focus?.level ?? report.level)
    let food = meals.filter { !$0.isWater }
    let totals = NutritionSummary.totals(food.flatMap(\.items))
    // Flüssigkeit aus Getränken und Lebensmitteln wie in der Übersicht der App.
    let water = Hydration.total(meals.flatMap(\.items)).total
    var mealKilocalories: [MealCategory: Double] = [:]
    for meal in food {
      mealKilocalories[MealSplit.slot(meal.category), default: 0] += NutritionSummary.totals(meal.items)[.kcal] ?? 0
    }
    let lastMeal = food.last.map {
      WidgetSnapshot.LastMeal(
        title: $0.title, at: $0.createdAt, kcal: NutritionSummary.totals($0.items)[.kcal] ?? 0)
    }
    let nutrition = WidgetSnapshot.nutrition(
      targets: targets.values, totals: totals, water: water, lastMeal: lastMeal, mealKilocalories: mealKilocalories)

    // Gym nur mit Krafttraining im Profil.
    var gymPart: WidgetSnapshot.Gym?
    if settings.profile.trains(.strength) {
      let monday = today.adding(days: -today.weekdayIndex)
      // Wie im Plan: App-Einheiten und Krafttraining von der Uhr, je Tag einmal.
      let watchDays = activities.filter { $0.sport == .strength }.compactMap(\.day)
      let weekDone = Set((gymDays + watchDays).filter { $0 >= monday && $0 <= today }).count
      let planned = settings.profile.mode == .personal ? settings.schedule(inWeekOf: today).count(of: .strength) : nil
      let openStrength = (focus?.items ?? []).first { $0.sport == .strength && $0.status != .done }
      let routine =
        settings.profile.mode == .personal
        ? RoutineRotation.next(routines: settings.gym.routines, sessions: gymSessions) : nil
      gymPart = WidgetSnapshot.Gym(
        next: routine?.name ?? gym.todayWorkout?.name ?? openStrength?.title,
        nextDetail: routine.map { "\($0.items.count) Übungen · ca. \(RoutineRotation.estimatedMinutes($0)) min" }
          ?? openStrength?.target,
        running: running, runningTitle: running ? gym.active?.title : nil,
        last: gymSessions.first.map {
          WidgetSnapshot.LastSession(title: $0.title, day: $0.day, sets: $0.doneSetCount, volumeKg: $0.volumeKg)
        }, weekDone: weekDone, weekPlanned: planned.flatMap { $0 > 0 ? $0 : nil })
      gymPart?.nextIsForDay = routine == nil ? true : nil
    }

    let battery = BodyBatteryAnalysis.summary(days: days, today: today).current
    return WidgetSnapshot(
      createdAt: now, day: today, today: todayPart, nutrition: nutrition, gym: gymPart,
      health: WidgetSnapshot.health(from: report, bodyBattery: battery))
  }
}
