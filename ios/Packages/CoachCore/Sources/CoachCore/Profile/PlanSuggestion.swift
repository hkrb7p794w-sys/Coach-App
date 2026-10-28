import Foundation

/// Ein Vorschlag zur Woche als Diff („Do: Qualitätslauf → Lockerer Lauf“) mit Regelprüfung. Übernehmen ersetzt die
/// Wochen-Ausnahmen (`adjustments`), Rückgängig stellt die vorherigen wieder her. Neue Konflikte mit den Planregeln
/// (zwei harte Tage hintereinander, kein Ruhetag …) stehen beim Vorschlag, statt still übernommen zu werden.
public struct PlanSuggestion: Equatable, Sendable, Identifiable {
  public enum Source: String, Sendable {
    case recovery, load, postWorkout, nextWeek

    public var label: String {
      switch self {
      case .recovery: "Tagesform"
      case .load: "Wochenbelastung"
      case .postWorkout: "Nach dem Training"
      case .nextWeek: "Wochenrückblick"
      }
    }
  }

  public struct Change: Equatable, Sendable, Identifiable {
    public var weekday: Weekday
    public var before: [SessionSlot]
    public var after: [SessionSlot]
    public var id: Int { weekday.rawValue }

    /// „Do: Langer Lauf → Lockerer Lauf“
    public var text: String {
      "\(weekday.short): \(PlanSuggestion.text(before)) → \(PlanSuggestion.text(after))"
    }
  }

  public var id: String
  public var source: Source
  public var title: String
  public var reason: String
  /// Montag der betroffenen Woche.
  public var week: CalendarDay
  /// Wochen-Ausnahmen nach dem Übernehmen.
  public var adjustments: PlanAdjustments
  /// Wochenplan nach dem Übernehmen (für „Anpassen“).
  public var schedule: WeekSchedule
  public var changes: [Change]
  /// Fordernde Tage, die bleiben („Sa: Langer Lauf bleibt“).
  public var unchanged: [String]
  /// Planregeln, die erst durch den Vorschlag verletzt werden.
  public var conflicts: [ScheduleHint]
  public var evidenceIDs: [String]

  /// Vorschlag aus einer Änderung der Wochen-Ausnahmen; `nil`, wenn sich am Plan nichts ändert.
  public static func make(
    id: String, source: Source, title: String, reason: String, profile: UserProfile, adjustments: PlanAdjustments,
    week day: CalendarDay, evidenceIDs: [String] = [], edit: (inout PlanAdjustments) -> Void
  ) -> PlanSuggestion? {
    var proposed = adjustments
    edit(&proposed)
    let before = adjustments.schedule(profile.schedule, inWeekOf: day)
    let after = proposed.schedule(profile.schedule, inWeekOf: day)
    let changes = diff(before, after)
    guard !changes.isEmpty else { return nil }
    let changed = Set(changes.map(\.weekday))
    let unchanged = Weekday.allCases.filter { !changed.contains($0) }.compactMap { weekday -> String? in
      let slots = after.slots(on: weekday).filter(\.isDemandingEndurance)
      return slots.isEmpty ? nil : "\(weekday.short): \(text(slots)) bleibt"
    }
    return PlanSuggestion(
      id: id, source: source, title: title, reason: reason, week: PlanAdjustments.monday(of: day),
      adjustments: proposed, schedule: after, changes: changes, unchanged: unchanged,
      conflicts: newConflicts(before: before, after: after, profile: profile), evidenceIDs: evidenceIDs)
  }

  public static func diff(_ before: WeekSchedule, _ after: WeekSchedule) -> [Change] {
    Weekday.allCases.compactMap { weekday in
      let old = before.slots(on: weekday)
      let new = after.slots(on: weekday)
      return old == new ? nil : Change(weekday: weekday, before: old, after: new)
    }
  }

  /// Hinweise (ab „Tipp“), die der Plan vorher nicht hatte.
  public static func newConflicts(before: WeekSchedule, after: WeekSchedule, profile: UserProfile) -> [ScheduleHint] {
    let existing = Set(ScheduleCheck.hints(schedule: before, profile: profile).map(\.id))
    return ScheduleCheck.hints(schedule: after, profile: profile).filter {
      $0.severity >= .tip && !existing.contains($0.id)
    }
  }

  public static func text(_ slots: [SessionSlot]) -> String {
    slots.isEmpty ? "frei" : slots.map(\.title).joined(separator: " + ")
  }

