import Foundation

/// Ein Messpunkt der Aktivität (FIT-Nachricht `record`, meist einer pro Sekunde).
public struct FitRecord: Equatable, Sendable {
  /// Sekunden seit dem FIT-Bezugszeitpunkt (31.12.1989 UTC).
  public var timestamp: Double
  public var heartRate: Double?
  /// m/s (`enhanced_speed`, sonst `speed`).
  public var speed: Double?
  public var power: Double?
  /// Meter seit Start.
  public var distance: Double?

  public init(
    timestamp: Double, heartRate: Double? = nil, speed: Double? = nil, power: Double? = nil, distance: Double? = nil
  ) {
    self.timestamp = timestamp
    self.heartRate = heartRate
    self.speed = speed
    self.power = power
    self.distance = distance
  }
}

/// Eine Runde (FIT-Nachricht `lap`), entspricht Garmins `lapDTOs` aus der Rundenansicht.
public struct FitLap: Codable, Equatable, Sendable {
  /// Art der Runde laut Uhr; bei strukturierten Workouts gesetzt (FIT-Typ `intensity`).
  public enum Intensity: Int, Codable, Sendable {
    case active = 0, rest, warmup, cooldown, recovery, interval, other
  }

  public var startTime: Double?
  /// Gesamtdauer inkl. Pausen (s).
  public var elapsedSeconds: Double?
  /// Dauer bei laufender Uhr (s), entspricht Garmins `movingDuration`/`duration` je Runde.
  public var timerSeconds: Double?
  public var distanceMeters: Double?
  public var averageHeartRate: Double?
  public var maxHeartRate: Double?
  public var intensity: Intensity?

  public init(
    timerSeconds: Double?, distanceMeters: Double?, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil,
    intensity: Intensity? = nil
  ) {
    self.timerSeconds = timerSeconds
    self.distanceMeters = distanceMeters
    self.averageHeartRate = averageHeartRate
    self.maxHeartRate = maxHeartRate
    self.intensity = intensity
  }

  /// Arbeitsrunde laut Workout (Garmins `intensityType` ACTIVE/INTERVAL).
  public var isWork: Bool {
    intensity == .active || intensity == .interval
  }
}

public struct FitActivity: Equatable, Sendable {
  public var records: [FitRecord] = []
  public var laps: [FitLap] = []

  public init(records: [FitRecord] = [], laps: [FitLap] = []) {
    self.records = records
    self.laps = laps
  }
}

/// Liest die für die Auswertung nötigen Nachrichten aus einer FIT-Datei (Garmin FIT-Protokoll 1.0/2.0).
///
/// Unterstützt Definitions- und Datennachrichten, beide Byte-Reihenfolgen, komprimierte Zeitstempel und
/// Entwicklerfelder (werden übersprungen). Feldnummern laut FIT-SDK-Profil: `record` (20): 253 Zeit,
/// 3 Herzfrequenz, 5 Distanz (1/100 m), 6 Tempo (1/1000 m/s), 7 Leistung, 73 erweitertes Tempo;
/// `lap` (19): 2 Start, 7 Gesamtzeit, 8 Uhrzeit (1/1000 s), 9 Distanz (1/100 m), 15/16 Ø/max HF, 23 Art.
public enum FitDecoder {
  public enum Failure: Error, Equatable {
    case notFit
    case truncated
    case undefinedLocalMessage(Int)
  }

  static func looksLikeFit(_ bytes: [UInt8]) -> Bool {
    bytes.count >= 12 && (bytes[0] == 12 || bytes[0] == 14) && bytes[8] == 0x2E && bytes[9] == 0x46
      && bytes[10] == 0x49 && bytes[11] == 0x54
  }

  struct Field {
    let number: Int
    let size: Int
  }

  struct Definition {
    let global: Int
    let bigEndian: Bool
    let fields: [Field]
    let developerBytes: Int
  }

  public static func decode(_ data: Data) throws -> FitActivity {
    let bytes = [UInt8](data)
    var activity = FitActivity()
    var start = 0
    // Mehrere FIT-Dateien können aneinanderhängen.
    while start + 12 <= bytes.count, looksLikeFit(Array(bytes[start..<min(bytes.count, start + 14)])) {
      let headerSize = Int(bytes[start])
      let dataSize =
        Int(bytes[start + 4]) | Int(bytes[start + 5]) << 8 | Int(bytes[start + 6]) << 16 | Int(bytes[start + 7]) << 24
      let end = min(bytes.count, start + headerSize + dataSize)
      try decodeMessages(bytes, from: start + headerSize, to: end, into: &activity)
      start = end + 2  // CRC
    }
    guard start > 0 else { throw Failure.notFit }
    return activity
  }

