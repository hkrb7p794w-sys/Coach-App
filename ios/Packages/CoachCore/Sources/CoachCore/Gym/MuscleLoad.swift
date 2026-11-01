import Foundation

/// Einzelne Muskeln für die Heatmap (feiner als `MuscleGroup`).
public enum Muscle: String, CaseIterable, Codable, Sendable, Identifiable {
  case chest, frontDelts, sideDelts, rearDelts, traps, lats, lowerBack, biceps, triceps, forearms
  case abs, obliques, glutes, quads, hamstrings, adductors, calves

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .chest: "Brust"
    case .frontDelts: "Vordere Schulter"
    case .sideDelts: "Seitliche Schulter"
    case .rearDelts: "Hintere Schulter"
    case .traps: "Nacken (Trapez)"
    case .lats: "Latissimus"
    case .lowerBack: "Unterer Rücken"
    case .biceps: "Bizeps"
    case .triceps: "Trizeps"
    case .forearms: "Unterarme"
    case .abs: "Bauch"
    case .obliques: "Seitliche Bauchmuskeln"
    case .glutes: "Gesäß"
    case .quads: "Oberschenkel vorn"
    case .hamstrings: "Oberschenkel hinten"
    case .adductors: "Adduktoren"
    case .calves: "Waden"
    }
  }

  /// Zuordnung zur bisherigen Muskelgruppe (Filter in der Bibliothek).
  public var group: MuscleGroup {
    switch self {
    case .chest: .chest
    case .frontDelts, .sideDelts, .rearDelts: .shoulders
    case .traps, .lats, .lowerBack: .back
    case .biceps: .biceps
    case .triceps: .triceps
    case .forearms: .forearms
    case .abs, .obliques: .core
    case .glutes, .quads, .hamstrings, .adductors, .calves: .legs
    }
  }
}

/// Wie stark eine Übung welchen Muskel beansprucht: Hauptmuskel 1, mitarbeitende Muskeln 0,5 („fractional sets“,
/// wie die Auswertung von Pelland et al. 2025). Praxis-Zuordnung, keine Messung.
public enum MuscleMap {
  public static let primary = 1.0
  public static let secondary = 0.5

  // swift-format-ignore
  static let table: [String: [Muscle: Double]] = [
    "bankdruecken": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
    "kurzhantel_bankdruecken": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
    "schraegbankdruecken": [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
    "kurzhantel_schraegbankdruecken": [.chest: 1, .frontDelts: 0.5, .triceps: 0.5],
    "brustpresse": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5],
    "fliegende": [.chest: 1, .frontDelts: 0.5],
    "fliegende_kabel_hoch": [.chest: 1, .frontDelts: 0.5],
    "liegestuetze": [.chest: 1, .triceps: 0.5, .frontDelts: 0.5, .abs: 0.5],
    "klimmzug": [.lats: 1, .biceps: 0.5, .rearDelts: 0.5, .forearms: 0.5],
    "latziehen": [.lats: 1, .biceps: 0.5, .rearDelts: 0.5],
    "latziehen_einarmig": [.lats: 1, .biceps: 0.5],
    "rudern_langhantel": [.lats: 1, .traps: 0.5, .rearDelts: 0.5, .biceps: 0.5, .lowerBack: 0.5],
    "rudern_kurzhantel": [.lats: 1, .traps: 0.5, .rearDelts: 0.5, .biceps: 0.5],
    "rudern_kabel": [.lats: 1, .traps: 0.5, .rearDelts: 0.5, .biceps: 0.5],
    "rudern_koerpergewicht": [.lats: 1, .traps: 0.5, .rearDelts: 0.5, .biceps: 0.5],
    "kabel_pullover": [.lats: 1],
    "rueckenstrecker": [.lowerBack: 1, .glutes: 0.5, .hamstrings: 0.5],
    "schulterdruecken": [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5],
    "kurzhantel_schulterdruecken": [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5],
    "seitheben": [.sideDelts: 1],
    "seitheben_kabel": [.sideDelts: 1],
    "frontheben": [.frontDelts: 1],
    "reverse_fly": [.rearDelts: 1, .traps: 0.5],
    "reverse_fly_kabel": [.rearDelts: 1, .traps: 0.5],
    "face_pull": [.rearDelts: 1, .traps: 0.5],
    "aufrechtes_rudern": [.sideDelts: 1, .traps: 0.5],
    "shrugs": [.traps: 1],
    "bizeps_curl": [.biceps: 1, .forearms: 0.5],
    "kurzhantel_curl": [.biceps: 1, .forearms: 0.5],
    "hammer_curl": [.biceps: 1, .forearms: 0.5],
    "hammer_curl_kabel": [.biceps: 1, .forearms: 0.5],
    "kabel_curl_liegend": [.biceps: 1],
    "trizeps_pushdown": [.triceps: 1],
    "trizepsstrecken": [.triceps: 1],
    "trizeps_kabel_schraegbank": [.triceps: 1],
    "dips": [.triceps: 1, .chest: 0.5, .frontDelts: 0.5],
    "dips_barren": [.triceps: 1, .chest: 0.5, .frontDelts: 0.5],
    "handgelenk_curl": [.forearms: 1],
    "kniebeuge": [.quads: 1, .glutes: 1, .adductors: 0.5, .lowerBack: 0.5],
    "goblet_squat": [.quads: 1, .glutes: 0.5, .adductors: 0.5],
    "beinpresse": [.quads: 1, .glutes: 0.5, .adductors: 0.5],
    "ausfallschritt": [.quads: 1, .glutes: 1, .adductors: 0.5],
    "bulgarische_kniebeuge": [.quads: 1, .glutes: 1, .adductors: 0.5],
    "rumaenisches_kreuzheben": [.hamstrings: 1, .glutes: 1, .lowerBack: 0.5],
    "kreuzheben": [.glutes: 1, .hamstrings: 0.5, .quads: 0.5, .lowerBack: 0.5, .traps: 0.5, .forearms: 0.5],
    "hueftstoss": [.glutes: 1, .hamstrings: 0.5],
    "beinstrecken": [.quads: 1],
    "beinbeugen": [.hamstrings: 1],
    "wadenheben": [.calves: 1],
    "kettlebell_swing": [.glutes: 1, .hamstrings: 0.5, .lowerBack: 0.5],
    "plank": [.abs: 1, .obliques: 0.5],
    "seitstuetz": [.obliques: 1, .abs: 0.5],
    "dead_bug": [.abs: 1],
    "crunch": [.abs: 1],
    "crunch_geraet": [.abs: 1],
    "crunch_kabel": [.abs: 1],
    "beinheben": [.abs: 1],
    "pallof": [.obliques: 1, .abs: 0.5],
    "rotation": [.obliques: 1, .abs: 0.5],
  ]

