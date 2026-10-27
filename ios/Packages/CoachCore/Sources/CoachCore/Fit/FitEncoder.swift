import Foundation

/// Schreibt FIT-Dateien (Protokoll 2.0, Little Endian) – hier für Krafttrainings, die zurück nach Garmin Connect gehen.
/// Feldnummern und Typen laut FIT-SDK-Profil 21.x (`@garmin/fitsdk`, Datei `profile.js`).
public struct FitEncoder {
  /// FIT-Grundtypen (Nummer, Größe in Byte).
  public enum BaseType: UInt8 {
    case enumeration = 0x00
    case uint8 = 0x02
    case uint16 = 0x84
    case uint32 = 0x86
    case uint32z = 0x8C

    var size: Int {
      switch self {
      case .enumeration, .uint8: 1
      case .uint16: 2
      case .uint32, .uint32z: 4
      }
    }
  }

  public struct Field {
    public var number: UInt8
    public var type: BaseType
    public var value: UInt32

    public init(_ number: UInt8, _ type: BaseType, _ value: UInt32) {
      self.number = number
      self.type = type
      self.value = value
    }
  }

  /// Sekunden zwischen 1970-01-01 und dem FIT-Bezugszeitpunkt 1989-12-31 00:00:00 UTC.
  public static let epochOffset: TimeInterval = 631_065_600

  public static func timestamp(_ date: Date) -> UInt32 {
    UInt32(max(0, date.timeIntervalSince1970 - epochOffset).rounded())
  }

  private var body: [UInt8] = []
  /// Definitionen je lokaler Nummer (globale Nummer und Feldaufbau), damit gleiche Nachrichten sie wiederverwenden.
  private var definitions: [Int: (global: UInt16, layout: [String])] = [:]

  public init() {}

  /// Fügt eine Datennachricht hinzu; die Definition wird bei Bedarf vorher geschrieben.
  public mutating func add(global: UInt16, fields: [Field]) {
    let layout = fields.map { "\($0.number):\($0.type.rawValue)" }
    let local: Int
    if let existing = definitions.first(where: { $0.value.global == global && $0.value.layout == layout })?.key {
      local = existing
    } else {
      local = definitions.count % 16
      definitions[local] = (global, layout)
      body.append(0x40 | UInt8(local))
      body += [0, 0]  // reserviert, Little Endian
      body += [UInt8(global & 0xFF), UInt8(global >> 8)]
      body.append(UInt8(fields.count))
      for field in fields { body += [field.number, UInt8(field.type.size), field.type.rawValue] }
    }
    body.append(UInt8(local))
    for field in fields {
      for index in 0..<field.type.size { body.append(UInt8((field.value >> (8 * UInt32(index))) & 0xFF)) }
    }
  }

  /// Fertige Datei mit Kopf und Prüfsummen.
  public func data() -> Data {
    let size = UInt32(body.count)
    var header: [UInt8] = [14, 0x20]
    header += [UInt8(2_132 & 0xFF), UInt8(2_132 >> 8)]  // Profilversion 21.32
    header += [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), UInt8((size >> 16) & 0xFF), UInt8(size >> 24)]
    header += Array(".FIT".utf8)
    let headerCRC = Self.crc(header)
    header += [UInt8(headerCRC & 0xFF), UInt8(headerCRC >> 8)]
    let fileCRC = Self.crc(body)
    return Data(header + body + [UInt8(fileCRC & 0xFF), UInt8(fileCRC >> 8)])
  }

  /// CRC-16 des FIT-Protokolls.
  public static func crc(_ bytes: [UInt8]) -> UInt16 {
    let table: [UInt16] = [
      0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
      0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400,
    ]
    var crc: UInt16 = 0
    for byte in bytes {
      var tmp = table[Int(crc & 0xF)]
      crc = (crc >> 4) & 0x0FFF
      crc = crc ^ tmp ^ table[Int(byte & 0xF)]
      tmp = table[Int(crc & 0xF)]
      crc = (crc >> 4) & 0x0FFF
      crc = crc ^ tmp ^ table[Int((byte >> 4) & 0xF)]
    }
    return crc
  }
}

