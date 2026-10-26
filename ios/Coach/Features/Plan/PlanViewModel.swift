import CoachCore
import Foundation
import Observation

/// Saisonplan Woche für Woche: Einheiten mit eingesetzten Testwerten und Erledigt-Status.
@Observable
final class PlanViewModel {
  let schedule: SeasonSchedule?
  private(set) var today = CalendarDay(date: .now)
  /// Index der angezeigten Woche in `schedule.weeks`.
  var weekIndex = 0
  private(set) var units: [PlannedUnit] = []

  private var activities: [GarminActivity] = []
  private var gymDays: [CalendarDay] = []
  private var config = SeasonConfig.standard
  private var decisions: CompetitionDecisions = [:]

  init(schedule: SeasonSchedule? = .load(), now: Date = .now) {
    self.schedule = schedule
    today = CalendarDay(date: now)
    weekIndex = currentWeekIndex
  }

  var week: PlanWeek? {
    guard let schedule, schedule.weeks.indices.contains(weekIndex) else { return nil }
    return schedule.weeks[weekIndex]
  }

  /// Aktuelle Woche; vor Planbeginn die erste, nach Planende die letzte.
  var currentWeekIndex: Int {
    guard let schedule, !schedule.weeks.isEmpty else { return 0 }
    if let index = schedule.index(of: today) { return index }
    return (schedule.weeks.first?.monday ?? today) > today ? 0 : schedule.weeks.count - 1
  }

  var isCurrentWeek: Bool { weekIndex == currentWeekIndex }
  var canGoBack: Bool { weekIndex > 0 }
  var canGoForward: Bool { weekIndex + 1 < (schedule?.weeks.count ?? 0) }

  var phaseInfo: PlanPhaseInfo? {
    week.flatMap { schedule?.phases[$0.ph] }
  }

  var weekTitle: String {
    guard let monday = week?.monday else { return "Plan" }
    let calendar = Calendar(identifier: .iso8601)
    let number = calendar.component(.weekOfYear, from: monday.localDate)
    return "KW \(number)"
  }

  var weekRange: String {
    guard let monday = week?.monday else { return "" }
    return "\(Formatters.shortDate(monday)) – \(Formatters.shortDate(monday.adding(days: 6)))"
  }

  var doneCount: Int { units.filter { $0.done && $0.kind != .bikeOptional }.count }
  var requiredCount: Int { units.filter { $0.kind != .bikeOptional }.count }

  func update(
    activities: [GarminActivity], gymDays: [CalendarDay], config: SeasonConfig, decisions: CompetitionDecisions,
    now: Date = .now
  ) {
    today = CalendarDay(date: now)
    self.activities = activities
    self.gymDays = gymDays
    self.config = config
    self.decisions = decisions
    rebuild()
  }

  func show(_ index: Int) {
    guard let schedule, schedule.weeks.indices.contains(index) else { return }
    weekIndex = index
    rebuild()
  }

  func step(_ offset: Int) {
    show(weekIndex + offset)
  }

  private func rebuild() {
    guard let schedule, let week else {
      units = []
      return
    }
    let planned = schedule.units(for: week, config: config, decisions: decisions)
    units = PlanProgress.mark(planned, week: week, activities: activities, gymDays: gymDays)
  }
}