  /// Hauptmuskel je Muskelgruppe (für eigene und unbekannte Übungen).
  static let main: [MuscleGroup: Muscle] = [
    .chest: .chest, .back: .lats, .shoulders: .sideDelts, .biceps: .biceps, .triceps: .triceps, .legs: .quads,
    .core: .abs, .forearms: .forearms,
  ]

  /// Beanspruchung einer Übung; eigene Übungen über Muskelgruppe und mitarbeitende Gruppen.
  public static func involvement(_ exerciseID: String, group: MuscleGroup, custom: [ExerciseInfo] = [])
    -> [Muscle: Double]
  {
    if let known = table[exerciseID] { return known }
    var result: [Muscle: Double] = [:]
    let info = ExerciseLibrary.info(exerciseID, custom: custom)
    if let muscle = main[info?.group ?? group] { result[muscle] = primary }
    for other in info?.secondary ?? [] {
      if let muscle = main[other], result[muscle] == nil { result[muscle] = secondary }
    }
    return result
  }
}

/// Muskelbeanspruchung aus Arbeitssätzen: Hauptmuskel zählt einen Satz voll, mitarbeitende Muskeln halb. Ein Satz
/// zählt je Muskel genau einmal (keine Doppelzählung über Gruppen). Sätze weit weg vom Versagen (RIR 4 oder mehr)
/// und Drop-Sätze zählen halb, Aufwärmsätze nicht. Grundlage: Sätze je Muskel und Woche (Schoenfeld et al. 2017,
/// Pelland et al. 2025); die Gewichte 1/0,5 und die Regenerationsgrenzen sind Praxiswerte, keine Messung von
/// Ermüdung.
public enum MuscleLoad {
  /// Unter dieser Menge (Sätze je Muskel) gilt eine Einheit nicht als nennenswerte Belastung.
  public static let meaningfulSets = 2.0
  /// So lange nach nennenswerter Belastung gilt ein Muskel als „vermutlich noch in der Erholung“.
  public static let recoveryHours = 48.0
  /// Ab so vielen Tagen ohne nennenswerte Belastung: „länger nicht trainiert“.
  public static let neglectedDays = 10
  /// Ab so vielen Sätzen pro Woche gilt ein Muskel als ausreichend trainiert – wie `MuscleVolume.goodRange` (solider
  /// Kraftaufbau neben Ausdauertraining); mehr bringt mehr, mit abnehmendem Ertrag.
  public static let weeklyEnough = Double(MuscleVolume.goodRange.lowerBound)
  /// Volle Farbe in der Wochen-Heatmap.
  public static let weeklyFull = 10.0

