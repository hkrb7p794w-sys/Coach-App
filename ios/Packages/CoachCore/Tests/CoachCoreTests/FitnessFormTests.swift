import Foundation
import Testing

@testable import CoachCore

struct FitnessFormTests {
  private let start = CalendarDay(year: 2026, month: 9, day: 1)

  private func activity(_ day: CalendarDay, load: Double, id: Int64) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.trainingLoad = load
    return activity
  }

  @Test func constantLoadConvergesAndFormIsZero() throws {
    let activities = (0..<120).map { activity(start.adding(days: $0), load: 100, id: Int64($0)) }
    let points = FitnessForm.series(activities: activities, from: start, to: start.adding(days: 119))
    let last = try #require(points.last)
    #expect(abs(last.fitness - 100) < 10)
    #expect(abs(last.fatigue - 100) < 0.5)
    #expect(abs(last.form) < 10)
    #expect(FitnessForm.isReliable(points))
  }

  @Test func restDaysMakeYouFresh() throws {
    // Sechs Wochen Training, dann eine Woche Pause: Ermüdung fällt schneller als Fitness.
    let activities = (0..<42).map { activity(start.adding(days: $0), load: 80, id: Int64($0)) }
    let points = FitnessForm.series(activities: activities, from: start, to: start.adding(days: 49))
    let last = try #require(points.last)
    #expect(last.fatigue < last.fitness)
    #expect(last.form > 0)
    let percent = try #require(last.formPercent)
    #expect(FitnessForm.Zone.of(percent) == .fresh)
  }

  @Test func loadSpikeIsProductiveOrHigh() throws {
    var activities = (0..<42).map { activity(start.adding(days: $0), load: 50, id: Int64($0)) }
    activities += (42..<49).map { activity(start.adding(days: $0), load: 150, id: Int64($0)) }
    let points = FitnessForm.series(activities: activities, from: start, to: start.adding(days: 49))
    let percent = try #require(points.last?.formPercent)
    #expect([.productive, .high].contains(FitnessForm.Zone.of(percent)))
  }

  @Test func zonesAndEmptyHistory() {
    #expect(FitnessForm.Zone.of(10) == .fresh)
    #expect(FitnessForm.Zone.of(0) == .neutral)
    #expect(FitnessForm.Zone.of(-20) == .productive)
    #expect(FitnessForm.Zone.of(-40) == .high)
    #expect(FitnessForm.series(activities: [], today: start).isEmpty)
  }
}