  static func decodeMessages(_ bytes: [UInt8], from begin: Int, to end: Int, into activity: inout FitActivity) throws {
    var definitions: [Int: Definition] = [:]
    var position = begin
    var lastTimestamp: UInt32 = 0

    func read(_ count: Int) throws -> ArraySlice<UInt8> {
      guard position + count <= end else { throw Failure.truncated }
      defer { position += count }
      return bytes[position..<(position + count)]
    }

    while position < end {
      let header = Int(try read(1).first!)
      if header & 0x80 != 0 {
        // Komprimierter Zeitstempel: 5 Bit Versatz zum letzten vollen Zeitstempel.
        let local = (header >> 5) & 0x3
        let offset = UInt32(header & 0x1F)
        var timestamp = (lastTimestamp & ~0x1F) + offset
        if offset < (lastTimestamp & 0x1F) { timestamp += 0x20 }
        lastTimestamp = timestamp
        guard let definition = definitions[local] else { throw Failure.undefinedLocalMessage(local) }
        var values = try readValues(definition, read: read)
        values[253] = Double(timestamp)
        apply(definition.global, values, to: &activity)
        continue
      }
      let local = header & 0x0F
      if header & 0x40 != 0 {
        // Reserviert, Byte-Reihenfolge, globale Nummer (2 Byte), Anzahl Felder.
        let fixed = Array(try read(5))
        let bigEndian = fixed[1] == 1
        let global = bigEndian ? Int(fixed[2]) << 8 | Int(fixed[3]) : Int(fixed[2]) | Int(fixed[3]) << 8
        var fields: [Field] = []
        for _ in 0..<Int(fixed[4]) {
          let field = try read(3)
          fields.append(Field(number: Int(field.first!), size: Int(field[field.startIndex + 1])))
        }
        var developerBytes = 0
        if header & 0x20 != 0 {
          for _ in 0..<Int(try read(1).first!) {
            developerBytes += Int(try read(3).dropFirst().first!)
          }
        }
        definitions[local] = Definition(
          global: global, bigEndian: bigEndian, fields: fields, developerBytes: developerBytes)
      } else {
        guard let definition = definitions[local] else { throw Failure.undefinedLocalMessage(local) }
        let values = try readValues(definition, read: read)
        if let timestamp = values[253] { lastTimestamp = UInt32(timestamp) }
        apply(definition.global, values, to: &activity)
      }
    }
  }

  /// Rohwerte je Feldnummer; ungültige Werte (alle Bits gesetzt) fehlen.
  static func readValues(
    _ definition: Definition, read: (Int) throws -> ArraySlice<UInt8>
  ) throws -> [Int: Double] {
    var values: [Int: Double] = [:]
    for field in definition.fields {
      let raw = try read(field.size)
      guard [1, 2, 4].contains(field.size) else { continue }
      var value: UInt32 = 0
      let ordered: [UInt8] = definition.bigEndian ? Array(raw) : Array(raw.reversed())
      for byte in ordered { value = value << 8 | UInt32(byte) }
      let invalid: UInt32 = field.size == 4 ? .max : (1 << (8 * field.size)) - 1
      if value != invalid { values[field.number] = Double(value) }
    }
    _ = try read(definition.developerBytes)
    return values
  }

  static func apply(_ global: Int, _ values: [Int: Double], to activity: inout FitActivity) {
    switch global {
    case 20:
      guard let timestamp = values[253] else { return }
      activity.records.append(
        FitRecord(
          timestamp: timestamp,
          heartRate: values[3].flatMap { $0 > 0 ? $0 : nil },
          speed: (values[73] ?? values[6]).map { $0 / 1000 },
          power: values[7],
          distance: values[5].map { $0 / 100 }))
    case 19:
      var lap = FitLap(
        timerSeconds: values[8].map { $0 / 1000 },
        distanceMeters: values[9].map { $0 / 100 },
        averageHeartRate: values[15],
        maxHeartRate: values[16],
        intensity: values[23].flatMap { FitLap.Intensity(rawValue: Int($0)) })
      lap.startTime = values[2]
      lap.elapsedSeconds = values[7].map { $0 / 1000 }
      activity.laps.append(lap)
    default:
      break
    }
  }
}
