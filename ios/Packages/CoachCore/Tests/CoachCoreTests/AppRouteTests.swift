import Foundation
import Testing

@testable import CoachCore

struct AppRouteTests {
  @Test func urlRoundTrip() {
    for route in AppRoute.allCases {
      #expect(AppRoute(url: route.url) == route)
    }
    #expect(AppRoute.logMeal.url.absoluteString == "coach://open/logMeal")
  }

  @Test func foreignLinksAreIgnored() throws {
    let invite = try #require(URL(string: "coach://join?worker=https://x&token=a&league=abcdef"))
    #expect(AppRoute(url: invite) == nil)
    let unknown = try #require(URL(string: "coach://open/somethingNew"))
    #expect(AppRoute(url: unknown) == nil)
    let other = try #require(URL(string: "https://open/logMeal"))
    #expect(AppRoute(url: other) == nil)
  }

  @Test func gymAndAILiveInsideOtherTabs() {
    #expect(AppRoute.startWorkout.tab == .training)
    #expect(AppRoute.gym.tab == .training)
    #expect(AppRoute.startWorkout.opensArea == .gym)
    #expect(AppRoute.aiAnalysis.tab == .today)
    #expect(AppRoute.aiAnalysis.opensArea == .ai)
    #expect(AppRoute.health.tab == .training)
    #expect(AppRoute.health.opensArea == nil)
    #expect(AppRoute.logMeal.tab == .nutrition)
    // Jede Route mit Bereich braucht eine Zielansicht, die sie übernimmt.
    for route in AppRoute.allCases where route.opensArea != nil { #expect(route.hasAction) }
  }

  @Test func quickActionsOnlyOfferWorkingEntries() {
    let all = QuickActions.routes(trainsStrength: true, aiAvailable: true)
    #expect(all == [.startWorkout, .logMeal, .health, .aiAnalysis])
    #expect(QuickActions.routes(trainsStrength: false, aiAvailable: false) == [.logMeal, .health])
    #expect(QuickActions.routes(trainsStrength: true, aiAvailable: true).count <= QuickActions.limit)
  }
}

struct MealWidgetRuleTests {
  @Test func logMealLinkCarriesCategory() throws {
    let url = AppRoute.logMealURL(.lunch)
    #expect(url.absoluteString == "coach://open/logMeal?mahlzeit=mittagessen")
    #expect(AppRoute(url: url) == .logMeal)
    #expect(AppRoute.mealCategory(from: url) == .lunch)
    #expect(AppRoute.mealCategory(from: AppRoute.logMeal.url) == nil)
  }

  @Test func hydrationCountsDrinksAndFoodWater() {
    var coffee = MealItem(name: "Kaffee", grams: 250, source: .bls, per100g: NutrientValues([.water: 98]))
    coffee.isDrink = true
    var juice = MealItem(name: "Saft", grams: 200, source: .ai, per100g: NutrientValues([.kcal: 45]))
    juice.isDrink = true
    let soup = MealItem(name: "Suppe", grams: 300, source: .bls, per100g: NutrientValues([.water: 90]))
    let bread = MealItem(name: "Brot", grams: 50, source: .manual, per100g: NutrientValues([.kcal: 250]))
    let total = Hydration.total([coffee, juice, soup, bread, .water(milliliters: 500)])
    #expect(total.drinks == 245 + 200 + 500)
    #expect(total.food == 270)
    #expect(total.total == 1215)
  }

  @Test func mealSplitSumsToDay() {
    let sum = MealSplit.order.compactMap { MealSplit.target($0, dayKilocalories: 2000) }.reduce(0, +)
    #expect(sum == 2000)
    #expect(MealSplit.target(.other, dayKilocalories: 2000) == 200)
    #expect(MealSplit.target(.lunch, dayKilocalories: nil) == nil)
    let nutrition = WidgetSnapshot.nutrition(
      targets: NutrientValues([.kcal: 2000]), totals: NutrientValues(), water: 0, lastMeal: nil,
      mealKilocalories: [.breakfast: 420.4])
    #expect(nutrition.meals?.first?.kcal == 420)
    #expect(nutrition.meals?.first?.target == 500)
    #expect(nutrition.meals?.map(\.category) == [.breakfast, .lunch, .dinner, .snack])
  }
}
