import Foundation

/// Erholungs- und Tageswerte eines Kalendertags, zusammengeführt aus mehreren Garmin-Endpunkten.
/// Alle Werte optional: Nicht jede Uhr liefert alles, und die Personal API ist nicht vollständig
/// dokumentiert.
public struct DailyMetrics: Codable, Equatable, Sendable {
  public var day: CalendarDay
  public var restingHeartRate: Double?
  public var hrvLastNightAverage: Double?
  public var hrvWeeklyAverage: Double?
  /// Garmins HRV-Status: `BALANCED`, `UNBALANCED`, `LOW`, `POOR`, `NONE`.
  public var hrvStatus: String?
  public var hrvBaselineLow: Double?
  public var hrvBaselineHigh: Double?
  public var sleepSeconds: Double?
  public var sleepScore: Double?
  public var bodyBatteryHigh: Double?
  public var bodyBatteryLow: Double?
  public var bodyBatteryLatest: Double?
  public var stressAverage: Double?
  public var steps: Double?
  public var activeKilocalories: Double?
  public var totalKilocalories: Double?

  public init(day: CalendarDay) {
    self.day = day
  }

  public var sleepHours: Double? {
    sleepSeconds.map { ($0 / 360).rounded() / 10 }
  }

  /// Vorhandene Werte von `other` überschreiben fehlende oder ältere Werte.
  public func merging(_ other: DailyMetrics) -> DailyMetrics {
    var result = self
    result.restingHeartRate = other.restingHeartRate ?? restingHeartRate
    result.hrvLastNightAverage = other.hrvLastNightAverage ?? hrvLastNightAverage
    result.hrvWeeklyAverage = other.hrvWeeklyAverage ?? hrvWeeklyAverage
    result.hrvStatus = other.hrvStatus ?? hrvStatus
    result.hrvBaselineLow = other.hrvBaselineLow ?? hrvBaselineLow
    result.hrvBaselineHigh = other.hrvBaselineHigh ?? hrvBaselineHigh
    result.sleepSeconds = other.sleepSeconds ?? sleepSeconds
    result.sleepScore = other.sleepScore ?? sleepScore
    result.bodyBatteryHigh = other.bodyBatteryHigh ?? bodyBatteryHigh
    result.bodyBatteryLow = other.bodyBatteryLow ?? bodyBatteryLow
    result.bodyBatteryLatest = other.bodyBatteryLatest ?? bodyBatteryLatest
    result.stressAverage = other.stressAverage ?? stressAverage
    result.steps = other.steps ?? steps
    result.activeKilocalories = other.activeKilocalories ?? activeKilocalories
    result.totalKilocalories = other.totalKilocalories ?? totalKilocalories
    return result
  }

  /// Namen der befüllten Felder – für die Diagnose in der App.
  public var presentFields: [String] {
    let fields: [(String, Any?)] = [
      ("Ruhepuls", restingHeartRate), ("HRV letzte Nacht", hrvLastNightAverage),
      ("HRV 7 Tage", hrvWeeklyAverage), ("HRV-Status", hrvStatus), ("HRV-Baseline", hrvBaselineLow),
      ("Schlafdauer", sleepSeconds), ("Schlaf-Score", sleepScore), ("Body Battery", bodyBatteryHigh),
      ("Stress", stressAverage), ("Schritte", steps), ("Aktive kcal", activeKilocalories),
    ]
    return fields.compactMap { $0.1 == nil ? nil : $0.0 }
  }
}

/// Liest Tageswerte aus den Antworten der Personal API.
///
/// Feldnamen: wie in den Connect-Endpunkten, auf denen die Personal API aufsetzt (bekannt aus
/// python-garminconnect und dem Altbestand, z. B. `hrvSummary.status`, `dailySleepDTO.sleepTimeSeconds`).
/// Jeder Wert hat mehrere Kandidaten, damit kleine Formatänderungen nichts kaputt machen.
public enum GarminMetricsParser {
  public typealias DayMap = [CalendarDay: DailyMetrics]

