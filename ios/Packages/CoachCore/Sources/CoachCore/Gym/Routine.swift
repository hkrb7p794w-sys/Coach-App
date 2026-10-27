import Foundation

/// Eine Übung in einer Routine: Sätze, Wiederholungsbereich und Pause.
public struct RoutineItem: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var exerciseID: String
  public var name: String
  public var sets: Int
  public var lowerReps: Int
  public var upperReps: Int
  public var restSeconds: Int
  /// Startgewicht, solange es für die Übung noch keinen Verlauf gibt (z. B. aus GymBook übernommen).
  public var weightKg: Double?

  public init(
    id: UUID = UUID(), exerciseID: String, name: String, sets: Int, lowerReps: Int, upperReps: Int,
    restSeconds: Int, weightKg: Double? = nil
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.name = name
    self.sets = max(sets, 1)
    self.lowerReps = max(lowerReps, 1)
    self.upperReps = max(upperReps, lowerReps, 1)
    self.restSeconds = restSeconds
    self.weightKg = weightKg
  }

  public var repRange: ClosedRange<Int> { lowerReps...upperReps }

  /// Standardwerte aus der Bibliothek.
  public init(exercise: ExerciseInfo, sets: Int = 3) {
    self.init(
      exerciseID: exercise.id, name: exercise.name, sets: sets, lowerReps: exercise.lowerReps,
      upperReps: exercise.upperReps, restSeconds: exercise.compound ? 120 : 90)
  }
}

/// Eigene Trainingseinheit (wie ein Workout in GymBook).
public struct Routine: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var items: [RoutineItem]

  public init(id: UUID = UUID(), name: String, items: [RoutineItem]) {
    self.id = id
    self.name = name
    self.items = items
  }

  /// Muskelgruppen mit ihren Sätzen, für die Übersicht.
  public var setsPerGroup: [MuscleGroup: Int] {
    var result: [MuscleGroup: Int] = [:]
    for item in items {
      let group = ExerciseLibrary.info(item.exerciseID)?.group ?? .other
      result[group, default: 0] += item.sets
    }
    return result
  }
}

/// Zielbereiche je Übung aus allen Routinen (für die Progression).
extension [Routine] {
  public var repRanges: [String: ClosedRange<Int>] {
    var ranges: [String: ClosedRange<Int>] = [:]
    for item in flatMap(\.items) { ranges[item.exerciseID] = item.repRange }
    return ranges
  }
}

/// Vorschläge für Routinen nach Profil, Anzahl der Krafttage und Ausstattung.
///
/// Aufbau: Jeder große Muskel wird mindestens zweimal pro Woche trainiert (Schoenfeld et al. 2016). Bei 1–3 Tagen
/// Ganzkörper, bei 4 Tagen Ober-/Unterkörper, ab 5 Tagen zusätzlich Push/Pull/Beine. Wiederholungsbereiche im
/// mittleren Bereich: Muskelaufbau gelingt über ein breites Lastspektrum (Schoenfeld et al. 2017), Grundübungen
/// etwas schwerer. Sätze je Übung nach Erfahrung (Einsteiger 2, sonst 3).
public enum RoutineTemplates {
  /// Die vier Pläne aus GymBook (Stand 27.10.2026, aus den Screenshots des Nutzers): je 2 Sätze à 12 Wiederholungen,
  /// Planks 2 × 60 Sekunden, mit den zuletzt genutzten Gewichten als Startwert.
  public static var gymBook: [Routine] {
    func item(_ id: String, _ name: String, _ weight: Double?, reps: Int = 12, rest: Int = 90) -> RoutineItem {
      RoutineItem(
        exerciseID: id, name: name, sets: 2, lowerReps: reps == 60 ? 60 : 10, upperReps: reps, restSeconds: rest,
        weightKg: weight)
    }
    return [
      Routine(
        name: "Lower",
        items: [
          item("beinbeugen", "Beinbeugen Sitzend", 110),
          item("beinstrecken", "Beinstrecken", 120),
          item("beinpresse", "Beinpressen Sitzend", 149, rest: 120),
          item("wadenheben", "Fersenheben am Gerät Stehend", 117),
          item("crunch_geraet", "Crunches am Gerät", 90),
        ]),
      Routine(
        name: "Push & Pull B",
        items: [
          item("hammer_curl_kabel", "Curls in Hammerhaltung am Kabel", 22.5),
          item("trizeps_kabel_schraegbank", "Armstrecken am Tiefen Kabel auf Schrägbank", 32.5),
          item("latziehen", "Lat-Ziehen mit Breitem Griff", 85, rest: 120),
          item("bankdruecken", "Bankdrücken mit Langhantel", 52.5, rest: 120),
          item("reverse_fly_kabel", "Reverse-Flyings am Hohen Kabel", 7.5),
          item("dips_barren", "Dips am Barren", 79),
        ]),
      Routine(
        name: "Pull A",
        items: [
          item("rudern_kabel", "Enges Rudern am Kabel Sitzend", 110, rest: 120),
          item("kabel_curl_liegend", "Curls am Kabel liegend", 50),
          item("latziehen_einarmig", "Einarmiges Lat-Ziehen", 52.5),
          item("hammer_curl_kabel", "Curls in Hammerhaltung am Kabel", 22.5),
          item("face_pull", "Face-Pulls am Kabel Sitzend", 45),
          item("crunch_kabel", "Crunches am Kabel Kniend", 65),
        ]),
      Routine(
        name: "Push A",
        items: [
          item("fliegende_kabel_hoch", "Flyings am Hohen Kabel", 22.5),
          item("trizeps_kabel_schraegbank", "Armstrecken am Tiefen Kabel auf Schrägbank", 32.5),
          item("bankdruecken", "Bankdrücken mit Langhantel", 52.5, rest: 120),
          item("seitheben_kabel", "Einarmiges Seitwärtsheben am Tiefen Kabel", 13.75),
          item("dips_barren", "Dips am Barren", 79),
          item("plank", "Planks", nil, reps: 60),
        ]),
    ]
  }