  /// Fordernde Ausdauer an einem Tag durch lockere ersetzen.
  static func easing(_ schedule: WeekSchedule, on weekday: Weekday) -> WeekSchedule {
    var adjusted = schedule
    adjusted.set(
      schedule.slots(on: weekday).map { $0.isDemandingEndurance ? SessionSlot($0.sport, .easy) : $0 }, on: weekday)
    return adjusted
  }

  // MARK: - Quellen

  /// Tagesampel: heutige Einheit auf den vorgeschlagenen Tag verschieben.
  public static func recovery(
    advice: ScheduleAdvice, profile: UserProfile, adjustments: PlanAdjustments, today: CalendarDay
  ) -> PlanSuggestion? {
    guard let move = advice.move else { return nil }
    let weekday = Weekday(day: today)
    return make(
      id: "recovery-\(today.iso)-\(move.rawValue)", source: .recovery,
      title: "Heutige Einheit auf \(move.long) verschieben", reason: advice.detail, profile: profile,
      adjustments: adjustments, week: today, evidenceIDs: advice.evidenceIDs
    ) { $0.move(weekday, to: move, inWeekOf: today) }
  }

  /// Wochenbelastung zu hoch: die nächste fordernde Ausdauereinheit dieser Woche (ab morgen) locker.
  public static func load(
    _ load: WeekLoad.Result, profile: UserProfile, adjustments: PlanAdjustments, today: CalendarDay
  ) -> PlanSuggestion? {
    guard let warning = load.warning else { return nil }
    let schedule = adjustments.schedule(profile.schedule, inWeekOf: today)
    guard
      let weekday = Weekday.allCases.first(where: {
        $0.rawValue > today.weekdayIndex && schedule.slots(on: $0).contains(where: \.isDemandingEndurance)
      })
    else { return nil }
    let titles = text(schedule.slots(on: weekday).filter(\.isDemandingEndurance))
    return make(
      id: "load-\(PlanAdjustments.monday(of: today).iso)-\(weekday.rawValue)", source: .load,
      title: "\(weekday.long): \(titles) locker", reason: warning, profile: profile, adjustments: adjustments,
      week: today, evidenceIDs: load.evidenceIDs
    ) { $0.setWeekPlan(easing(schedule, on: weekday), base: profile.schedule, inWeekOf: today) }
  }

  /// Nach einer sehr harten Einheit: morgen entschärfen.
  public static func postWorkout(
    _ suggestion: PostWorkout.Suggestion, activityID: Int64, profile: UserProfile, adjustments: PlanAdjustments
  ) -> PlanSuggestion? {
    make(
      id: "post-\(activityID)-\(suggestion.day.iso)", source: .postWorkout, title: "Morgen locker",
      reason: suggestion.text, profile: profile, adjustments: adjustments, week: suggestion.day,
      evidenceIDs: ["intensity.distribution"]
    ) { $0.setWeekPlan(suggestion.schedule, base: profile.schedule, inWeekOf: suggestion.day) }
  }

  /// Wochenrückblick: Nach einer Woche mit deutlich mehr Belastung beginnt die nächste ohne harte Einheit am Anfang –
  /// die erste fordernde Ausdauereinheit wird locker.
  public static func nextWeek(
    load: WeekLoad.Result, profile: UserProfile, adjustments: PlanAdjustments, today: CalendarDay
  ) -> PlanSuggestion? {
    guard load.warning != nil else { return nil }
    let monday = PlanAdjustments.monday(of: today).adding(days: 7)
    let schedule = adjustments.schedule(profile.schedule, inWeekOf: monday)
    guard let weekday = Weekday.allCases.first(where: { schedule.slots(on: $0).contains(where: \.isDemandingEndurance) })
    else { return nil }
    return make(
      id: "next-\(monday.iso)", source: .nextWeek,
      title: "Nächste Woche ruhiger beginnen",
      reason:
        "Diese Woche lag die Belastung \(Int(((load.increase ?? 0) * 100).rounded())) % über dem Schnitt. "
        + "\(weekday.long) locker statt fordernd gibt dem Körper Zeit, sich anzupassen.",
      profile: profile, adjustments: adjustments, week: monday, evidenceIDs: load.evidenceIDs
    ) { $0.setWeekPlan(easing(schedule, on: weekday), base: profile.schedule, inWeekOf: monday) }
  }
}
