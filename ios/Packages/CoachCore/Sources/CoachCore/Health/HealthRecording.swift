import Foundation

/// Verlauf eines Workouts aus Apple Health (Apple Watch und andere Uhren, die dorthin schreiben) als Aufzeichnung im
/// selben Format wie die Datei einer Garmin-Uhr (`FitActivity`). So gelten Auswertung, Splits und Diagramme
/// unverändert (`ActivityReportBuilder`).
public enum HealthRecording {
  /// Einzelwert zu einem Zeitpunkt (Sekunden seit Bezugsdatum).
  public struct Sample: Equatable, Sendable {
    public var time: Double
    public var value: Double

    public init(time: Double, value: Double) {
      self.time = time
      self.value = value
    }
  }

  /// Menge über einen Zeitraum (z. B. 12 m Distanz in 3 s).
  public struct Amount: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var value: Double

    public init(start: Double, end: Double, value: Double) {
      self.start = start
      self.end = end
      self.value = value
    }
  }

  public struct Location: Equatable, Sendable {
    public var time: Double
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double?

    public init(time: Double, latitude: Double, longitude: Double, altitude: Double? = nil) {
      self.time = time
      self.latitude = latitude
      self.longitude = longitude
      self.altitude = altitude
    }
  }

  public struct Interval: Equatable, Sendable {
    public var start: Double
    public var end: Double

    public init(start: Double, end: Double) {
      self.start = start
      self.end = end
    }
  }

  public struct Input: Equatable, Sendable {
    public var start: Double
    public var end: Double
    /// Schläge pro Minute.
    public var heartRate: [Sample] = []
    /// Meter je Zeitraum.
    public var distance: [Amount] = []
    /// Watt.
    public var power: [Sample] = []
    public var locations: [Location] = []
    /// Runden laut Uhr (Taste oder Bahn), nicht die automatischen Kilometer.
    public var laps: [Interval] = []
    public var pauses: [Interval] = []

    public init(start: Double, end: Double) {
      self.start = start
      self.end = end
    }
  }

  /// Raster der Aufzeichnung in Sekunden.
  public static let step = 5.0
  /// Ein Messwert gilt höchstens so lange (s); danach ist die Stelle leer.
  static let validSeconds = 30.0

  /// Messpunkte alle 5 Sekunden; pausierte Zeit bleibt als Lücke (zählt in der Auswertung als Standzeit).
  public static func fit(_ input: Input) -> FitActivity {
    guard input.end > input.start else { return FitActivity() }
    let heartRate = input.heartRate.sorted { $0.time < $1.time }
    let power = input.power.sorted { $0.time < $1.time }
    let distance = input.distance.filter { $0.end >= $0.start && $0.value >= 0 }.sorted { $0.start < $1.start }
    let locations = input.locations.sorted { $0.time < $1.time }
    var cursors = (heartRate: 0, power: 0, location: 0, distance: 0)
    var completed = 0.0
    var previous: (time: Double, distance: Double)?
    var records: [FitRecord] = []

    var time = input.start
    while time <= input.end + 0.001 {
      defer { time += step }
      if input.pauses.contains(where: { $0.start <= time && time < $0.end }) {
        previous = nil
        continue
      }
      var record = FitRecord(timestamp: time)
      record.heartRate = latest(heartRate, at: time, cursor: &cursors.heartRate)
      record.power = latest(power, at: time, cursor: &cursors.power)

      if !distance.isEmpty {
        // Abgeschlossene Zeiträume ganz, der laufende anteilig.
        while cursors.distance < distance.count, distance[cursors.distance].end <= time {
          completed += distance[cursors.distance].value
          cursors.distance += 1
        }
        var total = completed
        if cursors.distance < distance.count {
          let current = distance[cursors.distance]
          if current.start < time, current.end > current.start {
            total += current.value * (time - current.start) / (current.end - current.start)
          }
        }
        record.distance = total
        if let previous, time > previous.time {
          record.speed = max(0, (total - previous.distance) / (time - previous.time))
        }
        previous = (time, total)
      }

      while cursors.location + 1 < locations.count, locations[cursors.location + 1].time <= time {
        cursors.location += 1
      }
      if cursors.location < locations.count {
        let location = locations[cursors.location]
        if abs(location.time - time) <= validSeconds {
          record.latitude = location.latitude
          record.longitude = location.longitude
          record.altitude = location.altitude
        }
      }
      records.append(record)
    }
    return FitActivity(records: records, laps: laps(input, records: records))
  }

  /// Jüngster Wert bis `time`, höchstens 30 s alt.
  private static func latest(_ samples: [Sample], at time: Double, cursor: inout Int) -> Double? {
    while cursor + 1 < samples.count, samples[cursor + 1].time <= time { cursor += 1 }
    guard cursor < samples.count else { return nil }
    let sample = samples[cursor]
    return sample.time <= time && time - sample.time <= validSeconds ? sample.value : nil
  }

  /// Runden mit Zeit ohne Pausen, Distanz und Puls aus den Messpunkten.
  static func laps(_ input: Input, records: [FitRecord]) -> [FitLap] {
    input.laps.filter { $0.end > $0.start }.sorted { $0.start < $1.start }.map { lap in
      let inside = records.filter { $0.timestamp >= lap.start && $0.timestamp <= lap.end }
      let paused = input.pauses.reduce(0.0) { sum, pause in
        sum + max(0, min(pause.end, lap.end) - max(pause.start, lap.start))
      }
      let heartRates = inside.compactMap(\.heartRate)
      var meters: Double?
      if let first = inside.first?.distance, let last = inside.last?.distance { meters = max(0, last - first) }
      var result = FitLap(
        timerSeconds: lap.end - lap.start - paused, distanceMeters: meters,
        averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
        maxHeartRate: heartRates.max())
      result.elapsedSeconds = lap.end - lap.start
      result.startTime = lap.start
      if let meters, let seconds = result.timerSeconds, seconds > 0, meters > 0 {
        result.averageSpeed = meters / seconds
      }
      let powers = inside.compactMap(\.power)
      if !powers.isEmpty { result.averagePower = powers.reduce(0, +) / Double(powers.count) }
      return result
    }
  }
}
