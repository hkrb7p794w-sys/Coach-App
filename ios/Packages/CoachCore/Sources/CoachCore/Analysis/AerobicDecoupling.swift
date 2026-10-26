import Foundation

/// Aerobe Kopplung („aerobic decoupling“, Pa:HR bzw. Pw:HR) wie im Altbestand (`decoupling.py`, Methode 3).
///
/// Aufwärmen (10 min) abschneiden, den Rest nach Zeit halbieren und je Hälfte einen Effizienzfaktor
/// (Tempo bzw. Leistung je Herzschlag) bilden: Entkopplung % = (EF1 − EF2) / EF1 × 100. Positive Werte heißen,
/// die HF steigt relativ zur Leistung (Herz-Kreislauf-Drift). Unter 5 % gilt als stabile aerobe Basis für die
/// Dauer – eine Praxisregel, keine scharf belegte Schwelle. Nur gleichmäßige, aerobe Einheiten sind
/// aussagekräftig: höchstens 10 % der Zeit in Zone 4–5.
public enum AerobicDecoupling {
  public static let methodVersion = 3
  public static let warmupSeconds = 600.0
  public static let maxHighZoneShare = 0.10
  public static let minRunMinutes = 35.0
  public static let minRideMinutes = 45.0
  /// Unter diesem Wert gilt die Kopplung als stabil (Praxiswert nach Friel).
  public static let goodBelowPercent = 5.0

  public enum Sport: String, Codable, Sendable {
    case run, ride
  }

  public enum Source: String, Codable, Sendable {
    case series, laps
  }

  public struct Result: Codable, Equatable, Sendable {
    public var percent: Double
    public var firstHalfHeartRate: Double
    public var secondHalfHeartRate: Double
    /// Laufen: Tempo je Hälfte in s/km.
    public var firstHalfPace: Int?
    public var secondHalfPace: Int?
    /// Rad: Leistung je Hälfte in Watt.
    public var firstHalfPower: Int?
    public var secondHalfPower: Int?
    public var source: Source
  }

  public struct Sample: Equatable, Sendable {
    /// Sekunden seit Start.
    public var time: Double
    /// m/s (Laufen) oder Watt (Rad).
    public var output: Double
    public var heartRate: Double

    public init(time: Double, output: Double, heartRate: Double) {
      self.time = time
      self.output = output
      self.heartRate = heartRate
    }
  }

  // MARK: - Auswahl

  public static func highZoneShare(_ activity: GarminActivity) -> Double? {
    guard let zones = activity.secondsInZones, zones.count == 5 else { return nil }
    let total = zones.reduce(0, +)
    return total > 0 ? (zones[3] + zones[4]) / total : nil
  }

  /// Ob und als was die Aktivität infrage kommt (`classify`).
  public static func classify(_ activity: GarminActivity) -> Sport? {
    let minutes = (activity.durationSeconds ?? 0) / 60
    let sport: Sport
    switch activity.sport {
    case .run:
      guard minutes >= minRunMinutes else { return nil }
      sport = .run
    case .bike:
      // Nur die Zwift-Aufzeichnung mit Distanz und Leistung, nicht die HF-Zweitaufzeichnung der Uhr.
      guard minutes >= minRideMinutes, (activity.distanceMeters ?? 0) > 0, activity.averagePower != nil else {
        return nil
      }
      sport = .ride
    default:
      return nil
    }
    guard let share = highZoneShare(activity), share <= maxHighZoneShare else { return nil }
    return sport
  }

  /// Klartext, warum `classify` die Aktivität verworfen hat; `nil` für andere Sportarten und die
  /// HF-Zweitaufzeichnung der Uhr (`skip_reason`).
  public static func skipReason(_ activity: GarminActivity) -> String? {
    let minutes = (activity.durationSeconds ?? 0) / 60
    let isRun = activity.sport == .run
    let isRide = activity.sport == .bike
    guard isRun || isRide else { return nil }
    if isRide && (activity.distanceMeters ?? 0) <= 0 { return nil }
    if isRun && minutes < minRunMinutes { return "kürzer als \(Int(minRunMinutes)) min" }
    if isRide && minutes < minRideMinutes { return "kürzer als \(Int(minRideMinutes)) min" }
    if isRide && activity.averagePower == nil { return "keine Leistungsdaten" }
    guard let share = highZoneShare(activity) else { return "keine HF-Zonendaten von Garmin" }
    if share > maxHighZoneShare {
      return "zu intensiv (\(Int((share * 100).rounded(.toNearestOrEven))) % der Zeit in Zone 4-5)"
    }
    return "nicht geeignet"
  }

  // MARK: - Berechnung

  /// Messpunkte aus der FIT-Datei (Zeit relativ zum ersten Messpunkt).
  public static func samples(_ fit: FitActivity, sport: Sport) -> [Sample] {
    guard let start = fit.records.first?.timestamp else { return [] }
    return fit.records.compactMap { record in
      guard let heartRate = record.heartRate, heartRate > 0,
        let output = sport == .ride ? record.power : record.speed
      else { return nil }
      return Sample(time: record.timestamp - start, output: output, heartRate: heartRate)
    }
  }

