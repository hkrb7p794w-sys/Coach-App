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
  /// (am Ende wieder von vorn – mit „Später“ verschobene Übungen kommen so zum Schluss dran). Übersprungene Übungen
  /// zählen nicht mehr; nur wenn man sie ausdrücklich wählt, steht ihr nächster Satz auf der Fokus-Karte.
  public static func current(in session: GymSession, preferring exerciseID: UUID? = nil) -> Position? {
    let exercises = session.exercises
    guard !exercises.isEmpty else { return nil }
    let preferred = exerciseID.flatMap { id in exercises.firstIndex { $0.id == id } }
    if let preferred, exercises[preferred].skipped {
      return exercises[preferred].sets.firstIndex { !$0.done }.map { Position(exercise: preferred, set: $0) }
    }
    let start = preferred ?? 0
    for offset in 0..<exercises.count {
      let index = (start + offset) % exercises.count
      guard !exercises[index].skipped else { continue }
      if let set = exercises[index].sets.firstIndex(where: { !$0.done }) {
        return Position(exercise: index, set: set)
      }
    }
    return nil
  }

  /// Der Plan ist durch: Es gibt Übungen, und keine offene, nicht übersprungene Übung hat noch einen Satz.
  public static func isComplete(_ session: GymSession) -> Bool {
    !session.exercises.isEmpty && current(in: session) == nil
  }

  /// Die nächste andere Übung nach `index` (für die Vorschau „Danach“), ohne übersprungene und fertige.
  public static func nextExercise(after index: Int, in session: GymSession) -> Int? {
    let exercises = session.exercises
    guard exercises.count > 1 else { return nil }
    for offset in 1..<exercises.count {
      let candidate = (index + offset) % exercises.count
      let exercise = exercises[candidate]
      if !exercise.skipped, exercise.sets.contains(where: { !$0.done }) { return candidate }
    }
    return nil
  }

  /// Text für Pausenende und Live-Aktivität: „Weiter mit Schulterdrücken“ beim Übungswechsel, sonst
  /// „Weiter mit Satz 3 · Bankdrücken“; `nil`, wenn nichts mehr offen ist.
  public static func nextText(in session: GymSession, focus: UUID?, previous: UUID?) -> String? {
    guard let position = current(in: session, preferring: focus) else { return nil }
    let exercise = session.exercises[position.exercise]
    if exercise.id != previous || position.set == 0 {
      return "Weiter mit \(exercise.name)"
    }
    return "Weiter mit Satz \(position.set + 1) · \(exercise.name)"
  }

  /// Der Satz nach `position`, als Vorschau („Als Nächstes“).
  public static func upcoming(after position: Position, in session: GymSession) -> Position? {
    var copy = session
    guard copy.exercises.indices.contains(position.exercise),
      copy.exercises[position.exercise].sets.indices.contains(position.set)
    else { return nil }
    copy.exercises[position.exercise].sets[position.set].done = true
    let next = afterCompleting(exercise: position.exercise, in: copy)
    return current(in: copy, preferring: next.focus.map { copy.exercises[$0].id })
  }

  /// Nach dem Abhaken eines Satzes von Übung `index` (Satz ist schon abgehakt): welche Übung kommt, und startet
  /// eine Pause? Im Supersatz geht es ohne Pause zur nächsten Übung der Gruppe; Pause erst nach der Runde.
  public static func afterCompleting(exercise index: Int, in session: GymSession) -> (focus: Int?, rest: Bool) {
    let exercises = session.exercises
    guard exercises.indices.contains(index) else { return (nil, true) }
    let members = supersetMembers(of: index, in: session)
    if members.count > 1, let position = members.firstIndex(of: index) {
      let order = members[(position + 1)...] + members[..<position]
      if let next = order.first(where: { exercises[$0].sets.contains { !$0.done } }) {
        // Weiter hinten in der Gruppe: ohne Pause; zurück zur ersten Übung: neue Runde nach der Pause.
        return (next, next < index)
      }
    }
    let next = current(in: session, preferring: exercises[index].id)
    return (next?.exercise, true)
  }

  /// Indizes der Übungen im selben Supersatz (nur die Übung selbst, wenn sie keinem angehört).
  public static func supersetMembers(of index: Int, in session: GymSession) -> [Int] {
    guard session.exercises.indices.contains(index), let id = session.exercises[index].supersetID else {
      return [index]
    }
    return session.exercises.indices.filter { session.exercises[$0].supersetID == id }
  }

  /// Kürzel wie „A1“, „A2“, „B1“ für Übungen in Supersätzen (Reihenfolge des ersten Auftretens).
  public static func supersetLabels(in session: GymSession) -> [UUID: String] {
    var letters: [UUID: Character] = [:]
    var counts: [UUID: Int] = [:]
    var result: [UUID: String] = [:]
    let groups = Dictionary(grouping: session.exercises.compactMap(\.supersetID), by: { $0 })
    for exercise in session.exercises {
      guard let id = exercise.supersetID, (groups[id]?.count ?? 0) > 1 else { continue }
      if letters[id] == nil {
        letters[id] = Character(UnicodeScalar(UInt8(65 + min(letters.count, 25))))
      }
      counts[id, default: 0] += 1
      result[exercise.id] = "\(letters[id] ?? "A")\(counts[id] ?? 1)"
    }
    return result
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

  /// Übersprungene Übungen mit noch offenen Sätzen (beim Beenden: „2 übersprungen“).
  public static func skippedCount(_ session: GymSession) -> Int {
    session.exercises.filter { $0.skipped && $0.sets.contains { !$0.done } }.count
  }

  public static func summary(of session: GymSession, now: Date = .now) -> Summary {
    // Übersprungene Übungen zählen nicht als „vergessen“.
    let open = session.exercises.filter { !$0.skipped }.reduce(0) { count, exercise in
      count + exercise.sets.filter { !$0.done && $0.reps > 0 }.count
    }
    return Summary(
      minutes: max(0, Int(((session.end ?? now).timeIntervalSince(session.start) / 60).rounded())),
      doneSets: session.doneSetCount, volumeKg: session.volumeKg,
      exercises: session.exercises.filter { !$0.doneSets.isEmpty }.count, openSets: open)
  }

  /// Übernimmt alle offenen Sätze mit Wiederholungen als erledigt (übersprungene Übungen bleiben offen).
  public static func completingOpenSets(_ session: GymSession) -> GymSession {
    var copy = session
    for exercise in copy.exercises.indices where !copy.exercises[exercise].skipped {
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
