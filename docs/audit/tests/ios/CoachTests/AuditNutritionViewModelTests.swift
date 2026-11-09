import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

// Audit IOS2: Befunde IOS2-01 (Mahlzeit nach Mitternacht landet am Vortag) und IOS2-05 (Offline-Warteschlange
// verliert den Zeitpunkt). Beide Tests schlagen mit dem Stand 8baa407 fehl.
extension StubbedNetworkTests {
  @MainActor
  struct AuditNutritionViewModelTests {
    private let friday = CalendarDay(year: 2026, month: 10, day: 23).localDate

    private func environment() throws -> (ModelContainer, CoachSettings) {
      let defaults = try #require(UserDefaults(suiteName: "audit-\(UUID().uuidString)"))
      let settings = CoachSettings(defaults: defaults)
      settings.profile = .seasonPlan
      return (CoachSchema.makeContainer(inMemory: true), settings)
    }

    /// Ansicht zuletzt am Freitag 23:50 aktualisiert (`update`), eingetragen wird Samstag 00:10 – ohne dass sich
    /// dazwischen `refreshKey` ändert. Die Mahlzeit gehört zu Samstag.
    @Test func quickLogAfterMidnightBelongsToNewDay() throws {
      let (container, settings) = try environment()
      let context = container.mainContext
      let viewModel = NutritionViewModel()
      let lateFriday = friday.addingTimeInterval(23 * 3_600 + 50 * 60)
      let earlySaturday = friday.addingTimeInterval(24 * 3_600 + 10 * 60)
      viewModel.update(
        meals: [], activities: [], settings: settings, profile: nil, hasGarminData: false, now: lateFriday)

      viewModel.log(
        title: "Skyr", category: .snack, items: [.quick(kilocalories: 150, protein: 25)], context: context,
        foods: [], now: earlySaturday)

      let meal = try #require(try context.fetch(FetchDescriptor<MealRecord>()).first)
      #expect(meal.dayKey == CalendarDay(year: 2026, month: 10, day: 24).iso)
      #expect(CalendarDay(date: meal.createdAt).iso == meal.dayKey)
    }

    /// Ohne Netz am Donnerstag fotografiert, erst später ausgewertet: Der Entwurf muss den ursprünglichen Zeitpunkt
    /// tragen, sonst landet die Mahlzeit am Tag der Auswertung.
    @Test func pendingAnalysisKeepsOriginalTime() async throws {
      let standard = UserDefaults.standard
      let saved = standard.data(forKey: PendingAnalysis.key)
      defer {
        if let saved { standard.set(saved, forKey: PendingAnalysis.key) } else {
          standard.removeObject(forKey: PendingAnalysis.key)
        }
      }
      let thursday = CalendarDay(year: 2026, month: 10, day: 22)
      var pending = PendingAnalysis(text: "Spaghetti Bolognese", photo: nil)
      pending.created = thursday.localDate.addingTimeInterval(12 * 3_600)
      PendingAnalysis.save([pending])

      let (_, settings) = try environment()
      let store = try #require(UserDefaults(suiteName: "audit-ai-\(UUID().uuidString)"))
      let ai = AIClient(secrets: InMemorySecretStore(), defaults: store, session: StubURLProtocol.session())
      try ai.configure(url: "https://coach-ai.example.workers.dev", token: "t")
      StubURLProtocol.install { _ in
        (
          200,
          #"{"output": {"titel": "Spaghetti", "items": [{"name": "Spaghetti", "menge_g": 250}]}, "#
            + #""model": "m", "provider": "gemini"}"#
        )
      }
      let viewModel = NutritionViewModel()
      #expect(viewModel.pending.count == 1)

      await viewModel.retryPending(ai: ai, settings: settings, foods: [])

      let draft = try #require(viewModel.draft)
      #expect(draft.date.map { CalendarDay(date: $0) } == thursday)
    }
  }
}
