import Foundation
import Testing

@testable import CoachCore

struct PortionTests {
  @Test func portionsFromTextAndPackaging() throws {
    #expect(PortionGuess.from(amountText: "2 Scheiben", grams: 60) == Portion(name: "Scheibe", grams: 30))
    #expect(PortionGuess.from(amountText: "1 Tasse (200 ml)", grams: 200) == Portion(name: "Tasse", grams: 200))
    #expect(PortionGuess.from(amountText: "zwei Eier", grams: 110) == Portion(name: "Ei", grams: 55))
    #expect(PortionGuess.from(amountText: "150 g", grams: 150) == nil)
    #expect(PortionGuess.from(amountText: "etwas Öl", grams: 10) == nil)
    #expect(PortionGuess.serving(text: "1 Riegel (45 g)", grams: 45) == Portion(name: "Riegel", grams: 45))
    #expect(PortionGuess.serving(text: "45 g", grams: 45) == Portion(name: "Portion", grams: 45))
    #expect(PortionGuess.serving(text: nil, grams: nil) == nil)

    var bread = MealItem(name: "Brot", grams: 60, source: .ai, per100g: NutrientValues([.kcal: 250]))
    bread.portion = Portion(name: "Scheibe", grams: 30)
    #expect(bread.portionCount == 2)
    bread.setPortions(1.5)
    #expect(bread.grams == 45)
    #expect(bread.amountLabel == "1½ × Scheibe (45 g)")
    #expect(bread.scaled(by: 2).grams == 90)
    #expect(PortionGuess.format(0.5) == "½")
    #expect(PortionGuess.format(1.25) == "1,25")
  }

  @Test func missingValuesAndEnergyMismatch() {
    let full = MealItem(name: "A", grams: 100, source: .manual, per100g: NutrientValues([.kcal: 100, .protein: 5]))
    let empty = MealItem(name: "B", grams: 100, source: .manual, per100g: NutrientValues([.kcal: 50]))
    #expect(NutrientCheck.missing(.protein, in: [full, empty]) == 1)
    // Haferflocken: 13 P, 59 KH, 7 F, 10 Ballaststoffe ≈ 371 kcal – passt zu 372.
    let oats = NutrientValues([.kcal: 372, .protein: 13, .carbs: 59, .fat: 7, .fiber: 10])
    #expect(NutrientCheck.energyMismatch(oats) == nil)
    // Tippfehler: 37 statt 372 kcal.
    var typo = oats
    typo[.kcal] = 37
    #expect(NutrientCheck.energyMismatch(typo)?.contains("371") == true)
    #expect(NutrientCheck.energyMismatch(NutrientValues([.kcal: 5, .protein: 0, .carbs: 1, .fat: 0])) == nil)
  }
}

struct NutritionLabelTests {
  @Test func readsLabelAnswer() throws {
    let output = JSONValue.object([
      "name": .string("Proteinriegel Erdnuss"), "portion_name": .string("Riegel"), "portion_g": .number(45),
      "naehrwerte_100g": .object(["kcal": .number(380), "protein_g": .number(33), "fat_g": .number(14)]),
    ])
    let item = try #require(NutritionLabel.item(from: output))
    #expect(item.name == "Proteinriegel Erdnuss")
    #expect(item.grams == 45)
    #expect(item.portion == Portion(name: "Riegel", grams: 45))
    #expect(item.per100g[.protein] == 33)
    #expect(item.source == .manual)
    #expect(NutritionLabel.item(from: .object(["name": .string("x")])) == nil)
  }
}