  /// Je Platz Übungen in Reihenfolge der Vorliebe; die erste machbare wird genommen.
  static let slots: [String: (name: String, slots: [[String]])] = [
    "ganzkoerper_a": (
      "Ganzkörper A",
      [
        ["kniebeuge", "goblet_squat", "beinpresse", "bulgarische_kniebeuge"],
        ["bankdruecken", "kurzhantel_bankdruecken", "brustpresse", "liegestuetze"],
        ["rudern_kabel", "rudern_kurzhantel", "rudern_langhantel", "rudern_koerpergewicht"],
        ["rumaenisches_kreuzheben", "hueftstoss"],
        ["seitheben"],
        ["plank"],
      ]
    ),
    "ganzkoerper_b": (
      "Ganzkörper B",
      [
        ["rumaenisches_kreuzheben", "hueftstoss", "kettlebell_swing"],
        ["kurzhantel_schulterdruecken", "schulterdruecken", "seitheben"],
        ["kurzhantel_schraegbankdruecken", "schraegbankdruecken", "liegestuetze"],
        ["latziehen", "klimmzug", "rudern_kurzhantel", "rudern_koerpergewicht"],
        ["ausfallschritt", "bulgarische_kniebeuge", "beinpresse"],
        ["kurzhantel_curl", "bizeps_curl", "hammer_curl"],
        ["trizeps_pushdown", "trizepsstrecken", "dips"],
        ["dead_bug", "crunch"],
      ]
    ),
    "ganzkoerper_c": (
      "Ganzkörper C",
      [
        ["beinpresse", "goblet_squat", "bulgarische_kniebeuge"],
        ["kurzhantel_schraegbankdruecken", "schraegbankdruecken", "liegestuetze"],
        ["rudern_kurzhantel", "rudern_kabel", "rudern_koerpergewicht"],
        ["hueftstoss", "rumaenisches_kreuzheben"],
        ["face_pull", "reverse_fly"],
        ["seitstuetz"],
      ]
    ),
    "oberkoerper_a": (
      "Oberkörper A",
      [
        ["bankdruecken", "kurzhantel_bankdruecken", "brustpresse", "liegestuetze"],
        ["rudern_langhantel", "rudern_kabel", "rudern_kurzhantel", "rudern_koerpergewicht"],
        ["kurzhantel_schulterdruecken", "schulterdruecken"],
        ["latziehen", "klimmzug", "rudern_kurzhantel"],
        ["kurzhantel_curl", "bizeps_curl"],
        ["trizeps_pushdown", "trizepsstrecken"],
      ]
    ),
    "unterkoerper_a": (
      "Unterkörper A",
      [
        ["kniebeuge", "goblet_squat", "beinpresse"],
        ["rumaenisches_kreuzheben", "hueftstoss"],
        ["ausfallschritt", "bulgarische_kniebeuge"],
        ["beinbeugen", "hueftstoss"],
        ["wadenheben"],
        ["plank"],
      ]
    ),
    "oberkoerper_b": (
      "Oberkörper B",
      [
        ["kurzhantel_schraegbankdruecken", "schraegbankdruecken", "liegestuetze"],
        ["klimmzug", "latziehen", "rudern_kurzhantel"],
        ["rudern_kabel", "rudern_kurzhantel", "rudern_koerpergewicht"],
        ["seitheben"],
        ["face_pull", "reverse_fly"],
        ["hammer_curl", "kurzhantel_curl"],
        ["trizepsstrecken", "trizeps_pushdown", "dips"],
      ]
    ),
    "unterkoerper_b": (
      "Unterkörper B",
      [
        ["kreuzheben", "rumaenisches_kreuzheben", "kettlebell_swing"],
        ["beinpresse", "goblet_squat", "bulgarische_kniebeuge"],
        ["bulgarische_kniebeuge", "ausfallschritt"],
        ["beinstrecken", "goblet_squat"],
        ["wadenheben"],
        ["dead_bug", "beinheben"],
      ]
    ),
    "push": (
      "Push (Brust, Schultern, Trizeps)",
      [
        ["bankdruecken", "kurzhantel_bankdruecken", "liegestuetze"],
        ["kurzhantel_schulterdruecken", "schulterdruecken"],
        ["kurzhantel_schraegbankdruecken", "fliegende"],
        ["seitheben"],
        ["trizeps_pushdown", "trizepsstrecken", "dips"],
      ]
    ),
    "pull": (
      "Pull (Rücken, Bizeps)",
      [
        ["klimmzug", "latziehen"],
        ["rudern_langhantel", "rudern_kabel", "rudern_kurzhantel"],
        ["face_pull", "reverse_fly"],
        ["bizeps_curl", "kurzhantel_curl"],
        ["hammer_curl"],
      ]
    ),
    "beine": (
      "Beine",
      [
        ["kniebeuge", "goblet_squat", "beinpresse"],
        ["rumaenisches_kreuzheben", "hueftstoss"],
        ["beinpresse", "bulgarische_kniebeuge"],
        ["beinbeugen", "hueftstoss"],
        ["wadenheben"],
      ]
    ),
  ]

