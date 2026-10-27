import Foundation

/// Verlauf aus einem GymBook-Backup („GymBook-Backup-….database“, SQLite/Core Data) übernehmen. Die App liest die
/// Zeilen aus `ZEXERCISELOG` (verbunden mit `ZEXERCISE` und `ZWORKOUT`); hier werden sie zu Einheiten.
///
/// Felder im Backup (GymBook 7.1.9): `ZDAY` = Tag (`yyyy-MM-dd`), `ZTIME` = Sekunden seit Mitternacht,
/// `ZFREQUENCYVALUE` = Wiederholungen bzw. Sekunden (`ZFREQUENCYUNIT` `x` bzw. `s`), `ZQUANTITYVALUE` = Gewicht in
/// `ZQUANTITYUNIT` (kg), `ZSKIPPED` = ausgelassen. Ausdauer-Einträge (`m`, km) gehören nicht ins Gym-Protokoll.
public enum GymBookImport {
  public struct LogRow: Equatable, Sendable {
    public var day: String
    public var secondsOfDay: Double
    public var exercise: String
    /// z. B. `020.chest`
    public var region: String?
    /// z. B. `041.armFlexors|040.armExtensors`
    public var muscles: String?
    /// z. B. `070.cableMachine`
    public var equipment: String?
    public var frequency: Double?
    /// `x` Wiederholungen, `s` Sekunden, `m` Distanz
    public var frequencyUnit: String?
    public var quantity: Double?
    public var quantityUnit: String?
    public var skipped: Bool
    public var workout: String?

    public init(
      day: String, secondsOfDay: Double, exercise: String, region: String? = nil, muscles: String? = nil,
      equipment: String? = nil, frequency: Double?, frequencyUnit: String? = "x", quantity: Double?,
      quantityUnit: String? = "kg", skipped: Bool = false, workout: String? = nil
    ) {
      self.day = day
      self.secondsOfDay = secondsOfDay
      self.exercise = exercise
      self.region = region
      self.muscles = muscles
      self.equipment = equipment
      self.frequency = frequency
      self.frequencyUnit = frequencyUnit
      self.quantity = quantity
      self.quantityUnit = quantityUnit
      self.skipped = skipped
      self.workout = workout
    }
  }

  public struct Result: Equatable, Sendable {
    public var sessions: [GymSession]
    /// Neue eigene Übungen für GymBook-Übungen ohne Gegenstück in der Bibliothek.
    public var newCustom: [ExerciseInfo]
    /// Zeilen, die nicht übernommen wurden (ausgelassen, Ausdauer, ohne Wiederholungen).
    public var ignoredRows: Int
  }

  /// GymBook-Übungen mit gleichem Bewegungsablauf in der Bibliothek. Varianten mit anderem Gerät (Multipresse,
  /// Maschine statt Langhantel) bleiben eigene Übungen, weil die Gewichte nicht vergleichbar sind.
  public static let mapping: [String: String] = [
    "Dips am Barren": "dips_barren",
    "Einarmiges Seitwärtsheben am Tiefen Kabel": "seitheben_kabel",
    "Curls in Hammerhaltung am Kabel": "hammer_curl_kabel",
    "Lat-Ziehen mit Breitem Griff": "latziehen",
    "Bankdrücken mit Langhantel": "bankdruecken",
    "Armstrecken am Kabel": "trizeps_pushdown",
    "Enges Rudern am Kabel Sitzend": "rudern_kabel",
    "Schrägbankdrücken mit Langhantel": "schraegbankdruecken",
    "Armstrecken am Tiefen Kabel auf Schrägbank": "trizeps_kabel_schraegbank",
    "Beinstrecken": "beinstrecken",
    "Fersenheben am Gerät Stehend": "wadenheben",
    "Crunches am Gerät": "crunch_geraet",
    "Beinbeugen Sitzend": "beinbeugen",
    "Beinpressen Sitzend": "beinpresse",
    "Curls am Kabel liegend": "kabel_curl_liegend",
    "Flyings am Hohen Kabel": "fliegende_kabel_hoch",
    "Einarmiges Lat-Ziehen": "latziehen_einarmig",
    "Oberkörperheben": "rueckenstrecker",
    "Face-Pulls am Kabel Sitzend": "face_pull",
    "Crunches am Kabel Kniend": "crunch_kabel",
    "Reverse-Flyings am Hohen Kabel": "reverse_fly_kabel",
    "Pallof-Press am Kabel": "pallof",
    "Planks": "plank",
    "Pull-Over am Kabel Sitzend": "kabel_pullover",
    "Bulgarische Split-Kniebeugen mit Kurzhanteln": "bulgarische_kniebeuge",
    "Rumänisches Kreuzheben mit Langhantel": "rumaenisches_kreuzheben",
    "Beinheben am Gerät": "beinheben",
    "Abwechselnde Curls in Hammerhaltung": "hammer_curl",
    "Curls mit SZ-Stange": "bizeps_curl",
  ]

