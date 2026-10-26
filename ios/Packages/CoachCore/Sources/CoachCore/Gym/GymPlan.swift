import Foundation

/// Eine geplante Übung im Trainingsplan.
public struct PlannedExercise: Codable, Equatable, Sendable, Identifiable {
  public var name: String
  /// Garmin-Kategorie und -Übung („KATEGORIE (ÜBUNG)“) – Grundlage der Zuordnung zur kanonischen Übung.
  public var garmin: String
  public var sets: Int
  /// Ziel-Wiederholungen (Obergrenze des Bereichs); `nil` bei Haltübungen.
  public var reps: Int?
  /// Startgewicht laut Plan; `nil` = Körpergewicht.
  public var weightKg: Double?
  public var restSeconds: Int
  public var id: String { name }

  public init(name: String, garmin: String, sets: Int, reps: Int?, weightKg: Double?, restSeconds: Int) {
    self.name = name
    self.garmin = garmin
    self.sets = sets
    self.reps = reps
    self.weightKg = weightKg
    self.restSeconds = restSeconds
  }

  public var rule: ExerciseRule {
    ExerciseCatalog.classify(garmin, hasWeight: (weightKg ?? 0) > 0)
  }

  /// Zielbereich aus dem Plan: (Plan-Wdh. − 4) bis Plan-Wdh., wie `plan_rep_ranges` im Altbestand.
  public var planRepRange: ClosedRange<Int>? {
    reps.map { max(1, $0 - 4)...$0 }
  }
}

/// Eine Trainingseinheit des Plans (z. B. „Push A“).
public struct Workout: Codable, Equatable, Sendable, Identifiable {
  public var key: String
  public var name: String
  public var note: String
  public var exercises: [PlannedExercise]
  public var id: String { key }

  public init(key: String, name: String, note: String, exercises: [PlannedExercise]) {
    self.key = key
    self.name = name
    self.note = note
    self.exercises = exercises
  }
}

/// Trainingsplan mit Wochentagen (`gym_plan.json` im Altbestand).
public struct GymPlan: Codable, Equatable, Sendable {
  public var workouts: [Workout]
  /// Wochentag (0 = Montag) → Einheit.
  public var schedule: [Int: String]
  /// Flexible Einheiten: Schlüssel → mögliche Wochentage (erster freier Tag zählt).
  public var flex: [String: [Int]]

  public init(workouts: [Workout], schedule: [Int: String], flex: [String: [Int]]) {
    self.workouts = workouts
    self.schedule = schedule
    self.flex = flex
  }

  public func workout(_ key: String) -> Workout? {
    workouts.first { $0.key == key }
  }

  /// Zielbereiche je kanonischer Übung aus dem Plan.
  public var repRanges: [String: ClosedRange<Int>] {
    var ranges: [String: ClosedRange<Int>] = [:]
    for exercise in workouts.flatMap(\.exercises) {
      if let range = exercise.planRepRange { ranges[exercise.rule.id] = range }
    }
    return ranges
  }

  /// Geplante Einheiten einer Woche wie `planned_days` im Altbestand: Flexible Einheiten (Lower Di/Do) landen am
  /// ersten noch möglichen Tag und entfallen, wenn an einem ihrer Tage schon Kraft geloggt ist.
  public func plannedDays(monday: CalendarDay, today: CalendarDay, doneDays: Set<CalendarDay>) -> [CalendarDay: String]
  {
    var days: [CalendarDay: String] = [:]
    for (weekday, key) in schedule where flex[key] == nil {
      days[monday.adding(days: weekday)] = key
    }
    for (key, options) in flex {
      let candidates = options.sorted().map { monday.adding(days: $0) }
      if candidates.contains(where: doneDays.contains) { continue }
      if let day = candidates.first(where: { $0 >= today }) { days[day] = key }
    }
    return days
  }

