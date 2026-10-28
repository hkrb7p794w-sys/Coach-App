import Foundation

/// Nach dem Training: Anstrengung abfragen, gegen den Plan auswerten und – wenn nötig – den nächsten Tag
/// entschärfen. Die Regeln entscheiden; die Texte sind feste Bausteine.
public enum PostWorkout {
  /// Ab dieser Anstrengung (1–10, Borg CR10) gilt eine Einheit als hart.
  public static let hardEffort = 7
  /// Bis zu dieser Anstrengung als locker.
  public static let easyEffort = 4
  /// Ab hier wird der nächste Tag entschärft, wenn dort Fordernes geplant ist.
  public static let veryHardEffort = 8

  public struct Suggestion: Equatable, Sendable {
    public var day: CalendarDay
    public var text: String
    /// Wochenplan der betroffenen Woche mit entschärftem Tag.
    public var schedule: WeekSchedule
  }

  public struct Review: Equatable, Sendable {
    public var headline: String
    public var points: [String]
    public var tomorrow: Suggestion?
    public var evidenceIDs: [String]
  }

  /// `tomorrowSchedule` ist der Plan der Woche, in der `tomorrow` liegt (mit Ausnahmen). `planKnown` = es gibt eine
  /// Soll/Ist-Zuordnung (persönliches Profil); im Saisonplan fehlt sie, dann kein „außerplanmäßig“.
  public static func review(
    activity: GarminActivity, effort: Int?, planned: SessionResult?, planKnown: Bool = true, tomorrow: CalendarDay,
    tomorrowSchedule: WeekSchedule?
  ) -> Review {
    let measuredHard = SessionKind.isHard(activity) && activity.sport != .strength
    let feltHard = effort.map { $0 >= hardEffort } ?? false
    let feltEasy = effort.map { $0 <= easyEffort } ?? false
    var points: [String] = []
    var evidence: [String] = []
    var headline = "Gut gemacht"

    if let planned {
      let slot = planned.planned.slot
      switch planned.status {
      case .partial:
        headline = "Kürzer als geplant"
        points.append("\(planned.compareText) – zählt trotzdem; nicht am nächsten Tag dranhängen.")
      case .substituted:
        headline = "Anders gemacht"
        points.append("Statt \(slot.title) – zählt für die Ausdauer, die Woche bleibt im Rahmen.")
      default:
        headline = "Wie geplant"
        points.append("\(slot.title): \(planned.compareText).")
      }
      if slot.intensity == .easy, measuredHard || feltHard {
        points.append(
          "Für eine lockere Einheit war das hart. Locker heißt: Unterhalten geht noch. Viel lockeres Training ist "
            + "die Grundlage, auf der die harten Tage wirken.")
        evidence.append("intensity.distribution")
      } else if slot.intensity == .hard, !measuredHard, feltEasy {
        points.append("Lockerer als geplant – zählt als Grundlage, die Intensität nicht nachholen.")
      }
    } else if planKnown, activity.sport != .strength {
      headline = "Außerplanmäßig"
      points.append("Nicht im Plan – zählt für Wochenumfang und Belastung.")
    }
    if let effort, let minutes = activity.durationSeconds.map({ Int(($0 / 60).rounded()) }) {
      let load = Int(ManualActivity.estimatedLoad(minutes: minutes, effort: effort).rounded())
      points.append("Anstrengung \(effort)/10 × \(minutes) min ≈ Belastung \(load) (session RPE).")
      evidence.append("load.rpe")
    }

    var suggestion: Suggestion?
    let wasHard = (effort ?? 0) >= veryHardEffort || (measuredHard && (effort ?? hardEffort) >= hardEffort)
    if let tomorrowSchedule, wasHard {
      let weekday = Weekday(day: tomorrow)
      let slots = tomorrowSchedule.slots(on: weekday)
      if slots.contains(where: \.isDemandingEndurance) {
        var adjusted = tomorrowSchedule
        adjusted.set(
          slots.map { $0.isDemandingEndurance ? SessionSlot($0.sport, .easy) : $0 }, on: weekday)
        let titles = slots.filter(\.isDemandingEndurance).map(\.title).joined(separator: ", ")
        suggestion = Suggestion(
          day: tomorrow,
          text: "Morgen (\(weekday.long)) \(titles) locker statt fordernd – zwei harte Tage "
            + "hintereinander bringen wenig und kosten Erholung.", schedule: adjusted)
        evidence.append("intensity.distribution")
      }
    }
    return Review(headline: headline, points: points, tomorrow: suggestion, evidenceIDs: Array(Set(evidence)).sorted())
  }
}
