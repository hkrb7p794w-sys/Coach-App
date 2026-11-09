import Foundation

/// Regelbasierte Beobachtungen zum Krafttraining (für die KI-Hinweise und ohne KI) und der KI-Trainingsplan mit
/// Fragebogen. Die KI schlägt vor, die Regeln prüfen: nur Übungen aus der Bibliothek und der eigenen Ausstattung,
/// Sätze und Wiederholungen in festen Grenzen, Wochenvolumen je Muskel gegen die Empfehlungen.
public enum GymCoach {
  /// Mindest- und Zielvolumen je Muskelgruppe und Woche (Schoenfeld et al. 2017: mehr Sätze, mehr Zuwachs; 10+ als
  /// Praxisziel) und Häufigkeit (Schoenfeld et al. 2016: zweimal pro Woche).
  public static let minimumWeeklySets = 10
  public static let maximumWeeklySets = 20
  public static let majorGroups: [MuscleGroup] = [.chest, .back, .shoulders, .legs]

  // MARK: - Beobachtungen

  /// Hinweise aus dem Verlauf der letzten Wochen: Stillstand je Übung, Volumen und Häufigkeit je Muskel.
  public static func observations(sessions: [GymSession], today: CalendarDay) -> [String] {
    var lines: [String] = []
    let recent = sessions.filter { $0.day >= today.adding(days: -42) }.sorted { $0.start < $1.start }

    // Stillstand: in den letzten drei Einheiten einer Übung dasselbe Gewicht und keine Wiederholung mehr.
    var byExercise: [String: [(name: String, weight: Double, reps: Int)]] = [:]
    for session in recent {
      for exercise in session.exercises {
        guard let best = exercise.doneSets.max(by: { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }) else {
          continue
        }
        byExercise[exercise.exerciseID, default: []].append((exercise.name, best.weightKg, best.reps))
      }
    }
    for (_, history) in byExercise.sorted(by: { $0.key < $1.key }) where history.count >= 3 {
      let last = history.suffix(3)
      let weights = Set(last.map(\.weight))
      if weights.count == 1, let first = last.first, let latest = last.last, latest.reps <= first.reps,
        latest.weight > 0
      {
        lines.append(
          "\(latest.name): seit drei Einheiten \(GermanFormat.number(latest.weight)) kg ohne mehr Wiederholungen – "
            + "Stillstand. Satzzahl oder Variante ändern bzw. eine leichtere Woche einlegen.")
      }
    }

    // Volumen und Häufigkeit der letzten 7 Tage je großer Muskelgruppe.
    let week = recent.filter { $0.day > today.adding(days: -7) }
    for group in majorGroups {
      let sets = week.flatMap(\.exercises).filter { exerciseGroup($0) == group }.reduce(0) { $0 + $1.doneSets.count }
      let days = Set(week.filter { $0.exercises.contains { exerciseGroup($0) == group } }.map(\.day)).count
      if !week.isEmpty, sets < minimumWeeklySets {
        lines.append(
          "\(group.rawValue): \(sets) Sätze in 7 Tagen – unter \(minimumWeeklySets). Für mehr Zuwachs Sätze "
            + "ergänzen.")
      } else if sets > maximumWeeklySets {
        lines.append(
          "\(group.rawValue): \(sets) Sätze in 7 Tagen – mehr als \(maximumWeeklySets). Auf Erholung achten.")
      }
      if !week.isEmpty, days == 1, sets > 0 {
        lines.append("\(group.rawValue): nur an einem Tag trainiert – auf zwei Tage verteilen wirkt meist besser.")
      }
    }
    return lines
  }

  static func exerciseGroup(_ exercise: LoggedExercise) -> MuscleGroup {
    ExerciseLibrary.info(exercise.exerciseID)?.group ?? exercise.group
  }

  // MARK: - KI-Trainingsplan

  public enum PlanGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case muscle, strength, fitness, fatLoss

    public var id: String { rawValue }

    public var label: String {
      switch self {
      case .muscle: "Muskelaufbau"
      case .strength: "Kraft"
      case .fitness: "Allgemeine Fitness"
      case .fatLoss: "Abnehmen mit Krafterhalt"
      }
    }

