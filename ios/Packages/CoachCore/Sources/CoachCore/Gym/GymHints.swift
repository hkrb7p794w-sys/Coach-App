import Foundation

/// Eingabe für die KI-Hinweise zur Gewichtssteigerung (Worker-Aufgabe `gym_hints`). Entschieden haben die
/// Progressionsregeln; die KI formuliert daraus kurze Hinweise und darf nur Zahlen aus dieser Eingabe nennen.
public enum GymHints {
  public static let evidence = ["gym.progression", "gym.rir", "gym.load", "gym.frequency", "gym.volume"]

  /// Zeile je Übung: aktueller Stand, Entscheidung und Begründung der Regel.
  public static func line(_ item: ExerciseProgress) -> String {
    let weight = item.weightKg > 0 ? "\(GermanFormat.number(item.weightKg)) kg" : "Körpergewicht"
    let reps = item.reps.map(String.init).joined(separator: "/")
    return "\(item.name): zuletzt \(weight) × \(reps) Wdh., Ziel \(item.target.lowerBound)–"
      + "\(item.target.upperBound) → \(item.headline). \(item.detail)"
  }

  public static func input(
    progress: [ExerciseProgress], recovered: Bool?, volume: [MuscleGroup: Int], goal: FitnessGoal?,
    observations: [String] = []
  ) -> [String: JSONValue] {
    let recovery =
      switch recovered {
      case true?: "gut"
      case false?: "eingeschränkt (Steigerung erst bei guter Tagesform)"
      case nil: "unbekannt"
      }
    let groups = MuscleVolume.groups.map { "\($0.rawValue): \(volume[$0] ?? 0) Sätze in 7 Tagen" }
    var input: [String: JSONValue] = [
      "exercises": .array(progress.prefix(10).map { .string(line($0)) }),
      "recovery": .string(recovery),
      "volume": .array(groups.map { .string($0) }),
      "evidence": CoachingNote.evidenceInput(evidence),
    ]
    // Stillstand, Volumen und Häufigkeit aus `GymCoach.observations`.
    if !observations.isEmpty { input["observations"] = .array(observations.prefix(6).map { .string($0) }) }
    if let goal { input["goal"] = .string(goal.label) }
    return input
  }

  /// Regelbasierte Hinweise, wenn die KI nicht erreichbar ist: die Übungen mit Handlungsbedarf zuerst.
  public static func fallback(
    _ progress: [ExerciseProgress], observations: [String] = [], limit: Int = 4
  ) -> [String] {
    let relevant = progress.filter { [.increase, .restart, .check].contains($0.status) }
    let items = relevant.isEmpty ? Array(progress.prefix(2)) : Array(relevant.prefix(limit))
    return items.map { "\($0.name): \($0.headline)." } + observations.prefix(2)
  }
}