  /// `/usersummary-service/v2/dailysummaries`: Objekt mit Daten-Array, je Tag ein Eintrag.
  public static func dailySummaries(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.restingHeartRate = positive(
        record.first("restingHeartRate", "restingHeartRateValue", "currentDayRestingHeartRate"))
      metrics.steps = nonNegative(record.first("totalSteps"))
      metrics.stressAverage = nonNegative(record.first("averageStressLevel", "avgStressLevel"))
      metrics.bodyBatteryHigh = nonNegative(record.first("bodyBatteryHighestValue", "highestBodyBattery"))
      metrics.bodyBatteryLow = nonNegative(record.first("bodyBatteryLowestValue", "lowestBodyBattery"))
      metrics.bodyBatteryLatest = nonNegative(record.first("bodyBatteryMostRecentValue"))
      metrics.activeKilocalories = nonNegative(record.first("activeKilocalories"))
      metrics.totalKilocalories = nonNegative(record.first("totalKilocalories"))
    }
  }

  /// `/hrv-service/hrv/{date}` (`hrvSummary`) und `/hrv-service/hrv/daily/{start}/{end}`.
  public static func hrv(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.hrvLastNightAverage = positive(record.first("lastNightAvg", "lastNightAverage"))
      metrics.hrvWeeklyAverage = positive(record.first("weeklyAvg", "weeklyAverage"))
      metrics.hrvStatus = record.first("status", "hrvStatus")?.stringValue?.uppercased()
      metrics.hrvBaselineLow = positive(record.first("balancedLow"))
      metrics.hrvBaselineHigh = positive(record.first("balancedUpper", "balancedHigh"))
    }
  }

  /// `/sleep-service/sleep/dailySleep` (`dailySleepDTO`) und `dailySleepSummariesByDate`.
  public static func sleep(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.sleepSeconds = positive(record.first("sleepTimeSeconds", "totalSleepSeconds", "sleepDurationSeconds"))
      if let scores = record.first("sleepScores") {
        metrics.sleepScore = positive(scores["overall"]?["value"] ?? scores.firstValue(forAnyOf: ["value"]))
      }
      metrics.sleepScore = metrics.sleepScore ?? positive(record.first("overallSleepScore", "sleepScore"))
    }
  }

  /// `/wellness-service/wellness/bodyBattery/reports/daily`: je Tag ggf. eine Werteliste
  /// `bodyBatteryValuesArray` mit `[Zeitstempel, Wert]`.
  public static func bodyBattery(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      let values = (record["bodyBatteryValuesArray"]?.arrayValue ?? [])
        .compactMap { $0.arrayValue?.dropFirst().first?.doubleValue }
        .filter { $0 >= 0 }
      metrics.bodyBatteryHigh = values.max() ?? nonNegative(record.first("bodyBatteryHighestValue", "charged"))
      metrics.bodyBatteryLow = values.min() ?? nonNegative(record.first("bodyBatteryLowestValue"))
      metrics.bodyBatteryLatest = values.last ?? nonNegative(record.first("bodyBatteryMostRecentValue"))
    }
  }

  /// `/usersummary-service/stats/stress/daily/{start}/{end}`.
  public static func stress(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.stressAverage = nonNegative(
        record.first("averageStressLevel", "avgStressLevel", "overallStressLevel"))
    }
  }

  /// Führt mehrere Teilergebnisse zusammen (spätere überschreiben frühere, wenn befüllt).
  public static func merge(_ maps: [DayMap]) -> DayMap {
    maps.reduce(into: DayMap()) { result, map in
      for (day, metrics) in map {
        result[day] = result[day].map { $0.merging(metrics) } ?? metrics
      }
    }
  }

  // MARK: - Hilfen

  private static func records(
    in json: JSONValue,
    _ fill: ([String: JSONValue], inout DailyMetrics) -> Void
  ) -> DayMap {
    var result = DayMap()
    for record in json.objects(containingKey: "calendarDate") {
      guard let text = record["calendarDate"]?.stringValue, let day = CalendarDay(iso: text) else { continue }
      var metrics = DailyMetrics(day: day)
      fill(record, &metrics)
      result[day] = result[day].map { $0.merging(metrics) } ?? metrics
    }
    return result
  }

  /// Garmin nutzt negative Werte (-1, -2) für „kein Wert“.
  private static func nonNegative(_ value: JSONValue?) -> Double? {
    value?.doubleValue.flatMap { $0 >= 0 ? $0 : nil }
  }

  private static func positive(_ value: JSONValue?) -> Double? {
    value?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
  }
}
