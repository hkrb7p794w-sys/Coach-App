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
  /// Atemfrequenz tagsüber (wach) und im Schlaf, Atemzüge pro Minute.
  public var respirationWaking: Double?
  public var respirationSleep: Double?
  /// Sauerstoffsättigung in Prozent (Durchschnitt und tiefster Wert).
  public var spo2Average: Double?
  public var spo2Lowest: Double?
  public var bodyBatteryCharged: Double?
  public var bodyBatteryDrained: Double?
  public var deepSleepSeconds: Double?
  public var lightSleepSeconds: Double?
  public var remSleepSeconds: Double?
  public var awakeSleepSeconds: Double?
  public var sleepStress: Double?
  public var fitnessAge: Double?
  public var vo2Max: Double?
  /// Nur über den Garmin-Connect-Zugang: Training Readiness (0–100) mit Garmins Stufe (`HIGH`, `LOW` …),
  /// Trainingsstatus (z. B. `PRODUCTIVE_3`) und Endurance Score.
  public var trainingReadiness: Double?
  public var trainingReadinessLevel: String?
  public var trainingStatus: String?
  public var enduranceScore: Double?
  /// Einschlaf- und Aufwachzeit in Minuten nach Mitternacht (Ortszeit), z. B. 23:30 → 1410.
  public var sleepStartMinutes: Double?
  public var sleepEndMinutes: Double?
  /// Body Battery beim Aufwachen (Garmin-Konto `bodyBatteryAtWakeTime`).
  public var bodyBatteryAtWake: Double?
  /// Tagesverlauf der Body Battery, höchstens ein Wert je 15 Minuten.
  public var bodyBatteryCurve: [BodyBatterySample]?
  /// Grundumsatz („Ruhekalorien“) des Tages.
  public var restingKilocalories: Double?
  /// Niedrigster und höchster Puls des Tages.
  public var minHeartRate: Double?
  public var maxHeartRate: Double?
  /// Regenerationszeit der Uhr in Stunden (Training Readiness, nur Garmin-Konto).
  public var recoveryHours: Double?
  /// Akute (7 Tage) und chronische (28 Tage) Trainingsbelastung der Uhr (nur Garmin-Konto).
  public var acuteLoad: Double?
  public var chronicLoad: Double?

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
    result.respirationWaking = other.respirationWaking ?? respirationWaking
    result.respirationSleep = other.respirationSleep ?? respirationSleep
    result.spo2Average = other.spo2Average ?? spo2Average
    result.spo2Lowest = other.spo2Lowest ?? spo2Lowest
    result.bodyBatteryCharged = other.bodyBatteryCharged ?? bodyBatteryCharged
    result.bodyBatteryDrained = other.bodyBatteryDrained ?? bodyBatteryDrained
    result.deepSleepSeconds = other.deepSleepSeconds ?? deepSleepSeconds
    result.lightSleepSeconds = other.lightSleepSeconds ?? lightSleepSeconds
    result.remSleepSeconds = other.remSleepSeconds ?? remSleepSeconds
    result.awakeSleepSeconds = other.awakeSleepSeconds ?? awakeSleepSeconds
    result.sleepStress = other.sleepStress ?? sleepStress
    result.fitnessAge = other.fitnessAge ?? fitnessAge
    result.vo2Max = other.vo2Max ?? vo2Max
    result.trainingReadiness = other.trainingReadiness ?? trainingReadiness
    result.trainingReadinessLevel = other.trainingReadinessLevel ?? trainingReadinessLevel
    result.trainingStatus = other.trainingStatus ?? trainingStatus
    result.enduranceScore = other.enduranceScore ?? enduranceScore
    result.sleepStartMinutes = other.sleepStartMinutes ?? sleepStartMinutes
    result.sleepEndMinutes = other.sleepEndMinutes ?? sleepEndMinutes
    result.bodyBatteryAtWake = other.bodyBatteryAtWake ?? bodyBatteryAtWake
    result.bodyBatteryCurve = other.bodyBatteryCurve ?? bodyBatteryCurve
    result.restingKilocalories = other.restingKilocalories ?? restingKilocalories
    result.minHeartRate = other.minHeartRate ?? minHeartRate
    result.maxHeartRate = other.maxHeartRate ?? maxHeartRate
    result.recoveryHours = other.recoveryHours ?? recoveryHours
    result.acuteLoad = other.acuteLoad ?? acuteLoad
    result.chronicLoad = other.chronicLoad ?? chronicLoad
    return result
  }

  /// Namen der befüllten Felder – für die Diagnose in der App.
  public var presentFields: [String] {
    let fields: [(String, Any?)] = [
      ("Ruhepuls", restingHeartRate), ("HRV letzte Nacht", hrvLastNightAverage),
      ("HRV 7 Tage", hrvWeeklyAverage), ("HRV-Status", hrvStatus), ("HRV-Baseline", hrvBaselineLow),
      ("Schlafdauer", sleepSeconds), ("Schlaf-Score", sleepScore), ("Body Battery", bodyBatteryHigh),
      ("Stress", stressAverage), ("Schritte", steps), ("Aktive kcal", activeKilocalories),
      ("Atemfrequenz", respirationWaking ?? respirationSleep), ("SpO2", spo2Average),
      ("Schlafphasen", deepSleepSeconds), ("Fitnessalter", fitnessAge), ("VO2max", vo2Max),
      ("Training Readiness", trainingReadiness), ("Trainingsstatus", trainingStatus),
      ("Endurance Score", enduranceScore), ("Body-Battery-Verlauf", bodyBatteryCurve),
      ("Ruhekalorien", restingKilocalories), ("Höchster Puls", maxHeartRate),
      ("Regenerationszeit", recoveryHours), ("Akute Belastung", acuteLoad),
    ]
    return fields.compactMap { $0.1 == nil ? nil : $0.0 }
  }
}