  /// Stabile ID je Tag und Routine, damit ein zweiter Import nichts doppelt anlegt.
  public static func workoutKey(day: String, workout: String?) -> String {
    "gymbook:\(day):\(workout ?? "")"
  }

  public static func sessions(
    _ rows: [LogRow], custom existing: [ExerciseInfo], timeZone: TimeZone = .current
  ) -> Result {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var custom = existing
    var newCustom: [ExerciseInfo] = []
    var ignored = 0
    var groups: [String: [LogRow]] = [:]
    for row in rows {
      let unit = row.frequencyUnit ?? "x"
      guard !row.skipped, unit == "x" || unit == "s", let value = row.frequency, value > 0,
        CalendarDay(iso: row.day) != nil
      else {
        ignored += 1
        continue
      }
      groups[workoutKey(day: row.day, workout: row.workout), default: []].append(row)
    }

    var sessions: [GymSession] = []
    for (key, rows) in groups {
      let rows = rows.sorted { $0.secondsOfDay < $1.secondsOfDay }
      guard let first = rows.first, let day = CalendarDay(iso: first.day),
        let midnight = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
      else { continue }
      var exercises: [LoggedExercise] = []
      for row in rows {
        let info = exerciseInfo(for: row, custom: &custom, newCustom: &newCustom)
        let set = LoggedSet(reps: Int(row.frequency?.rounded() ?? 0), weightKg: max(row.quantity ?? 0, 0))
        if let index = exercises.lastIndex(where: { $0.exerciseID == info.id }) {
          exercises[index].sets.append(set)
        } else {
          exercises.append(
            LoggedExercise(
              exerciseID: info.id, name: info.name, group: info.group, sets: [set],
              restSeconds: info.compound ? 120 : 90))
        }
      }
      let start = midnight.addingTimeInterval(first.secondsOfDay)
      let end = midnight.addingTimeInterval((rows.last?.secondsOfDay ?? first.secondsOfDay) + 60)
      let title = first.workout?.trimmingCharacters(in: .whitespaces) ?? "GymBook"
      sessions.append(
        GymSession(
          id: stableID(key), workoutKey: key, title: title, start: start, end: end, exercises: exercises))
    }
    return Result(sessions: sessions.sorted { $0.start < $1.start }, newCustom: newCustom, ignoredRows: ignored)
  }

  static func exerciseInfo(for row: LogRow, custom: inout [ExerciseInfo], newCustom: inout [ExerciseInfo])
    -> ExerciseInfo
  {
    if let id = mapping[row.exercise], let info = ExerciseLibrary.info(id) { return info }
    let tracking: ExerciseTracking = row.frequencyUnit == "s" ? .time : .weightReps
    let made = ExerciseInfo.custom(
      name: row.exercise, group: group(region: row.region, muscles: row.muscles),
      equipment: equipment(row.equipment), tracking: tracking)
    if let known = custom.first(where: { $0.id == made.id }) { return known }
    custom.append(made)
    newCustom.append(made)
    return made
  }

  static func group(region: String?, muscles: String?) -> MuscleGroup {
    let region = region ?? ""
    let muscles = muscles ?? ""
    if region.hasSuffix("arms") {
      return muscles.contains("armFlexors") && !muscles.contains("armExtensors") ? .biceps : .triceps
    }
    if region.hasSuffix("chest") { return .chest }
    if region.hasSuffix("back") { return .back }
    if region.hasSuffix("shoulders") { return .shoulders }
    if region.hasSuffix("abdomen") { return .core }
    if region.hasSuffix("legs") || region.hasSuffix("buttocks") { return .legs }
    return .other
  }

  static func equipment(_ text: String?) -> Equipment {
    let text = text ?? ""
    if text.contains("cable") { return .cable }
    if text.contains("Machine") || text.contains("smith") { return .machine }
    if text.contains("barbell") || text.contains("ezBar") { return .barbell }
    if text.contains("dumbbell") { return .dumbbell }
    if text.contains("kettlebell") { return .kettlebell }
    return .bodyweight
  }

  /// UUID aus dem Schlüssel (FNV-1a), damit dieselbe Einheit immer dieselbe ID bekommt.
  static func stableID(_ key: String) -> UUID {
    var first: UInt64 = 0xcbf2_9ce4_8422_2325
    var second: UInt64 = 0x8422_2325_cbf2_9ce4
    for byte in key.utf8 {
      first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
      second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ 1
    }
    var bytes = [UInt8](repeating: 0, count: 16)
    for index in 0..<8 {
      bytes[index] = UInt8(truncatingIfNeeded: first >> (index * 8))
      bytes[index + 8] = UInt8(truncatingIfNeeded: second >> (index * 8))
    }
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
        bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }
}