  /// Entkopplung aus der Zeitreihe (`compute_from_details`).
  public static func fromSeries(_ samples: [Sample], sport: Sport) -> Result? {
    let points = samples.filter { $0.heartRate > 0 && $0.time >= warmupSeconds }
    guard points.count >= 20, let first = points.first, let last = points.last,
      last.time - first.time >= 20 * 60
    else { return nil }
    let mid = first.time + (last.time - first.time) / 2
    let firstHalf = points.filter { $0.time < mid }
    let secondHalf = points.filter { $0.time >= mid }
    guard !firstHalf.isEmpty, !secondHalf.isEmpty else { return nil }
    func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }
    let output1 = mean(firstHalf.map(\.output))
    let heart1 = mean(firstHalf.map(\.heartRate))
    let output2 = mean(secondHalf.map(\.output))
    let heart2 = mean(secondHalf.map(\.heartRate))
    guard output1 > 0, heart1 > 0, heart2 > 0 else { return nil }
    let efficiency1 = output1 / heart1
    let efficiency2 = output2 / heart2
    var result = Result(
      percent: round1((efficiency1 - efficiency2) / efficiency1 * 100),
      firstHalfHeartRate: round1(heart1), secondHalfHeartRate: round1(heart2), source: .series)
    if sport == .ride {
      result.firstHalfPower = Int(output1.rounded(.toNearestOrEven))
      result.secondHalfPower = Int(output2.rounded(.toNearestOrEven))
    } else {
      result.firstHalfPace = pace(speed: output1)
      result.secondHalfPace = pace(speed: output2)
    }
    return result
  }

  /// Rundenmethode für Läufe ohne Zeitreihe (`compute_from_laps_trimmed`): Runden der ersten 10 Minuten
  /// fallen weg, dann Teilung nach Distanz.
  public static func fromLaps(_ laps: [FitLap]) -> Result? {
    var kept: [FitLap] = []
    var elapsed = 0.0
    for lap in laps {
      if elapsed >= warmupSeconds { kept.append(lap) }
      elapsed += lap.timerSeconds ?? lap.elapsedSeconds ?? 0
    }
    let metrics: [(distance: Double, duration: Double, heartRate: Double)] = kept.compactMap { lap in
      guard let distance = lap.distanceMeters, distance > 0,
        let duration = lap.timerSeconds ?? lap.elapsedSeconds, duration > 0,
        let heartRate = lap.averageHeartRate, heartRate > 0
      else { return nil }
      return (distance, duration, heartRate)
    }
    guard metrics.count >= 2 else { return nil }
    let half = metrics.reduce(0) { $0 + $1.distance } / 2
    var firstHalf: [(distance: Double, duration: Double, heartRate: Double)] = []
    var secondHalf: [(distance: Double, duration: Double, heartRate: Double)] = []
    var cumulative = 0.0
    for lap in metrics {
      cumulative += lap.distance
      if cumulative <= half { firstHalf.append(lap) } else { secondHalf.append(lap) }
    }
    if firstHalf.isEmpty || secondHalf.isEmpty {
      // Grenze fällt bei wenigen, ungleichen Runden so, dass eine Seite leer bleibt: nach Rundenzahl teilen.
      let mid = max(metrics.count / 2, 1)
      firstHalf = Array(metrics[..<mid])
      secondHalf = Array(metrics[mid...])
    }
    func stats(_ part: [(distance: Double, duration: Double, heartRate: Double)]) -> (speed: Double, heart: Double)? {
      let distance = part.reduce(0) { $0 + $1.distance }
      let duration = part.reduce(0) { $0 + $1.duration }
      guard distance > 0, duration > 0 else { return nil }
      return (distance / duration, part.reduce(0) { $0 + $1.heartRate * $1.duration } / duration)
    }
    guard let first = stats(firstHalf), let second = stats(secondHalf) else { return nil }
    let efficiency1 = first.speed / first.heart
    let efficiency2 = second.speed / second.heart
    return Result(
      percent: round1((efficiency1 - efficiency2) / efficiency1 * 100),
      firstHalfHeartRate: round1(first.heart), secondHalfHeartRate: round1(second.heart),
      firstHalfPace: lapPace(speed: first.speed), secondHalfPace: lapPace(speed: second.speed), source: .laps)
  }

  /// Zeitreihe zuerst, bei Läufen notfalls die Runden (wie `_update_decoupling_cache`).
  public static func compute(_ fit: FitActivity, sport: Sport) -> Result? {
    fromSeries(samples(fit, sport: sport), sport: sport) ?? (sport == .run ? fromLaps(fit.laps) : nil)
  }

  static func round1(_ value: Double) -> Double {
    (value * 10).rounded(.toNearestOrEven) / 10
  }

  static func pace(speed: Double) -> Int? {
    speed > 0 ? Int((1000 / speed).rounded(.toNearestOrEven)) : nil
  }

  /// Wie im Altbestand: erst auf 1/100 min/km, dann auf Sekunden runden.
  static func lapPace(speed: Double) -> Int? {
    guard speed > 0 else { return nil }
    let minutes = ((1000 / speed) / 60 * 100).rounded(.toNearestOrEven) / 100
    return Int((minutes * 60).rounded(.toNearestOrEven))
  }
}
