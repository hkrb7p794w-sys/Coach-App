import Foundation

/// Vollständige Auswertung einer aufgezeichneten Aktivität aus der Datei der Uhr (FIT): Runden, Splits, Verlauf für
/// die Diagramme und Kennzahlen zu Tempo-Einteilung, Puls-Drift, Intervallen und Standzeit. Wird beim Abruf für jede
/// Aktivität erzeugt und gespeichert, damit Detailansicht, Coach und KI-Export sie ohne erneuten Abruf nutzen.
public struct ActivityReport: Codable, Equatable, Sendable, Identifiable {
  /// Abschnitt fester Länge (Laufen/Gehen 1 km, Rad 5 km, Schwimmen 100 m).
  public struct Split: Codable, Equatable, Sendable, Identifiable {
    public var index: Int
    public var meters: Double
    public var seconds: Double
    public var averageHeartRate: Double?
    public var ascentMeters: Double?
    public var id: Int { index }
    /// m/s
    public var speed: Double { seconds > 0 ? meters / seconds : 0 }
  }

  /// Vergleich erste gegen zweite Hälfte (nach Bewegungszeit).
  public struct Halves: Codable, Equatable, Sendable {
    /// Tempoänderung der zweiten Hälfte in Prozent (+ = schneller).
    public var speedChangePercent: Double?
    /// Pulsänderung der zweiten Hälfte in Prozent (+ = höher).
    public var heartRateChangePercent: Double?
  }

  public static let version = 1
  public static let maxLaps = 80

  public let id: Int64
  public var day: CalendarDay
  public var name: String?
  public var sport: GarminActivity.Sport
  public var version: Int
  public var laps: [FitLap]
  public var splits: [Split]
  public var splitMeters: Double
  public var samples: [ActivityDetails.Sample]
  public var byDistance: Bool
  public var halves: Halves
  /// Zeit mit angehaltener Uhr bzw. im Stand (s).
  public var pausedSeconds: Double
  public var movingSeconds: Double
  /// Anteil der Zeit in Zone 4–5 in Prozent (aus der Aktivität).
  public var highZonePercent: Double?
  /// Schritte pro Minute (Laufen) bzw. Umdrehungen pro Minute.
  public var averageCadence: Double?
}

public enum ActivityReportBuilder {
  /// Unter dieser Geschwindigkeit gilt ein Messpunkt als Stand (m/s).
  static let movingSpeed = 0.5

  public static func splitLength(_ sport: GarminActivity.Sport) -> Double {
    switch sport {
    case .bike: 5_000
    case .swim: 100
    default: 1_000
    }
  }

  public static func build(_ activity: GarminActivity, fit: FitActivity) -> ActivityReport {
    let sport = activity.sport
    let records = fit.records
    let length = splitLength(sport)
    let moving = movingSeconds(records)
    let elapsed = (records.last?.timestamp ?? 0) - (records.first?.timestamp ?? 0)
    let total = activity.elapsedSeconds ?? activity.durationSeconds ?? elapsed
    let cadence = mean(records.compactMap(\.cadence).filter { $0 > 0 }).map { sport == .run ? $0 * 2 : $0 }
    return ActivityReport(
      id: activity.id, day: activity.day ?? CalendarDay(year: 2000, month: 1, day: 1), name: activity.name,
      sport: sport, version: ActivityReport.version, laps: Array(fit.laps.prefix(ActivityReport.maxLaps)),
      splits: splits(records, length: length), splitMeters: length,
      samples: ActivityDetails.samples(fit, sport: sport, maxPoints: 150),
      byDistance: records.contains { ($0.distance ?? 0) > 0 }, halves: halves(records),
      pausedSeconds: max(0, max(total, elapsed) - moving), movingSeconds: moving,
      highZonePercent: AerobicDecoupling.highZoneShare(activity).map { AerobicDecoupling.round1($0 * 100) },
      averageCadence: cadence.map { ($0 * 10).rounded() / 10 })
  }

  static func mean(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }

  /// Zeitabstand zum Vorgänger; Lücken über 10 s (angehaltene Uhr) zählen nicht als Bewegung.
  private static func steps(_ records: [FitRecord]) -> [(record: FitRecord, seconds: Double, moving: Bool)] {
    var result: [(record: FitRecord, seconds: Double, moving: Bool)] = []
    for index in records.indices.dropFirst() {
      let delta = records[index].timestamp - records[index - 1].timestamp
      guard delta > 0 else { continue }
      let speed = records[index].speed
      let moving = delta <= 10 && (speed == nil || (speed ?? 0) >= movingSpeed)
      result.append((record: records[index], seconds: min(delta, 10), moving: moving))
    }
    return result
  }

  static func movingSeconds(_ records: [FitRecord]) -> Double {
    steps(records).filter(\.moving).reduce(0) { $0 + $1.seconds }
  }

