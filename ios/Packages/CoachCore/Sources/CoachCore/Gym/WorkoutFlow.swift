import Foundation

/// Ablauf der laufenden Einheit für die Fokus-Karte: welcher Satz ist jetzt dran, was kommt danach, was fehlt
/// beim Beenden. Im Gym zählt nur „Was mache ich jetzt?“ – die App sucht den Satz, nicht die Person.
public enum WorkoutFlow {
  public struct Position: Equatable, Hashable, Sendable {
    public var exercise: Int
    public var set: Int

    public init(exercise: Int, set: Int) {
      self.exercise = exercise
      self.set = set
    }
  }

  /// Nächster offener Satz: zuerst in der gewählten Übung, sonst ab dort die nächste Übung mit offenem Satz
  /// (am Ende wieder von vorn – übersprungene Übungen kommen so zum Schluss dran).
  public static func current(in session: GymSession, preferring exerciseID: UUID? = nil) -> Position? {
    let exercises = session.exercises
    guard !exercises.isEmpty else { return nil }
    let start = exerciseID.flatMap { id in exercises.firstIndex { $0.id == id } } ?? 0
    for offset in 0..<exercises.count {
      let index = (start + offset) % exercises.count
      if let set = exercises[index].sets.firstIndex(where: { !$0.done }) {
        return Position(exercise: index, set: set)
      }
    }
    return nil
  }

  /// Der Satz nach `position`, als Vorschau („Als Nächstes“).
  public static func upcoming(after position: Position, in session: GymSession) -> Position? {
    var copy = session
    guard copy.exercises.indices.contains(position.exercise),
      copy.exercises[position.exercise].sets.indices.contains(position.set)
    else { return nil }
    copy.exercises[position.exercise].sets[position.set].done = true
    return current(in: copy, preferring: copy.exercises[position.exercise].id)
  }

  /// Fortschritt einer Übung, z. B. „2/4“.
  public static func progress(of exercise: LoggedExercise) -> (done: Int, total: Int) {
    (exercise.sets.filter(\.done).count, exercise.sets.count)
  }

  public struct Summary: Equatable, Sendable {
    public var minutes: Int
    public var doneSets: Int
    public var volumeKg: Double
    public var exercises: Int
    /// Nicht abgehakte Sätze mit eingetragenen Wiederholungen – vermutlich gemacht und vergessen.
    public var openSets: Int
  }

  public static func summary(of session: GymSession, now: Date = .now) -> Summary {
    let open = session.exercises.reduce(0) { count, exercise in
      count + exercise.sets.filter { !$0.done && $0.reps > 0 }.count
    }
    return Summary(
      minutes: max(0, Int(((session.end ?? now).timeIntervalSince(session.start) / 60).rounded())),
      doneSets: session.doneSetCount, volumeKg: session.volumeKg,
      exercises: session.exercises.filter { !$0.doneSets.isEmpty }.count, openSets: open)
  }

  /// Übernimmt alle offenen Sätze mit Wiederholungen als erledigt.
  public static func completingOpenSets(_ session: GymSession) -> GymSession {
    var copy = session
    for exercise in copy.exercises.indices {
      for set in copy.exercises[exercise].sets.indices where copy.exercises[exercise].sets[set].reps > 0 {
        copy.exercises[exercise].sets[set].done = true
      }
    }
    return copy
  }
}

/// Eingabe über den großen Ziffernblock (Gewicht mit Komma, Wiederholungen ganzzahlig).
public enum NumberPad {
  public enum Key: Equatable, Sendable {
    case digit(Int)
    case comma
    case delete
  }

  /// Hängt eine Taste an den Text an. Gewichte erlauben ein Komma und zwei Nachkommastellen, höchstens 4 Ziffern
  /// vor dem Komma; Wiederholungen höchstens 3 Ziffern.
  public static func apply(_ key: Key, to text: String, allowsDecimals: Bool) -> String {
    switch key {
    case .delete:
      return String(text.dropLast())
    case .comma:
      guard allowsDecimals, !text.contains(",") else { return text }
      return (text.isEmpty ? "0" : text) + ","
    case .digit(let digit):
      guard (0...9).contains(digit) else { return text }
      if let comma = text.firstIndex(of: ",") {
        return text[text.index(after: comma)...].count < 2 ? text + "\(digit)" : text
      }
      let limit = allowsDecimals ? 4 : 3
      if text == "0" { return "\(digit)" }
      return text.count < limit ? text + "\(digit)" : text
    }
  }

  /// `"62,5"` → 62.5; leer → `nil`.
  public static func value(_ text: String) -> Double? {
    guard !text.isEmpty else { return nil }
    return Double(text.replacingOccurrences(of: ",", with: "."))
  }

  /// Startwert für den Ziffernblock (`62,5`, `8`, `0` → leer).
  public static func text(for value: Double) -> String {
    value > 0 ? GermanFormat.number(value) : ""
  }
}
