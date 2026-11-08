import Foundation
import Testing

@testable import CoachCore

/// Basisportion: 200 g Linsen-Curry (150 kcal je 100 g, 10 g Protein, 20 g KH, 3,3 g Fett) = 300 kcal, 20 g Protein.
private func recipeJSON(
  title: String = "Testcurry", prep: Bool = true, fridge: Double = 3, freezable: Bool = true,
  ingredient: String = "Testcurry Zyx"
) -> JSONValue {
  .object([
    "titel": .string(title), "minuten": .number(25), "zubereitung": .array([.string("Kochen")]),
    "zutaten": .array([
      .object([
        "name": .string(ingredient), "menge_g": .number(200), "menge_text": .string("200 g"),
        "naehrwerte_100g": .object([
          "kcal": .number(150), "protein_g": .number(10), "carbs_g": .number(20), "fat_g": .number(3.3),
        ]),
      ])
    ]),
    "vorkochen_geeignet": .bool(prep), "haltbarkeit_tage": .number(fridge), "einfrierbar": .bool(freezable),
    "lagerung": .string("Luftdicht im Kühlschrank"), "aufwaermen": .string("In der Pfanne"),
    "kompromiss": .string("Mehr Protein für Person 1, weniger Energie für Person 2."),
  ])
}

private func output(_ recipes: JSONValue...) -> JSONValue { .object(["rezepte": .array(recipes)]) }

private let me = CookPerson(
  id: CookPerson.meID,
  share: CookShare(name: "Ich", kcal: 2_400, protein: 160, carbs: 280, fat: 80, diet: .omnivore))
private let partner = CookPerson(
  id: "abcdefghij",
  share: CookShare(
    name: "Lena", kcal: 1_800, protein: 100, carbs: 200, fat: 60, diet: .vegetarian, allergens: [.nuts],
    dislikes: "Pilze"
  ))
private let created = Date(timeIntervalSince1970: 1_800_000_000)

private func makePlan(_ people: [CookPerson], amount: CookAmount, meal: MealCategory = .dinner) throws -> CookPlan {
  let result = CookPlanner.plans(
    output: output(recipeJSON()), people: people, meal: meal, amount: amount, source: "KI", created: created)
  return try #require(result.plans.first)
}

struct CookPlanTests {
  // MARK: - Teller und Mengen

  @Test func portionsAreSplitAndDaysCountPerPerson() {
    #expect(CookPlanner.plates(.portions(4), people: [me, partner]) == [me.id: 2, partner.id: 2])
    #expect(CookPlanner.plates(.portions(3), people: [me, partner]) == [me.id: 2, partner.id: 1])
    #expect(CookPlanner.plates(.days(3), people: [me, partner]) == [me.id: 3, partner.id: 3])
    #expect(CookPlanner.plates(.portions(6), people: [me]) == [me.id: 6])
    #expect(CookPlanner.plates(.days(99), people: [me]) == [me.id: CookAmount.maxDays])
  }

  /// Abendessen sind 30 % des Tages: 720 kcal und 540 kcal; die Basisportion hat 300 kcal.
  @Test func portionSizeFollowsEachPersonsTarget() throws {
    let result = try makePlan([me, partner], amount: .portions(2))
    let mine = try #require(result.portions.first { $0.person.id == me.id })
    let hers = try #require(result.portions.first { $0.person.id == partner.id })
    #expect(abs(mine.factor - 1.8) < 0.001)  // 2,4 wären zu viel: auf 1,8 begrenzt.
    #expect(abs(hers.factor - 1.8) < 0.001)
    #expect(abs(mine.sharePercent - 50) < 0.1)
  }

