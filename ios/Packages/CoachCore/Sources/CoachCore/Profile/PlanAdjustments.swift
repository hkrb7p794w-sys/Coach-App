import Foundation

/// Ausnahme vom Wochenplan für genau eine Woche: Einheiten eines Tages auslassen oder auf einen anderen Tag
/// derselben Woche verschieben. Der eigentliche Wochenplan bleibt unverändert.
public struct PlanChange: Codable, Equatable, Hashable, Sendable {
  /// Montag der betroffenen Woche.
  public var week: CalendarDay
  public var from: Weekday
  /// Zieltag; `nil` = ausgelassen.
  public var to: Weekday?

  public init(week: CalendarDay, from: Weekday, to: Weekday?) {
    self.week = week
    self.from = from
    self.to = to
  }

  public var isSkip: Bool { to == nil }
}

/// Alle Ausnahmen, gespeichert in der Reihenfolge, in der sie gemacht wurden.
public struct PlanAdjustments: Codable, Equatable, Hashable, Sendable {
  public private(set) var changes: [PlanChange]

  public init(changes: [PlanChange] = []) {
    self.changes = changes
  }

  public static func monday(of day: CalendarDay) -> CalendarDay {
    day.adding(days: -day.weekdayIndex)
  }

  public func changes(inWeekOf day: CalendarDay) -> [PlanChange] {
    let monday = Self.monday(of: day)
    return changes.filter { $0.week == monday }
  }

  /// Der Plan der Woche, die `day` enthält, mit allen Ausnahmen dieser Woche.
  public func schedule(_ base: WeekSchedule, inWeekOf day: CalendarDay) -> WeekSchedule {
    var result = base
    for change in changes(inWeekOf: day) {
      let moved = result.slots(on: change.from)
      guard !moved.isEmpty else { continue }
      result.set([], on: change.from)
      if let target = change.to {
        result.set(result.slots(on: target) + moved, on: target)
      }
    }
    return result
  }

  /// Einheiten dieses Tages in dieser Woche auslassen.
  public mutating func skip(_ weekday: Weekday, inWeekOf day: CalendarDay) {
    changes.append(PlanChange(week: Self.monday(of: day), from: weekday, to: nil))
  }

  /// Einheiten dieses Tages in dieser Woche auf einen anderen Tag verschieben.
  public mutating func move(_ weekday: Weekday, to target: Weekday, inWeekOf day: CalendarDay) {
    guard weekday != target else { return }
    changes.append(PlanChange(week: Self.monday(of: day), from: weekday, to: target))
  }

  /// Ausnahmen der Woche zurücknehmen, die diesen Tag betreffen (von dort weg oder dorthin verschoben).
  public mutating func undo(_ weekday: Weekday, inWeekOf day: CalendarDay) {
    let monday = Self.monday(of: day)
    changes.removeAll { $0.week == monday && ($0.from == weekday || $0.to == weekday) }
  }

  /// Alle Ausnahmen der Woche zurücknehmen.
  public mutating func reset(weekOf day: CalendarDay) {
    let monday = Self.monday(of: day)
    changes.removeAll { $0.week == monday }
  }

  /// Ausnahmen vergangener Wochen entfernen (sie wirken nicht mehr).
  public mutating func prune(before day: CalendarDay) {
    let monday = Self.monday(of: day)
    changes.removeAll { $0.week < monday }
  }

  /// Wurde an diesem Tag etwas ausgelassen oder weggeschoben?
  public func note(for weekday: Weekday, inWeekOf day: CalendarDay) -> String? {
    let week = changes(inWeekOf: day)
    if let moved = week.last(where: { $0.from == weekday && $0.to != nil }), let target = moved.to {
      return "verschoben auf \(target.long)"
    }
    if week.contains(where: { $0.from == weekday && $0.isSkip }) { return "diese Woche ausgelassen" }
    if let incoming = week.last(where: { $0.to == weekday }) { return "von \(incoming.from.long) verschoben" }
    return nil
  }
}

