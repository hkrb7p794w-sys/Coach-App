import CoachCore
import Foundation
import Observation
import SwiftData

/// Rezeptideen für die kommende Woche: Tagesziele aus Wochenplan und Ernährungszielen, Lücken der letzten zwei
/// Wochen und häufige Lebensmittel als Eingabe; die KI schlägt Gerichte vor, die Regeln prüfen und passen an.
@Observable
final class RecipeViewModel {
  static let checkedKey = "recipes.checked"

  private(set) var plan: WeeklyRecipePlan?
  private(set) var targets: [RecipeDayTarget] = []
  private(set) var gaps: [String] = []
  private(set) var isWorking = false
  var errorMessage: String?
  /// Abgehakte Einträge der Einkaufsliste.
  private(set) var checked: Set<String>

  private let defaults: UserDefaults
  private let fileURL: URL?

  init(defaults: UserDefaults = .standard, fileURL: URL? = RecipeViewModel.defaultURL) {
    self.defaults = defaults
    self.fileURL = fileURL
    checked = Set(defaults.stringArray(forKey: Self.checkedKey) ?? [])
    plan = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap {
      let decoder = JSONDecoder()
      return try? decoder.decode(WeeklyRecipePlan.self, from: $0)
    }
  }

  static var defaultURL: URL? {
    try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appending(path: "recipes.json")
  }

  /// Erster Tag der Planung: der kommende Montag (am Sonntag also morgen).
  static func startDay(today: CalendarDay) -> CalendarDay {
    today.adding(days: 7 - today.weekdayIndex)
  }

  /// Tagesziele und Lücken neu berechnen.
  func update(
    settings: CoachSettings, garminProfile: GarminProfile?, meals: [MealRecord], today: CalendarDay = CalendarDay(date: .now)
  ) {
    let start = Self.startDay(today: today)
    targets = (0..<7).map { offset in
      let day = start.adding(days: offset)
      let (items, sessions) = Self.planned(day: day, settings: settings)
      let values = NutritionPlanner.compute(
        activities: [], planItems: items, settings: settings.nutrition, garminProfile: garminProfile, day: day,
        hasGarminData: false)
      return RecipeDayTarget(day: day, sessions: sessions, targets: values)
    }
    gaps = Self.gaps(meals: meals, settings: settings, garminProfile: garminProfile, today: today)
  }

  /// Geplante Einheiten eines Tages: eigener Wochenplan (mit Ausnahmen) oder Saisonplan.
  static func planned(day: CalendarDay, settings: CoachSettings) -> (items: [TemplateItem], sessions: [String]) {
    switch settings.profile.mode {
    case .personal:
      let schedule = settings.schedule(inWeekOf: day)
      let weekday = Weekday(day: day)
      return (schedule.templateItems(on: weekday), schedule.slots(on: weekday).map(\.title))
    case .season:
      let items = SeasonPlan.state(today: day, config: settings.season, week: WeeklyVolume()).todayFixed
      return (items, items.map(\.text))
    }
  }

  /// Nährstoffe, die in den letzten 14 Tagen (Tage mit mindestens 2 Mahlzeiten) zu kurz kamen.
  static func gaps(meals: [MealRecord], settings: CoachSettings, garminProfile: GarminProfile?, today: CalendarDay)
    -> [String]
  {
    let start = today.adding(days: -14).iso
    let recent = meals.filter { $0.dayKey >= start && $0.dayKey < today.iso }
    let byDay = Dictionary(grouping: recent, by: \.dayKey).filter { $0.value.count >= 2 }
    let totals = byDay.values.map { NutritionSummary.totals($0.flatMap(\.items)) }
    let reference = NutritionPlanner.compute(
      activities: [], planItems: [], settings: settings.nutrition, garminProfile: garminProfile, day: today,
      hasGarminData: false)
    return RecipePlanner.gaps(dailyTotals: totals, targets: reference.values)
  }

  func generate(ai: AIClient, settings: CoachSettings, favorites: [String], now: Date = .now) async {
    guard ai.isConfigured else {
      errorMessage = "Für Rezeptideen muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker)."
      return
    }
    guard !isWorking, !targets.isEmpty else { return }
    isWorking = true
    defer { isWorking = false }
    let nutrition = settings.nutrition
    let input = RecipePlanner.input(
      days: targets, preferences: settings.recipes, diet: nutrition.diet, goal: settings.profile.goal.label,
      gaps: gaps, favorites: favorites)
    do {
      let response = try await ai.run(task: "weekly_recipes", input: input)
      guard
        let plan = RecipePlanner.plan(
          output: response.output, targets: targets, diet: nutrition.diet, allergens: settings.recipes.allergens,
          source: "KI · \(response.model)", created: now)
      else {
        errorMessage = "Die KI hat keine brauchbaren Rezepte geliefert. Bitte erneut versuchen."
        return
      }
      store(plan)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// Rezept als Mahlzeit von heute eintragen (für eine Person).
  func log(_ recipe: Recipe, context: ModelContext, now: Date = .now) {
    context.insert(
      MealRecord(
        day: CalendarDay(date: now), category: recipe.meal == .other ? .snack : recipe.meal, title: recipe.title,
        hint: "Aus Rezeptidee (Nährwerte KI-geschätzt)", items: recipe.ingredients, at: now))
    try? context.save()
  }

  func toggle(_ item: RecipePlanner.ShoppingItem) {
    if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
    defaults.set(Array(checked), forKey: Self.checkedKey)
  }

  private func store(_ plan: WeeklyRecipePlan) {
    self.plan = plan
    checked = []
    defaults.set([String](), forKey: Self.checkedKey)
    if let fileURL, let data = try? JSONEncoder().encode(plan) {
      try? data.write(to: fileURL, options: .atomic)
    }
  }
}
