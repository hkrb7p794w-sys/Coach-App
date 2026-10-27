import Foundation

/// Scheibenrechner: welche Scheiben je Seite auf die Langhantel gehören.
public enum PlateCalculator {
  public static let standardPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
  public static let standardBar = 20.0

  public struct Result: Equatable, Sendable {
    /// Scheiben je Seite, schwerste zuerst.
    public var perSide: [Double]
    /// Was mit den Scheiben nicht genau erreichbar ist (kg gesamt).
    public var remainder: Double
  }

  /// `nil`, wenn das Gewicht unter der Stange liegt.
  public static func plates(total: Double, bar: Double = standardBar, available: [Double] = standardPlates)
    -> Result?
  {
    guard total >= bar else { return nil }
    var side = (total - bar) / 2
    var result: [Double] = []
    for plate in available.sorted(by: >) {
      while side + 0.001 >= plate {
        result.append(plate)
        side -= plate
      }
    }
    return Result(perSide: result, remainder: ((side * 2) * 100).rounded() / 100)
  }

  public static func text(_ result: Result) -> String {
    guard !result.perSide.isEmpty else { return "Nur die Stange" }
    let plates = result.perSide.map { GermanFormat.number($0) }.joined(separator: " + ")
    let rest = result.remainder > 0 ? " (\(GermanFormat.number(result.remainder)) kg fehlen)" : ""
    return "Je Seite: \(plates) kg\(rest)"
  }
}

/// Aufwärmsätze vor schweren Grundübungen: steigend bis knapp unter das Arbeitsgewicht, wenige Wiederholungen.
/// Das Schema ist ein verbreiteter Praxiswert, kein Studienergebnis.
public enum WarmUp {
  public struct Step: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int
  }

  public static func steps(working: Double, equipment: [Equipment], compound: Bool) -> [Step] {
    guard compound else { return [] }
    if equipment.first == .barbell {
      guard working >= 40 else { return [] }
      let bar = PlateCalculator.standardBar
      var steps = [Step(weightKg: bar, reps: 10)]
      var shares: [(Double, Int)] = [(0.5, 5), (0.7, 3)]
      if working >= 60 { shares.append((0.85, 2)) }
      for (share, reps) in shares {
        let weight = (working * share / 2.5).rounded() * 2.5
        if weight > (steps.last?.weightKg ?? 0), weight < working { steps.append(Step(weightKg: weight, reps: reps)) }
      }
      return steps
    }
    if equipment.first == .dumbbell || equipment.first == .machine || equipment.first == .cable {
      guard working >= 12 else { return [] }
      return [(0.5, 8), (0.75, 4)].compactMap { share, reps in
        let weight = (working * share).rounded()
        return weight > 0 && weight < working ? Step(weightKg: weight, reps: reps) : nil
      }
    }
    return []
  }

  public static func text(_ steps: [Step]) -> String {
    "Aufwärmen: " + steps.map { "\(GermanFormat.number($0.weightKg)) kg × \($0.reps)" }.joined(separator: " · ")
  }
}
