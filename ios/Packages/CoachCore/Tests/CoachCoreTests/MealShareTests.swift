import Foundation
import Testing

@testable import CoachCore

struct MealShareTests {
  @Test func roundTripKeepsAmountsAndNutrients() throws {
    var rice = MealItem(name: "Reis", grams: 200, source: .bls, per100g: NutrientValues([.kcal: 130, .protein: 2.7]))
    rice.amountText = "1 Portion"
    let chicken = MealItem(name: "Hähnchen", grams: 150, source: .ai, per100g: NutrientValues([.kcal: 110]))
    // Nur 50 % gegessen – geteilt wird die ganze Mahlzeit.
    let eaten = MealPortion.adjusted([rice, chicken], to: 0.5)
    let shared = SharedMeal(title: "Reis mit Hähnchen", items: eaten)
    let decoded = try JSONDecoder().decode(SharedMeal.self, from: JSONEncoder().encode(shared))
    let items = decoded.mealItems
    #expect(items.map(\.grams) == [200, 150])
    #expect(items[0].source == .bls)
    #expect(items[0].per100g[.protein] == 2.7)
    #expect(items[0].amountText == "1 Portion")
    #expect(items.allSatisfy { $0.plannedGrams == nil })
    #expect(Set(items.map(\.id)).isDisjoint(with: Set(eaten.map(\.id))))
    #expect(decoded.kilocalories == 425)
  }

  @Test func unknownSourcesAndNutrientsAreDropped() throws {
    let json =
      #"{"title": "X", "items": [{"name": "A", "grams": 10, "isDrink": false, "source": "fremd", "#
      + #""per100g": {"kcal": 50, "zauber": 1}}]}"#
    let meal = try JSONDecoder().decode(SharedMeal.self, from: Data(json.utf8))
    #expect(meal.mealItems[0].source == .manual)
    #expect(meal.mealItems[0].per100g.values.count == 1)
  }

  @Test func codesFromLinksAndText() {
    #expect(MealShare.code(from: "coach://meal/abcdefgh23") == "abcdefgh23")
    #expect(MealShare.code(from: "https://coach-ai.example.workers.dev/m/abcdefgh23") == "abcdefgh23")
    #expect(MealShare.code(from: "  ABCDEFGH23 ") == "abcdefgh23")
    #expect(MealShare.code(from: "coach://join?code=x") == nil)
    #expect(MealShare.code(from: "abc") == nil)
    let text = MealShare.message(
      title: "Bowl", kilocalories: 512.4, link: URL(string: "https://w.dev/m/abcdefgh23"), code: "abcdefgh23")
    #expect(text.contains("512 kcal"))
    #expect(text.contains("https://w.dev/m/abcdefgh23"))
  }
}
