import Foundation
import Testing

@testable import CoachCore

struct MealLibraryTests {
  let today = CalendarDay(year: 2026, month: 11, day: 2)

  func item(_ name: String, _ grams: Double, kcal: Double = 200) -> MealItem {
    MealItem(name: name, grams: grams, source: .manual, per100g: NutrientValues([.kcal: kcal, .protein: 10]))
  }

  func entry(_ title: String, _ items: [MealItem], daysAgo: Int, category: MealCategory = .lunch) -> MealEntry {
    let day = today.adding(days: -daysAgo)
    return MealEntry(
      day: day, date: day.referenceDate, category: category, title: title, items: items)
  }

  @Test func portionScalesFromOriginalAndRestores() {
    let meal = [item("Curry", 400), item("Reis", 100)]
    let eaten = MealPortion.adjusted(meal, to: 0.75)
    #expect(eaten.map(\.grams) == [300, 75])
    #expect(eaten.map(\.plannedGrams) == [400, 100])
    #expect(NutritionSummary.totals(eaten)[.kcal] == 750)
    #expect(MealPortion.eatenFraction(eaten) == 0.75)
    #expect(MealPortion.label(eaten) == "75 % von 500 g")
    // Zweite Anpassung rechnet von der ursprünglichen Menge, nicht von 75 %.
    let half = MealPortion.adjusted(eaten, to: 0.5)
    #expect(half.map(\.grams) == [200, 50])
    // 100 % stellt den Ausgangszustand her.
    #expect(MealPortion.adjusted(half, to: 1) == meal)
    #expect(MealPortion.eatenFraction(meal) == 1)
  }

  @Test func recipeAndFavoriteStayUnchanged() {
    let recipe = OwnRecipe(name: "Chili", ingredients: [item("Bohnen", 300), item("Tomaten", 200)], portions: 2)
    let logged = recipe.item()
    let eaten = MealPortion.adjusted([logged], to: 0.5)
    #expect(recipe.ingredients.map(\.grams) == [300, 200])
    #expect(recipe.item().grams == 250)
    #expect(eaten[0].grams == 125)
    // Favorit speichert die ursprüngliche Menge.
    let favorite = FavoriteMeal(title: "Chili", items: eaten)
    #expect(favorite.items[0].grams == 250)
    #expect(favorite.items[0].plannedGrams == nil)
    #expect(MealShortcuts.favorite(for: eaten, in: [favorite])?.id == favorite.id)
  }

  @Test func recentAndFrequent() {
    let bowl = [item("Haferflocken", 60), item("Milch", 200)]
    let pasta = [item("Nudeln", 250)]
    let entries = [
      entry("Porridge", bowl, daysAgo: 0, category: .breakfast),
      entry("Porridge", bowl, daysAgo: 1, category: .breakfast),
      entry("Pasta", pasta, daysAgo: 2),
      entry("Porridge halb", MealPortion.adjusted(bowl, to: 0.5), daysAgo: 3, category: .breakfast),
      entry("Leer", [], daysAgo: 0),
    ]
    let recent = MealShortcuts.recent(entries)
    #expect(recent.map(\.title) == ["Porridge", "Pasta"])
    let frequent = MealShortcuts.frequent(entries, today: today)
    #expect(frequent.map(\.title) == ["Porridge"])
    #expect(frequent.first?.count == 2)
  }

  @Test func oldItemsWithoutPlannedGramsDecode() throws {
    // Gespeicherte Positionen von vor der Portionsanpassung haben kein Feld `plannedGrams`.
    let data = try JSONEncoder().encode(item("Apfel", 150))
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "plannedGrams")
    let decoded = try JSONDecoder().decode(MealItem.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.plannedGrams == nil)
    #expect(decoded.grams == 150)
  }
}
