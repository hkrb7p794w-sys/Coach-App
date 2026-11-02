import Foundation
import Testing

@testable import CoachCore

struct MealAmendTests {
  func item(_ name: String, _ grams: Double, kcal: Double) -> JSONValue {
    .object([
      "name": .string(name), "menge_g": .number(grams), "sicherheit": .string("mittel"),
      "naehrwerte_100g": .object(["kcal": .number(kcal), "protein_g": .number(20)]),
    ])
  }

  @Test func analysisReadsPossiblyMissing() throws {
    let output: JSONValue = .object([
      "titel": .string("Reis mit Gemüse"), "items": .array([item("Reis gekocht", 200, kcal: 130)]),
      "vielleicht_vergessen": .array([.string("Bratöl"), .string("Soße"), .string(""), .number(3)]),
    ])
    let analysis = try #require(MealAnalysis(output: output))
    #expect(analysis.possiblyMissing == ["Bratöl", "Soße"])
  }

  @Test func amendmentAddsOnlyNewItems() {
    let existing = [MealItem(name: "Reis", grams: 200, source: .ai, per100g: NutrientValues([.kcal: 130]))]
    let output: JSONValue = .object([
      "items": .array([item("Hähnchenbrust", 150, kcal: 110), item("Olivenöl", 10, kcal: 884)]),
      "hinweis": .string(""),
    ])
    let amendment = MealAnalysis.amendment(from: output)
    #expect(amendment.items.map(\.name) == ["Hähnchenbrust", "Olivenöl"])
    let combined = existing + amendment.items
    // Bestehende Position unverändert, Summe neu: 260 + Hähnchen (BLS oder 165) + Öl (BLS oder 88,4).
    #expect(combined[0] == existing[0])
    #expect((NutritionSummary.totals(combined)[.kcal] ?? 0) > 260 + 150)
    #expect(amendment.items.allSatisfy { $0.source == .ai || $0.source == .bls })
    // Leere Ergänzung bleibt leer (kein Fehler, kein Überschreiben).
    let empty = MealAnalysis.amendment(from: .object(["items": .array([]), "hinweis": .string("Unklar")]))
    #expect(empty.items.isEmpty)
    #expect(empty.hint == "Unklar")
  }

  @Test func amendIsCaptureTask() {
    #expect(AIPolicy.kind(of: "meal_amend") == .capture)
    #expect(AIPolicy.allows(.captureOnly, task: "meal_amend", trigger: .user))
  }
}
