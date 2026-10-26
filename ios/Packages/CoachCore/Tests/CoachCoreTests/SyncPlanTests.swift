import Foundation
import Testing

@testable import CoachCore

struct SyncPlanTests {
  private let today = CalendarDay(year: 2026, month: 10, day: 23)

  @Test func firstSyncLoadsSixtyDays() {
    let range = SyncPlan.range(latestStored: nil, today: today)
    #expect(range.end == today)
    #expect(range.dayCount == 60)
  }

  @Test func laterSyncsOverlapTwoDays() {
    let range = SyncPlan.range(latestStored: today.adding(days: -1), today: today)
    #expect(range.start == today.adding(days: -3))
    #expect(range.end == today)
  }

  @Test func longPauseIsCappedAtSixtyDays() {
    let range = SyncPlan.range(latestStored: today.adding(days: -200), today: today)
    #expect(range.dayCount == 60)
  }

  @Test func futureDataFallsBackToInitialRange() {
    #expect(SyncPlan.range(latestStored: today.adding(days: 5), today: today).dayCount == 60)
  }

  @Test func dueAfterInterval() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(SyncPlan.isDue(lastSync: nil, now: now))
    #expect(!SyncPlan.isDue(lastSync: now.addingTimeInterval(-60), now: now))
    #expect(SyncPlan.isDue(lastSync: now.addingTimeInterval(-16 * 60), now: now))
    #expect(SyncPlan.isDue(lastSync: now.addingTimeInterval(3_600), now: now))
  }

  private func activity(_ id: Int64, _ day: CalendarDay) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.startLocal = "\(day.iso) 07:00:00"
    return activity
  }

  @Test func pagingStopsAtKnownOrOldActivities() {
    let page = (0..<3).map { activity(Int64(100 - $0), today.adding(days: -$0)) }
    let start = today.adding(days: -10)

    #expect(
      SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: [], rangeStart: start, pagesLoaded: 1))
    #expect(
      !SyncPlan.shouldLoadNextPage(page: page, pageSize: 4, knownIDs: [], rangeStart: start, pagesLoaded: 1))
    #expect(
      !SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: [99], rangeStart: start, pagesLoaded: 1))
    #expect(
      !SyncPlan.shouldLoadNextPage(
        page: page, pageSize: 3, knownIDs: [], rangeStart: today.adding(days: -1), pagesLoaded: 1))
    #expect(
      !SyncPlan.shouldLoadNextPage(page: page, pageSize: 3, knownIDs: [], rangeStart: start, pagesLoaded: 6))
  }

  @Test func jsonValueRoundTrips() throws {
    let value = JSONValue.object(["a": .array([.number(1), .bool(true), .null, .string("ü")])])
    let data = try JSONEncoder().encode(value)
    #expect(try JSONValue(data: data) == value)
  }
}
