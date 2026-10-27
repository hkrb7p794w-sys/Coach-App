import Foundation

/// Änderungen an der laufenden Einheit, die im Gym oft vorkommen: Gerät belegt (später, ersetzen), Supersätze,
/// Aufwärmsätze, Gewicht für Folgesätze. Reine Funktionen, damit sie getestet sind.
public enum WorkoutEdits {
  /// Übung ans Ende schieben („später“, z. B. Gerät belegt).
  public static func moveToEnd(_ exerciseID: UUID, in session: inout GymSession) {
    guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
    let exercise = session.exercises.remove(at: index)
    session.exercises.append(exercise)
  }

  public static func move(fromOffsets source: IndexSet, toOffset destination: Int, in session: inout GymSession) {
    let moving = source.sorted().filter { session.exercises.indices.contains($0) }.map { session.exercises[$0] }
    let before = source.filter { $0 < destination }.count
    for index in source.sorted(by: >) where session.exercises.indices.contains(index) {
      session.exercises.remove(at: index)
    }
    let target = min(max(destination - before, 0), session.exercises.count)
    session.exercises.insert(contentsOf: moving, at: target)
  }

  /// Übung mit der nächsten zum Supersatz verbinden; ist sie schon in einem, wird sie herausgelöst.
  public static func toggleSuperset(_ exerciseID: UUID, in session: inout GymSession) {
    guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
    if let group = session.exercises[index].supersetID {
      session.exercises[index].supersetID = nil
      let rest = session.exercises.indices.filter { session.exercises[$0].supersetID == group }
      if rest.count == 1 { session.exercises[rest[0]].supersetID = nil }
      return
    }
    let next = index + 1
    guard session.exercises.indices.contains(next) else { return }
    let group = session.exercises[next].supersetID ?? UUID()
    session.exercises[index].supersetID = group
    session.exercises[next].supersetID = group
  }

  /// Übung tauschen. Ohne erledigte Sätze wird sie ersetzt (Satzzahl und Wiederholungen bleiben); sonst behält die
  /// alte Übung ihre erledigten Sätze und die neue übernimmt die offenen.
  public static func replace(
    _ exerciseID: UUID, with info: ExerciseInfo, weightKg: Double, in session: inout GymSession
  ) {
    guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
    let old = session.exercises[index]
    let open = old.sets.filter { !$0.done }
    let sets = (open.isEmpty ? [LoggedSet(reps: info.upperReps, weightKg: 0, done: false)] : open).map { set in
      LoggedSet(reps: set.reps > 0 ? set.reps : info.upperReps, weightKg: weightKg, done: false, kind: set.kind)
    }
    let replacement = LoggedExercise(
      exerciseID: info.id, name: info.name, group: info.group, sets: sets, restSeconds: old.restSeconds,
      supersetID: old.supersetID)
    if old.sets.contains(where: \.done) {
      session.exercises[index].sets = old.sets.filter(\.done)
      session.exercises.insert(replacement, at: index + 1)
    } else {
      session.exercises[index] = replacement
    }
  }

  /// Alternativen für dieselbe Muskelgruppe mit vorhandener Ausstattung; gleiche Art (Grund-/Isolationsübung) zuerst.
  public static func alternatives(
    for exerciseID: String, custom: [ExerciseInfo] = [], equipment: Set<Equipment>
  ) -> [ExerciseInfo] {
    guard let current = ExerciseLibrary.info(exerciseID, custom: custom) else { return [] }
    let all = ExerciseLibrary.all + custom
    return all.filter { candidate in
      candidate.id != exerciseID && candidate.group == current.group
        && candidate.equipment.contains { equipment.contains($0) || $0 == .bodyweight }
    }
    .sorted { (rank($0, current), $0.name) < (rank($1, current), $1.name) }
  }

  /// Gleiche Art (Grund- oder Isolationsübung) zuerst.
  private static func rank(_ candidate: ExerciseInfo, _ current: ExerciseInfo) -> Int {
    candidate.compound == current.compound ? 0 : 1
  }

  /// Aufwärmsätze vor die Arbeitssätze setzen (nur, solange die Übung noch nicht begonnen ist).
  public static func insertWarmUp(_ steps: [WarmUp.Step], into exerciseID: UUID, in session: inout GymSession) {
    guard let index = session.exercises.firstIndex(where: { $0.id == exerciseID }),
      !session.exercises[index].sets.contains(where: \.done), !steps.isEmpty
    else { return }
    session.exercises[index].sets.removeAll { $0.kind == .warmup }
    let warmUps = steps.map { LoggedSet(reps: $0.reps, weightKg: $0.weightKg, done: false, kind: .warmup) }
    session.exercises[index].sets.insert(contentsOf: warmUps, at: 0)
  }

