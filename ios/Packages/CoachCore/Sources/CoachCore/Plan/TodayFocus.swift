import Foundation

/// „Jetzt dran“: eine Karte für beide Modi. Heutige Einheiten mit Soll, Ampel, eine Zeile „warum“, der Widerspruch
/// zwischen Regel und Plan und der Wochenfortschritt. Nur die Quelle der Einheiten unterscheidet sich: Musterwoche
/// des Saisonplans oder eigener Wochenplan mit Soll/Ist.
public struct TodayFocus: Equatable, Sendable {
  public struct Item: Equatable, Sendable, Identifiable {
    public var id: String
    /// `nil` = Ruhetag bzw. Regeneration.
    public var sport: TrainingSport?
    public var title: String
    /// Soll bzw. Soll/Ist: „Soll 45 min · Locker“, Saisonplan: Pace/Watt aus dem Plan.
    public var target: String
    public var demanding: Bool
    public var status: SessionStatus?
    /// Hinweis bei gelber/roter Ampel („nicht heute“).
    public var chip: String
    /// Ablauf zum Aufklappen.
    public var detail: String
  }

  public struct Progress: Equatable, Sendable {
    public var sessionsDone: Int
    public var sessionsPlanned: Int
    public var minutesDone: Int
    public var minutesPlanned: Int?

    public var fraction: Double {
      if let minutesPlanned, minutesPlanned > 0 { return min(Double(minutesDone) / Double(minutesPlanned), 1) }
      return sessionsPlanned > 0 ? min(Double(sessionsDone) / Double(sessionsPlanned), 1) : 0
    }

    /// „3/5 Einheiten · 140/210 min“
    public var text: String {
      "\(sessionsDone)/\(sessionsPlanned) Einheiten · "
        + (minutesPlanned.map { "\(minutesDone)/\($0) min" } ?? "\(minutesDone) min")
    }
  }

  /// `nil`, wenn noch keine Erholungswerte vorliegen.
  public var level: RecoveryLevel?
  public var headline: String
  public var detail: String
  public var why: String?
  /// Regel und Plan widersprechen sich – beides steht da, die Regel gilt.
  public var conflict: String?
  public var items: [Item]
  public var progress: Progress
  public var evidenceIDs: [String]

  // MARK: - Eigener Wochenplan

  public static func personal(
    advice: ScheduleAdvice, recommendation: Recommendation?, week: SessionMatcher.Week,
    activities: [GarminActivity], today: CalendarDay
  ) -> TodayFocus {
    let items = week.results(on: today).map { result in
      let slot = result.planned.slot
      return Item(
        id: result.id, sport: slot.sport, title: slot.title,
        target: result.actualMinutes == nil
          ? "Soll \(result.planned.targetMinutes) min · \(slot.intensity.label)" : result.compareText,
        demanding: slot.intensity.isDemanding, status: result.status, chip: "", detail: slot.guide)
    }
    let level = recommendation?.level
    let planned = week.results.map(\.planned)
    let totals = SessionMatcher.totals(planned: planned, activities: activities, monday: PlanAdjustments.monday(of: today))
    let progress = Progress(
      sessionsDone: week.results.filter(\.status.counts).count, sessionsPlanned: week.results.count,
      minutesDone: totals.reduce(0) { $0 + $1.actual },
      minutesPlanned: planned.isEmpty ? nil : planned.reduce(0) { $0 + $1.targetMinutes })
    let reasons = recommendation?.reasons ?? []
    return TodayFocus(
      level: level, headline: advice.headline, detail: advice.detail, why: why(reasons),
      conflict: advice.mode == .done
        ? nil : conflict(level: level, reasons: reasons, planned: items.filter(\.demanding).map(\.title)),
      items: items, progress: progress,
      evidenceIDs: Array(Set(advice.evidenceIDs + (recommendation?.evidenceIDs ?? []))).sorted())
  }

  // MARK: - Saisonplan

  public static func season(
    today: TodayPlan, recommendation: Recommendation, hasMetrics: Bool, plan: PlanState, week: WeeklyVolume
  ) -> TodayFocus {
    let items = today.items.map { item in
      Item(
        id: item.id, sport: sport(item.sport), title: item.title, target: item.caption, demanding: item.hardness >= 2,
        status: item.done ? .done : nil, chip: item.chip, detail: item.detail)
    }
    let level = hasMetrics ? recommendation.level : nil
    let progress = Progress(
      sessionsDone: plan.targets.reduce(0) { $0 + min($1.done, $1.target.minimum) },
      sessionsPlanned: plan.targets.reduce(0) { $0 + $1.target.minimum },
      minutesDone: Int(week.minutes.values.reduce(0, +).rounded()), minutesPlanned: nil)
    let reasons = hasMetrics ? recommendation.reasons : []
    return TodayFocus(
      level: level, headline: recommendation.label, detail: today.advice, why: why(reasons),
      conflict: conflict(level: level, reasons: reasons, planned: items.filter { $0.demanding && $0.status == nil }
        .map(\.title)),
      items: items, progress: progress, evidenceIDs: recommendation.evidenceIDs)
  }

  static func sport(_ sport: TodayPlan.Sport) -> TrainingSport? {
    switch sport {
    case .swim: .swim
    case .bike: .bike
    case .run: .run
    case .strength: .strength
    case .rest: nil
    }
  }

  /// Unauffällige Gründe („HRV-Status ausgeglichen“) sind keine Begründung wert.
  static func why(_ reasons: [String]) -> String? {
    let relevant = reasons.filter { $0 != "keine Erholungswerte auffällig" && $0 != "HRV-Status ausgeglichen" }
    return relevant.isEmpty ? nil : relevant.joined(separator: " · ")
  }

  /// „Regel: locker (HRV unter Baseline) · geplant: Qualitätslauf“ – die KI darf die Regel nicht überstimmen.
  static func conflict(level: RecoveryLevel?, reasons: [String], planned: [String]) -> String? {
    guard let level, level != .normal, !planned.isEmpty else { return nil }
    let rule = level == .pause ? "Pause" : "locker"
    let because = why(reasons).map { " (\($0))" } ?? ""
    return "Regel: \(rule)\(because) · geplant: \(planned.joined(separator: ", ")). Es gilt die Regel."
  }
}
