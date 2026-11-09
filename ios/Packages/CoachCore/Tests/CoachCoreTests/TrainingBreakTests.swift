import Testing

@testable import CoachCore

struct TrainingBreakTests {
  let monday = CalendarDay(year: 2026, month: 11, day: 9)

  @Test func rangeIsOrderedAndInclusive() {
    let pause = TrainingBreak(start: monday.adding(days: 4), end: monday.adding(days: 2))
    #expect(pause.start == monday.adding(days: 2))
    #expect(pause.contains(monday.adding(days: 2)))
    #expect(pause.contains(monday.adding(days: 4)))
    #expect(!pause.contains(monday.adding(days: 5)))
    #expect(!pause.isOver(today: monday.adding(days: 4)))
    #expect(pause.isOver(today: monday.adding(days: 5)))
  }

  @Test func scheduleLosesOnlyDaysInsideTheBreak() {
    var week = WeekSchedule()
    week.set([SessionSlot(.run)], on: .tuesday)
    week.set([SessionSlot(.strength)], on: .thursday)
    week.set([SessionSlot(.run)], on: .saturday)
    let pause = TrainingBreak(start: monday.adding(days: 3), end: monday.adding(days: 10))
    let result = pause.removing(from: week, monday: monday)
    #expect(!result.slots(on: .tuesday).isEmpty)
    #expect(result.slots(on: .thursday).isEmpty)
    #expect(result.slots(on: .saturday).isEmpty)
  }
}