  /// Gewicht setzen und offene Folgesätze derselben Art mit gleichem Gewicht mitziehen (Aufwärmsätze ziehen die
  /// Arbeitssätze nicht herunter). Gibt die Zahl der mitgezogenen Sätze zurück.
  @discardableResult
  public static func setWeight(
    _ weight: Double, set index: Int, of exerciseID: UUID, allowsNegative: Bool = false, in session: inout GymSession
  ) -> Int {
    guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
      session.exercises[exerciseIndex].sets.indices.contains(index)
    else { return 0 }
    var sets = session.exercises[exerciseIndex].sets
    let old = sets[index].weightKg
    let kind = sets[index].kind
    let value = allowsNegative ? max(weight, -200) : max(weight, 0)
    sets[index].weightKg = value
    var moved = 0
    for later in sets.indices where later > index && !sets[later].done && sets[later].kind == kind {
      if abs(sets[later].weightKg - old) < 0.01, abs(old - value) >= 0.01 {
        sets[later].weightKg = value
        moved += 1
      }
    }
    session.exercises[exerciseIndex].sets = sets
    return moved
  }
}

/// Rückfrage bei unplausiblen Eingaben (625 statt 62,5 kg), damit Diagramme und Progression nicht kippen.
public enum SetCheck {
  public static func warning(weightKg: Double, reps: Int, isTime: Bool, previousBestKg: Double?) -> String? {
    if weightKg > 350 { return "\(GermanFormat.number(weightKg)) kg ist ungewöhnlich viel. Stimmt das?" }
    if let best = previousBestKg, best > 0, weightKg > best * 1.5 + 10 {
      return "\(GermanFormat.number(weightKg)) kg liegt weit über deinem bisherigen Höchstgewicht "
        + "(\(GermanFormat.number(best)) kg). Stimmt das?"
    }
    if isTime, reps > 600 { return "\(reps) Sekunden sind ungewöhnlich lang. Stimmt das?" }
    if !isTime, reps > 50 { return "\(reps) Wiederholungen sind ungewöhnlich viele. Stimmt das?" }
    return nil
  }
}

/// Pausenlänge: bei schweren Grundübungen und kaum Reserve (RIR 0–1) 30 s länger. Längere Pausen zwischen
/// schweren Sätzen erhalten Leistung und Kraftzuwachs (Schoenfeld et al. 2016, Grgic et al. 2017).
public enum RestAdvisor {
  public static let extraSeconds = 30
  public static let maximumSeconds = 300

  public static func seconds(base: Int, compound: Bool, rir: Int?) -> Int {
    guard compound, let rir, rir <= 1 else { return base }
    return min(base + extraSeconds, max(base, maximumSeconds))
  }
}

/// Anzeige-Hilfen je Übung: Gewicht je Hantel, Wiederholungen je Seite, Zusatz- oder Hilfsgewicht.
public enum ExerciseUnits {
  /// Einseitige Übungen: Wiederholungen gelten je Seite.
  public static let unilateral: Set<String> = [
    "latziehen_einarmig", "rudern_kurzhantel", "ausfallschritt", "bulgarische_kniebeuge", "seitstuetz",
    "seitheben_kabel", "pallof",
  ]

  public static func isUnilateral(_ exerciseID: String) -> Bool { unilateral.contains(exerciseID) }

  /// Körpergewichtsübungen: positives Gewicht = Zusatz, negatives = Unterstützung.
  public static func allowsAssistance(_ info: ExerciseInfo?) -> Bool {
    guard let info else { return false }
    return info.equipment.first == .bodyweight || info.equipment.first == .pullupBar
  }

  public static func isPerDumbbell(_ info: ExerciseInfo?) -> Bool { info?.equipment.first == .dumbbell }

  /// „62,5 kg“, „20 kg je Hantel“, „+10 kg Zusatz“, „20 kg Hilfe“, „Körpergewicht“.
  public static func weightText(_ weight: Double, info: ExerciseInfo?) -> (value: String, unit: String) {
    if weight == 0 { return ("Körpergewicht", "") }
    if allowsAssistance(info) {
      return weight > 0
        ? ("+\(GermanFormat.number(weight))", "kg Zusatz") : (GermanFormat.number(-weight), "kg Hilfe")
    }
    return (GermanFormat.number(weight), isPerDumbbell(info) ? "kg je Hantel" : "kg")
  }

  public static func repsUnit(_ exerciseID: String, isTime: Bool) -> String {
    let base = isTime ? "s" : "Wdh."
    return isUnilateral(exerciseID) ? "\(base) je Seite" : base
  }
}