  /// Abschnitte fester Länge aus der Distanzspur; ein Rest unter 40 % der Länge entfällt.
  static func splits(_ records: [FitRecord], length: Double) -> [ActivityReport.Split] {
    var result: [ActivityReport.Split] = []
    var startDistance = 0.0
    var seconds = 0.0
    var heartRates: [Double] = []
    var ascent = 0.0
    var hasAltitude = false
    var lastAltitude: Double?
    func close(_ meters: Double) {
      result.append(
        ActivityReport.Split(
          index: result.count + 1, meters: meters, seconds: seconds, averageHeartRate: mean(heartRates),
          ascentMeters: hasAltitude ? ascent.rounded() : nil))
    }
    for step in steps(records) {
      guard let distance = step.record.distance else { continue }
      if step.moving { seconds += step.seconds }
      if let heartRate = step.record.heartRate { heartRates.append(heartRate) }
      if let altitude = step.record.altitude {
        hasAltitude = true
        if let last = lastAltitude, altitude > last { ascent += altitude - last }
        lastAltitude = altitude
      }
      if distance - startDistance >= length {
        close(length)
        startDistance += length
        seconds = 0
        heartRates = []
        ascent = 0
      }
    }
    let rest = (records.last?.distance ?? 0) - startDistance
    if rest >= length * 0.4, seconds > 0 { close(rest) }
    return result
  }

  /// Erste gegen zweite Hälfte der Bewegungszeit: mittleres Tempo und mittlerer Puls.
  static func halves(_ records: [FitRecord]) -> ActivityReport.Halves {
    let moving = steps(records).filter(\.moving)
    let total = moving.reduce(0) { $0 + $1.seconds }
    guard total >= 600 else { return ActivityReport.Halves() }
    var first: (speed: [Double], heartRate: [Double]) = ([], [])
    var second: (speed: [Double], heartRate: [Double]) = ([], [])
    var passed = 0.0
    for step in moving {
      passed += step.seconds
      if passed <= total / 2 {
        if let speed = step.record.speed, speed > 0 { first.speed.append(speed) }
        if let heartRate = step.record.heartRate { first.heartRate.append(heartRate) }
      } else {
        if let speed = step.record.speed, speed > 0 { second.speed.append(speed) }
        if let heartRate = step.record.heartRate { second.heartRate.append(heartRate) }
      }
    }
    func change(_ a: [Double], _ b: [Double]) -> Double? {
      guard a.count >= 60, b.count >= 60, let early = mean(a), let late = mean(b), early > 0 else { return nil }
      return AerobicDecoupling.round1((late / early - 1) * 100)
    }
    return ActivityReport.Halves(
      speedChangePercent: change(first.speed, second.speed),
      heartRateChangePercent: change(first.heartRate, second.heartRate))
  }
}

/// Aussagen zu einer Aktivität in klaren Sätzen. Regeln entscheiden; die KI bekommt nur diese Sätze.
public enum ActivityFindings {
  public struct Finding: Equatable, Sendable, Identifiable {
    public enum Tone: String, Sendable { case good, neutral, attention }
    public var id: String
    public var text: String
    public var tone: Tone
    /// Enthält Pulswerte in Schlägen (im Datenschutzmodus „reduziert“ nicht an die KI).
    public var hasRawHeartRate = false
  }

  /// Schwellen: Tempo ab ±2 % nennenswert, ab −5 % deutlich; Puls-Drift ab 5 % bei gleichmäßigem Tempo
  /// (übliche Grenze der aeroben Entkopplung, vgl. `AerobicDecoupling`).
  public static func findings(_ report: ActivityReport) -> [Finding] {
    var result: [Finding] = []
    let sport = report.sport
    let intervals = report.laps.filter(\.isWork)
    let structured = intervals.count >= 3 && report.laps.contains { !$0.isWork && $0.intensity != nil }

    if structured {
      result += intervalFindings(intervals, sport: sport)
    } else if let change = report.halves.speedChangePercent, sport != .strength, sport != .other {
      if change >= 2 {
        result.append(
          Finding(
            id: "pacing", text: "Zweite Hälfte \(percent(change)) schneller als die erste – gut eingeteilt.",
            tone: .good))
      } else if change <= -5 {
        result.append(
          Finding(
            id: "pacing",
            text: "Zweite Hälfte \(percent(-change)) langsamer als die erste – vermutlich zu schnell begonnen.",
            tone: .attention))
      } else {
        result.append(Finding(id: "pacing", text: "Tempo über die ganze Einheit gleichmäßig.", tone: .good))
      }
      if abs(change) < 3, let drift = report.halves.heartRateChangePercent {
        if drift >= 5 {
          result.append(
            Finding(
              id: "drift",
              text: "Puls stieg bei gleichem Tempo um \(percent(drift)) – Zeichen für Ermüdung, Wärme oder zu wenig "
                + "Trinken.", tone: .attention))
        } else if drift > -5 {
          result.append(Finding(id: "drift", text: "Puls blieb bei gleichem Tempo stabil.", tone: .good))
        }
      }
    }

    let full = report.splits.filter { $0.meters >= report.splitMeters * 0.99 && $0.seconds > 0 }
    if !structured, full.count >= 3, let fastest = full.max(by: { $0.speed < $1.speed }),
      let slowest = full.min(by: { $0.speed < $1.speed })
    {
      let unit = splitName(report.splitMeters)
      result.append(
        Finding(
          id: "splits",
          text: "Schnellster \(unit): Nr. \(fastest.index) (\(ActivityDetails.speed(fastest.speed, sport: sport))), "
            + "langsamster: Nr. \(slowest.index) (\(ActivityDetails.speed(slowest.speed, sport: sport))).",
          tone: .neutral))
    }

    let total = report.movingSeconds + report.pausedSeconds
    if total > 0, report.pausedSeconds >= 120, report.pausedSeconds / total >= 0.1 {
      result.append(
        Finding(
          id: "pause",
          text: "\(Int((report.pausedSeconds / 60).rounded())) min Standzeit "
            + "(\(Int((report.pausedSeconds / total * 100).rounded())) % der Gesamtzeit).", tone: .neutral))
    }
    if let high = report.highZonePercent, high >= 1 {
      result.append(
        Finding(
          id: "zones", text: "\(GermanFormat.decimal(high)) % der Zeit in Zone 4–5.",
          tone: high >= 40 ? .attention : .neutral))
    }
    return result
  }

