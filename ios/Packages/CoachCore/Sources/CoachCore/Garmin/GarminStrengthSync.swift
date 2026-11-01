import Foundation

/// Sätze einer Gym-Einheit in die Krafttraining-Aktivität der Uhr schreiben – statt einer zweiten Aktivität.
///
/// Garmin Connect kann zwei Aktivitäten nicht zusammenführen. Die Connect-Webseite bearbeitet die Sätze einer
/// Krafttraining-Aktivität aber über `GET/PUT /activity-service/activity/{id}/exerciseSets` (inoffiziell; so auch
/// python-garminconnect `set_activity_exercise_sets` und strong-garmin-sync, MIT-Lizenz). Damit bleiben Kalorien,
/// Herzfrequenz und Zeit der Uhr erhalten, und die Übungen, Wiederholungen und Gewichte kommen dazu.
///
/// Zwei Arten wie bei strong-garmin-sync: **Füllen**, wenn die Uhr mindestens so viele aktive Satz-Abschnitte
/// erkannt hat wie die App Sätze (die echte Zeit je Satz bleibt), sonst **Ersetzen** durch einen Satz je App-Satz,
/// gleichmäßig über die Dauer verteilt.
public enum GarminStrengthSync {
  /// Höchster Abstand der Startzeiten von Einheit und Uhr-Aktivität.
  public static let matchWindow: TimeInterval = 2 * 3_600
  /// Längere aktive Abschnitte sind kein einzelner Satz (die Uhr hat mehrere zusammengefasst).
  static let maxSetSeconds = 600.0

  public enum Mode: String, Sendable {
    case fill, replace
  }

  public struct Result: Equatable, Sendable {
    public var payload: JSONValue
    public var mode: Mode
    public var sets: Int
  }

  // MARK: - Übungsnamen

