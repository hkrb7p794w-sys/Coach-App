import Foundation

/// Tagesnotiz für das persönliche Profil: dieselbe Idee wie `CoachingNote`, aber ohne Saisonplan-Werte
/// (keine FTP, Schwellenpace oder Almere). Die Empfehlung kommt aus `ScheduleAdvisor`; die KI formuliert sie nur.
public enum PersonalNote {
  public static let evidence = [
    "recovery.hrv", "recovery.rhr", "recovery.sleep", "recovery.subjective", "intensity.distribution", "load.rpe",
    "strength.interference", "run.progression",
  ]

  public static func input(
    profile: UserProfile, advice: ScheduleAdvice, recommendation: Recommendation?, metrics: DailyMetrics?,
    week: SessionMatcher.Week?, today: CalendarDay, privacy: PrivacyMode
  ) -> [String: JSONValue] {
    let results = week?.results ?? []
    let reasons =
      recommendation.map { privacy == .full ? $0.reasons : CoachingNote.neutralReasons($0, metrics) } ?? []
    var input: [String: JSONValue] = [
      "goal": .string(profile.goal.label),
      "sports": .array(profile.sports.map { .string($0.label) }),
      "weekday": .string(Weekday(day: today).long),
      "todayItems": .array(
        results.filter { $0.planned.day == today }.map {
          .string("\($0.planned.slot.title) (\($0.status.label))")
        }),
      "weekDone": .number(Double(results.filter(\.status.counts).count)),
      "weekPlanned": .number(Double(results.count)),
      "missed": .array(results.filter { $0.status == .missed }.map { .string($0.planned.slot.title) }),
      "vitals": .array(CoachingNote.vitals(metrics, privacy: privacy).map { .string($0) }),
      "decision": .object([
        "label": .string(advice.headline),
        "advice": .string(advice.detail),
        "reasons": .array(reasons.map { .string($0) }),
      ]),
      "evidence": CoachingNote.evidenceInput(evidence),
    ]
    if let event = profile.event {
      input["event"] = .string("\(event.name) in \(max(today.days(until: event.date), 0)) Tagen")
    }
    return input
  }

  /// Ohne KI: Empfehlung, Begründung und Stand der Woche als feste Sätze.
  public static func fallback(
    advice: ScheduleAdvice, recommendation: Recommendation?, week: SessionMatcher.Week?
  ) -> [String] {
    var lines = ["\(advice.headline): \(advice.detail)"]
    if let recommendation, !recommendation.reasons.isEmpty {
      lines.append("Grund: " + recommendation.reasons.joined(separator: "; ") + ".")
    }
    if let results = week?.results, !results.isEmpty {
      let done = results.filter(\.status.counts).count
      lines.append("Diese Woche: \(done) von \(results.count) Einheiten geschafft.")
    }
    return lines
  }
}