    /// Wiederholungsbereich für Grundübungen (Schoenfeld et al. 2017: Zuwachs in einem weiten Bereich).
    var repRange: ClosedRange<Int> {
      switch self {
      case .strength: 3...6
      case .muscle: 6...12
      case .fitness, .fatLoss: 8...15
      }
    }
  }

  /// Antworten aus dem Fragebogen vor dem Erstellen.
  public struct PlanRequest: Codable, Equatable, Sendable {
    public var goal: PlanGoal = .muscle
    public var daysPerWeek = 3
    public var minutesPerSession = 60
    public var focus: [MuscleGroup] = []
    public var limitations = ""
    /// Übungen aus den eigenen Routinen bevorzugen.
    public var keepFavorites = true
    /// Für diesen Plan; `nil` = Angabe aus dem Profil.
    public var experience: ExperienceLevel?
    /// Für diesen Plan; `nil` = Ausstattung aus den Einstellungen.
    public var equipment: Set<Equipment>?

    public init() {}
  }

  public struct PlanResult: Equatable, Sendable {
    public var routines: [Routine]
    public var notes: [String]
    /// Vom Plan der KI verworfene oder korrigierte Punkte.
    public var corrections: [String]

    public init(routines: [Routine], notes: [String], corrections: [String]) {
      self.routines = routines
      self.notes = notes
      self.corrections = corrections
    }
  }

  /// Was vor dem Absenden auffällt: `blocking` verhindert den Plan, `hints` erklärt ungünstige Kombinationen.
  public static func planIssues(_ request: PlanRequest, equipment: Set<Equipment>) -> (
    blocking: [String], hints: [String]
  ) {
    var blocking: [String] = []
    var hints: [String] = []
    let usable = request.equipment ?? equipment
    if usable.isEmpty { blocking.append("Wähle mindestens eine Ausstattung, sonst gibt es keine passenden Übungen.") }
    if request.daysPerWeek >= 5, request.minutesPerSession <= 30 {
      hints.append("Sehr viele kurze Einheiten: Drei längere Einheiten sind meist leichter unterzubringen.")
    }
    if request.goal == .strength, request.minutesPerSession <= 30 {
      hints.append("Für Kraft sind lange Pausen nötig. In 30 Minuten passen nur wenige Übungen.")
    }
    if request.focus.count > request.daysPerWeek * 2 {
      hints.append("Viele Schwerpunkte bei wenigen Tagen: Die KI kann nicht alle gleich gewichten.")
    }
    return (blocking, hints)
  }

  /// Eingabe für die Worker-Aufgabe `gym_plan`.
  public static func planInput(
    request: PlanRequest, profile: UserProfile, equipment: Set<Equipment>, routines: [Routine],
    sessions: [GymSession], custom: [ExerciseInfo], today: CalendarDay, notes: [String: String] = [:]
  ) -> [String: JSONValue] {
    let usable = request.equipment ?? equipment
    let available = (ExerciseLibrary.all + custom).filter { $0.isAvailable(with: usable) }
    let library = available.map { exercise in
      let tracking = exercise.tracking == .time ? "Sekunden" : "Wiederholungen"
      let kind = exercise.compound ? "Grundübung" : "Isolation"
      return "\(exercise.id) | \(exercise.name) | \(exercise.group.rawValue) | \(tracking) | \(kind)"
    }
    let favorites = Array(Set(routines.flatMap { $0.items.map(\.exerciseID) })).sorted()
    let lastWeights = lastSets(sessions).sorted { $0.key < $1.key }.map { id, set in
      "\(id): \(GermanFormat.number(set.weightKg)) kg × \(set.reps)"
    }
    let otherSports = profile.sports.filter { $0 != .strength }.map(\.label)
    return [
      "goal": .string(request.goal.label),
      "days": .number(Double(min(max(request.daysPerWeek, 1), 6))),
      "minutes": .number(Double(min(max(request.minutesPerSession, 20), 120))),
      "focus": .array(request.focus.map { .string($0.rawValue) }),
      "limitations": .string(String(request.limitations.prefix(300))),
      "experience": .string((request.experience ?? profile.level(for: .strength)).label),
      "otherSports": .array(otherSports.map { .string($0) }),
      "library": .array(library.map { .string($0) }),
      "favorites": .array((request.keepFavorites ? favorites : []).map { .string($0) }),
      "lastWeights": .array(lastWeights.prefix(30).map { .string($0) }),
      "repRange": .string("\(request.goal.repRange.lowerBound)–\(request.goal.repRange.upperBound)"),
      "observations": .array(observations(sessions: sessions, today: today).map { .string($0) }),
      "exerciseNotes": .array(
        notes.sorted { $0.key < $1.key }.prefix(30).map { .string("\($0.key): \(String($0.value.prefix(120)))") }),
      "recentPerformance": .array(recentPerformance(sessions).map { .string($0) }),
      "evidence": CoachingNote.evidenceInput(["gym.frequency", "gym.volume", "gym.load", "gym.rir", "gym.progression"]),
    ]
  }

  /// Tatsächlich Geschafftes je Übung über alle Pläne hinweg: die letzten drei Einheiten, neueste zuerst.
  public static func recentPerformance(_ sessions: [GymSession]) -> [String] {
    var byExercise: [String: [String]] = [:]
    for session in sessions.sorted(by: { $0.start > $1.start }) {
      for exercise in session.exercises {
        guard (byExercise[exercise.exerciseID]?.count ?? 0) < 3,
          let best = exercise.doneSets.max(by: { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) })
        else { continue }
        byExercise[exercise.exerciseID, default: []].append("\(GermanFormat.number(best.weightKg)) kg × \(best.reps)")
      }
    }
    return byExercise.sorted { $0.key < $1.key }.prefix(40).map { "\($0.key): \($0.value.joined(separator: ", "))" }
  }

  /// Schwerster Satz je Übung aus der jeweils letzten Einheit mit Gewicht (Startgewicht für neue Routinen).
  public static func lastSets(_ sessions: [GymSession]) -> [String: LoggedSet] {
    var result: [String: LoggedSet] = [:]
    for session in sessions.sorted(by: { $0.start > $1.start }) {
      for exercise in session.exercises where result[exercise.exerciseID] == nil {
        if let best = exercise.doneSets.max(by: { $0.weightKg < $1.weightKg }), best.weightKg > 0 {
          result[exercise.exerciseID] = best
        }
      }
    }
    return result
  }

  /// Prüft den Vorschlag der KI (`{"routinen": [{"name", "uebungen": [{"id", "saetze", "wdh_min", "wdh_max",
  /// "pause"}]}], "hinweise": [...]}`) und ergänzt Hinweise der Regeln.
  public static func validatePlan(
    _ output: JSONValue, request: PlanRequest, equipment: Set<Equipment>, custom: [ExerciseInfo],
    lastWeights: [String: Double] = [:]
  ) -> PlanResult {
    var corrections: [String] = []
    var routines: [Routine] = []
    let maxExercises = max(3, min(10, request.minutesPerSession / 8))
    for raw in (output["routinen"]?.arrayValue ?? []).prefix(request.daysPerWeek) {
      let name = String((raw["name"]?.stringValue ?? "Einheit \(routines.count + 1)").prefix(40))
      var items: [RoutineItem] = []
      for entry in raw["uebungen"]?.arrayValue ?? [] {
        guard let id = entry["id"]?.stringValue, let info = ExerciseLibrary.info(id, custom: custom) else {
          corrections.append("Unbekannte Übung „\(entry["id"]?.stringValue ?? "?")“ entfernt.")
          continue
        }
        guard info.isAvailable(with: equipment) else {
          corrections.append("\(info.name) braucht Ausstattung, die du nicht hast – entfernt.")
          continue
        }
        guard !items.contains(where: { $0.exerciseID == id }), items.count < maxExercises else { continue }
        let sets = entry["saetze"]?.clampedInt(-1_000...1_000) ?? 3
        let isTime = info.tracking == .time
        let limits = isTime ? 10...120 : 3...30
        var lower = entry["wdh_min"]?.clampedInt(limits) ?? info.lowerReps
        var upper = entry["wdh_max"]?.clampedInt(limits) ?? info.upperReps
        lower = min(max(lower, limits.lowerBound), limits.upperBound)
        upper = min(max(upper, lower), limits.upperBound)
        let clampedSets = min(max(sets, 1), 5)
        if clampedSets != sets { corrections.append("\(info.name): Sätze auf \(clampedSets) begrenzt.") }
        let rest = entry["pause"]?.clampedInt(45...240) ?? (info.compound ? 120 : 90)
        items.append(
          RoutineItem(
            exerciseID: id, name: info.name, sets: clampedSets, lowerReps: lower, upperReps: upper, restSeconds: rest,
            weightKg: lastWeights[id]))
      }
      if !items.isEmpty { routines.append(Routine(name: name, items: items)) }
    }

    var notes = (output["hinweise"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(5).map {
      String($0.prefix(300))
    }
    // Wochenvolumen je großer Muskelgruppe prüfen (Sätze aus Haupt- und Nebengruppen zählen voll bzw. halb nicht;
    // hier nur Hauptgruppe, wie in der Übersicht der App).
    var weekly: [MuscleGroup: Int] = [:]
    for routine in routines { for (group, sets) in routine.setsPerGroup { weekly[group, default: 0] += sets } }
    for group in majorGroups where !routines.isEmpty {
      let sets = weekly[group] ?? 0
      if sets < minimumWeeklySets {
        notes.append(
          "\(group.rawValue): \(sets) Sätze pro Woche – für Muskelaufbau eher \(minimumWeeklySets) oder mehr.")
      } else if sets > maximumWeeklySets {
        notes.append("\(group.rawValue): \(sets) Sätze pro Woche – viel; auf Erholung achten.")
      }
    }
    return PlanResult(routines: routines, notes: notes, corrections: corrections)
  }
}
