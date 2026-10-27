import Foundation
import Testing

@testable import CoachCore

struct WeightForecastTests {
  let today = CalendarDay(year: 2026, month: 10, day: 27)

  @Test func halfPercentPerWeek() throws {
    let result = try #require(
      WeightForecast.compute(
        currentKilograms: 90, weeklyChangePercent: -0.5, heightCentimeters: 180, maintenanceKilocalories: 2_800,
        target: 85, today: today))
    #expect(result.weeklyKilograms == 0.45)
    #expect(result.dailyDeficit == 500)
    #expect(!result.deficitCapped)
    #expect(result.points.map(\.weeks) == [4, 8, 12])
    #expect(result.points[0].kilograms == 88.2)
    #expect(result.points[2].kilograms == 85)
    #expect(result.weeksToTarget == 12)
    #expect(result.targetDay == today.adding(days: 84))
  }

  @Test func deficitCappedAtQuarterOfNeeds() throws {
    let result = try #require(
      WeightForecast.compute(
        currentKilograms: 120, weeklyChangePercent: -1, heightCentimeters: 175, maintenanceKilocalories: 2_400,
        target: nil, today: today))
    #expect(result.deficitCapped)
    #expect(result.dailyDeficit == 600)
    #expect(result.weeklyPercent < 1)
  }

  @Test func neverBelowHealthyFloor() throws {
    let result = try #require(
      WeightForecast.compute(
        currentKilograms: 62, weeklyChangePercent: -1, heightCentimeters: 180, maintenanceKilocalories: nil,
        target: 50, today: today))
    #expect(result.floorKilograms == 60)
    #expect(result.target == 60)
    #expect(result.points.allSatisfy { $0.kilograms >= 60 })
    let gain = WeightForecast.compute(
      currentKilograms: 80, weeklyChangePercent: 0.25, heightCentimeters: 180, maintenanceKilocalories: nil,
      target: nil, today: today)
    #expect(gain == nil)
  }
}
