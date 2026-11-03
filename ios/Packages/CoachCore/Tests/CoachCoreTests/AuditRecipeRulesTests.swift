import Foundation
import Testing

@testable import CoachCore

/// Audit CORE1-09/10: Ernährungsweise- und Allergenprüfung der KI-Rezepte (RecipePlan.swift:344–392).
struct AuditRecipeRulesTests {
  /// „vegetarisch“ im Namen schaltet für VEGANE Ernährung die Ei-/Milchprüfung ab (Zeile 347–361).
  /// Erwartet „Milchprodukte“; tatsächlich keine Verletzung.
  @Test func vegetarianLabelIsNotVeganSafe() {
    let problems = RecipePlanner.violations("Vegetarische Käse-Lasagne", diet: .vegan, allergens: [])
    #expect(problems.contains("Milchprodukte"))
  }

  /// „Hühner…“ trifft keines der Fleisch-Stichwörter („huhn“, „hühnchen“, Zeile 266–269).
  @Test func chickenStockIsMeat() {
    #expect(RecipePlanner.violations("Hühnerbrühe", diet: .vegetarian, allergens: []).contains("Fleisch"))
    #expect(RecipePlanner.violations("Hühnerbrust", diet: .pescetarian, allergens: []).contains("Fleisch"))
  }

  /// `isEgg` erkennt „Eischnee“ nicht (Zeile 330–335) – das Allergen Ei wird übersehen.
  @Test func beatenEggWhiteIsEgg() {
    #expect(RecipePlanner.violations("Eischnee", diet: .omnivore, allergens: [.egg]).contains("Ei"))
  }
}
