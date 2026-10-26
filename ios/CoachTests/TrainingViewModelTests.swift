import CoachCore
import Foundation
import Testing

@testable import Coach

@MainActor
struct TrainingViewModelTests {
  private let now = CalendarDay(year: 2026, month: 10, day: 22).localDate

  @Test func buildsTrendsTilesAndZones() {
    let today = CalendarDay(date: now)
    let days = (0..<10).map { offset -> DailyMetrics in
      var metrics = DailyMetrics(day: today.adding(days: -offset))
      metrics.restingHeartRate = 50
      metrics.hrvWeeklyAverage = 60
      metrics.spo2Average = 95
      metrics.respirationWaking = 14
      return metrics
    }
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.startLocal = today.iso + " 07:00:00"
    run.distanceMeters = 10_000
    run.vo2Max = 52
    var profile = GarminProfile()
    profile.lactateThresholdHeartRate = 168

    let viewModel = TrainingViewModel()
    viewModel.update(
      days: days, activities: [run], profile: profile, watchZones: nil, overrides: HeartRateOverrides(), now: now)

    #expect(viewModel.recovery.map(\.title) == ["HRV · 7-Tage-Schnitt", "Ruhepuls"])
    #expect(viewModel.tiles.contains(TrainingViewModel.Tile(title: "SpO2", value: "95 %")))
    #expect(viewModel.tiles.contains { $0.title == "VO2max Laufen" })
    #expect(viewModel.weeks.count == 12)
    #expect(viewModel.weeks.last?.volume.kilometers[.run] == 10)
    #expect(viewModel.zones?.run.lactateThreshold == 168)
  }
}
