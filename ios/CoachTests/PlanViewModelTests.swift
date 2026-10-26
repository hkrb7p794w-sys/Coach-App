import CoachCore
import Foundation
import Testing

@testable import Coach

@MainActor
struct PlanViewModelTests {
  @Test func startsAtCurrentWeekAndNavigates() throws {
    let now = CalendarDay(year: 2026, month: 10, day: 29).localDate
    let viewModel = PlanViewModel(now: now)
    try #require(viewModel.schedule != nil)
    viewModel.update(activities: [], gymDays: [], config: .standard, decisions: [:], now: now)

    #expect(viewModel.week?.w == "2026-10-26")
    #expect(viewModel.isCurrentWeek)
    #expect(viewModel.weekTitle == "KW 44")
    #expect(viewModel.weekRange == "26.10. – 01.11.")
    #expect(viewModel.units.first?.title == "Z03 Sweet Spot 2×20")
    #expect(viewModel.requiredCount == 8)

    viewModel.step(1)
    #expect(viewModel.week?.w == "2026-11-02")
    #expect(!viewModel.isCurrentWeek)
    viewModel.show(viewModel.currentWeekIndex)
    #expect(viewModel.isCurrentWeek)
  }

  @Test func beforeSeasonShowsFirstWeek() {
    let viewModel = PlanViewModel(now: CalendarDay(year: 2026, month: 1, day: 5).localDate)
    #expect(viewModel.weekIndex == 0)
    #expect(viewModel.canGoBack == false)
  }
}