/// Ein Wert des Body-Battery-Tagesverlaufs: Minuten nach Mitternacht (Ortszeit) und Stand 0–100.
public struct BodyBatterySample: Codable, Equatable, Hashable, Sendable {
  public var minute: Int
  public var value: Int

  public init(minute: Int, value: Int) {
    self.minute = minute
    self.value = value
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
      metrics.bodyBatteryCharged = nonNegative(record.first("bodyBatteryChargedValue"))
      metrics.bodyBatteryDrained = nonNegative(record.first("bodyBatteryDrainedValue"))
      metrics.respirationWaking = positive(record.first("avgWakingRespirationValue", "averageRespirationValue"))
      metrics.spo2Average = positive(record.first("averageSpo2", "averageSpO2", "avgSpo2"))
      metrics.spo2Lowest = positive(record.first("lowestSpo2", "lowestSpO2"))
      metrics.bodyBatteryAtWake = nonNegative(record.first("bodyBatteryAtWakeTime"))
      metrics.restingKilocalories = positive(record.first("bmrKilocalories"))
      metrics.minHeartRate = positive(record.first("minHeartRate", "minHeartRateInBeatsPerMinute"))
      metrics.maxHeartRate = positive(record.first("maxHeartRate", "maxHeartRateInBeatsPerMinute"))
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
      metrics.deepSleepSeconds = nonNegative(record.first("deepSleepSeconds"))
      metrics.lightSleepSeconds = nonNegative(record.first("lightSleepSeconds"))
      metrics.remSleepSeconds = nonNegative(record.first("remSleepSeconds"))
      metrics.awakeSleepSeconds = nonNegative(record.first("awakeSleepSeconds"))
      metrics.respirationSleep = positive(record.first("averageRespirationValue", "avgSleepRespirationValue"))
      metrics.spo2Average = positive(record.first("averageSpO2Value", "averageSpo2Value"))
      metrics.spo2Lowest = positive(record.first("lowestSpO2Value", "lowestSpo2Value"))
      metrics.sleepStress = nonNegative(record.first("avgSleepStress"))
      // Connect: `sleepStartTimestampLocal` (ms, Ortszeit als UTC kodiert); Personal API: Start in s + Versatz.
      if let local = record.first("sleepStartTimestampLocal")?.doubleValue {
        metrics.sleepStartMinutes = minutesOfDay(milliseconds: local)
      } else if let start = record.first("startTimeInSeconds")?.doubleValue {
        metrics.sleepStartMinutes = minutesOfDay(
          milliseconds: (start + (record.first("startTimeOffsetInSeconds")?.doubleValue ?? 0)) * 1000)
      }
      if let local = record.first("sleepEndTimestampLocal")?.doubleValue {
        metrics.sleepEndMinutes = minutesOfDay(milliseconds: local)
      } else if let start = record.first("startTimeInSeconds")?.doubleValue,
        let duration = record.first("durationInSeconds")?.doubleValue
      {
        let offset = record.first("startTimeOffsetInSeconds")?.doubleValue ?? 0
        metrics.sleepEndMinutes = minutesOfDay(milliseconds: (start + duration + offset) * 1000)
      }
    }
  }

  /// Minuten nach Mitternacht aus einem Zeitstempel, dessen Uhrzeit bereits Ortszeit ist.
  static func minutesOfDay(milliseconds: Double) -> Double? {
    guard milliseconds > 0 else { return nil }
    let seconds = (milliseconds / 1000).truncatingRemainder(dividingBy: 86_400)
    return (seconds / 60).rounded()
  }

  /// `/wellness-service/wellness/bodyBattery/reports/daily`: Liste mit einem Eintrag je Tag. Der Tag steht unter
  /// `date` (nicht `calendarDate` wie sonst), die Werte in `bodyBatteryValuesArray` als `[Zeitstempel GMT in ms,
  /// Wert]` – oder, laut `bodyBatteryValueDescriptorDTOList`, mit Status an Stelle 1 und dem Wert an Stelle 2.
  public static func bodyBattery(_ json: JSONValue, timeZone: TimeZone = .current) -> DayMap {
    var result = DayMap()
    let entries = json.objects(containingKey: "bodyBatteryValuesArray") + json.objects(containingKey: "charged")
    for record in entries {
      guard let text = (record["calendarDate"] ?? record["date"])?.stringValue,
        let day = CalendarDay(iso: String(text.prefix(10)))
      else { continue }
      var metrics = DailyMetrics(day: day)
      let samples = bodyBatterySamples(record, timeZone: timeZone)
      let values = samples.map { Double($0.value) }
      metrics.bodyBatteryHigh = values.max() ?? nonNegative(record.first("bodyBatteryHighestValue"))
      metrics.bodyBatteryLow = values.min() ?? nonNegative(record.first("bodyBatteryLowestValue"))
      metrics.bodyBatteryLatest = values.last ?? nonNegative(record.first("bodyBatteryMostRecentValue"))
      metrics.bodyBatteryCharged = nonNegative(record["charged"])
      metrics.bodyBatteryDrained = nonNegative(record["drained"])
      metrics.bodyBatteryCurve = samples.isEmpty ? nil : samples
      result[day] = result[day].map { $0.merging(metrics) } ?? metrics
    }
    return result
  }

  /// Werte als Ortszeit-Minuten, je Viertelstunde der letzte Wert. Der Versatz zur Ortszeit kommt aus
  /// `startTimestampLocal`/`startTimestampGMT` (stimmt auch auf Reisen), sonst aus `timeZone`.
  static func bodyBatterySamples(_ record: [String: JSONValue], timeZone: TimeZone) -> [BodyBatterySample] {
    var timeIndex = 0
    var valueIndex = 1
    for descriptor in record["bodyBatteryValueDescriptorDTOList"]?.arrayValue ?? [] {
      guard let index = descriptor["bodyBatteryValueDescriptorIndex"]?.doubleValue,
        let key = descriptor["bodyBatteryValueDescriptorKey"]?.stringValue
      else { continue }
      if key == "timestamp" { timeIndex = Int(index) }
      if key == "bodyBatteryLevel" { valueIndex = Int(index) }
    }
    var offset: Double?
    if let local = (record["startTimestampLocal"]?.stringValue).flatMap(gmtSeconds),
      let gmt = (record["startTimestampGMT"]?.stringValue).flatMap(gmtSeconds)
    {
      offset = local - gmt
    }
    var buckets: [Int: Int] = [:]
    for entry in record["bodyBatteryValuesArray"]?.arrayValue ?? [] {
      guard let row = entry.arrayValue, row.count > max(timeIndex, valueIndex),
        let milliseconds = row[timeIndex].doubleValue, let raw = row[valueIndex].doubleValue,
        raw >= 0, raw <= 100
      else { continue }
      let seconds = milliseconds / 1000
      let shift = offset ?? Double(timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: seconds)))
      let minute = Int(
        ((seconds + shift).truncatingRemainder(dividingBy: 86_400) + 86_400)
          .truncatingRemainder(dividingBy: 86_400) / 60)
      buckets[minute / 15] = Int(raw.rounded())
    }
    return buckets.keys.sorted().map { BodyBatterySample(minute: $0 * 15, value: buckets[$0] ?? 0) }
  }

  /// „2026-04-21T00:00:00.0“ als Sekunden (ohne Zeitzone gelesen, nur für Differenzen).
  static func gmtSeconds(_ text: String) -> Double? {
    let parts = text.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
    guard parts.count == 6 else { return nil }
    var components = DateComponents()
    components.year = parts[0]
    components.month = parts[1]
    components.day = parts[2]
    components.hour = parts[3]
    components.minute = parts[4]
    components.second = parts[5]
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar.date(from: components)?.timeIntervalSince1970
  }

  /// `/usersummary-service/stats/stress/daily/{start}/{end}`.
  public static func stress(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.stressAverage = nonNegative(
        record.first("averageStressLevel", "avgStressLevel", "overallStressLevel"))
    }
  }

  /// `/wellness-service/wellness/daily/spo2acclimation/{date}`.
  public static func spo2(_ json: JSONValue) -> DayMap {
    records(in: json) { record, metrics in
      metrics.spo2Average = positive(
        record.first("averageSpO2", "averageSpo2", "avgSpO2", "averageSPO2", "dailyAverageSpO2"))
      metrics.spo2Lowest = positive(record.first("lowestSpO2", "lowestSpo2", "minSpO2"))
    }
  }

  /// `/fitnessage-service/fitnessage/v2/{date}`. Die Antwort hat nicht immer `calendarDate`, daher mit Tag.
  public static func fitnessAge(_ json: JSONValue, day: CalendarDay) -> DayMap {
    var metrics = DailyMetrics(day: day)
    metrics.fitnessAge = positive(json.firstValue(forAnyOf: ["fitnessAge"]))
    metrics.vo2Max = positive(json.firstValue(forAnyOf: ["vo2Max", "vo2MaxValue", "vO2MaxValue"]))
    guard metrics.fitnessAge != nil || metrics.vo2Max != nil else { return [:] }
    return [day: metrics]
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
