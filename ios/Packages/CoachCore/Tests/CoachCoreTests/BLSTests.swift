import Foundation
import Testing

@testable import CoachCore

struct BLSTests {
  @Test func tableLoads() throws {
    #expect(BLS.foods.count > 7_000)
    let oats = try #require(BLS.food(code: "C133000"))
    #expect(oats.name == "Hafer Flocken")
    #expect(oats.per100g[.kcal] == 348)
    #expect(oats.per100g[.protein] == 13.22)
    #expect(oats.per100g[.vitaminC] == nil)
  }

  @Test(arguments: [
    ("Hühnerei gekocht", "E111132"), ("Eier gekocht", "E111132"), ("Haferflocken", "C133000"),
    ("Möhren gekocht", "G620132"), ("Karotte", "G620100"), ("Erdnüsse", "H110600"), ("Walnüsse", "H120100"),
    ("Kartoffeln gekocht", "K110132"), ("Nudeln gekocht", "E401032"), ("Reis poliert, gekocht", "C352032"),
    ("Vollmilch 3,5 % Fett", "M111300"), ("Kaffee mit Milch", "N410200"), ("Butter", "Q611000"),
    ("Pilsner Bier", "P163000"), ("Weizenbrötchen", "B511000"), ("Apfel", "F110100"), ("Tomaten", "G561100"),
  ])
  func matchesSearchTerm(term: String, code: String) {
    #expect(BLS.match(term)?.code == code, "\(term) → \(BLS.match(term)?.name ?? "nil")")
  }

  @Test(arguments: ["Brötchen", "Bier", "Müsli", "Cola", "Rührei", "", "x"])
  func keepsEstimateWhenUnclear(term: String) {
    #expect(BLS.match(term) == nil, "\(term) → \(BLS.match(term)?.name ?? "nil")")
  }

  @Test func specialProductsNeedToBeNamed() {
    #expect(BLS.match("Butter")?.name.contains("gesalzen") == false)
    #expect(BLS.match("Butter gesalzen")?.code == "Q6A4000")
    #expect(BLS.match("Teigwaren glutenfrei gekocht")?.code == "E612032")
  }

  @Test func enrichReplacesEstimateKeepsMissing() throws {
    var item = MealItem(
      name: "Haferflocken", grams: 50, source: .ai,
      per100g: NutrientValues([.kcal: 370, .protein: 12, .vitaminC: 1]))
    item.searchTerm = "Haferflocken"
    let enriched = BLS.enrich(item)
    #expect(enriched.source == .bls)
    #expect(enriched.blsCode == "C133000")
    #expect(enriched.name == "Haferflocken")
    #expect(enriched.per100g[.kcal] == 348)
    #expect(enriched.per100g[.vitaminC] == 1)
    #expect(enriched.amounts[.kcal] == 174)

    let other = try #require(BLS.food(code: "E111132"))
    let switched = BLS.apply(other, to: enriched)
    #expect(switched.per100g[.vitaminC] == other.per100g[.vitaminC])
    #expect(switched.blsCode == "E111132")
  }

  @Test func otherSourcesStay() {
    let manual = MealItem(name: "Haferflocken", grams: 50, source: .manual, per100g: NutrientValues([.kcal: 1]))
    #expect(BLS.enrich(manual) == manual)
    var unknown = MealItem(name: "Omas Spezialkuchen", grams: 100, source: .ai, per100g: NutrientValues([.kcal: 300]))
    unknown.searchTerm = "Spezialkuchen"
    #expect(BLS.enrich(unknown).source == .ai)
  }

  @Test func searchFindsBasicsFirst() {
    let results = BLS.search("hafer")
    #expect(!results.isEmpty)
    #expect(results.first?.name.hasPrefix("Hafer") == true)
    #expect(results.contains { $0.code == "C133000" })
    #expect(BLS.search("x").isEmpty)
    #expect(BLS.search("apfel roh").first?.code == "F110100")
  }

  @Test func parsesTable() {
    let foods = BLS.parse("# Kommentar\ncode\tname\tkcal\tprotein_g\tunbekannt\nA1\tTest\t100\t\t5\n\nkaputt\n")
    #expect(foods.count == 1)
    #expect(foods[0].per100g[.kcal] == 100)
    #expect(foods[0].per100g[.protein] == nil)
  }

  @Test func drinksAreDetected() throws {
    #expect(try #require(BLS.food(code: "N410100")).item().isDrink)
    #expect(try #require(BLS.food(code: "C133000")).item().isDrink == false)
  }
}
