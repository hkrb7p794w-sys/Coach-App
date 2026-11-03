import Foundation
import Testing

@testable import CoachCore

/// Audit CORE1-13: `Int(Double)` stürzt bei sehr großen Zahlen aus KI-Antworten ab (Exit-Tests, Swift 6.2).
/// `GymCoach.validatePlan` ist schon in AuditAIOutputTests abgedeckt; hier Rezepte und Mahlzeiten.
struct AuditCoreCrashTests {
  /// RecipePlan.swift:233 – `Int(value["minuten"]?.doubleValue ?? 0)` mit 1e20.
  @Test func hugeRecipeMinutesDoNotCrash() async {
    await #expect(processExitsWith: .success) {
      let ingredient = JSONValue.object([
        "name": .string("Reis"), "menge_g": .number(100), "naehrwerte_100g": .object(["kcal": .number(350)]),
      ])
      let raw = JSONValue.object([
        "titel": .string("Test"), "minuten": .number(1e20), "zutaten": .array([ingredient]),
      ])
      _ = RecipePlanner.recipe(raw)
    }
  }

  /// QuickLog.swift:36 – die Signatur rechnet `Int(grams / 10)`; `menge_g` der KI ist nach oben nicht begrenzt
  /// (Meal.swift:109).
  @Test func hugeMealAmountDoesNotCrash() async {
    await #expect(processExitsWith: .success) {
      let item = MealItem(name: "Reis", grams: 1e20, source: .ai, per100g: NutrientValues([.kcal: 350]))
      _ = MealSuggestions.signature([item])
    }
  }
}