  /// Garmins Kategorie und Unterkategorie als Text, wie die Satz-Schnittstelle sie erwartet (FIT-Profil,
  /// `ExerciseCategory` und `*ExerciseName`). Unterkategorien, die nicht sicher im Profil stehen, bleiben leer –
  /// Garmin nimmt die Kategorie allein immer an.
  // swift-format-ignore
  static let names: [String: (category: String, name: String?)] = [
    "bankdruecken": ("BENCH_PRESS", "BARBELL_BENCH_PRESS"),
    "kurzhantel_bankdruecken": ("BENCH_PRESS", "DUMBBELL_BENCH_PRESS"),
    "schraegbankdruecken": ("BENCH_PRESS", "INCLINE_BARBELL_BENCH_PRESS"),
    "kurzhantel_schraegbankdruecken": ("BENCH_PRESS", "INCLINE_DUMBBELL_BENCH_PRESS"),
    "brustpresse": ("BENCH_PRESS", nil),
    "fliegende": ("FLYE", "DUMBBELL_FLYE"),
    "fliegende_kabel_hoch": ("FLYE", "CABLE_CROSSOVER"),
    "liegestuetze": ("PUSH_UP", "PUSH_UP"),
    "klimmzug": ("PULL_UP", "PULL_UP"),
    "latziehen": ("PULL_UP", "WIDE_GRIP_LAT_PULLDOWN"),
    "latziehen_einarmig": ("PULL_UP", "LAT_PULLDOWN"),
    "kabel_pullover": ("PULL_UP", "STANDING_CABLE_PULLOVER"),
    "rudern_langhantel": ("ROW", nil),
    "rudern_kurzhantel": ("ROW", "DUMBBELL_ROW"),
    "rudern_kabel": ("ROW", "SEATED_CABLE_ROW"),
    "rudern_koerpergewicht": ("ROW", nil),
    "face_pull": ("ROW", "FACE_PULL"),
    "rueckenstrecker": ("HYPEREXTENSION", nil),
    "schulterdruecken": ("SHOULDER_PRESS", "OVERHEAD_BARBELL_PRESS"),
    "kurzhantel_schulterdruecken": ("SHOULDER_PRESS", "SEATED_DUMBBELL_SHOULDER_PRESS"),
    "seitheben": ("LATERAL_RAISE", nil),
    "seitheben_kabel": ("LATERAL_RAISE", "ONE_ARM_CABLE_LATERAL_RAISE"),
    "frontheben": ("LATERAL_RAISE", "FRONT_RAISE"),
    "reverse_fly": ("FLYE", nil),
    "reverse_fly_kabel": ("FLYE", "SINGLE_ARM_STANDING_CABLE_REVERSE_FLYE"),
    "aufrechtes_rudern": ("SHRUG", nil),
    "shrugs": ("SHRUG", "BARBELL_SHRUG"),
    "bizeps_curl": ("CURL", "BARBELL_BICEPS_CURL"),
    "kurzhantel_curl": ("CURL", nil),
    "hammer_curl": ("CURL", "DUMBBELL_HAMMER_CURL"),
    "hammer_curl_kabel": ("CURL", "CABLE_HAMMER_CURL"),
    "kabel_curl_liegend": ("CURL", "CABLE_BICEPS_CURL"),
    "handgelenk_curl": ("CURL", nil),
    "trizeps_pushdown": ("TRICEPS_EXTENSION", "TRICEPS_PRESSDOWN"),
    "trizepsstrecken": ("TRICEPS_EXTENSION", "OVERHEAD_DUMBBELL_TRICEPS_EXTENSION"),
    "trizeps_kabel_schraegbank": ("TRICEPS_EXTENSION", "CABLE_OVERHEAD_TRICEPS_EXTENSION"),
    "dips": ("TRICEPS_EXTENSION", "BODY_WEIGHT_DIP"),
    "dips_barren": ("TRICEPS_EXTENSION", "WEIGHTED_DIP"),
    "kniebeuge": ("SQUAT", "BARBELL_BACK_SQUAT"),
    "goblet_squat": ("SQUAT", "GOBLET_SQUAT"),
    "beinpresse": ("SQUAT", "LEG_PRESS"),
    "ausfallschritt": ("LUNGE", "DUMBBELL_LUNGE"),
    "bulgarische_kniebeuge": ("LUNGE", nil),
    "rumaenisches_kreuzheben": ("DEADLIFT", nil),
    "kreuzheben": ("DEADLIFT", "BARBELL_DEADLIFT"),
    "hueftstoss": ("HIP_RAISE", nil),
    "kettlebell_swing": ("HIP_RAISE", "KETTLEBELL_SWING"),
    "beinstrecken": ("UNKNOWN", nil),
    "beinbeugen": ("LEG_CURL", "LEG_CURL"),
    "wadenheben": ("CALF_RAISE", "STANDING_CALF_RAISE"),
    "plank": ("PLANK", "PLANK"),
    "seitstuetz": ("PLANK", "SIDE_PLANK"),
    "dead_bug": ("HIP_STABILITY", "DEAD_BUG"),
    "crunch": ("CRUNCH", "CRUNCH"),
    "crunch_geraet": ("CRUNCH", "WEIGHTED_CRUNCH"),
    "crunch_kabel": ("CRUNCH", "CABLE_CRUNCH"),
    "beinheben": ("LEG_RAISE", "HANGING_LEG_RAISE"),
    "pallof": ("CORE", nil),
    "rotation": ("CORE", "RUSSIAN_TWIST"),
  ]

  /// FIT-Kategorien als Text (für eigene Übungen über `GarminExerciseMapping`).
  static let categories: [UInt16: String] = [
    0: "BENCH_PRESS", 1: "CALF_RAISE", 5: "CORE", 6: "CRUNCH", 7: "CURL", 8: "DEADLIFT", 9: "FLYE", 10: "HIP_RAISE",
    11: "HIP_STABILITY", 13: "HYPEREXTENSION", 14: "LATERAL_RAISE", 15: "LEG_CURL", 16: "LEG_RAISE", 17: "LUNGE",
    19: "PLANK", 21: "PULL_UP", 22: "PUSH_UP", 23: "ROW", 24: "SHOULDER_PRESS", 26: "SHRUG", 28: "SQUAT",
    30: "TRICEPS_EXTENSION",
  ]

  public static func garminName(for exerciseID: String) -> (category: String, name: String?) {
    if let known = names[exerciseID] { return known }
    return (categories[GarminExerciseMapping.code(for: exerciseID).category] ?? "UNKNOWN", nil)
  }

  // MARK: - Ablauf

