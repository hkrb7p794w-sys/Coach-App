import Foundation

/// Empfehlung für heute, abgeleitet aus dem eigenen Wochenplan und der Erholung. Die Regeln entscheiden;
/// formuliert wird mit festen Sätzen, die KI kann sie bei Bedarf umschreiben.
public struct ScheduleAdvice: Equatable, Sendable {
  public enum Mode: String, Sendable {
    /// Einheit wie geplant.
    case asPlanned
    /// Dieselbe Einheit, aber lockerer.
    case lighter
    /// Heute besser frei, ggf. mit Vorschlag zum Verschieben.
    case rest
    /// Laut Plan frei.
    case restDay
    /// Heute schon trainiert.
    case done
  }

  public var mode: Mode
  public var headline: String
  public var detail: String
  /// Vorgeschlagener Tag, auf den eine Einheit verschoben werden kann.
  public var move: Weekday?
  public var plannedTitles: [String]
  public var evidenceIDs: [String]
}

public enum ScheduleAdvisor {
  /// - Parameters:
  ///   - recovery: Tagesampel aus Garmin-Werten; `nil`, wenn heute noch keine Werte vorliegen.
  ///   - trainedToday: Für heute ist schon eine Aktivität aufgezeichnet.
  ///   - schedule: Plan dieser Woche mit Ausnahmen (`PlanAdjustments`); Standard ist der Wochenplan des Profils.
  public static func advice(
    profile: UserProfile, schedule: WeekSchedule? = nil, day: CalendarDay, recovery: RecoveryLevel?,
    trainedToday: Bool
  ) -> ScheduleAdvice {
    let schedule = schedule ?? profile.schedule
    let weekday = Weekday(day: day)
    let slots = schedule.slots(on: weekday)
    let titles = slots.map(\.title)
    let joined = titles.joined(separator: " + ")
    let demanding = slots.contains { $0.intensity.isDemanding }
    let tomorrow = tomorrowNote(schedule.slots(on: weekday.next), weekday.next)
    let recoveryEvidence = ["recovery.hrv", "recovery.subjective"]

    if slots.isEmpty {
      let base =
        recovery == .pause
        ? "Dein Plan sieht heute frei vor – gut, denn deine Erholung ist niedrig. Schlafe ausreichend und bewege dich nur locker."
        : "Heute ist laut deinem Plan frei. Nutze den Tag zur Erholung; ein Spaziergang ist in Ordnung."
      return ScheduleAdvice(
        mode: .restDay, headline: "Ruhetag", detail: "\(base) \(tomorrow)", move: nil, plannedTitles: [],
        evidenceIDs: recovery == .pause ? recoveryEvidence : [])
    }

    if trainedToday {
      return ScheduleAdvice(
        mode: .done, headline: "Geschafft",
        detail: "Heute hast du trainiert. Jetzt gut essen und erholen. \(tomorrow)", move: nil, plannedTitles: titles,
        evidenceIDs: [])
    }

    switch recovery {
    case .pause?:
      if demanding {
        let target = schedule.nextRestDay(after: weekday, within: 3)
        var detail = "Deine Erholung ist niedrig. Mache heute nur einen lockeren Spaziergang und hole "
        detail += "\(joined) nach, sobald die Erholung wieder passt."
        if let target {
          detail = "Deine Erholung ist niedrig. Verschiebe \(joined) auf \(target.long), deinen nächsten freien Tag, "
          detail += "und ruhe dich heute aus."
        }
        return ScheduleAdvice(
          mode: .rest, headline: "Heute besser frei", detail: detail, move: target, plannedTitles: titles,
          evidenceIDs: recoveryEvidence)
      }
      return ScheduleAdvice(
        mode: .rest, headline: "Heute nur ganz locker oder frei",
        detail: "Deine Erholung ist niedrig. Statt \(joined) reicht heute Bewegung im Alltag oder ein Spaziergang.",
        move: nil, plannedTitles: titles, evidenceIDs: recoveryEvidence)

    case .locker?:
      let detail =
        demanding
        ? "Deine Erholung ist nur mittel. Mache \(joined) heute lockerer: kürzer, ohne Tempo bzw. mit leichteren "
          + "Gewichten, und höre auf deinen Körper."
        : "Deine Erholung ist nur mittel. Halte \(joined) heute ruhig und eher kurz."
      return ScheduleAdvice(
        mode: .lighter, headline: "Heute lockerer", detail: "\(detail) \(tomorrow)", move: nil, plannedTitles: titles,
        evidenceIDs: recoveryEvidence)

    case .normal?:
      return ScheduleAdvice(
        mode: .asPlanned, headline: joined,
        detail: "Deine Erholung passt – ziehe die Einheit wie geplant durch. \(tomorrow)", move: nil,
        plannedTitles: titles, evidenceIDs: [])

    case nil:
      return ScheduleAdvice(
        mode: .asPlanned, headline: joined,
        detail: "Für heute liegen noch keine Garmin-Werte vor. Richte dich nach deinem Gefühl. \(tomorrow)",
        move: nil, plannedTitles: titles, evidenceIDs: [])
    }
  }

  static func tomorrowNote(_ slots: [SessionSlot], _ weekday: Weekday) -> String {
    slots.isEmpty
      ? "Morgen (\(weekday.long)) ist frei."
      : "Morgen (\(weekday.long)): \(slots.map(\.title).joined(separator: " + "))."
  }
}
