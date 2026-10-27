import Foundation

/// Aufbereitung einer Aktivität für die Detailansicht, gegliedert wie in Garmin Connect: Übersicht, Zeit,
/// Tempo, Herzfrequenz, Höhe, Laufdynamik, Leistung, Schwimmen, Trainingseffekt. Nur vorhandene Werte erscheinen.
public enum ActivityDetails {
  public struct Row: Equatable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var id: String { label }
  }

  public struct Section: Equatable, Sendable, Identifiable {
    public var title: String
    public var rows: [Row]
    public var id: String { title }
  }

  public static func sections(_ activity: GarminActivity) -> [Section] {
    let sport = activity.sport
    var sections: [Section] = []
    func add(_ title: String, _ rows: [Row?]) {
      let rows = rows.compactMap { $0 }
      if !rows.isEmpty { sections.append(Section(title: title, rows: rows)) }
    }
    func row(_ label: String, _ value: Double?, _ format: (Double) -> String) -> Row? {
      guard let value, value.isFinite, value > 0 else { return nil }
      return Row(label: label, value: format(value))
    }

    add(
      "Übersicht",
      [
        row("Distanz", activity.distanceMeters) { distance($0, sport: sport) },
        row("Zeit", activity.durationSeconds) { duration($0) },
        row(speedLabel(sport), activity.averageSpeed) { speed($0, sport: sport) },
        row("Ø Herzfrequenz", activity.averageHeartRate) { "\(Int($0.rounded())) bpm" },
        row("Kalorien", activity.calories) { "\(Int($0.rounded())) kcal" },
        row("Anstieg", activity.elevationGain) { "\(Int($0.rounded())) m" },
      ])
    add(
      "Zeit",
      [
        row("Zeit", activity.durationSeconds) { duration($0) },
        row("Bewegungszeit", activity.movingSeconds) { duration($0) },
        row("Verstrichene Zeit", activity.elapsedSeconds) { duration($0) },
      ])
    add(
      sport == .run || sport == .swim ? "Pace" : "Geschwindigkeit",
      [
        row(speedLabel(sport), activity.averageSpeed) { speed($0, sport: sport) },
        row(sport == .run ? "Beste Pace" : "Max. Geschwindigkeit", activity.maxSpeed) { speed($0, sport: sport) },
        row("Ø bewegt", movingSpeed(activity)) { speed($0, sport: sport) },
      ])
    add(
      "Herzfrequenz",
      [
        row("Ø Herzfrequenz", activity.averageHeartRate) { "\(Int($0.rounded())) bpm" },
        row("Max. Herzfrequenz", activity.maxHeartRate) { "\(Int($0.rounded())) bpm" },
      ] + zoneRows(activity.secondsInZones))
    add(
      "Höhe",
      [
        row("Anstieg", activity.elevationGain) { "\(Int($0.rounded())) m" },
        row("Abstieg", activity.elevationLoss) { "\(Int($0.rounded())) m" },
        row("Min. Höhe", activity.minElevation) { "\(Int($0.rounded())) m" },
        row("Max. Höhe", activity.maxElevation) { "\(Int($0.rounded())) m" },
      ])
    let cadenceUnit = sport == .bike ? "U/min" : "spm"
    add(
      sport == .run ? "Laufdynamik" : "Kadenz",
      [
        row("Ø Kadenz", activity.averageCadence) { "\(Int($0.rounded())) \(cadenceUnit)" },
        row("Max. Kadenz", activity.maxCadence) { "\(Int($0.rounded())) \(cadenceUnit)" },
        row("Ø Schrittlänge", activity.strideLength) { "\(GermanFormat.number($0.rounded() / 100)) m" },
        row("Ø Bodenkontaktzeit", activity.groundContactTime) { "\(Int($0.rounded())) ms" },
        row("Ø Vertikale Bewegung", activity.verticalOscillation) { "\(GermanFormat.decimal($0)) cm" },
        row("Ø Vertikales Verhältnis", activity.verticalRatio) { "\(GermanFormat.decimal($0)) %" },
        row("Schritte", activity.steps) { "\(Int($0.rounded()))" },
      ])
    add(
      "Leistung",
      [
        row("Ø Leistung", activity.averagePower) { "\(Int($0.rounded())) W" },
        row("Max. Leistung", activity.maxPower) { "\(Int($0.rounded())) W" },
        row("Normalized Power", activity.normalizedPower) { "\(Int($0.rounded())) W" },
      ])
    add(
      "Schwimmen",
      [
        row("Bahnlänge", activity.poolLength) { "\(GermanFormat.number($0)) m" },
        row("Bahnen", activity.lengths) { "\(Int($0.rounded()))" },
        row("Züge gesamt", activity.strokes) { "\(Int($0.rounded()))" },
        row("Ø Zugfrequenz", activity.strokeRate) { "\(Int($0.rounded())) Züge/min" },
        row("Ø SWOLF", activity.swolf) { "\(Int($0.rounded()))" },
      ])
    add(
      "Trainingseffekt",
      [
        row("Aerob", activity.aerobicTrainingEffect) { GermanFormat.decimal($0) },
        row("Anaerob", activity.anaerobicTrainingEffect) { GermanFormat.decimal($0) },
        activity.trainingEffectLabel.map { Row(label: "Schwerpunkt", value: effectLabel($0)) },
        row("Trainingsbelastung", activity.trainingLoad) { "\(Int($0.rounded()))" },
        row("VO2max", activity.vo2Max) { GermanFormat.decimal($0) },
      ])
    add(
      "Sonstiges",
      [
        row("Aktive Kalorien", activity.activeKilocalories) { "\(Int($0.rounded())) kcal" },
        activity.minTemperature.map { Row(label: "Min. Temperatur", value: "\(Int($0.rounded())) °C") },
        activity.maxTemperature.map { Row(label: "Max. Temperatur", value: "\(Int($0.rounded())) °C") },
        row("Runden", activity.lapCount) { "\(Int($0.rounded()))" },
        activity.locationName.map { Row(label: "Ort", value: $0) },
      ])
    return sections
  }

  static func zoneRows(_ zones: [Double]?) -> [Row?] {
    guard let zones, zones.count == 5 else { return [] }
    let total = zones.reduce(0, +)
    guard total > 0 else { return [] }
    return zones.enumerated().map { index, seconds in
      Row(
        label: "Zone \(index + 1)",
        value: "\(duration(seconds)) (\(Int((seconds / total * 100).rounded())) %)")
    }
  }

  static func movingSpeed(_ activity: GarminActivity) -> Double? {
    guard let distance = activity.distanceMeters, let moving = activity.movingSeconds, moving > 0 else { return nil }
    return distance / moving
  }

  public static func speedLabel(_ sport: GarminActivity.Sport) -> String {
    sport == .run || sport == .swim ? "Ø Pace" : "Ø Geschwindigkeit"
  }

  /// Laufen: min/km, Schwimmen: min/100 m, sonst km/h.
  public static func speed(_ metersPerSecond: Double, sport: GarminActivity.Sport) -> String {
    guard metersPerSecond > 0 else { return "–" }
    switch sport {
    case .run:
      return "\(clock(1_000 / metersPerSecond)) /km"
    case .swim:
      return "\(clock(100 / metersPerSecond)) /100 m"
    default:
      return "\(GermanFormat.decimal(metersPerSecond * 3.6)) km/h"
    }
  }

  public static func distance(_ meters: Double, sport: GarminActivity.Sport) -> String {
    sport == .swim ? "\(Int(meters.rounded())) m" : "\(GermanFormat.number((meters / 10).rounded() / 100)) km"
  }

  /// „1:05:30“ bzw. „42:10“.
  public static func duration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let hours = total / 3_600
    let minutes = total % 3_600 / 60
    let rest = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
  }

  static func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  static func effectLabel(_ key: String) -> String {
    switch key.uppercased() {
    case "RECOVERY": "Erholung"
    case "AEROBIC_BASE": "Grundlage"
    case "TEMPO": "Tempo"
    case "LACTATE_THRESHOLD": "Laktatschwelle"
    case "SPEED": "Schnelligkeit"
    case "VO2MAX": "VO2max"
    case "ANAEROBIC_CAPACITY": "Anaerobe Kapazität"
    case "SPRINT": "Sprint"
    default: key.capitalized
    }
  }

  // MARK: - Verlauf aus der FIT-Datei

  public struct Sample: Equatable, Sendable, Identifiable {
    /// km seit Start (oder Minuten, wenn keine Distanz vorliegt)
    public var x: Double
    public var heartRate: Double?
    /// Laufen: s/km, Schwimmen: s/100 m, sonst km/h
    public var pace: Double?
    public var altitude: Double?
    public var cadence: Double?
    public var power: Double?
    public var id: Double { x }
  }

  /// Höchstens `maxPoints` gemittelte Punkte für Diagramme. Laufkadenz wird auf Schritte pro Minute verdoppelt.
  public static func samples(_ fit: FitActivity, sport: GarminActivity.Sport, maxPoints: Int = 300) -> [Sample] {
    let records = fit.records
    guard let first = records.first else { return [] }
    let byDistance = records.contains { ($0.distance ?? 0) > 0 }
    let bucket = max(1, records.count / maxPoints)
    var result: [Sample] = []
    var index = 0
    while index < records.count {
      let slice = records[index..<min(index + bucket, records.count)]
      func mean(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
      let last = slice[slice.endIndex - 1]
      let x = byDistance ? (last.distance ?? 0) / 1_000 : (last.timestamp - first.timestamp) / 60
      let speed = mean(slice.compactMap(\.speed).filter { $0 > 0.3 })
      var pace: Double?
      if let speed {
        switch sport {
        case .run: pace = 1_000 / speed
        case .swim: pace = 100 / speed
        default: pace = speed * 3.6
        }
      }
      let cadence = mean(slice.compactMap(\.cadence).filter { $0 > 0 }).map { sport == .run ? $0 * 2 : $0 }
      result.append(
        Sample(
          x: (x * 1_000).rounded() / 1_000, heartRate: mean(slice.compactMap(\.heartRate)), pace: pace,
          altitude: mean(slice.compactMap(\.altitude)), cadence: cadence,
          power: mean(slice.compactMap(\.power))))
      index += bucket
    }
    return result
  }

  /// GPS-Strecke (höchstens `maxPoints` Punkte).
  public static func route(_ fit: FitActivity, maxPoints: Int = 1_500) -> [(latitude: Double, longitude: Double)] {
    let points = fit.records.compactMap { record -> (latitude: Double, longitude: Double)? in
      guard let latitude = record.latitude, let longitude = record.longitude else { return nil }
      return (latitude, longitude)
    }
    let step = max(1, points.count / maxPoints)
    return stride(from: 0, to: points.count, by: step).map { points[$0] }
  }
}
