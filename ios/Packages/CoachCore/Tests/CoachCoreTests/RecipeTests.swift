import Foundation
import Testing

@testable import CoachCore

/// Montag, 2.11.2026.
private let monday = CalendarDay(year: 2026, month: 11, day: 2)

private func ingredient(_ name: String, grams: Double, kcal: Double, protein: Double = 0) -> JSONValue {
  .object([
    "name": .string(name), "menge_g": .number(grams),
    "naehrwerte_100g": .object(["kcal": .number(kcal), "protein_g": .number(protein)]),
  ])
}

private func dish(_ title: String, meal: String, _ ingredients: [JSONValue]) -> JSONValue {
  .object([
    "titel": .string(title), "mahlzeit": .string(meal), "minuten": .number(15),
    "zubereitung": .array([.string("Alles mischen."), .string("Servieren.")]), "zutaten": .array(ingredients),
  ])
}

private let targets = [
  RecipeDayTarget(
    day: monday, sessions: ["Lockerer Lauf"], dayType: .moderate, kcal: 2000, protein: 120, carbs: 250, fat: 60),
  RecipeDayTarget(
    day: monday.adding(days: 1), sessions: [], dayType: .restDay, kcal: 1800, protein: 120, carbs: 180, fat: 60),
]

struct RecipeRuleTests {
  @Test func dietRules() {
    #expect(RecipePlanner.violations("Hähnchenbrust", diet: .vegetarian, allergens: []) == ["Fleisch"])
    #expect(RecipePlanner.violations("Lachsfilet", diet: .pescetarian, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Lachsfilet", diet: .vegetarian, allergens: []) == ["Fisch"])
    #expect(RecipePlanner.violations("Sojahack", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Hühnerei", diet: .vegan, allergens: []) == ["Ei"])
    #expect(RecipePlanner.violations("Naturreis", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Haferbrei", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Skyr", diet: .vegan, allergens: []) == ["Milchprodukte"])
    #expect(RecipePlanner.violations("Haferdrink", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Sojajoghurt", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Erdnussbutter", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Vegane Bratwurst", diet: .vegan, allergens: []).isEmpty)
    #expect(RecipePlanner.violations("Honig", diet: .vegan, allergens: []) == ["Honig"])
    #expect(RecipePlanner.violations("Rinderhack", diet: .omnivore, allergens: []).isEmpty)
  }

