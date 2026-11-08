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
    try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    .appending(path: "recipes.json")
  }

  /// Erster Tag der Planung: der kommende Montag (am Sonntag also morgen).
  static func startDay(today: CalendarDay) -> CalendarDay {
    today.adding(days: 7 - today.weekdayIndex)
  }

  /// Tagesziele und Lücken neu berechnen.
  func update(
    settings: CoachSettings, garminProfile: GarminProfile?, meals: [MealRecord],
    today: CalendarDay = CalendarDay(date: .now)
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
    // Nebeneinander in Teilen: Eine Antwort über sieben Tage überschreitet das Antwortlimit der KI.
    let batches = RecipePlanner.batches(targets)
    var parts: [WeeklyRecipePlan] = []
    var failures: [String] = []
    let requests = batches.map { batch in
      Task { await requestBatch(batch, ai: ai, settings: settings, favorites: favorites, now: now) }
    }
    for request in requests {
      switch await request.value {
      case .plan(let plan): parts.append(plan)
      case .failed(let message): failures.append(message)
      }
    }
    guard var plan = WeeklyRecipePlan.merged(parts, created: now) else {
      errorMessage = failures.first ?? "Die KI hat keine brauchbaren Rezepte geliefert. Bitte erneut versuchen."
      return
    }
    if !failures.isEmpty {
      plan.notes.append("Nicht alle Tage konnten erstellt werden. „Neu erstellen“ versucht es noch einmal.")
    }
    store(plan)
    errorMessage = nil
  }

  private nonisolated enum BatchResult: Sendable {
    case plan(WeeklyRecipePlan)
    case failed(String)
  }

  /// Ein Teil der Woche. Bei einem vorübergehenden Ausfall genau ein zweiter Versuch, damit keine Kosten auflaufen.
  private func requestBatch(
    _ days: [RecipeDayTarget], ai: AIClient, settings: CoachSettings, favorites: [String], now: Date
  ) async -> BatchResult {
    let nutrition = settings.nutrition
    let input = RecipePlanner.input(
      days: days, preferences: settings.recipes, diet: nutrition.diet, goal: settings.coachingProfile.goal.label,
      gaps: gaps, favorites: favorites)
    for attempt in 0..<2 {
      do {
        let response = try await ai.run(task: "weekly_recipes", input: input)
        guard
          let plan = RecipePlanner.plan(
            output: response.output, targets: days, diet: nutrition.diet, allergens: settings.recipes.allergens,
            source: "KI · \(response.model)", created: now)
        else { return .failed("Die KI hat keine brauchbaren Rezepte geliefert. Bitte erneut versuchen.") }
        return .plan(plan)
      } catch AIClientError.http(let status, _) where attempt == 0 && AIErrorText.isTemporary(status: status) {
        try? await Task.sleep(for: .seconds(2))
      } catch {
        return .failed(error.localizedDescription)
      }
    }
    return .failed(AIErrorText.message(status: 502, code: nil, detail: ""))
  }

  // MARK: - Gemeinsam kochen und vorkochen

  /// Kochpläne dieses Geräts, neueste zuerst.
  private(set) var cookPlans: [CookPlan] = []
  private(set) var cookNotes: [String] = []
  private(set) var isCooking = false
  var cookError: String?

  /// Eigene Angaben für den Plan: dieselben Tagesziele wie in der Wochenübersicht.
  func myself(settings: CoachSettings, garminProfile: GarminProfile?, today: CalendarDay = CalendarDay(date: .now))
    -> CookPerson
  {
    let body = settings.nutrition.profile(garmin: garminProfile, on: today)
    let share = CookPlanner.share(
      name: "Ich", week: targets, diet: settings.nutrition.diet, preferences: settings.recipes,
      fields: CookShareFields(), safety: GoalRules.weightGuard(settings: settings.nutrition, body: body))
    return CookPerson(id: CookPerson.meID, share: share)
  }

  /// Vorschläge erstellen. Freigaben werden vorher neu geholt: Was zurückgezogen ist, wird nicht mehr verwendet.
  func createCookPlans(
    audience: CookAudience, partner: CookPartner?, meal: MealCategory, amount: CookAmount, ai: AIClient,
    settings: CoachSettings, garminProfile: GarminProfile?, favorites: [String], now: Date = .now
  ) async {
    guard ai.isConfigured else {
      cookError = "Für Rezeptideen muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker)."
      return
    }
    guard !isCooking else { return }
    isCooking = true
    defer { isCooking = false }
    cookError = nil
    do {
      var people: [CookPerson] = []
      if audience != .partner { people.append(myself(settings: settings, garminProfile: garminProfile)) }
      if audience != .me {
        guard let partner else {
          cookError = "Verbinde zuerst eine Person unter „Gemeinsam kochen“."
          return
        }
        let fresh = try await CookShareService.fetch(partner.code, ai: ai)
        if let index = settings.cookPartners.firstIndex(where: { $0.code == partner.code }) {
          settings.cookPartners[index].share = fresh
        }
        people.append(CookPerson(id: partner.code, share: fresh))
      }
      let input = CookPlanner.input(
        people: people, meal: meal, amount: amount, preferences: settings.recipes, favorites: favorites)
      let response = try await runCookPlan(ai: ai, input: input)
      let result = CookPlanner.plans(
        output: response.output, people: people, meal: meal, amount: amount, source: "KI · \(response.model)",
        created: now)
      cookNotes = result.notes
      guard !result.plans.isEmpty else {
        cookError = "Kein vorgeschlagenes Rezept passte zu euren Angaben. Bitte erneut versuchen."
        return
      }
      cookPlans = result.plans + cookPlans.prefix(12)
      storeCookPlans()
    } catch AIClientError.http(404, _) {
      if let partner { forget(partner, settings: settings) }
      cookError = "Die Freigabe wurde zurückgezogen oder ist abgelaufen. Die gespeicherten Angaben wurden gelöscht."
    } catch {
      cookError = error.localizedDescription
    }
  }

  private func runCookPlan(ai: AIClient, input: [String: JSONValue]) async throws -> AIResponse {
    do {
      return try await ai.run(task: "cook_plan", input: input)
    } catch AIClientError.http(let status, _) where AIErrorText.isTemporary(status: status) {
      try? await Task.sleep(for: .seconds(2))
      return try await ai.run(task: "cook_plan", input: input)
    }
  }

  func update(_ plan: CookPlan) {
    guard let index = cookPlans.firstIndex(where: { $0.id == plan.id }) else { return }
    cookPlans[index] = plan
    storeCookPlans()
  }

  func delete(_ plan: CookPlan) {
    cookPlans.removeAll { $0.id == plan.id }
    storeCookPlans()
  }

  /// Verbindung lösen: Auch Pläne mit den Angaben dieser Person werden gelöscht.
  func forget(_ partner: CookPartner, settings: CoachSettings) {
    settings.cookPartners.removeAll { $0.code == partner.code }
    cookPlans.removeAll { plan in plan.people.contains { $0.id == partner.code } }
    storeCookPlans()
  }

  func loadCookPlans() {
    guard cookPlans.isEmpty, let url = Self.cookPlansURL, let data = try? Data(contentsOf: url) else { return }
    cookPlans = (try? JSONDecoder().decode([CookPlan].self, from: data)) ?? []
  }

  private func storeCookPlans() {
    guard let url = Self.cookPlansURL, let data = try? JSONEncoder().encode(cookPlans) else { return }
    try? data.write(to: url, options: .atomic)
  }

  static var cookPlansURL: URL? {
    try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    .appending(path: "cook-plans.json")
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
