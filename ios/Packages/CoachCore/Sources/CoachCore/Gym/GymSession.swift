import Foundation

/// Ein Satz: Wiederholungen (bei Haltübungen Sekunden) und Gewicht in kg (0 = Körpergewicht).
public struct LoggedSet: Codable, Equatable, Sendable {
  public var reps: Int
  public var weightKg: Double
  /// Abgehakt: nur abgehakte Sätze zählen.
  public var done: Bool
  /// Wiederholungen in Reserve (RIR): wie viele noch gegangen wären; `nil` = nicht angegeben.
  public var rir: Int?

  public init(reps: Int, weightKg: Double, done: Bool = true, rir: Int? = nil) {
    self.reps = reps
    self.weightKg = weightKg
    self.done = done
    self.rir = rir
  }
}

/// Eine Übung innerhalb einer Einheit.
public struct LoggedExercise: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  /// Kanonische Übung (`ExerciseRule.id`).
  public var exerciseID: String
  public var name: String
  public var group: MuscleGroup
  public var sets: [LoggedSet]
  public var restSeconds: Int

  public init(
    id: UUID = UUID(), exerciseID: String, name: String, group: MuscleGroup, sets: [LoggedSet],
    restSeconds: Int = 90
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.name = name
    self.group = group
    self.sets = sets
    self.restSeconds = restSeconds
  }

  public var doneSets: [LoggedSet] { sets.filter { $0.done && $0.reps > 0 } }
}

/// Eine Krafteinheit.
public struct GymSession: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var workoutKey: String?
  public var title: String
  public var start: Date
  public var end: Date?
  public var exercises: [LoggedExercise]

  public init(
    id: UUID = UUID(), workoutKey: String?, title: String, start: Date, end: Date? = nil,
    exercises: [LoggedExercise]
  ) {
    self.id = id
    self.workoutKey = workoutKey
    self.title = title
    self.start = start
    self.end = end
    self.exercises = exercises
  }

  public var day: CalendarDay { CalendarDay(date: start) }

  public var doneSetCount: Int { exercises.reduce(0) { $0 + $1.doneSets.count } }

  /// Bewegte Last (Gewicht × Wiederholungen) in kg.
  public var volumeKg: Double {
    exercises.flatMap(\.doneSets).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }
}

/// Sätze je Muskelgruppe der letzten 7 Tage (Karte `coach-gym`, Modus Volumen, im Altbestand).
///
/// Grün ab 5 Sätzen: solider Kraftaufbau neben Ausdauertraining; mehr Sätze bringen mehr, aber mit abnehmendem
/// Ertrag (Schoenfeld 2017, Pelland 2025).
public enum MuscleVolume {
  public static let goodRange = 5...9
  public static let groups: [MuscleGroup] = [.chest, .back, .shoulders, .biceps, .triceps, .legs, .core]

  public static func setsPerGroup(sessions: [GymSession], today: CalendarDay) -> [MuscleGroup: Int] {
    let start = today.adding(days: -6)
    var counts = Dictionary(uniqueKeysWithValues: groups.map { ($0, 0) })
    for session in sessions where start <= session.day && session.day <= today {
      for exercise in session.exercises where counts[exercise.group] != nil {
        counts[exercise.group, default: 0] += exercise.doneSets.count
      }
    }
    return counts
  }

  /// Tage seit dem letzten Beintraining (`nil` = noch nie).
  public static func daysSinceLegs(sessions: [GymSession], today: CalendarDay) -> Int? {
    sessions.filter { $0.exercises.contains { $0.group == .legs && !$0.doneSets.isEmpty } }
      .map(\.day).max().map { $0.days(until: today) }
  }
}