  @Test func allergenRules() {
    #expect(RecipePlanner.violations("Vollkornnudeln", diet: .omnivore, allergens: [.gluten]) == ["Gluten"])
    #expect(RecipePlanner.violations("Buchweizen", diet: .omnivore, allergens: [.gluten]).isEmpty)
    #expect(RecipePlanner.violations("Erdnussbutter", diet: .omnivore, allergens: [.nuts]).isEmpty)
    #expect(RecipePlanner.violations("Erdnussbutter", diet: .omnivore, allergens: [.peanuts]) == ["Erdnüsse"])
    #expect(RecipePlanner.violations("Walnusskerne", diet: .omnivore, allergens: [.nuts]) == ["Schalenfrüchte (Nüsse)"])
    #expect(RecipePlanner.violations("Laktosefreie Milch", diet: .omnivore, allergens: [.lactose]).isEmpty)
    #expect(RecipePlanner.violations("Bergkäse", diet: .omnivore, allergens: [.lactose]) == ["Laktose / Milch"])
    #expect(RecipePlanner.violations("Tofu natur", diet: .vegan, allergens: [.soy]) == ["Soja"])
    #expect(
      RecipePlanner.violations("Garnelen", diet: .omnivore, allergens: [.shellfish]) == ["Krebstiere und Weichtiere"])
    #expect(RecipePlanner.violations("Tahin", diet: .vegan, allergens: [.sesame]) == ["Sesam"])
    #expect(RecipePlanner.violations("Spiegelei", diet: .omnivore, allergens: [.egg]) == ["Ei"])
  }

  @Test func preferencesDecodeTolerantly() throws {
    let decoded = try JSONDecoder().decode(
      RecipePreferences.self, from: Data(#"{"servings":0,"allergens":["gluten"]}"#.utf8))
    #expect(decoded.servings == 1)
    #expect(decoded.allergens == [.gluten])
    #expect(decoded.maxMinutes == 30)
  }
}

struct RecipePlanTests {
  private func output(_ days: [(CalendarDay, [JSONValue])]) -> JSONValue {
    .object([
      "tage": .array(days.map { day, dishes in .object(["datum": .string(day.iso), "gerichte": .array(dishes)]) })
    ])
  }

  @Test func scalesToTargetAndDropsViolations() throws {
    let monday1 = [
      dish("Porridge", meal: "fruehstueck", [ingredient("Haferflocken", grams: 100, kcal: 370, protein: 13)]),
      dish("Linsencurry", meal: "mittagessen", [ingredient("Rote Linsen", grams: 150, kcal: 340, protein: 25)]),
      dish("Hähnchen-Bowl", meal: "abendessen", [ingredient("Hähnchenbrust", grams: 200, kcal: 110, protein: 23)]),
    ]
    let plan = try #require(
      RecipePlanner.plan(
        output: output([(monday, monday1)]), targets: targets, diet: .vegetarian, allergens: [], source: "KI · test",
        created: .now))
    let day = try #require(plan.day(monday))
    #expect(day.recipes.map(\.title) == ["Porridge", "Linsencurry"])
    #expect(plan.notes.contains("„Hähnchen-Bowl“ verworfen: enthält Fleisch."))
    #expect(plan.notes.contains("Dienstag: keine Rezepte erhalten."))
    // 370 + 510 = 880 kcal → höchstens ×1,33 → Hinweis auf Abweichung.
    #expect(day.scale == 1.33)
    #expect(day.recipes.first?.ingredients.first?.grams == 135)
    #expect(plan.notes.contains { $0.hasPrefix("Montag: Rezepte ergeben ca.") })
  }

  @Test func closeEnoughNeedsNoNote() throws {
    let dishes = [
      dish("Frühstück", meal: "fruehstueck", [ingredient("Haferflocken", grams: 200, kcal: 370)]),
      dish("Mittag", meal: "mittagessen", [ingredient("Nudeln", grams: 300, kcal: 350)]),
      dish("Abend", meal: "abendessen", [ingredient("Kartoffeln", grams: 300, kcal: 77)]),
    ]
    let plan = try #require(
      RecipePlanner.plan(
        output: output([(monday, dishes)]), targets: [targets[0]], diet: .omnivore, allergens: [], source: "KI",
        created: .now))
    let day = try #require(plan.days.first)
    let kcal = try #require(day.totals[.kcal])
    #expect(abs(kcal - 2000) / 2000 < 0.05)
    #expect(plan.notes.isEmpty)
  }

  @Test func rejectsEmptyOrBrokenAnswers() {
    #expect(
      RecipePlanner.plan(
        output: .object([:]), targets: targets, diet: .omnivore, allergens: [], source: "", created: .now)
        == nil)
    let noNutrients = dish("Leer", meal: "snack", [.object(["name": .string("Apfel"), "menge_g": .number(150)])])
    #expect(
      RecipePlanner.plan(
        output: output([(monday, [noNutrients])]), targets: targets, diet: .omnivore, allergens: [], source: "",
        created: .now) == nil)
  }

  @Test func shoppingListSumsAcrossWeek() throws {
    let dishes = [
      dish("A", meal: "fruehstueck", [ingredient("Haferflocken", grams: 80, kcal: 370)]),
      dish(
        "B", meal: "snack",
        [ingredient("haferflocken", grams: 40, kcal: 370), ingredient("Banane", grams: 120, kcal: 90)]),
    ]
    let plan = try #require(
      RecipePlanner.plan(
        output: output([(monday, dishes)]),
        targets: [
          RecipeDayTarget(day: monday, sessions: [], dayType: .restDay, kcal: 552, protein: 0, carbs: 0, fat: 0)
        ],
        diet: .omnivore, allergens: [], source: "", created: .now))
    let list = RecipePlanner.shoppingList(plan, servings: 2)
    #expect(list.map(\.name) == ["Banane", "Haferflocken"])
    #expect(list.last?.grams == 240)
  }
}

struct RecipeInputTests {
  @Test func gapsOnlyWithEnoughDays() {
    let targets = NutrientValues([.protein: 120, .fiber: 30, .iron: 15])
    let day = NutrientValues([.protein: 115, .fiber: 18, .iron: 14])
    #expect(RecipePlanner.gaps(dailyTotals: [day, day], targets: targets).isEmpty)
    #expect(
      RecipePlanner.gaps(dailyTotals: [day, day, day], targets: targets) == [
        "Ballaststoffe: im Schnitt 18 von 30 g (60 %)"
      ])
  }

  @Test func inputCarriesTargetsAndPreferences() {
    let preferences = RecipePreferences(allergens: [.peanuts], dislikes: "Pilze", maxMinutes: 20, snacks: false)
    let input = RecipePlanner.input(
      days: targets, preferences: preferences, diet: .vegetarian, goal: "Abnehmen", gaps: ["Eisen"], favorites: ["Skyr"]
    )
    let first = input["days"]?.arrayValue?.first
    #expect(first?["datum"]?.stringValue == "2026-11-02")
    #expect(first?["wochentag"]?.stringValue == "Montag")
    #expect(first?["training"]?.stringValue == "Lockerer Lauf")
    #expect(first?["kcal"]?.doubleValue == 2000)
    #expect(input["days"]?.arrayValue?.last?["training"]?.stringValue == "frei")
    #expect(input["diet"]?.stringValue == "vegetarisch")
    #expect(input["allergens"]?.arrayValue?.first?.stringValue == "Erdnüsse")
    #expect(input["snacks"] == .bool(false))
    #expect(input["evidence"]?.arrayValue?.count == RecipePlanner.evidence.count)
  }
}