  /// Welche Vorlagen bei wie vielen Krafttagen.
  public static func templateKeys(strengthDays: Int) -> [String] {
    switch strengthDays {
    case ...2: ["ganzkoerper_a", "ganzkoerper_b"]
    case 3: ["ganzkoerper_a", "ganzkoerper_b", "ganzkoerper_c"]
    case 4: ["oberkoerper_a", "unterkoerper_a", "oberkoerper_b", "unterkoerper_b"]
    default: ["push", "pull", "beine", "oberkoerper_a", "unterkoerper_a"]
    }
  }

  public static func suggest(profile: UserProfile, equipment: Set<Equipment>) -> [Routine] {
    let days = max(profile.schedule.count(of: .strength), 1)
    let level = profile.level(for: .strength)
    let sets = level == .beginner ? 2 : 3
    return templateKeys(strengthDays: days).compactMap { key in
      routine(key, sets: sets, equipment: equipment)
    }
  }

  static func routine(_ key: String, sets: Int, equipment: Set<Equipment>) -> Routine? {
    guard let template = slots[key] else { return nil }
    var used = Set<String>()
    let items = template.slots.compactMap { options -> RoutineItem? in
      let pick = options.compactMap { ExerciseLibrary.byID[$0] }
        .first { $0.isAvailable(with: equipment) && !used.contains($0.id) }
      guard let pick else { return nil }
      used.insert(pick.id)
      return RoutineItem(exercise: pick, sets: sets)
    }
    return items.isEmpty ? nil : Routine(name: template.name, items: items)
  }
}

/// Gym-Einstellungen: eigene Routinen, eigene Übungen, Ausstattung.
public struct GymSettings: Codable, Equatable, Hashable, Sendable {
  public var routines: [Routine]
  public var customExercises: [ExerciseInfo]
  public var equipment: Set<Equipment>
  /// Wiederholungen in Reserve je Satz abfragen.
  public var tracksRIR: Bool
  /// Beendete Einheiten als Krafttraining nach Garmin Connect übertragen.
  public var uploadsToGarmin: Bool = true

  public init(
    routines: [Routine] = [], customExercises: [ExerciseInfo] = [], equipment: Set<Equipment> = Equipment.gym,
    tracksRIR: Bool = true
  ) {
    self.routines = routines
    self.customExercises = customExercises
    self.equipment = equipment
    self.tracksRIR = tracksRIR
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    routines = (try? container.decodeIfPresent([Routine].self, forKey: .routines)) ?? []
    customExercises = (try? container.decodeIfPresent([ExerciseInfo].self, forKey: .customExercises)) ?? []
    equipment = (try? container.decodeIfPresent(Set<Equipment>.self, forKey: .equipment)) ?? Equipment.gym
    tracksRIR = (try? container.decodeIfPresent(Bool.self, forKey: .tracksRIR)) ?? true
    uploadsToGarmin = (try? container.decodeIfPresent(Bool.self, forKey: .uploadsToGarmin)) ?? true
  }

  /// Übung zur ID inklusive eigener Übungen.
  public func exercise(_ id: String) -> ExerciseInfo? {
    ExerciseLibrary.info(id, custom: customExercises)
  }

  public mutating func addCustom(_ exercise: ExerciseInfo) {
    customExercises.removeAll { $0.id == exercise.id }
    customExercises.append(exercise)
  }
}