/// Wohin sich eine Einheit sinnvoll verschieben lässt.
public enum PlanMoveAdvisor {
  /// Mögliche Zieltage in derselben Woche nach `today`, die besten zuerst: keine zwei fordernden Ausdauertage
  /// direkt hintereinander (Seiler 2006), möglichst ein freier Tag.
  public static func options(
    for weekday: Weekday, schedule: WeekSchedule, profile: UserProfile, today: CalendarDay, limit: Int = 3
  ) -> [Weekday] {
    let todayIndex = today.weekdayIndex
    let moving = schedule.slots(on: weekday)
    guard !moving.isEmpty else { return [] }
    let candidates = Weekday.allCases.filter { $0.rawValue > todayIndex && $0 != weekday }
    let scored = candidates.map { target -> (Weekday, Int) in
      var moved = schedule
      moved.set([], on: weekday)
      moved.set(moved.slots(on: target) + moving, on: target)
      var score = ScheduleCheck.penalty(schedule: moved, profile: profile)
      if !schedule.slots(on: target).isEmpty { score += 2 }
      if createsBackToBack(moved, around: target) { score += 20 }
      return (target, score)
    }
    return scored.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.rawValue < $1.0.rawValue }.prefix(limit).map(\.0)
  }

  static func createsBackToBack(_ schedule: WeekSchedule, around day: Weekday) -> Bool {
    guard schedule.slots(on: day).contains(where: \.isDemandingEndurance) else { return false }
    return schedule.slots(on: day.previous).contains(where: \.isDemandingEndurance)
      || schedule.slots(on: day.next).contains(where: \.isDemandingEndurance)
  }
}

/// Eine geplante Trainings-Erinnerung.
public struct TrainingReminder: Equatable, Sendable, Identifiable {
  public var day: CalendarDay
  public var titles: [String]
  /// Mit Auslassen/Verschieben (nur beim eigenen Wochenplan).
  public var canAdjust: Bool

  public var id: String { "coach.reminder.\(day.iso)" }

  public var title: String {
    "Heute: \(titles.joined(separator: " + "))"
  }
}

public enum ReminderPlanner {
  /// Erinnerungen für die kommenden `days` Tage ab `today` (iOS erlaubt höchstens 64 geplante Mitteilungen).
  /// Heute nur, wenn die Uhrzeit noch nicht vorbei ist und noch nicht trainiert wurde.
  public static func personal(
    profile: UserProfile, adjustments: PlanAdjustments, today: CalendarDay, includeToday: Bool, days: Int = 14
  ) -> [TrainingReminder] {
    (0..<days).compactMap { offset in
      if offset == 0, !includeToday { return nil }
      let day = today.adding(days: offset)
      let slots = adjustments.schedule(profile.schedule, inWeekOf: day).slots(on: Weekday(day: day))
      guard !slots.isEmpty else { return nil }
      return TrainingReminder(day: day, titles: slots.map(\.title), canAdjust: true)
    }
  }

  /// Erinnerungen für den Saisonplan: die festen Einheiten der Tage laut `TodayPlan`, ohne Auslassen/Verschieben
  /// (der Saisonplan verteilt offene Einheiten selbst).
  public static func season(
    schedule: SeasonSchedule, config: SeasonConfig, decisions: CompetitionDecisions, today: CalendarDay,
    includeToday: Bool, days: Int = 14
  ) -> [TrainingReminder] {
    (0..<days).compactMap { offset in
      if offset == 0, !includeToday { return nil }
      let day = today.adding(days: offset)
      let plan = TodayPlan(
        schedule: schedule, config: config, decisions: decisions, today: day, level: nil, advice: "",
        done: TodayPlan.Done(), gymDays: [], runZones: nil)
      let titles = plan.items.filter { $0.sport != .rest }.map(\.title)
      guard !titles.isEmpty else { return nil }
      return TrainingReminder(day: day, titles: titles, canAdjust: false)
    }
  }

  /// Text der Mitteilung. Kurz, freundlich, ohne Druck.
  public static func body(for reminder: TrainingReminder, companion: String? = nil) -> String {
    let base =
      reminder.canAdjust
      ? "Passt es heute nicht? Du kannst die Einheit verschieben oder diese Woche auslassen."
      : "Schau in der App, was heute ansteht."
    guard let companion, !companion.isEmpty else { return base }
    return "\(companion) freut sich schon. \(base)"
  }
}
