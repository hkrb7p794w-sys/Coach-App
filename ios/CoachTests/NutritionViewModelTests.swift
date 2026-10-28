import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

extension StubbedNetworkTests {
  @MainActor
  struct NutritionViewModelTests {
    private func environment() throws -> (ModelContainer, CoachSettings) {
      let defaults = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
      let settings = CoachSettings(defaults: defaults)
      // Diese Tests prüfen die Musterwoche des Saisonplans.
      settings.profile = .seasonPlan
      return (CoachSchema.makeContainer(inMemory: true), settings)
    }

    /// Freitag: laut Musterwoche Push + Pull (Kraft) → leichter Tag.
    private let friday = CalendarDay(year: 2026, month: 10, day: 23).localDate

    @Test func savedMealCountsTowardsTodaysTotals() throws {
      let (container, settings) = try environment()
      let context = container.mainContext
      let viewModel = NutritionViewModel(openFoodFacts: OpenFoodFactsClient(session: StubURLProtocol.session()))
      viewModel.update(meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false, now: friday)

      var per100g = NutrientValues()
      per100g[.kcal] = 360
      per100g[.protein] = 13
      viewModel.save(
        NutritionViewModel.Draft(
          title: "", category: .breakfast, hint: "",
          items: [MealItem(name: "Haferflocken", grams: 80, source: .manual, per100g: per100g)]),
        context: context, foods: [])

      let meals = try context.fetch(FetchDescriptor<MealRecord>())
      let foods = try context.fetch(FetchDescriptor<FoodRecord>())
      #expect(meals.count == 1)
      #expect(meals.first?.title == "Haferflocken")
      #expect(foods.first?.useCount == 1)
      #expect(viewModel.draft == nil)

      viewModel.update(
        meals: meals, activities: [], settings: settings, profile: nil, hasGarminData: false, now: friday)
      #expect(viewModel.totals[.kcal] == 288)
      #expect(viewModel.targets?.dayType == .light)
      #expect(viewModel.targets?.source == .planned)
    }

    @Test func emptyDraftIsRejected() throws {
      let (container, _) = try environment()
      let viewModel = NutritionViewModel()
      viewModel.save(
        NutritionViewModel.Draft(
          title: "", category: .snack, hint: "",
          items: [MealItem(name: " ", grams: 0, source: .manual, per100g: NutrientValues())]),
        context: container.mainContext, foods: [])
      #expect(viewModel.errorMessage != nil)
      #expect(try container.mainContext.fetch(FetchDescriptor<MealRecord>()).isEmpty)
    }

    @Test func barcodeLookupCreatesDraftAndCachesProduct() async throws {
      let (container, _) = try environment()
      StubURLProtocol.install { _ in
        (
          200,
          #"{"status": 1, "product": {"product_name": "Skyr", "serving_quantity": 150, "#
            + #""nutriments": {"energy-kcal_100g": 63}}}"#
        )
      }
      let viewModel = NutritionViewModel(openFoodFacts: OpenFoodFactsClient(session: StubURLProtocol.session()))

      await viewModel.lookup(barcode: "4006381333931", foods: [], context: container.mainContext)

      #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "User-Agent") == OpenFoodFacts.userAgent)
      let item = try #require(viewModel.draft?.items.first)
      #expect(item.name == "Skyr")
      #expect(item.grams == 150)
      #expect(try container.mainContext.fetch(FetchDescriptor<FoodRecord>()).first?.key == "barcode:4006381333931")
    }

    @Test func invalidBarcodeShowsError() async throws {
      let (container, _) = try environment()
      let viewModel = NutritionViewModel()
      await viewModel.lookup(barcode: "123", foods: [], context: container.mainContext)
      #expect(viewModel.errorMessage?.contains("Barcode") == true)
      #expect(viewModel.draft == nil)
    }

    @Test func quickLogOnPickedDayAndUndo() throws {
      let (container, settings) = try environment()
      let context = container.mainContext
      let viewModel = NutritionViewModel()
      viewModel.update(meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false, now: friday)
      // Donnerstag nachtragen.
      let thursday = CalendarDay(year: 2026, month: 10, day: 22)
      viewModel.selectedDay = thursday
      viewModel.log(
        title: "Skyr", category: .snack, items: [.quick(kilocalories: 150, protein: 25)], context: context,
        foods: [], now: friday)
      let meals = try context.fetch(FetchDescriptor<MealRecord>())
      #expect(meals.first?.dayKey == thursday.iso)
      #expect(CalendarDay(date: meals.first?.createdAt ?? .now) == thursday)
      #expect(viewModel.lastLogged?.label == "Skyr eingetragen")
      viewModel.undoLastLog(context: context)
      #expect(try context.fetch(FetchDescriptor<MealRecord>()).isEmpty)

      viewModel.log(
        title: "Wasser", category: .snack, items: [.water(milliliters: 250)], context: context, foods: [], now: friday)
      let water = try context.fetch(FetchDescriptor<MealRecord>())
      #expect(water.first?.isWater == true)
      #expect(NutritionViewModel.entries(water).isEmpty)
    }
  }
}
