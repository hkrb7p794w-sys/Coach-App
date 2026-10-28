import Foundation
import Testing

@testable import CoachCore

struct QuickLogTests {
  let today = CalendarDay(year: 2026, month: 10, day: 28)

  func item(_ name: String, _ grams: Double, kcal: Double = 100) -> MealItem {
    MealItem(name: name, grams: grams, source: .manual, per100g: NutrientValues([.kcal: kcal, .protein: 10]))
  }

  func entry(_ daysAgo: Int, _ category: MealCategory, _ items: [MealItem], title: String = "x") -> MealEntry {
    let day = today.adding(days: -daysAgo)
    return MealEntry(
      day: day, date: Date(timeIntervalSince1970: Double(1_000_000 - daysAgo * 86_400)), category: category,
      title: title, items: items)
  }

  @Test func frequentMealsByCategory() {
    let oats = [item("Haferflocken", 60), item("Milch", 200)]
    let skyr = [item("Skyr", 250)]
    let entries = [
      entry(1, .breakfast, oats, title: "Porridge"),
      entry(2, .breakfast, [item("Milch", 198), item("Haferflocken", 58)]),
      entry(3, .breakfast, skyr), entry(4, .lunch, skyr), entry(90, .breakfast, skyr),
    ]
    let result = MealSuggestions.frequent(entries, category: .breakfast, today: today)
    #expect(result.map(\.count) == [2, 1])
    #expect(result.first?.title == "Porridge")
    #expect(result.first?.kilocalories == 260)

    // Heute schon Porridge gegessen: nicht noch einmal vorschlagen.
    let withToday = entries + [entry(0, .breakfast, oats)]
    #expect(MealSuggestions.frequent(withToday, category: .breakfast, today: today).map(\.count) == [1])
    #expect(MealSuggestions.yesterday(entries, category: .breakfast, today: today).first?.title == "Porridge")
    #expect(MealSuggestions.yesterday(entries, category: .dinner, today: today).isEmpty)
  }

  @Test func searchFindsUmlautsAndRanksPrefixFirst() {
    let now = Date(timeIntervalSince1970: 0)
    let candidates = [
      FoodSearch.Candidate(id: "1", title: "Bircher Müsli", useCount: 9, lastUsed: now),
      FoodSearch.Candidate(id: "2", title: "Müsliriegel", useCount: 1, lastUsed: now),
      FoodSearch.Candidate(id: "3", title: "Skyr Natur", useCount: 20, lastUsed: now),
    ]
    #expect(FoodSearch.rank(candidates, query: "muesli").map(\.id) == ["2", "1"])
    #expect(FoodSearch.rank(candidates, query: "MÜSLI birch").map(\.id) == ["1"])
    #expect(FoodSearch.rank(candidates, query: " ").isEmpty)
  }

  @Test func budgetLinesAndQuickItems() throws {
    let targets = NutrientValues([.kcal: 2_600, .protein: 140, .sugar: 50])
    let totals = NutrientValues([.kcal: 1_450, .protein: 160, .sugar: 60])
    let kcal = try #require(NutritionBudget.line(.kcal, targets: targets, totals: totals))
    #expect(kcal.remaining == 1_150)
    #expect(!kcal.isOver)
    let protein = try #require(NutritionBudget.line(.protein, targets: targets, totals: totals))
    #expect(NutritionBudget.remainingText(protein) == "20 g drüber")
    #expect(!protein.isOver)
    #expect(NutritionBudget.line(.sugar, targets: targets, totals: totals)?.isOver == true)
    #expect(NutritionBudget.line(.fat, targets: targets, totals: totals) == nil)

    let quick = MealItem.quick(kilocalories: 800, protein: 40)
    #expect(quick.amounts[.kcal] == 800)
    #expect(quick.amounts[.protein] == 40)
    #expect(quick.amounts[.fat] == nil)
    #expect(quick.isQuickEstimate)
    #expect(MealItem.water(milliliters: 250).amounts[.water] == 250)
  }
}
