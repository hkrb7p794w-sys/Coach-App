import Foundation
import Testing

@testable import CoachCore

struct WeeklyReportTests {
  /// Mittwoch, 11.11.2026; berichtet wird die Woche ab Montag, 2.11.
  private let today = CalendarDay(year: 2026, month: 11, day: 11)

  private func run(_ day: CalendarDay, minutes: Double, kilometers: Double, id: Int64) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.startLocal = "\(day.iso) 07:00:00"
    activity.durationSeconds = minutes * 60
    activity.distanceMeters = kilometers * 1_000
    activity.trainingLoad = minutes
    return activity
  }

  @Test func summarizesLastWeekAgainstThePrevious() {
    let monday = CalendarDay(year: 2026, month: 11, day: 2)
    let activities = [
      run(monday, minutes: 60, kilometers: 10, id: 1), run(monday.adding(days: 2), minutes: 60, kilometers: 10, id: 2),
      run(monday.adding(days: -5), minutes: 40, kilometers: 6, id: 3),
    ]
    var night = DailyMetrics(day: monday.adding(days: 1))
    night.sleepSeconds = 6 * 3_600
    let report = WeeklyReport.lastWeek(
      activities: activities, days: [night], gymDays: [monday.adding(days: 4)], today: today)
    #expect(report.monday == monday)
    #expect(report.week.sessions == 3)
    #expect(report.week.minutes == 120)
    #expect(report.week.kilometers[.run] == 20)
    #expect(report.previous.minutes == 40)
    #expect(report.highlights.contains { $0.contains("Deutlich mehr Trainingszeit") })
    #expect(report.highlights.contains { $0.contains("Stunden Schlaf") })
  }

  @Test func emptyWeekGetsAHint() {
    let report = WeeklyReport.lastWeek(activities: [], days: [], gymDays: [], today: today)
    #expect(report.week.sessions == 0)
    #expect(report.highlights.first?.contains("Keine Einheit") == true)
  }
}