  /// Wie stark ein Satz zählt.
  public static func setFactor(_ set: LoggedSet) -> Double {
    guard set.kind != .warmup, set.reps > 0 else { return 0 }
    if set.kind == .drop { return 0.5 }
    if let rir = set.rir, rir >= 4 { return 0.5 }
    return 1
  }

  /// Effektive Sätze je Muskel einer Einheit (nur abgehakte Sätze).
  public static func session(_ session: GymSession, custom: [ExerciseInfo] = []) -> [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for exercise in session.exercises {
      let sets = exercise.sets.filter(\.done).reduce(0) { $0 + setFactor($1) }
      guard sets > 0 else { continue }
      for (muscle, share) in MuscleMap.involvement(exercise.exerciseID, group: exercise.group, custom: custom) {
        result[muscle, default: 0] += sets * share
      }
    }
    return result
  }

  /// Geplante Sätze je Muskel einer Routine (eine Einheit).
  public static func routine(_ routine: Routine, custom: [ExerciseInfo] = []) -> [Muscle: Double] {
    var result: [Muscle: Double] = [:]
    for item in routine.items {
      let group = ExerciseLibrary.info(item.exerciseID, custom: custom)?.group ?? .other
      for (muscle, share) in MuscleMap.involvement(item.exerciseID, group: group, custom: custom) {
        result[muscle, default: 0] += Double(item.sets) * share
      }
    }
    return result
  }

  public enum Recovery: String, Sendable {
    /// Nennenswert belastet in den letzten 48 h: vermutlich noch in der Erholung.
    case recovering
    /// Bereit.
    case ready
    /// Länger als `neglectedDays` ohne nennenswerte Belastung (oder noch nie).
    case neglected

    public var label: String {
      switch self {
      case .recovering: "vermutlich noch in der Erholung"
      case .ready: "bereit"
      case .neglected: "länger nicht trainiert"
      }
    }
  }

  public struct Status: Equatable, Sendable, Identifiable {
    public var muscle: Muscle
    /// Effektive Sätze der letzten 7 Tage.
    public var weeklySets: Double
    /// Effektive Sätze der letzten 28 Tage, je Woche gemittelt.
    public var averageWeeklySets: Double
    /// Letzte nennenswerte Belastung.
    public var lastLoaded: Date?
    public var recovery: Recovery
    public var id: String { muscle.rawValue }

    /// Unter dem, was als ausreichend gilt.
    public var isLow: Bool { weeklySets < weeklyEnough }
  }

  /// Stand je Muskel zu `now`: Wochensätze, Mittel über 4 Wochen, letzte Belastung, Regeneration.
  public static func status(sessions: [GymSession], now: Date, custom: [ExerciseInfo] = []) -> [Status] {
    let week = now.addingTimeInterval(-7 * 86_400)
    let month = now.addingTimeInterval(-28 * 86_400)
    var weekly: [Muscle: Double] = [:]
    var monthly: [Muscle: Double] = [:]
    var last: [Muscle: Date] = [:]
    for session in sessions where session.start <= now {
      let load = self.session(session, custom: custom)
      for (muscle, sets) in load {
        if session.start >= week { weekly[muscle, default: 0] += sets }
        if session.start >= month { monthly[muscle, default: 0] += sets }
        let finished = session.end ?? session.start
        if sets >= meaningfulSets, (last[muscle] ?? .distantPast) < finished { last[muscle] = finished }
      }
    }
    return Muscle.allCases.map { muscle in
      let lastLoaded = last[muscle]
      let hours = lastLoaded.map { now.timeIntervalSince($0) / 3_600 }
      let recovery: Recovery =
        if let hours, hours < recoveryHours {
          .recovering
        } else if let hours, hours < Double(neglectedDays) * 24 {
          .ready
        } else {
          .neglected
        }
      return Status(
        muscle: muscle, weeklySets: ((weekly[muscle] ?? 0) * 10).rounded() / 10,
        averageWeeklySets: ((monthly[muscle] ?? 0) / 4 * 10).rounded() / 10, lastLoaded: lastLoaded,
        recovery: recovery)
    }
  }

  /// Farbstufe 0…1 für die Heatmap: 0 = nichts, 1 = viel (ab `full` Sätzen).
  public static func intensity(_ sets: Double, full: Double) -> Double {
    guard full > 0 else { return 0 }
    return min(max(sets / full, 0), 1)
  }
}