/// Krafttraining als FIT-Aktivität für Garmin Connect: je Satz Übung (Kategorie und Unterart aus dem FIT-Profil),
/// Wiederholungen und Gewicht, dazwischen Pausen. Garmin zeigt die Einheit danach wie eine Uhr-Aufzeichnung.
public enum StrengthFitExport {
  public static func fit(_ session: GymSession, end: Date? = nil) -> Data {
    let start = session.start
    let finish = max(end ?? session.end ?? start.addingTimeInterval(3_600), start.addingTimeInterval(60))
    let sets = session.exercises.flatMap { exercise in exercise.doneSets.map { (exercise, $0) } }
    var encoder = FitEncoder()
    let startStamp = FitEncoder.timestamp(start)
    let endStamp = FitEncoder.timestamp(finish)
    let total = Double(endStamp - startStamp)

    encoder.add(
      global: 0,
      fields: [
        .init(0, .enumeration, 4),  // Typ: Aktivität
        .init(1, .uint16, 255),  // Hersteller: development
        .init(2, .uint16, 1),
        .init(3, .uint32z, 20_261_027),
        .init(4, .uint32, startStamp),
      ])
    encoder.add(
      global: 21, fields: [.init(253, .uint32, startStamp), .init(0, .enumeration, 0), .init(1, .enumeration, 0)])

    // Dauer je Satz: gezeitete Sätze mit ihrer Zeit, sonst 3 s je Wiederholung (mind. 20 s); der Rest sind Pausen.
    let active = sets.map { exercise, set -> Double in
      ExerciseLibrary.info(exercise.exerciseID)?.tracking == .time ? Double(set.reps) : max(Double(set.reps) * 3, 20)
    }
    let pause = sets.isEmpty ? 0 : max(0, (total - active.reduce(0, +)) / Double(sets.count))
    var clock = Double(startStamp)
    var index: UInt32 = 0
    for (offset, (exercise, set)) in sets.enumerated() {
      let mapping = GarminExerciseMapping.code(for: exercise.exerciseID)
      let duration = active[offset]
      let isTime = ExerciseLibrary.info(exercise.exerciseID)?.tracking == .time
      var fields: [FitEncoder.Field] = [
        .init(254, .uint32, UInt32(clock + duration)),
        .init(0, .uint32, UInt32(duration * 1_000)),
        .init(5, .uint8, 1),  // aktiver Satz
        .init(6, .uint32, UInt32(clock)),
        .init(7, .uint16, UInt32(mapping.category)),
        .init(8, .uint16, UInt32(mapping.subtype ?? 0xFFFF)),
        .init(10, .uint16, index),
      ]
      if !isTime { fields.append(.init(3, .uint16, UInt32(max(set.reps, 0)))) }
      if set.weightKg > 0 { fields.append(.init(4, .uint16, UInt32((set.weightKg * 16).rounded()))) }
      encoder.add(global: 225, fields: fields)
      clock += duration
      index += 1
      if offset < sets.count - 1, pause > 0 {
        encoder.add(
          global: 225,
          fields: [
            .init(254, .uint32, UInt32(clock + pause)),
            .init(0, .uint32, UInt32(pause * 1_000)),
            .init(5, .uint8, 0),  // Pause
            .init(6, .uint32, UInt32(clock)),
            .init(7, .uint16, 0xFFFF),
            .init(8, .uint16, 0xFFFF),
            .init(10, .uint16, index),
          ])
        clock += pause
        index += 1
      }
    }

    let elapsed = UInt32(total * 1_000)
    encoder.add(
      global: 21, fields: [.init(253, .uint32, endStamp), .init(0, .enumeration, 0), .init(1, .enumeration, 4)])
    encoder.add(
      global: 19,
      fields: [
        .init(253, .uint32, endStamp), .init(0, .enumeration, 9), .init(1, .enumeration, 1),
        .init(2, .uint32, startStamp), .init(7, .uint32, elapsed), .init(8, .uint32, elapsed),
      ])
    encoder.add(
      global: 18,
      fields: [
        .init(253, .uint32, endStamp), .init(0, .enumeration, 8), .init(1, .enumeration, 1),
        .init(2, .uint32, startStamp), .init(5, .enumeration, 10), .init(6, .enumeration, 20),
        .init(7, .uint32, elapsed), .init(8, .uint32, elapsed), .init(25, .uint16, 0), .init(26, .uint16, 1),
      ])
    let offset = Int32(TimeZone.current.secondsFromGMT(for: finish))
    encoder.add(
      global: 34,
      fields: [
        .init(253, .uint32, endStamp), .init(0, .uint32, elapsed), .init(1, .uint16, 1),
        .init(2, .enumeration, 0), .init(3, .enumeration, 26), .init(4, .enumeration, 1),
        .init(5, .uint32, UInt32(Int64(endStamp) + Int64(offset))),
      ])
    return encoder.data()
  }
}

/// Zuordnung der Übungen zu Garmins Übungskatalog (FIT `exercise_category` und `*_exercise_name`).
public enum GarminExerciseMapping {
  public struct Code: Equatable, Sendable {
    public var category: UInt16
    public var subtype: UInt16?
  }

  // Kategorien laut FIT-Profil.
  static let benchPress: UInt16 = 0, calfRaise: UInt16 = 1, core: UInt16 = 5, crunch: UInt16 = 6, curl: UInt16 = 7
  static let deadlift: UInt16 = 8, flye: UInt16 = 9, hipRaise: UInt16 = 10, hipStability: UInt16 = 11
  static let hyperextension: UInt16 = 13, lateralRaise: UInt16 = 14, legCurl: UInt16 = 15, legRaise: UInt16 = 16
  static let lunge: UInt16 = 17, plank: UInt16 = 19, pullUp: UInt16 = 21, pushUp: UInt16 = 22, row: UInt16 = 23
  static let shoulderPress: UInt16 = 24, shrug: UInt16 = 26, squat: UInt16 = 28, tricepsExtension: UInt16 = 30
  static let banded: UInt16 = 37
  static let unknown: UInt16 = 65_534

