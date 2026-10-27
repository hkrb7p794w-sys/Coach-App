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

/// Eigener Plan für genau eine Woche (aus „Nächste Woche planen“); ersetzt dort den Wochenplan.
public struct WeekPlan: Codable, Equatable, Hashable, Sendable {
  /// Montag der Woche.
  public var week: CalendarDay
  public var schedule: WeekSchedule

  public init(week: CalendarDay, schedule: WeekSchedule) {
    self.week = week
    self.schedule = schedule
  }
}

/// Alle Ausnahmen, gespeichert in der Reihenfolge, in der sie gemacht wurden.
public struct PlanAdjustments: Codable, Equatable, Hashable, Sendable {
  public private(set) var changes: [PlanChange]
  public private(set) var weekPlans: [WeekPlan]

  public init(changes: [PlanChange] = [], weekPlans: [WeekPlan] = []) {
    self.changes = changes
    self.weekPlans = weekPlans
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    changes = try container.decodeIfPresent([PlanChange].self, forKey: .changes) ?? []
    // Ältere Daten ohne Wochenpläne bleiben lesbar.
    weekPlans = (try? container.decodeIfPresent([WeekPlan].self, forKey: .weekPlans)) ?? []
  }

  /// Eigener Plan der Woche, die `day` enthält, falls angelegt.
  public func weekPlan(inWeekOf day: CalendarDay) -> WeekSchedule? {
    let monday = Self.monday(of: day)
    return weekPlans.first { $0.week == monday }?.schedule
  }

  /// Plan für genau diese Woche festlegen. Entspricht er dem Wochenplan, wird nichts gespeichert. Ausnahmen
  /// (Auslassen/Verschieben) der Woche gehen in dem neuen Plan auf und werden entfernt.
  public mutating func setWeekPlan(_ schedule: WeekSchedule, base: WeekSchedule, inWeekOf day: CalendarDay) {
    let monday = Self.monday(of: day)
    weekPlans.removeAll { $0.week == monday }
    changes.removeAll { $0.week == monday }
    if schedule != base { weekPlans.append(WeekPlan(week: monday, schedule: schedule)) }
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
    var result = weekPlan(inWeekOf: day) ?? base
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
    weekPlans.removeAll { $0.week == monday }
  }