  // swift-format-ignore
  public static let standard = GymPlan(
    workouts: [
    Workout(
      key: "push", name: "Push A", note: "Home-Gym · nur Wiederholungen anpassen",
      exercises: [
        PlannedExercise(
          name: "Flyings am hohen Kabel", garmin: "FLYE (CABLE_CROSSOVER)",
          sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
        PlannedExercise(
          name: "Armstrecken am tiefen Kabel auf Schrägbank", garmin: "TRICEPS_EXTENSION (CABLE_OVERHEAD_TRICEPS_EXTENSION)",
          sets: 2, reps: 12, weightKg: 32.5, restSeconds: 90),
        PlannedExercise(
          name: "Bankdrücken mit Langhantel", garmin: "BENCH_PRESS (BARBELL_BENCH_PRESS)",
          sets: 2, reps: 12, weightKg: 52.5, restSeconds: 120),
        PlannedExercise(
          name: "Einarmiges Seitwärtsheben am tiefen Kabel", garmin: "LATERAL_RAISE (ONE_ARM_CABLE_LATERAL_RAISE)",
          sets: 2, reps: 12, weightKg: 13.75, restSeconds: 90),
        PlannedExercise(
          name: "Dips am Barren", garmin: "TRICEPS_EXTENSION (BODY_WEIGHT_DIP)",
          sets: 2, reps: 12, weightKg: nil, restSeconds: 90),
        PlannedExercise(
          name: "Planks", garmin: "PLANK (PLANK)",
          sets: 2, reps: nil, weightKg: nil, restSeconds: 60),
      ]),
    Workout(
      key: "pull", name: "Pull A", note: "Home-Gym · nur Wiederholungen anpassen",
      exercises: [
        PlannedExercise(
          name: "Enges Rudern am Kabel sitzend", garmin: "ROW (V_GRIP_CABLE_ROW)",
          sets: 2, reps: 12, weightKg: 110, restSeconds: 120),
        PlannedExercise(
          name: "Curls am Kabel liegend", garmin: "CURL (CABLE_BICEPS_CURL)",
          sets: 2, reps: 12, weightKg: 50, restSeconds: 90),
        PlannedExercise(
          name: "Einarmiges Lat-Ziehen", garmin: "PULL_UP (_30_DEGREE_LAT_PULLDOWN)",
          sets: 2, reps: 12, weightKg: 52.5, restSeconds: 90),
        PlannedExercise(
          name: "Curls in Hammerhaltung am Kabel", garmin: "CURL (CABLE_HAMMER_CURL)",
          sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
        PlannedExercise(
          name: "Face-Pulls am Kabel sitzend", garmin: "ROW (FACE_PULL)",
          sets: 2, reps: 12, weightKg: 45, restSeconds: 90),
        PlannedExercise(
          name: "Crunches am Kabel kniend", garmin: "CRUNCH (KNEELING_CABLE_CRUNCH)",
          sets: 2, reps: 12, weightKg: 65, restSeconds: 60),
      ]),
    Workout(
      key: "pp", name: "Push & Pull B", note: "Home-Gym · nur Wiederholungen anpassen",
      exercises: [
        PlannedExercise(
          name: "Curls in Hammerhaltung am Kabel", garmin: "CURL (CABLE_HAMMER_CURL)",
          sets: 2, reps: 12, weightKg: 22.5, restSeconds: 90),
        PlannedExercise(
          name: "Armstrecken am tiefen Kabel auf Schrägbank", garmin: "TRICEPS_EXTENSION (CABLE_OVERHEAD_TRICEPS_EXTENSION)",
          sets: 2, reps: 12, weightKg: 32.5, restSeconds: 90),
        PlannedExercise(
          name: "Lat-Ziehen mit breitem Griff", garmin: "PULL_UP (WIDE_GRIP_LAT_PULLDOWN)",
          sets: 2, reps: 12, weightKg: 85, restSeconds: 120),
        PlannedExercise(
          name: "Bankdrücken mit Langhantel", garmin: "BENCH_PRESS (BARBELL_BENCH_PRESS)",
          sets: 2, reps: 12, weightKg: 52.5, restSeconds: 120),
        PlannedExercise(
          name: "Reverse-Flyings am hohen Kabel", garmin: "FLYE (SINGLE_ARM_STANDING_CABLE_REVERSE_FLYE)",
          sets: 2, reps: 12, weightKg: 7.5, restSeconds: 90),
        PlannedExercise(
          name: "Dips am Barren", garmin: "TRICEPS_EXTENSION (BODY_WEIGHT_DIP)",
          sets: 2, reps: 12, weightKg: nil, restSeconds: 90),
      ]),
    Workout(
      key: "legs", name: "Lower", note: "nur Wiederholungen anpassen",
      exercises: [
        PlannedExercise(
          name: "Beinbeugen sitzend", garmin: "LEG_CURL (LEG_CURL)",
          sets: 2, reps: 12, weightKg: 110, restSeconds: 90),
        PlannedExercise(
          name: "Beinstrecken", garmin: "BANDED_EXERCISES (LEG_EXTENSION)",
          sets: 2, reps: 12, weightKg: 120, restSeconds: 90),
        PlannedExercise(
          name: "Beinpressen sitzend", garmin: "SQUAT (LEG_PRESS)",
          sets: 2, reps: 12, weightKg: 149, restSeconds: 120),
        PlannedExercise(
          name: "Fersenheben am Gerät stehend", garmin: "CALF_RAISE (WEIGHTED_STANDING_CALF_RAISE)",
          sets: 2, reps: 12, weightKg: 117, restSeconds: 90),
        PlannedExercise(
          name: "Crunches am Gerät", garmin: "CRUNCH (WEIGHTED_CRUNCH)",
          sets: 2, reps: 12, weightKg: 90, restSeconds: 60),
      ]),
    ],
    schedule: [0: "push", 1: "legs", 2: "pull", 4: "pp"],
    flex: ["legs": [1, 3]])
}
