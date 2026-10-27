import Foundation

/// Hinweis zu einer Eingabe (Körperdaten, Ziele): unplausibel, sehr ehrgeizig oder realistisch.
public struct InputIssue: Equatable, Sendable, Identifiable {
  public enum Severity: Int, Comparable, Sendable {
    case info = 0, tip, warning

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
  }

  public let id: String
  public let severity: Severity
  public let message: String
  public let evidenceIDs: [String]
}

/// Prüft Eingaben, bevor die App damit rechnet: Tippfehler bei Körperdaten, widersprüchliche Ziele und Zielzeiten
/// im Vergleich zur Wettkampfprognose der Uhr.
public enum InputCheck {
  /// Ab so viel schneller als die Prognose gilt ein Ziel als sehr ehrgeizig (Praxiswert).
  static let veryAmbitious = 0.90
  static let ambitious = 0.97

  public static func body(_ body: BodyProfile) -> [InputIssue] {
    var issues: [InputIssue] = []
    if !(30...250).contains(body.weightKilograms) {
      issues.append(
        InputIssue(
          id: "weight", severity: .warning,
          message: "Gewicht \(GermanFormat.number(body.weightKilograms)) kg wirkt unplausibel – bitte prüfen.",
          evidenceIDs: []))
    }
    if !(120...230).contains(body.heightCentimeters) {
      issues.append(
        InputIssue(
          id: "height", severity: .warning,
          message: "Größe \(GermanFormat.number(body.heightCentimeters)) cm wirkt unplausibel – bitte prüfen.",
          evidenceIDs: []))
    }
    if !(14...100).contains(body.age) {
      issues.append(
        InputIssue(
          id: "age", severity: .warning, message: "Alter \(body.age) wirkt unplausibel – bitte prüfen.", evidenceIDs: []
        ))
    }
    return issues
  }

  public static func goals(
    profile: UserProfile, body: BodyProfile, predictions: RacePredictions?, today: CalendarDay
  ) -> [InputIssue] {
    var issues: [InputIssue] = []
    let targets = profile.targets
    if let target = targets.targetWeightKilograms {
      if profile.goal.losesWeight, target >= body.weightKilograms {
        issues.append(
          InputIssue(
            id: "target-weight-direction", severity: .warning,
            message:
              "Dein Ziel ist Abnehmen, das Zielgewicht (\(GermanFormat.number(target)) kg) liegt aber nicht unter "
              + "deinem Gewicht (\(GermanFormat.number(body.weightKilograms)) kg).",
            evidenceIDs: []))
      }
      if profile.goal.gainsWeight, target <= body.weightKilograms {
        issues.append(
          InputIssue(
            id: "target-weight-direction", severity: .warning,
            message:
              "Dein Ziel ist Zunehmen, das Zielgewicht (\(GermanFormat.number(target)) kg) liegt aber nicht über "
              + "deinem Gewicht (\(GermanFormat.number(body.weightKilograms)) kg).",
            evidenceIDs: []))
      }
    }
    if let pulse = targets.restingHeartRate, !(38...90).contains(pulse) {
      issues.append(
        InputIssue(
          id: "resting-hr", severity: .tip,
          message: "Ein Ruhepuls-Ziel von \(pulse) bpm ist ungewöhnlich – bitte prüfen.", evidenceIDs: ["rhr.endurance"]
        ))
    }
    if let event = profile.event {
      let days = today.days(until: event.date)
      if days < 0 {
        issues.append(
          InputIssue(
            id: "event-past", severity: .warning,
            message: "„\(event.name)“ liegt in der Vergangenheit. Trage ein neues Ziel ein oder entferne es.",
            evidenceIDs: []))
      } else if let distance = event.kind.distanceKilometers, let target = event.targetSeconds,
        let predicted = predictedSeconds(distanceKilometers: distance, predictions: predictions)
      {
        issues.append(
          compare(
            id: "event-time", target: Double(target), predicted: predicted,
            what: "Zielzeit \(time(Double(target))) für \(event.kind.label)", weeks: days / 7))
      }
    }
    if let distance = targets.runDistanceKilometers, let pace = targets.runPaceSecondsPerKilometer,
      let predicted = predictedSeconds(distanceKilometers: distance, predictions: predictions)
    {
      issues.append(
        compare(
          id: "run-pace", target: Double(pace) * distance, predicted: predicted,
          what: "Zielpace \(paceText(Double(pace))) /km über \(GermanFormat.number(distance)) km", weeks: nil))
    }
    return issues.sorted { $0.severity > $1.severity }
  }

  /// Vergleich mit der Prognose der Uhr; die Schwellen 3 % und 10 % sind Praxiswerte.
  static func compare(id: String, target: Double, predicted: Double, what: String, weeks: Int?) -> InputIssue {
    let ratio = target / predicted
    let faster = Int(((1 - ratio) * 100).rounded())
    let prognosis = "Prognose deiner Uhr: \(time(predicted))"
    let timeLeft = weeks.map { " Bis zum Wettkampf bleiben \($0) Wochen." } ?? ""
    if ratio < veryAmbitious {
      return InputIssue(
        id: id, severity: .warning,
        message:
          "\(what) ist \(faster) % schneller als die \(prognosis). Das ist sehr ehrgeizig – plane lieber ein "
          + "Zwischenziel.\(timeLeft)",
        evidenceIDs: [])
    }
    if ratio < ambitious {
      return InputIssue(
        id: id, severity: .tip,
        message: "\(what) ist \(faster) % schneller als die \(prognosis): ehrgeizig, aber erreichbar.\(timeLeft)",
        evidenceIDs: [])
    }
    return InputIssue(
      id: id, severity: .info, message: "\(what) passt zur \(prognosis) – realistisch.\(timeLeft)", evidenceIDs: [])
  }

  /// Prognose für eine Strecke: direkt oder zwischen zwei Prognosen der Uhr interpoliert (log-log). Außerhalb der
  /// Spanne 5 km bis Marathon gibt es keine Schätzung.
  public static func predictedSeconds(distanceKilometers: Double, predictions: RacePredictions?) -> Double? {
    guard let predictions else { return nil }
    let points = [
      (5.0, predictions.fiveK), (10.0, predictions.tenK), (21.0975, predictions.halfMarathon),
      (42.195, predictions.marathon),
    ].compactMap { distance, seconds in seconds.map { (distance, $0) } }
    if let exact = points.first(where: { abs($0.0 - distanceKilometers) < 0.05 }) { return exact.1 }
    for (lower, upper) in zip(points, points.dropFirst())
    where lower.0 < distanceKilometers && distanceKilometers < upper.0 {
      let share = log(distanceKilometers / lower.0) / log(upper.0 / lower.0)
      return exp(log(lower.1) + share * (log(upper.1) - log(lower.1)))
    }
    return nil
  }

  static func time(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = total % 3600 / 60
    let rest = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d h", hours, minutes, rest) : String(format: "%d:%02d min", minutes, rest)
  }

  static func paceText(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}
