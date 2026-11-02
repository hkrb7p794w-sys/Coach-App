import Foundation
import Testing

@testable import CoachCore

private let today = CalendarDay(year: 2026, month: 11, day: 2)

struct HealthDashboardTests {
  @Test func standardHasNoDuplicatesAndAllVisible() {
    let dashboard = HealthDashboard()
    #expect(dashboard.entries.map(\.kind) == HealthDashboard.standard)
    #expect(dashboard.entries.allSatisfy { !$0.hidden && $0.style == .week })
  }

  @Test func addRemoveHideAndStyle() {
    var dashboard = HealthDashboard(entries: [.init(kind: .sleep), .init(kind: .hrv)])
    dashboard.add(.weight, style: .month)
    #expect(dashboard.entries.map(\.kind) == [.sleep, .hrv, .weight])
    dashboard.add(.weight)
    #expect(dashboard.entries.count == 3)
    dashboard.setHidden(.hrv, true)
    #expect(dashboard.visible(available: [.sleep, .hrv, .weight]).map(\.kind) == [.sleep, .weight])
    // Wieder hinzufügen blendet ein, statt doppelt anzulegen.
    dashboard.add(.hrv)
    #expect(dashboard.visible(available: [.sleep, .hrv, .weight]).map(\.kind) == [.sleep, .hrv, .weight])
    dashboard.setStyle(.sleep, .value)
    #expect(dashboard.entries[0].style == .value)
    dashboard.remove(.sleep)
    #expect(!dashboard.contains(.sleep))
    #expect(dashboard.addable(available: [.sleep, .hrv, .steps]) == [.sleep, .steps])
  }

  @Test func moveLikeSwiftUIList() {
    var dashboard = HealthDashboard(entries: [.init(kind: .sleep), .init(kind: .hrv), .init(kind: .stress)])
    dashboard.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(dashboard.entries.map(\.kind) == [.hrv, .stress, .sleep])
    dashboard.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
    #expect(dashboard.entries.map(\.kind) == [.sleep, .hrv, .stress])
    dashboard.move(fromOffsets: IndexSet([0, 2]), toOffset: 2)
    #expect(dashboard.entries.map(\.kind) == [.hrv, .sleep, .stress])
  }

  @Test func hiddenAndStyleSurviveSaving() throws {
    var dashboard = HealthDashboard()
    dashboard.setHidden(.stress, true)
    dashboard.setStyle(.hrv, .month)
    let decoded = try JSONDecoder().decode(HealthDashboard.self, from: JSONEncoder().encode(dashboard))
    #expect(decoded == dashboard)
  }

  @Test func decodingDropsUnknownAndDuplicateWidgets() throws {
    let json =
      #"{"entries": [{"kind": "hrv"}, {"kind": "zukunft"}, {"kind": "hrv", "style": "month"}, "#
      + #"{"kind": "sleep", "style": "value", "hidden": true}]}"#
    let data = Data(json.utf8)
    let dashboard = try JSONDecoder().decode(HealthDashboard.self, from: data)
    #expect(dashboard.entries.map(\.kind) == [.hrv, .sleep])
    #expect(dashboard.entries[0].style == .week)
    #expect(dashboard.entries[1].hidden)
  }

  @Test func onlyWidgetsWithDataAreAvailable() {
    var day = DailyMetrics(day: today)
    day.restingHeartRate = 50
    day.sleepSeconds = 7 * 3_600
    var old = DailyMetrics(day: today.adding(days: -40))
    old.stressAverage = 30
    let weight = [DayValue(day: today.adding(days: -3), value: 80.4)]
    let available = HealthDashboard.available(days: [day, old], extra: [.weight: weight], today: today)
    #expect(available == [.restingHeartRate, .sleep, .weight])
    #expect(!available.contains(.bodyBattery))
    #expect(!available.contains(.stress))
    let visible = HealthDashboard().visible(available: available).map(\.kind)
    #expect(visible == [.sleep, .restingHeartRate])
  }

  @Test func seriesPrefersDailyValuesOverFallback() {
    var day = DailyMetrics(day: today)
    day.acuteLoad = 500
    let fallback = [DayValue(day: today, value: 120), DayValue(day: today.adding(days: -1), value: 110)]
    let series = HealthDashboard.series(
      .trainingLoad, days: [day], extra: [.trainingLoad: fallback], today: today, window: 7)
    #expect(series.map(\.value) == [110, 500])
  }

  @Test func everyWidgetHasCategoryAndTitle() {
    for widget in HealthWidget.allCases {
      #expect(!widget.title.isEmpty)
      #expect(HealthCategory.allCases.contains(widget.category))
    }
  }
}

struct WakePlanTests {
  @Test func wakeIfSleepingNowAddsLatencyAndRounds() {
    #expect(WakePlan.wakeIfSleepingNow(nowMinutes: 23 * 60 + 40, sleepMinutes: 480) == .init(hour: 7, minute: 55))
    #expect(WakePlan.wakeIfSleepingNow(nowMinutes: 22 * 60 + 31, sleepMinutes: 480) == .init(hour: 6, minute: 50))
  }

  @Test func sleepMinutesAcrossMidnight() {
    #expect(WakePlan.sleepMinutes(bedtimeMinutes: 22 * 60 + 30, wake: .init(hour: 6, minute: 45)) == 480)
  }

  @Test func nextDateIsTomorrowOrToday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 22)))
    let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 5)))
    let time = WakePlan.Time(hour: 6, minute: 30)
    let next = try #require(WakePlan.nextDate(time, after: evening, calendar: calendar))
    #expect(calendar.dateComponents([.day, .hour, .minute], from: next) == DateComponents(day: 3, hour: 6, minute: 30))
    #expect(WakePlan.dayLabel(next, now: evening, calendar: calendar) == "morgen")
    let same = try #require(WakePlan.nextDate(time, after: morning, calendar: calendar))
    #expect(WakePlan.dayLabel(same, now: morning, calendar: calendar) == "heute")
  }

  @Test func nextDateKeepsClockTimeOverDaylightSavingChange() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
    // Nacht der Zeitumstellung (25.10.2026, 3 Uhr → 2 Uhr).
    let evening = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23)))
    let next = try #require(WakePlan.nextDate(.init(hour: 6, minute: 30), after: evening, calendar: calendar))
    #expect(calendar.dateComponents([.day, .hour, .minute], from: next) == DateComponents(day: 25, hour: 6, minute: 30))
    #expect(next.timeIntervalSince(evening) == 8.5 * 3_600)
  }

  @Test func repeatWeekdays() {
    #expect(WakePlan.Repeat.once.weekdays.isEmpty)
    #expect(WakePlan.Repeat.weekdays.weekdays == [2, 3, 4, 5, 6])
    #expect(WakePlan.Repeat.daily.weekdays.count == 7)
  }

  @Test func timeClampsAndWraps() {
    #expect(WakePlan.Time(minutes: 1_500) == .init(hour: 1, minute: 0))
    #expect(WakePlan.Time(minutes: -30) == .init(hour: 23, minute: 30))
    #expect(WakePlan.Time(hour: 6, minute: 5).text == "6:05")
  }
}
