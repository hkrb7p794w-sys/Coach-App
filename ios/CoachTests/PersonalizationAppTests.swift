import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

extension StubbedNetworkTests {
  @MainActor
  struct PersonalizationAppTests {
    /// Freitag, 23.10.2026.
    private let friday = CalendarDay(year: 2026, month: 10, day: 23)

    private func defaults() throws -> UserDefaults {
      try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
    }

    private func personalSettings(_ store: UserDefaults) -> CoachSettings {
      let settings = CoachSettings(defaults: store)
      var profile = UserProfile(
        mode: .personal, onboardingDone: true, sports: [.run, .strength], goal: .loseWeight)
      profile.schedule.set([SessionSlot(.run, .hard)], on: .friday)
      profile.schedule.set([SessionSlot(.strength, .hard)], on: .saturday)
      settings.profile = profile
      return settings
    }

    @Test func freshInstallStartsWithTheAssistant() throws {
      let settings = CoachSettings(defaults: try defaults())
      #expect(settings.profile.mode == .personal)
      #expect(!settings.profile.onboardingDone)
    }

    @Test func existingUsersKeepTheSeasonPlan() throws {
      let store = try defaults()
      store.set(Date.now, forKey: GarminSyncService.lastSyncKey)
      let settings = CoachSettings(defaults: store)
      #expect(settings.profile.mode == .season)
      #expect(settings.profile.onboardingDone)
      // Auch nach dem Neustart.
      #expect(CoachSettings(defaults: store).profile.mode == .season)
    }

    @Test func profilePersists() throws {
      let store = try defaults()
      let settings = personalSettings(store)
      let reloaded = CoachSettings(defaults: store)
      #expect(reloaded.profile == settings.profile)
      #expect(reloaded.profile.schedule.slots(on: .friday) == [SessionSlot(.run, .hard)])
    }

    @Test func goalShapesNutritionOnlyForPersonalProfiles() throws {
      let store = try defaults()
      let settings = personalSettings(store)
      settings.nutrition.weightKilograms = 68
      settings.nutrition.heightCentimeters = 168
      settings.nutrition.age = 32
      settings.nutrition.isFemale = true
      let assessment = settings.applyProfileToNutrition(garmin: nil, day: friday)
      #expect(assessment.nutritionGoal == .lose)
      #expect(settings.nutrition.goal == .lose)
      #expect(settings.nutrition.weeklyWeightChangePercent == -0.5)

      // Saisonplan: Ernährung bleibt unberührt.
      let season = CoachSettings(defaults: try defaults())
      season.profile = .seasonPlan
      season.applyProfileToNutrition(garmin: nil, day: friday)
      #expect(season.nutrition.weeklyWeightChangePercent == nil)
    }

    @Test func nutritionUsesTheOwnWeekPlan() throws {
      let settings = personalSettings(try defaults())
      let viewModel = NutritionViewModel()
      // Freitag: harter Lauf geplant → harter Tag, noch keine Aktivität.
      viewModel.update(
        meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false, now: friday.localDate)
      #expect(viewModel.targets?.dayType == .hard)
      #expect(viewModel.targets?.source == .planned)
      // Samstag: Krafttraining → leichter Tag. Sonntag: nichts geplant.
      viewModel.update(
        meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false,
        now: friday.adding(days: 1).localDate)
      #expect(viewModel.targets?.dayType == .light)
      viewModel.update(
        meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false,
        now: friday.adding(days: 2).localDate)
      #expect(viewModel.targets?.dayType == .restDay)
    }

    @Test func todayAdvisesFromTheOwnPlanAndRecovery() throws {
      let store = try defaults()
      let settings = personalSettings(store)
      let viewModel = TodayViewModel(defaults: store)
      var metrics = DailyMetrics(day: friday)
      metrics.restingHeartRate = 60
      metrics.hrvStatus = "LOW"
      let history = [metrics] + (1...7).map { offset -> DailyMetrics in
        var day = DailyMetrics(day: friday.adding(days: -offset))
        day.restingHeartRate = 50
        return day
      }
      viewModel.update(days: history, activities: [], settings: settings, now: friday.localDate)
      let advice = try #require(viewModel.snapshot?.advice)
      #expect(advice.mode == .rest)
      // Samstag ist als Nächstes belegt, Sonntag frei: dorthin verschieben.
      #expect(advice.move == .sunday)
      #expect(advice.plannedTitles == ["Qualitätslauf (Tempo oder Intervalle)"])
    }

    @Test func seasonProfilesGetNoPersonalAdvice() throws {
      let store = try defaults()
      let settings = CoachSettings(defaults: store)
      settings.profile = .seasonPlan
      let viewModel = TodayViewModel(defaults: store)
      viewModel.update(days: [], activities: [], settings: settings, now: friday.localDate)
      #expect(viewModel.snapshot?.advice == nil)
    }

    @Test func trainedTodayIsRecognised() throws {
      let store = try defaults()
      let settings = personalSettings(store)
      let viewModel = TodayViewModel(defaults: store)
      var run = GarminActivity(id: 1)
      run.typeKey = "running"
      run.startLocal = "2026-10-23 07:00:00"
      run.durationSeconds = 2_400
      viewModel.update(days: [], activities: [run], settings: settings, now: friday.localDate)
      #expect(viewModel.snapshot?.advice?.mode == .done)
    }
  }
}
