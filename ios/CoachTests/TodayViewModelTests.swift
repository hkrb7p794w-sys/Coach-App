import CoachCore
import Foundation
import Testing

@testable import Coach

@MainActor
struct TodayViewModelTests {
  private let now = CalendarDay(year: 2026, month: 10, day: 23).localDate

  private func defaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
  }

  private func metrics(_ offset: Int, rhr: Double, hrv: String? = nil) -> DailyMetrics {
    var metrics = DailyMetrics(day: CalendarDay(date: now).adding(days: -offset))
    metrics.restingHeartRate = rhr
    metrics.hrvStatus = hrv
    return metrics
  }

  @Test func evaluatesTodayAgainstSevenDayAverage() throws {
    let store = try defaults()
    let viewModel = TodayViewModel(defaults: store)
    let history = [metrics(0, rhr: 58, hrv: "BALANCED")] + (1...7).map { metrics($0, rhr: 50) }

    viewModel.update(days: history, activities: [], settings: CoachSettings(defaults: store), now: now)

    let snapshot = try #require(viewModel.snapshot)
    #expect(!snapshot.isFromYesterday)
    #expect(snapshot.recommendation.level == .locker)
    #expect(snapshot.plan.weekday == "Freitag")
    // Ohne KI-Worker steht die regelbasierte Notiz da.
    #expect(viewModel.notePoints.first?.hasPrefix("Locker / verkürzt") == true)
  }

  @Test func fallsBackToYesterday() throws {
    let store = try defaults()
    let viewModel = TodayViewModel(defaults: store)

    viewModel.update(
      days: [metrics(1, rhr: 50, hrv: "LOW")], activities: [], settings: CoachSettings(defaults: store), now: now)

    #expect(viewModel.snapshot?.isFromYesterday == true)
    #expect(viewModel.snapshot?.recommendation.level == .pause)
  }

  @Test func settingsPersist() throws {
    let store = try defaults()
    let settings = CoachSettings(defaults: store)
    settings.season.ftpWatts = 205
    settings.privacy = .full

    let reloaded = CoachSettings(defaults: store)
    #expect(reloaded.season.ftpWatts == 205)
    #expect(reloaded.privacy == .full)
  }
}