  /// Basisportion nah am Ziel: Teller unterscheiden sich im Verhältnis 720 : 540.
  @Test func portionsDifferByKilocalories() throws {
    var plan = try makePlan([me, partner], amount: .portions(2))
    plan.setGrams(400, of: try #require(plan.base.first).id)  // 600 kcal
    let portions = plan.portions
    let mine = try #require(portions.first { $0.person.id == me.id })
    let hers = try #require(portions.first { $0.person.id == partner.id })
    #expect(abs((mine.nutrients[.kcal] ?? 0) - 720) < 0.5)
    #expect(abs((hers.nutrients[.kcal] ?? 0) - 540) < 0.5)
    #expect(abs(mine.sharePercent - 720.0 / 1_260 * 100) < 0.1)
    #expect(abs(mine.grams - 480) < 0.5)
    #expect(abs(hers.grams - 360) < 0.5)
  }

  /// Ganzes Gericht = Summe aller Teller; die Nährwerte je Teller bleiben beim Hochrechnen gleich.
  @Test func wholeDishEqualsSumOfPlatesAndPortionStaysConstant() throws {
    var two = try makePlan([me, partner], amount: .portions(2))
    var six = try makePlan([me, partner], amount: .portions(6))
    two.setGrams(400, of: try #require(two.base.first).id)
    six.setGrams(400, of: try #require(six.base.first).id)
    #expect(two.portions.map { $0.nutrients } == six.portions.map { $0.nutrients })
    let sum = six.portions.reduce(0) { $0 + Double($1.plates) * ($1.nutrients[.kcal] ?? 0) }
    #expect(abs((six.wholeNutrients[.kcal] ?? 0) - sum) < 0.5)
    #expect(abs((six.wholeNutrients[.kcal] ?? 0) - 3 * (720 + 540)) < 0.5)
    #expect((six.totalIngredients.first?.grams ?? 0) == 2_520)  // 3 × (480 + 360) g
  }

  @Test func personWithoutTargetsGetsBasePortion() throws {
    let open = CookPerson(id: "kkkkkkkkkk", share: CookShare(name: "Mia"))
    let portion = try #require(try makePlan([open], amount: .portions(1)).portions.first)
    #expect(portion.factor == 1)
    #expect(portion.target == nil)
  }

  @Test func noteWhenProteinFallsShort() throws {
    let portion = try #require(try makePlan([me], amount: .portions(1)).portions.first)
    #expect(portion.notes.contains { $0.contains("Protein") })
  }

  // MARK: - Gemeinsame Regeln

  @Test func strictestDietAndAllAllergensApply() {
    #expect(CookPlanner.mergedDiet([me, partner]) == .vegetarian)
    #expect(CookPlanner.mergedAllergens([me, partner]) == [.nuts])
    let result = CookPlanner.plans(
      output: output(recipeJSON(ingredient: "Hähnchenbrust")), people: [me, partner], meal: .dinner,
      amount: .portions(2),
      source: "KI", created: created)
    #expect(result.plans.isEmpty)
    #expect(result.notes.first?.contains("Fleisch") == true)
  }

  @Test func aiInputContainsNoNames() throws {
    let input = CookPlanner.input(
      people: [me, partner], meal: .dinner, amount: .days(2), preferences: RecipePreferences(), favorites: [])
    let text = String(data: try JSONEncoder().encode(JSONValue.object(input)), encoding: .utf8) ?? ""
    #expect(!text.contains("Lena"))
    #expect(text.contains("Person 2"))
    #expect(input["vorkochen"] == .bool(true))
    #expect(input["dislikes"] == .string("Pilze"))
  }

  // MARK: - Vorkochen

  @Test func unsuitableDishIsRejectedForSeveralDays() {
    let result = CookPlanner.plans(
      output: output(recipeJSON(prep: false)), people: [me], meal: .dinner, amount: .days(3), source: "KI",
      created: created)
    #expect(result.plans.isEmpty)
    #expect(result.notes.first?.contains("Vorkochen") == true)
  }

  @Test func singleFreshMealIgnoresStorage() {
    let result = CookPlanner.plans(
      output: output(recipeJSON(prep: false, fridge: 0, freezable: false)), people: [me], meal: .dinner,
      amount: .portions(1), source: "KI", created: created)
    #expect(result.plans.count == 1)
  }

  /// Zwei Personen, zwei Teller: Jede Person isst einmal, also keine Lagerung.
  @Test func portionsEatenTogetherNeedNoStorage() throws {
    #expect(try makePlan([me, partner], amount: .portions(2)).mealsPerPerson == 1)
  }

  @Test func storagePlanFreezesAfterFridgeLimit() {
    #expect(CookPlanner.storagePlan(meals: 3, fridgeDays: 3, freezable: false) == [.fresh, .fridge, .fridge])
    #expect(
      CookPlanner.storagePlan(meals: 6, fridgeDays: 3, freezable: true)
        == [.fresh, .fridge, .fridge, .fridge, .freezer, .freezer])
    #expect(CookPlanner.storagePlan(meals: 5, fridgeDays: 3, freezable: false) == nil)
  }

  /// Sagt die KI 7 Tage, gelten trotzdem höchstens 3.
  @Test func fridgeClaimIsCapped() throws {
    let result = CookPlanner.plans(
      output: output(recipeJSON(fridge: 7, freezable: false)), people: [me], meal: .dinner, amount: .days(5),
      source: "KI",
      created: created)
    #expect(result.plans.isEmpty)
    #expect(result.notes.first?.contains("hält nicht") == true)
  }

  @Test func extremeShelfLifeDoesNotCrash() {
    let result = CookPlanner.plans(
      output: output(recipeJSON(fridge: 1e30)), people: [me], meal: .dinner, amount: .days(2), source: "KI",
      created: created)
    #expect(result.plans.first?.fridgeDays == CookPlanner.maxFridgeDays)
  }

  // MARK: - Bearbeiten

  @Test func editingRecalculatesAndKeepsLastIngredient() throws {
    var plan = try makePlan([me], amount: .portions(1))
    let id = try #require(plan.base.first).id
    plan.remove(itemID: id)
    #expect(plan.base.count == 1)
    plan.setGrams(100, of: id)
    #expect(plan.baseNutrients[.kcal] == 150)
  }

  // MARK: - Freigabe und Datenschutz

  private func week(_ kcal: Double) -> [RecipeDayTarget] {
    [kcal - 200, kcal + 200].enumerated().map { offset, value in
      RecipeDayTarget(
        day: CalendarDay(year: 2026, month: 11, day: 9 + offset), sessions: [], dayType: .restDay, kcal: value,
        protein: 120,
        carbs: 250, fat: 70)
    }
  }

  @Test func shareContainsOnlyReleasedFields() throws {
    var fields = CookShareFields()
    fields.targets = false
    fields.dislikes = false
    let preferences = RecipePreferences(allergens: [.egg], dislikes: "Pilze")
    let share = CookPlanner.share(
      name: " Lena ", week: week(2_000), diet: .vegan, preferences: preferences, fields: fields, safety: .free)
    #expect(share.name == "Lena")
    #expect(share.kcal == nil)
    #expect(share.dislikes.isEmpty)
    #expect(share.allergens == [.egg])
    let json = String(data: try JSONEncoder().encode(share), encoding: .utf8) ?? ""
    #expect(!json.contains("kcal"))
  }

  @Test func shareAveragesWeekTargets() {
    let share = CookPlanner.share(
      name: "A", week: week(2_000), diet: .omnivore, preferences: RecipePreferences(), fields: CookShareFields(),
      safety: .free)
    #expect(share.kcal == 2_000)
    #expect(share.protein == 120)
  }

  /// Schwangerschaft/Stillzeit oder Essstörung: keine Kalorienziele, auch nicht an andere.
  @Test func withheldTargetsAreNeverShared() {
    let share = CookPlanner.share(
      name: "A", week: week(2_000), diet: .omnivore, preferences: RecipePreferences(), fields: CookShareFields(),
      safety: .noTargets)
    #expect(share.kcal == nil)
    #expect(share.protein == nil)
  }

  @Test func unknownValuesDoNotBreakDecoding() throws {
    let data = Data(#"{"name":"A","diet":"neu","allergens":["egg","neu"],"kcal":1800}"#.utf8)
    let share = try JSONDecoder().decode(CookShare.self, from: data)
    #expect(share.diet == nil)
    #expect(share.allergens == [.egg])
    #expect(share.kcal == 1_800)
  }

  @Test func linksCarryOnlyTheCode() throws {
    #expect(CookLink(url: try #require(URL(string: "coach://cook/abcdefghij"))) == .partner("abcdefghij"))
    #expect(CookLink(url: try #require(URL(string: "coach://open/cookShare"))) == .release)
    #expect(CookLink(url: try #require(URL(string: "coach://open/gym"))) == nil)
    #expect(CookLink(url: try #require(URL(string: "coach://meal/abcdefghij"))) == nil)
    #expect(CookPlanner.code(from: "https://w.example/k/abcdefghij") == "abcdefghij")
    #expect(CookPlanner.code(from: " ABCDEFGHIJ ") == "abcdefghij")
    #expect(CookPlanner.code(from: "https://w.example/other/abcdefghij") == nil)
    #expect(CookPlanner.code(from: "kurz") == nil)
  }

  // MARK: - Woche in Teilen und Fehlertexte

  private func days(_ count: Int) -> [RecipeDayTarget] {
    (0..<count).map {
      RecipeDayTarget(
        day: CalendarDay(year: 2026, month: 11, day: 9 + $0), sessions: [], dayType: .restDay, kcal: 2_000,
        protein: 120,
        carbs: 250, fat: 70)
    }
  }

  @Test func weekIsSplitIntoSmallRequests() {
    #expect(RecipePlanner.batches(days(7)).map(\.count) == [2, 2, 2, 1])
    #expect(RecipePlanner.batches(days(2)).map(\.count) == [2])
    #expect(RecipePlanner.batches([]).isEmpty)
    #expect(RecipePlanner.batches(days(7)).flatMap { $0 } == days(7))
  }

  @Test func partialPlansMergeInCalendarOrder() throws {
    let all = days(4)
    let late = WeeklyRecipePlan(
      created: created, days: [RecipeDay(day: all[3].day, recipes: [], scale: 1)], source: "KI · a", notes: ["x"])
    let early = WeeklyRecipePlan(
      created: created, days: [RecipeDay(day: all[0].day, recipes: [], scale: 1)], source: "KI · b", notes: [])
    let merged = try #require(WeeklyRecipePlan.merged([late, early], created: created))
    #expect(merged.days.map(\.day) == [all[0].day, all[3].day])
    #expect(merged.source == "KI · a, KI · b")
    #expect(WeeklyRecipePlan.merged([], created: created) == nil)
  }

  @Test func serverErrorsBecomeReadableButKeepTheCode() {
    let busy = AIErrorText.message(status: 502, code: "ai_unavailable", detail: "Gemini HTTP 503")
    #expect(busy.contains("nicht erreichbar"))
    #expect(busy.contains("502"))
    #expect(!busy.contains("Gemini"))
    #expect(AIErrorText.message(status: 502, code: "ai_invalid", detail: "x").contains("brauchbare"))
    #expect(AIErrorText.message(status: 400, code: nil, detail: "Name fehlt") == "Name fehlt")
    #expect(AIErrorText.isTemporary(status: 503))
    #expect(!AIErrorText.isTemporary(status: 400))
  }

  @Test func cookPlanCountsAsPlanningTask() {
    #expect(AIPolicy.allows(.full, task: "cook_plan", trigger: .user))
  }
}
