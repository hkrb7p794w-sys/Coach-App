import Foundation
import Testing

@testable import CoachCore

struct MealPlanningTests {
  let today = CalendarDay(year: 2026, month: 10, day: 28)

  func ingredient(_ name: String, _ grams: Double, kcal: Double, protein: Double = 10) -> JSONValue {
    .object([
      "name": .string(name), "menge_g": .number(grams),
      "naehrwerte_100g": .object(["kcal": .number(kcal), "protein_g": .number(protein)]),
    ])
  }

  @Test func mealNowScalesAndFilters() throws {
    #expect(MealNow.targetKilocalories(remaining: 1_400) == 900)
    #expect(MealNow.targetKilocalories(remaining: 500) == 500)
    #expect(MealNow.targetKilocalories(remaining: 100) == nil)

    let output = JSONValue.object([
      "gerichte": .array([
        .object([
          "titel": .string("Linsen-Bowl"), "mahlzeit": .string("abendessen"),
          "zutaten": .array([ingredient("Linsen", 100, kcal: 300), ingredient("Spinat", 100, kcal: 20)]),
        ]),
        .object([
          "titel": .string("Hähnchen-Reis"), "mahlzeit": .string("abendessen"),
          "zutaten": .array([ingredient("Hähnchenbrust", 150, kcal: 110, protein: 23)]),
        ]),
      ])
    ])
    let result = MealNow.suggestions(output: output, targetKilocalories: 480, diet: .vegetarian, allergens: [])
    #expect(result.recipes.map(\.title) == ["Linsen-Bowl"])
    #expect(result.notes.first?.contains("Hähnchen-Reis") == true)
    // 320 kcal → 480 kcal: Faktor 1,5, auf 5 g gerundet.
    #expect(result.recipes.first?.ingredients.map(\.grams) == [150, 150])

    let input = MealNow.input(
      remaining: NutrientValues([.kcal: 1_800, .protein: 90]), category: .dinner, diet: .vegetarian,
      preferences: RecipePreferences(), pantry: ["Linsen"], favorites: [])
    #expect(input["kcal"] == .number(900))
    #expect(input["protein_g"] == .number(45))
    #expect(input["pantry"] == .array([.string("Linsen")]))
  }

  @Test func ownRecipePortionsAndStock() {
    let rice = MealItem(name: "Reis", grams: 400, source: .manual, per100g: NutrientValues([.kcal: 350]))
    let beans = MealItem(name: "Bohnen", grams: 400, source: .manual, per100g: NutrientValues([.kcal: 100]))
    var chili = OwnRecipe(
      name: "Chili", ingredients: [rice, beans], cookedGrams: 2_000, portions: 4, remainingPortions: 4)
    #expect(chili.totals[.kcal] == 1_800)
    let portion = chili.item()
    #expect(portion.grams == 500)
    #expect(portion.amounts[.kcal] == 450)
    #expect(portion.portion == Portion(name: "Portion", grams: 500))
    #expect(chili.item(grams: 350).amounts[.kcal] == 315)
    chili.consume(grams: 750)
    #expect(chili.remainingPortions == 2.5)
  }

  @Test func weekSummaryCountsLoggedDaysOnly() {
    let monday = CalendarDay(year: 2026, month: 10, day: 26)
    let food = MealItem(name: "x", grams: 100, source: .manual, per100g: NutrientValues([.kcal: 2_000, .protein: 100]))
    let entries = [
      MealEntry(day: monday, date: .now, category: .lunch, title: "x", items: [food]),
      MealEntry(day: monday.adding(days: 1), date: .now, category: .lunch, title: "x", items: [food.scaled(by: 1.2)]),
    ]
    let targets = [monday: NutrientValues([.kcal: 2_200]), monday.adding(days: 1): NutrientValues([.kcal: 2_600])]
    let summary = NutritionWeek.summary(
      entries: entries, monday: monday, targets: targets, trainedDays: [monday], today: today)
    #expect(summary.days.count == 3)
    #expect(summary.days[0].trained)
    #expect(summary.days[2].logged == false)
    #expect(summary.averageKilocalories == 2_200)
    #expect(summary.averageTargetKilocalories == 2_400)
    #expect(summary.averageProtein == 110)
  }

  @Test func aislesAndEveningReminder() {
    #expect(ShoppingAisle.of(name: "Spinat", group: "gemuese") == .produce)
    #expect(ShoppingAisle.of(name: "Vollkornbrot", group: "vollkorn") == .bakery)
    #expect(ShoppingAisle.of(name: "Olivenöl", group: nil) == .spices)
    #expect(ShoppingAisle.of(name: "Skyr", group: "milch") == .cooled)
    #expect(ShoppingAisle.of(name: "Irgendwas", group: nil) == .other)

    let notes = ReminderPlanner.nutritionReview(today: today, minutesNow: 21 * 60, days: 3)
    #expect(notes.map(\.day) == [today.adding(days: 1), today.adding(days: 2)])
    #expect(notes.first?.hour == 20)
    #expect(notes.first?.kind == .nutritionReview)
  }
}