  /// So lange wartet eine Einheit auf die Aufzeichnung der Uhr, bevor sie als eigene Aktivität hochgeladen wird.
  public static let fallbackDelay: TimeInterval = 3 * 3_600

  public enum Action: Equatable, Sendable {
    case enrich(activityID: Int64)
    case upload
    case wait
    case none
  }

  /// Was mit einer Einheit geschieht: nur wartende Einheiten werden bearbeitet (ältere ohne Verbindung bleiben
  /// unberührt). Mit Aufzeichnung der Uhr: Sätze hineinschreiben; ohne: warten, nach `fallbackDelay` hochladen.
  public static func action(
    for session: GymSession, activities: [GarminActivity], linked: Set<Int64>, now: Date, fallbackUpload: Bool,
    timeZone: TimeZone = .current
  ) -> Action {
    guard session.garmin?.status == .pending else { return .none }
    if let match = match(session: session, activities: activities, linked: linked, timeZone: timeZone) {
      return .enrich(activityID: match.id)
    }
    let ended = session.end ?? session.start
    return fallbackUpload && now.timeIntervalSince(ended) >= fallbackDelay ? .upload : .wait
  }

  // MARK: - Zuordnung

  /// Die Uhr-Aktivität zu einer Einheit: Krafttraining von Garmin (keine Apple-Health- oder nachgetragene),
  /// Start höchstens 2 h entfernt, noch keiner anderen Einheit zugeordnet. Bevorzugt mit Herzfrequenz (von der Uhr
  /// aufgezeichnet, kein hochgeladener Export), dann die nächstgelegene.
  public static func match(
    session: GymSession, activities: [GarminActivity], linked: Set<Int64>, timeZone: TimeZone = .current
  ) -> GarminActivity? {
    let candidates = activities.compactMap { activity -> (GarminActivity, TimeInterval)? in
      guard activity.sport == .strength, ActivitySource.of(activity.id) == .garmin, !linked.contains(activity.id),
        let start = ActivityFeed.start(activity, timeZone: timeZone)
      else { return nil }
      let distance = abs(start.timeIntervalSince(session.start))
      return distance <= matchWindow ? (activity, distance) : nil
    }
    return candidates.min { lhs, rhs in
      let lhsWatch = lhs.0.averageHeartRate != nil
      let rhsWatch = rhs.0.averageHeartRate != nil
      return lhsWatch != rhsWatch ? lhsWatch : lhs.1 < rhs.1
    }?.0
  }

  /// Hat die Aktivität schon Wiederholungen (vom Benutzer oder einer früheren Übertragung)?
  public static func isEnriched(_ exerciseSets: JSONValue) -> Bool {
    (exerciseSets["exerciseSets"]?.arrayValue ?? []).contains { ($0["repetitionCount"]?.doubleValue ?? 0) > 0 }
  }

  // MARK: - Nutzdaten

  struct FlatSet {
    var exerciseID: String
    var set: LoggedSet
    var isTime: Bool
  }

  /// Alle abgehakten Sätze in Reihenfolge, Aufwärmsätze eingeschlossen (sie sind tatsächlich gemacht worden).
  static func flatten(_ session: GymSession, custom: [ExerciseInfo]) -> [FlatSet] {
    session.exercises.flatMap { exercise in
      let isTime = ExerciseLibrary.info(exercise.exerciseID, custom: custom)?.tracking == .time
      return exercise.loggedSets.map { FlatSet(exerciseID: exercise.exerciseID, set: $0, isTime: isTime) }
    }
  }

