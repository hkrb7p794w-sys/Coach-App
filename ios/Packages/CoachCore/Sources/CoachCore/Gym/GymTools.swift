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

/// Aufwärmsätze nach Übung und Arbeitsgewicht: bei schweren Grundübungen steigend bis knapp unter das Arbeitsgewicht,
/// bei schweren Isolationsübungen ein Satz, bei leichten keiner. Ist der Muskel in dieser Einheit schon gearbeitet,
/// genügt ein Einstiegssatz. Das Schema ist ein verbreiteter Praxiswert, kein Studienergebnis.
public enum WarmUp {
  public struct Step: Equatable, Sendable {
    public var weightKg: Double
    public var reps: Int
  }

  /// Darunter lohnt bei Isolationsübungen kein eigener Aufwärmsatz.
  static let isolationMinimumKg = 15.0

  public static func steps(
    working: Double, equipment: [Equipment], compound: Bool, bar: Double = PlateCalculator.standardBar,
    level: ExperienceLevel? = nil, warmedUp: Bool = false
  ) -> [Step] {
    guard working > 0, let first = equipment.first, first != .bodyweight else { return [] }
    let step = first == .barbell ? 2.5 : 1
    func feeler(_ share: Double, _ reps: Int) -> [Step] {
      let weight = (working * share / step).rounded() * step
      return weight > 0 && weight < working ? [Step(weightKg: weight, reps: reps)] : []
    }
    guard compound else {
      guard !warmedUp, working >= isolationMinimumKg else { return [] }
      return feeler(0.6, 10)
    }
    if warmedUp { return working >= 20 ? feeler(0.7, 3) : [] }
    if first == .barbell {
      guard working >= max(40, bar * 2) else { return [] }
      var steps = [Step(weightKg: bar, reps: 10)]
      var shares: [(Double, Int)] = [(0.5, 5), (0.7, 3)]
      // Einsteiger:innen bewegen wenig Last; ein Satz nah am Arbeitsgewicht ermüdet dann nur.
      if working >= 60, level != .beginner { shares.append((0.85, 2)) }
      for (share, reps) in shares {
        let weight = (working * share / 2.5).rounded() * 2.5
        if weight > (steps.last?.weightKg ?? 0), weight < working { steps.append(Step(weightKg: weight, reps: reps)) }
      }
      return steps
    }
    if first == .dumbbell || first == .machine || first == .cable {
      guard working >= 12 else { return [] }
      return [(0.5, 8), (0.75, 4)].compactMap { share, reps in
        let weight = (working * share).rounded()
        return weight > 0 && weight < working ? Step(weightKg: weight, reps: reps) : nil
      }
    }
    return []
  }

  /// Hat eine andere Übung derselben Muskelgruppe in dieser Einheit schon erledigte Sätze?
  public static func isWarmedUp(_ exercise: LoggedExercise, info: ExerciseInfo?, in session: GymSession) -> Bool {
    guard let info else { return false }
    return session.exercises.contains { $0.id != exercise.id && $0.group == info.group && !$0.doneSets.isEmpty }
  }

  /// Vorschlag vor dem ersten Arbeitssatz: nur solange die Übung noch keine Aufwärm- und keine erledigten Sätze hat;
  /// Gewichte aus dem schwersten geplanten Arbeitssatz.
  public static func suggestion(
    for exercise: LoggedExercise, info: ExerciseInfo?, bar: Double, level: ExperienceLevel? = nil,
    warmedUp: Bool = false
  ) -> [Step] {
    guard let info, !exercise.sets.contains(where: { $0.kind == .warmup || $0.done }) else { return [] }
    let working = exercise.sets.filter { $0.kind != .warmup }.map(\.weightKg).max() ?? 0
    return steps(
      working: working, equipment: info.equipment, compound: info.compound, bar: bar, level: level, warmedUp: warmedUp)
  }

  public static func text(_ steps: [Step]) -> String {
    "Aufwärmen: " + steps.map { "\(GermanFormat.number($0.weightKg)) kg × \($0.reps)" }.joined(separator: " · ")
  }
}

/// Pausenauswahl und -anzeige: „45 s“, „1:30 min“, „3 min“.
public enum RestText {
  public static let options = [30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300]

  public static func format(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds) s" }
    let rest = seconds % 60
    return rest == 0 ? "\(seconds / 60) min" : String(format: "%d:%02d min", seconds / 60, rest)
  }
}

/// Halteübungen (Plank, Wandsitzen): Stoppuhr statt Eintippen. Die gemessene Zeit wird übernommen und lässt sich
/// danach korrigieren (zu spät gestoppt, Handy erst nach dem Hinlegen gestartet).
public enum HoldTimer {
  /// Auf ganze Sekunden gerundet, mindestens 1.
  public static func seconds(from start: Date, to end: Date) -> Int {
    max(1, Int(end.timeIntervalSince(start).rounded()))
  }

  /// Korrektur in ±1/±5 s, nie unter 1 s.
  public static func corrected(_ seconds: Int, by delta: Int) -> Int {
    max(1, seconds + delta)
  }

  /// „noch 12 s“ bis zum Ziel bzw. „+8 s über Ziel“.
  public static func targetText(elapsed: Int, target: Int) -> String {
    elapsed < target ? "noch \(target - elapsed) s bis \(target) s" : "+\(elapsed - target) s über Ziel"
  }
}