  // swift-format-ignore
  static let table: [String: Code] = [
    "bankdruecken": Code(category: benchPress, subtype: 1),
    "kurzhantel_bankdruecken": Code(category: benchPress, subtype: 6),
    "schraegbankdruecken": Code(category: benchPress, subtype: 8),
    "kurzhantel_schraegbankdruecken": Code(category: benchPress, subtype: 9),
    "brustpresse": Code(category: banded, subtype: 5),
    "fliegende": Code(category: flye, subtype: 2),
    "fliegende_kabel_hoch": Code(category: flye, subtype: 0),
    "liegestuetze": Code(category: pushUp, subtype: 77),
    "klimmzug": Code(category: pullUp, subtype: 38),
    "latziehen": Code(category: pullUp, subtype: 25),
    "latziehen_einarmig": Code(category: pullUp, subtype: 13),
    "kabel_pullover": Code(category: pullUp, subtype: 19),
    "rudern_langhantel": Code(category: row, subtype: 46),
    "rudern_kurzhantel": Code(category: row, subtype: 2),
    "rudern_kabel": Code(category: row, subtype: 18),
    "rudern_koerpergewicht": Code(category: row, subtype: 35),
    "face_pull": Code(category: row, subtype: 5),
    "rueckenstrecker": Code(category: hyperextension, subtype: nil),
    "schulterdruecken": Code(category: shoulderPress, subtype: 14),
    "kurzhantel_schulterdruecken": Code(category: shoulderPress, subtype: 17),
    "seitheben": Code(category: lateralRaise, subtype: 34),
    "seitheben_kabel": Code(category: lateralRaise, subtype: 14),
    "frontheben": Code(category: lateralRaise, subtype: 10),
    "reverse_fly": Code(category: flye, subtype: 11),
    "reverse_fly_kabel": Code(category: flye, subtype: 6),
    "aufrechtes_rudern": Code(category: shrug, subtype: 24),
    "shrugs": Code(category: shrug, subtype: 1),
    "bizeps_curl": Code(category: curl, subtype: 3),
    "kurzhantel_curl": Code(category: curl, subtype: nil),
    "hammer_curl": Code(category: curl, subtype: 16),
    "hammer_curl_kabel": Code(category: curl, subtype: 9),
    "kabel_curl_liegend": Code(category: curl, subtype: 8),
    "trizeps_pushdown": Code(category: tricepsExtension, subtype: 39),
    "trizepsstrecken": Code(category: tricepsExtension, subtype: 15),
    "trizeps_kabel_schraegbank": Code(category: tricepsExtension, subtype: 5),
    "dips": Code(category: tricepsExtension, subtype: 2),
    "dips_barren": Code(category: tricepsExtension, subtype: 40),
    "kniebeuge": Code(category: squat, subtype: 6),
    "goblet_squat": Code(category: squat, subtype: 37),
    "beinpresse": Code(category: squat, subtype: 0),
    "ausfallschritt": Code(category: lunge, subtype: 21),
    "bulgarische_kniebeuge": Code(category: lunge, subtype: nil),
    "rumaenisches_kreuzheben": Code(category: deadlift, subtype: 23),
    "kreuzheben": Code(category: deadlift, subtype: 0),
    "hueftstoss": Code(category: hipRaise, subtype: nil),
    "kettlebell_swing": Code(category: hipRaise, subtype: 23),
    "beinstrecken": Code(category: banded, subtype: 29),
    "beinbeugen": Code(category: legCurl, subtype: 0),
    "wadenheben": Code(category: calfRaise, subtype: 18),
    "plank": Code(category: plank, subtype: 43),
    "seitstuetz": Code(category: plank, subtype: 66),
    "dead_bug": Code(category: hipStability, subtype: 1),
    "crunch": Code(category: crunch, subtype: 83),
    "crunch_geraet": Code(category: crunch, subtype: 79),
    "crunch_kabel": Code(category: crunch, subtype: 1),
    "beinheben": Code(category: legRaise, subtype: 1),
    "pallof": Code(category: core, subtype: nil),
    "rotation": Code(category: core, subtype: 46),
  ]

  /// Unbekannte oder eigene Übungen über die Muskelgruppe einer passenden Kategorie zuordnen.
  public static func code(for exerciseID: String) -> Code {
    if let code = table[exerciseID] { return code }
    switch ExerciseLibrary.info(exerciseID)?.group {
    case .chest: return Code(category: benchPress, subtype: nil)
    case .back: return Code(category: row, subtype: nil)
    case .shoulders: return Code(category: shoulderPress, subtype: nil)
    case .biceps, .forearms: return Code(category: curl, subtype: nil)
    case .triceps: return Code(category: tricepsExtension, subtype: nil)
    case .legs: return Code(category: squat, subtype: nil)
    case .core: return Code(category: core, subtype: nil)
    default: return Code(category: unknown, subtype: nil)
    }
  }
}