  /// Nutzdaten für PUT aus der Antwort von GET (`existing`). Rein, ohne Netz.
  public static func payload(
    existing: JSONValue, session: GymSession, custom: [ExerciseInfo] = [], useNames: Bool = true
  ) -> Result {
    var root = existing.objectValue ?? [:]
    var sets = existing["exerciseSets"]?.arrayValue ?? []
    let flat = flatten(session, custom: custom)
    let active = sets.indices.filter { index in
      sets[index]["setType"]?.stringValue == "ACTIVE" && (sets[index]["duration"]?.doubleValue ?? 0) <= maxSetSeconds
    }
    let mode: Mode
    if !flat.isEmpty, active.count >= flat.count {
      mode = .fill
      for (offset, index) in active.prefix(flat.count).enumerated() {
        guard var set = sets[index].objectValue else { continue }
        for (key, value) in fields(flat[offset], useNames: useNames) { set[key] = value }
        sets[index] = .object(set)
      }
    } else {
      mode = .replace
      let span = span(of: sets) ?? (session.start, session.end ?? session.start.addingTimeInterval(60 * 60))
      let total = max(1, span.end.timeIntervalSince(span.start))
      let gap = total / Double(max(flat.count, 1))
      sets = flat.enumerated().map { offset, item in
        var set = fields(item, useNames: useNames)
        let duration = item.isTime ? Double(item.set.reps) : max(5, min(gap * 0.8, 120))
        set["setType"] = .string("ACTIVE")
        set["startTime"] = .string(timeText(span.start.addingTimeInterval(gap * Double(offset))))
        set["duration"] = .number(duration)
        set["wktStepIndex"] = .null
        set["messageIndex"] = .number(Double(offset))
        return .object(set)
      }
    }
    root["exerciseSets"] = .array(sets)
    return Result(payload: .object(root), mode: mode, sets: flat.count)
  }

  /// Übung, Wiederholungen und Gewicht (Gramm) eines Satzes. Halteübungen ohne Wiederholungen; Körpergewicht und
  /// Unterstützung ohne Gewicht.
  static func fields(_ item: FlatSet, useNames: Bool) -> [String: JSONValue] {
    let garmin = garminName(for: item.exerciseID)
    let exercise: JSONValue = .object([
      "category": .string(garmin.category),
      "name": useNames ? garmin.name.map(JSONValue.string) ?? .null : .null,
    ])
    let weight = item.set.weightKg > 0 ? JSONValue.number((item.set.weightKg * 1_000).rounded()) : .null
    return [
      "exercises": .array([exercise]),
      "repetitionCount": item.isTime ? .null : .number(Double(item.set.reps)),
      "weight": weight,
    ]
  }

  static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'.0'"
    return formatter
  }()

  static func timeText(_ date: Date) -> String { formatter.string(from: date) }

  static func parseTime(_ text: String?) -> Date? {
    guard let text else { return nil }
    return formatter.date(from: String(text.prefix(19)) + ".0")
  }

  /// Anfang und Ende der Satz-Abschnitte der Uhr.
  static func span(of sets: [JSONValue]) -> (start: Date, end: Date)? {
    let ranges = sets.compactMap { set -> (Date, Date)? in
      guard let start = parseTime(set["startTime"]?.stringValue) else { return nil }
      return (start, start.addingTimeInterval(set["duration"]?.doubleValue ?? 0))
    }
    guard let start = ranges.map(\.0).min(), let end = ranges.map(\.1).max() else { return nil }
    return (start, end)
  }
}

/// Doppelte Krafttrainings: ein hochgeladener Export (ohne Herzfrequenz) neben der Aufzeichnung der Uhr. Für
/// Verlauf, Belastung und Kalorien zählt nur die Aufzeichnung der Uhr.
public enum StrengthDuplicates {
  /// IDs der überzähligen Aktivitäten.
  public static func redundant(_ activities: [GarminActivity], timeZone: TimeZone = .current) -> Set<Int64> {
    let strength = activities.filter { $0.sport == .strength && ActivitySource.of($0.id) == .garmin }
    let recorded = strength.filter { $0.averageHeartRate != nil }
    var result = Set<Int64>()
    for activity in strength where activity.averageHeartRate == nil {
      guard let start = ActivityFeed.start(activity, timeZone: timeZone) else { continue }
      let twin = recorded.contains { other in
        guard other.day == activity.day, let otherStart = ActivityFeed.start(other, timeZone: timeZone) else {
          return false
        }
        return abs(otherStart.timeIntervalSince(start)) <= GarminStrengthSync.matchWindow
      }
      if twin { result.insert(activity.id) }
    }
    return result
  }

  /// Aktivitäten ohne die überzähligen.
  public static func removing(from activities: [GarminActivity], timeZone: TimeZone = .current) -> [GarminActivity] {
    let redundant = redundant(activities, timeZone: timeZone)
    return redundant.isEmpty ? activities : activities.filter { !redundant.contains($0.id) }
  }
}