  /// Ausnahmen vergangener Wochen entfernen (sie wirken nicht mehr).
  public mutating func prune(before day: CalendarDay) {
    let monday = Self.monday(of: day)
    changes.removeAll { $0.week < monday }
    weekPlans.removeAll { $0.week < monday }
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

/// Was schon trainiert wurde (Aktivitäten aus Garmin/Health, Krafteinheiten der App): Erinnerungen für
/// Erledigtes entfallen.
public struct TrainingLog: Sendable {
  public var activities: [GarminActivity]
  public var gymDays: Set<CalendarDay>

  public init(activities: [GarminActivity] = [], gymDays: Set<CalendarDay> = []) {
    self.activities = activities
    self.gymDays = gymDays
  }

  /// Tage mit mindestens 15 Minuten Training oder einer Krafteinheit.
  public var trainedDays: Set<CalendarDay> {
    Set(activities.filter { ($0.durationSeconds ?? 0) >= 900 }.compactMap(\.day)).union(gymDays)
  }

  /// Saisonplan-Tag mit dem bis `today` Erledigten dieser Woche.
  func seasonPlan(
    schedule: SeasonSchedule, config: SeasonConfig, decisions: CompetitionDecisions, day: CalendarDay,
    today: CalendarDay
  ) -> TodayPlan {
    let progress = TodayPlan.done(activities: activities, gymDays: gymDays, weekOf: day, upTo: today)
    return TodayPlan(
      schedule: schedule, config: config, decisions: decisions, today: day, level: nil, advice: "",
      done: progress.done, gymDays: progress.strengthDays, runZones: nil)
  }
}

public enum ReminderPlanner {
  /// Erinnerungen für die kommenden `days` Tage ab `today` (iOS erlaubt höchstens 64 geplante Mitteilungen).
  /// Heute nur, wenn die Uhrzeit noch nicht vorbei ist und noch nicht trainiert wurde.
  public static func personal(
    profile: UserProfile, adjustments: PlanAdjustments, today: CalendarDay, includeToday: Bool, days: Int = 14,
    log: TrainingLog = TrainingLog()
  ) -> [TrainingReminder] {
    let trainedToday = log.trainedDays.contains(today)
    return (0..<days).compactMap { offset in
      if offset == 0, !includeToday || trainedToday { return nil }
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
    includeToday: Bool, days: Int = 14, log: TrainingLog = TrainingLog()
  ) -> [TrainingReminder] {
    (0..<days).compactMap { offset in
      if offset == 0, !includeToday { return nil }
      let day = today.adding(days: offset)
      let plan = log.seasonPlan(schedule: schedule, config: config, decisions: decisions, day: day, today: today)
      let titles = plan.items.filter { $0.sport != .rest && !$0.done }.map(\.title)
      guard !titles.isEmpty else { return nil }
      return TrainingReminder(day: day, titles: titles, canAdjust: false)
    }
  }

  /// Text der Mitteilung. Kurz, freundlich, ohne Druck; `lead` ist ein Satz des Begleiters.
  public static func body(for reminder: TrainingReminder, lead: String? = nil) -> String {
    let base =
      reminder.canAdjust
      ? "Passt es heute nicht? Du kannst die Einheit verschieben oder diese Woche auslassen."
      : "Schau in der App, was heute ansteht."
    guard let lead, !lead.isEmpty else { return base }
    return "\(lead) \(base)"
  }
}

/// Erinnerung zu einer festen Uhrzeit, die nicht am Trainingstag selbst kommt: Ausrüstung am Vorabend,
/// Wochenplanung am Sonntag.
public struct ScheduledNote: Equatable, Sendable, Identifiable {
  public enum Kind: String, Sendable {
    case equipment, weekPlanning
  }

  public var kind: Kind
  public var day: CalendarDay
  public var hour: Int
  public var minute: Int
  public var title: String
  public var body: String

  public var id: String { "coach.reminder.\(kind.rawValue).\(day.iso)" }
}

extension ReminderPlanner {
  public static let equipmentHour = 18

  /// Schwimmen mit Ausrüstung (Pull-Buoy, Paddles, Flossen, Schnorchel): Erinnerung am Vorabend um 18 Uhr.
  /// Nur der Saisonplan kennt die Ausrüstung je Einheit; im eigenen Wochenplan gibt es keine Angabe dazu.
  public static func swimEquipment(
    schedule: SeasonSchedule, config: SeasonConfig, decisions: CompetitionDecisions, today: CalendarDay,
    minutesNow: Int, days: Int = 14, log: TrainingLog = TrainingLog()
  ) -> [ScheduledNote] {
    (1...max(days, 1)).compactMap { offset in
      let training = today.adding(days: offset)
      let evening = training.adding(days: -1)
      if evening == today, minutesNow >= equipmentHour * 60 { return nil }
      // Schon geschwommen (z. B. am Dienstag): Am Donnerstag stehen dann die Beine an, keine Erinnerung.
      let plan = log.seasonPlan(
        schedule: schedule, config: config, decisions: decisions, day: training, today: today)
      guard plan.items.contains(where: { $0.sport == .swim && !$0.done }),
        let week = schedule.week(containing: training)
      else { return nil }
      let equipment = SwimStepText.equipment(in: week.ss ?? [])
      guard !equipment.isEmpty else { return nil }
      let list = ListFormat.german(equipment)
      return ScheduledNote(
        kind: .equipment, day: evening, hour: equipmentHour, minute: 0,
        title: "Morgen Schwimmen: \(list) einpacken",
        body: "Für die Schwimmeinheit morgen brauchst du \(list). Am besten gleich in die Tasche legen.")
    }
  }

  /// Sonntags „Nächste Woche planen“ (heute nur, wenn die Uhrzeit noch nicht vorbei ist).
  public static func weekPlanning(
    mode: UserProfile.Mode, today: CalendarDay, minutesNow: Int, hour: Int, minute: Int, days: Int = 14
  ) -> [ScheduledNote] {
    (0..<days).compactMap { offset in
      let day = today.adding(days: offset)
      guard day.weekdayIndex == 6 else { return nil }
      if offset == 0, minutesNow >= hour * 60 + minute { return nil }
      let body =
        mode == .personal
        ? "Leg fest, an welchen Tagen du nächste Woche trainierst – Termine, Wetter, Erholung."
        : "Schau dir die Einheiten der nächsten Woche an und plane, wann du sie unterbringst."
      return ScheduledNote(
        kind: .weekPlanning, day: day, hour: hour, minute: minute, title: "Nächste Woche planen", body: body)
    }
  }
}

enum ListFormat {
  /// „A“, „A und B“, „A, B und C“.
  static func german(_ items: [String]) -> String {
    guard let last = items.last else { return "" }
    return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " und " + last
  }
}