  static func intervalFindings(_ intervals: [FitLap], sport: GarminActivity.Sport) -> [Finding] {
    let speeds = intervals.compactMap { lap -> Double? in
      if let speed = lap.averageSpeed, speed > 0 { return speed }
      guard let meters = lap.distanceMeters, let seconds = lap.timerSeconds, seconds > 0, meters > 0 else { return nil }
      return meters / seconds
    }
    guard speeds.count >= 3, let mean = ActivityReportBuilder.mean(speeds), let first = speeds.first,
      let last = speeds.last
    else { return [] }
    var result = [
      Finding(
        id: "intervals",
        text: "\(speeds.count) Intervalle, im Schnitt \(ActivityDetails.speed(mean, sport: sport)).", tone: .neutral)
    ]
    let change = (last / first - 1) * 100
    if change <= -4 {
      result.append(
        Finding(
          id: "fade",
          text: "Letztes Intervall \(percent(-change)) langsamer als das erste – das Tempo war am Anfang zu hoch.",
          tone: .attention))
    } else {
      result.append(Finding(id: "fade", text: "Tempo bis zum letzten Intervall gehalten.", tone: .good))
    }
    let heartRates = intervals.compactMap(\.averageHeartRate)
    if heartRates.count >= 3, let top = heartRates.max() {
      result.append(
        Finding(
          id: "intervalHeartRate", text: "Höchster Intervall-Schnitt: \(Int(top.rounded())) Schläge pro Minute.",
          tone: .neutral, hasRawHeartRate: true))
    }
    return result
  }

  static func percent(_ value: Double) -> String { "\(GermanFormat.decimal(value)) %" }

  /// Überschrift der Split-Liste.
  public static func splitTitle(_ meters: Double) -> String {
    switch meters {
    case 100: "100-m-Abschnitte"
    case 5_000: "5-km-Abschnitte"
    default: "Kilometer"
    }
  }

  static func splitName(_ meters: Double) -> String {
    switch meters {
    case 100: "100-m-Abschnitt"
    case 5_000: "5-km-Abschnitt"
    default: "Kilometer"
    }
  }

  /// Zeile für den Coach, z. B. „Morgenlauf (10.11.): Tempo gleichmäßig. Puls stabil.“ – im Modus „reduziert“ ohne
  /// Pulswerte in Schlägen.
  public static func contextLine(_ report: ActivityReport, full: Bool) -> String? {
    let texts = findings(report).filter { full || !$0.hasRawHeartRate }.map(\.text)
    guard !texts.isEmpty else { return nil }
    let name = report.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return "\(name.isEmpty ? "Aktivität" : name) (\(GermanFormat.date(report.day))): " + texts.joined(separator: " ")
  }
}

/// Welche Aktivitäten vollständig übertragen werden.
public enum ActivityReportPlanner {
  /// So weit zurück werden Aktivitäten vollständig nachgeladen.
  public static let days = 42
  public static let minSeconds = 300.0

  /// Aktivitäten ohne (aktuellen) Bericht, jüngste zuerst. Garmin-Aktivitäten (positive IDs) haben eine Datei der
  /// Uhr; mit `health` stattdessen die Workouts aus Apple Health (negative IDs), deren Verlauf HealthKit liefert.
  public static func pending(
    _ activities: [GarminActivity], known: [Int64: ActivityReport], failed: Set<Int64> = [], today: CalendarDay,
    health: Bool = false
  ) -> [GarminActivity] {
    let start = today.adding(days: -days)
    return
      activities
      .filter { activity in
        guard (activity.id < 0) == health, let day = activity.day, day >= start, day <= today else { return false }
        guard (activity.durationSeconds ?? 0) >= minSeconds, !failed.contains(activity.id) else { return false }
        return known[activity.id]?.version != ActivityReport.version
      }
      .sorted { ($0.startLocal ?? "") > ($1.startLocal ?? "") }
  }
}
