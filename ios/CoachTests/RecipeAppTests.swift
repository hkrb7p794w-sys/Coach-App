import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

@MainActor
struct RecipeAppTests {
  /// Mittwoch, 28.10.2026.
  private let wednesday = CalendarDay(year: 2026, month: 10, day: 28)

  private func settings() throws -> CoachSettings {
    let store = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
    let settings = CoachSettings(defaults: store)
    var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run, .strength], goal: .loseWeight)
    profile.schedule.set([SessionSlot(.run, .long)], on: .sunday)
    profile.schedule.set([SessionSlot(.strength, .hard)], on: .tuesday)
    settings.profile = profile
    return settings
  }

  @Test func targetsCoverNextWeekWithTrainingDays() throws {
    let settings = try settings()
    let viewModel = RecipeViewModel(defaults: try #require(UserDefaults(suiteName: "r-\(UUID().uuidString)")), fileURL: nil)
    viewModel.update(settings: settings, garminProfile: nil, meals: [], today: wednesday)
    #expect(viewModel.targets.count == 7)
    #expect(viewModel.targets.first?.day == CalendarDay(year: 2026, month: 11, day: 2))
    #expect(viewModel.targets[1].sessions == ["Krafttraining"])
    let sunday = try #require(viewModel.targets.last)
    #expect(sunday.sessions == ["Langer Lauf"])
    #expect(sunday.dayType > viewModel.targets[0].dayType)
    #expect(sunday.carbs > viewModel.targets[0].carbs)
    #expect(RecipeViewModel.startDay(today: CalendarDay(year: 2026, month: 11, day: 1)) == viewModel.targets.first?.day)
  }

  @Test func gapsComeFromLoggedMeals() throws {
    let settings = try settings()
    var meals: [MealRecord] = []
    for offset in 1...3 {
      let day = wednesday.adding(days: -offset)
      let item = MealItem(name: "Toast", grams: 100, source: .manual, per100g: NutrientValues([.kcal: 260, .fiber: 3]))
      meals.append(MealRecord(day: day, category: .breakfast, title: "A", hint: "", items: [item]))
      meals.append(MealRecord(day: day, category: .lunch, title: "B", hint: "", items: [item]))
    }
    let gaps = RecipeViewModel.gaps(meals: meals, settings: settings, garminProfile: nil, today: wednesday)
    #expect(gaps.contains { $0.hasPrefix("Ballaststoffe: im Schnitt 6 von 30 g") })
  }

  @Test func recipeCanBeLoggedAsMeal() throws {
    let container = CoachSchema.makeContainer(inMemory: true)
    let viewModel = RecipeViewModel(defaults: try #require(UserDefaults(suiteName: "r-\(UUID().uuidString)")), fileURL: nil)
    let recipe = Recipe(
      meal: .dinner, title: "Linsencurry", minutes: 25,
      ingredients: [MealItem(name: "Rote Linsen", grams: 120, source: .ai, per100g: NutrientValues([.kcal: 340]))],
      steps: ["Kochen."])
    viewModel.log(recipe, context: container.mainContext, now: wednesday.localDate)
    let meals = try container.mainContext.fetch(FetchDescriptor<MealRecord>())
    #expect(meals.first?.title == "Linsencurry")
    #expect(meals.first?.category == .dinner)
    #expect(meals.first?.dayKey == wednesday.iso)
  }
}
