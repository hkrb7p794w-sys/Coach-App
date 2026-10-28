import Foundation

/// Wochenbelastung über alle Sportarten: letzte 7 Tage gegen den Wochenschnitt der drei Wochen davor, wie die
/// Laufumfang-Regel (`LoadCheck`), aber mit der Belastung statt Kilometern. Grundlage ist die Belastung der Uhr; ohne
/// sie schätzt die App aus Dauer × Intensität (nachgetragene Einheiten: Dauer × Anstrengung, Foster et al. 2001).
/// Ab 30 % mehr gibt es einen Hinweis zum Dosieren – als Verletzungsvorhersage ist so ein Verhältnis nicht belegt
/// (Impellizzeri et al. 2020).
public enum WeekLoad {
  public static let maxIncrease = 0.30
  /// Unter dieser Differenz wird nicht gewarnt (etwa eine Stunde lockeres Training).
  public static let minimumDifference = 60.0
  /// Geschätzte Belastung je Minute ohne Wert der Uhr, in der Größenordnung von Garmin und session RPE
  /// (locker ≈ Anstrengung 4, hart ≈ 8, Kraft ≈ 4).
  public static let easyPerMinute = 1.0
  public static let hardPerMinute = 2.0
  public static let strengthPerMinute = 1.0
  /// Gym-Einheit der App ohne Endzeit.
  static let defaultGymMinutes = 45

  public struct Result: Equatable, Sendable {
    public var last: Double
    public var baseline: Double
    /// Belastung der letzten 7 Tage je Sportart.
    public var bySport: [TrainingSport: Double]
    /// Anteil der letzten 7 Tage, der geschätzt ist (0…1).
    public var estimatedShare: Double
    public var increase: Double?
    public var warning: String?

    public var evidenceIDs: [String] { ["load.weekly", "load.rpe"] }
  }

  /// Belastung einer Aktivität: Wert der Uhr, sonst aus Dauer und Intensität geschätzt.
  public static func load(_ activity: GarminActivity) -> (value: Double, estimated: Bool) {
    if let load = activity.trainingLoad, load > 0 { return (load, false) }
    let minutes = (activity.durationSeconds ?? 0) / 60
    guard minutes > 0 else { return (0, true) }
    if activity.sport == .strength { return (minutes * strengthPerMinute, true) }
    return (minutes * (SessionKind.isHard(activity) ? hardPerMinute : easyPerMinute), true)
  }

  /// Gym-Einheiten der App, die schon als Garmin-Krafttraining vorliegen, zählen nur einmal (`ActivityFeed`).
  public static func check(
    activities: [GarminActivity], gym: [ActivityFeed.GymItem] = [], today: CalendarDay,
    timeZone: TimeZone = .current
  ) -> Result {
    let start = today.adding(days: -27)
    let recent = activities.filter { ($0.day.map { $0 >= start && $0 <= today }) ?? false }
    let recentGym = gym.filter {
      let day = CalendarDay(date: $0.start, timeZone: timeZone)
      return day >= start && day <= today
    }
    var last = 0.0
    var estimated = 0.0
    var earlier = 0.0
    var bySport: [TrainingSport: Double] = [:]
    let lastStart = today.adding(days: -6)
    for entry in ActivityFeed.entries(activities: recent, gym: recentGym, timeZone: timeZone) {
      let (value, isEstimate): (Double, Bool) =
        if let activity = entry.activity {
          load(activity)
        } else {
          (Double(entry.gym?.minutes ?? defaultGymMinutes) * strengthPerMinute, true)
        }
      if entry.day >= lastStart {
        last += value
        if isEstimate { estimated += value }
        bySport[SessionMatcher.sport(entry.sport), default: 0] += value
      } else {
        earlier += value
      }
    }
    let baseline = earlier / 3
    var result = Result(
      last: last.rounded(), baseline: baseline.rounded(), bySport: bySport.mapValues { $0.rounded() },
      estimatedShare: last > 0 ? estimated / last : 0)
    guard baseline > 0 else { return result }
    let increase = last / baseline - 1
    result.increase = (increase * 100).rounded() / 100
    if increase > maxIncrease, last - baseline >= minimumDifference {
      result.warning =
        "Belastung der letzten 7 Tage über alle Sportarten: \(Int(result.last)), "
        + "\(Int((increase * 100).rounded())) % mehr als im Schnitt der drei Wochen davor (\(Int(result.baseline))). "
        + "Plane die nächsten Tage eher locker."
        + (result.estimatedShare > 0.5 ? " Ein Großteil ist aus Dauer und Intensität geschätzt." : "")
    }
    return result
  }
}

extension FitnessForm {
  /// Unter dieser Form (in % der Fitness, Zone „sehr hohe Belastung“) rät die Ampel zu lockerem Training. Praxiswert;
  /// nie zu einer Pause, denn als Vorhersage taugt die Kurve nicht.
  public static let lockerBelowPercent = -30.0
  static let reasonPrefix = "Form "

  /// Grund für die Ampel, wenn die Ermüdung weit über der Fitness liegt (nur bei eingeschwungener Kurve).
  public static func recoveryReason(_ points: [Point]) -> String? {
    guard isReliable(points), let percent = points.last?.formPercent, percent < lockerBelowPercent else {
      return nil
    }
    return "\(reasonPrefix)\(Int(percent.rounded())) % der Fitness – Ermüdung weit über dem Gewohnten"
  }
}

extension Recommendation {
  /// Tagesampel mit der Form: sehr negative Form ergibt höchstens „locker“ (eine Pause bleibt eine Pause).
  public func limited(byForm points: [FitnessForm.Point]) -> Recommendation {
    guard let reason = FitnessForm.recoveryReason(points) else { return self }
    return Recommendation(level: max(level, .locker), reasons: reasons + [reason])
  }

  /// Die Form hat die Ampel mitbestimmt.
  public var isLimitedByForm: Bool { reasons.contains { $0.hasPrefix(FitnessForm.reasonPrefix) } }
}
