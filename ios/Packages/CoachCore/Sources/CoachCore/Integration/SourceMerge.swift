import Foundation

/// Führt Tageswerte mehrerer Anbieter zusammen: je Datenart genau eine Quelle (die erste mit Werten in der
/// Reihenfolge der Einstellungen), immer als ganze Gruppe. So mischt die App nie Schlafdauer von WHOOP mit
/// Schlafphasen von Garmin, zählt Kalorien nicht doppelt und zeigt keine widersprüchlichen Werte nebeneinander.
public enum MetricsMerge {
  public struct Result: Equatable, Sendable {
    public var metrics: DailyMetrics
    /// Welche Quelle je Datenart gewonnen hat.
    public var sources: [DataKind: DataProvider]
  }

  /// Datenarten, die Tageswerte tragen (Aktivitäten werden getrennt zusammengeführt).
  public static let dailyKinds: [DataKind] = [
    .sleep, .hrv, .restingHeartRate, .stress, .calories, .steps, .trainingLoad, .recovery, .body,
  ]

  public static func merge(
    _ perProvider: [DataProvider: DailyMetrics], day: CalendarDay, preferences: SourcePreferences
  ) -> Result {
    var metrics = DailyMetrics(day: day)
    var sources: [DataKind: DataProvider] = [:]
    let connected = Set(perProvider.keys)
    for kind in dailyKinds {
      for provider in preferences.order(for: kind, connected: connected) {
        guard let values = perProvider[provider], hasValues(kind, values) else { continue }
        copy(kind, from: values, into: &metrics)
        sources[kind] = provider
        break
      }
    }
    return Result(metrics: metrics, sources: sources)
  }

  public static func hasValues(_ kind: DataKind, _ m: DailyMetrics) -> Bool {
    switch kind {
    case .sleep: m.sleepSeconds != nil || m.sleepScore != nil || m.deepSleepSeconds != nil
    case .hrv: m.hrvLastNightAverage != nil || m.hrvWeeklyAverage != nil || m.hrvStatus != nil
    case .restingHeartRate: m.restingHeartRate != nil
    case .stress: m.stressAverage != nil
    case .calories: m.activeKilocalories != nil || m.totalKilocalories != nil || m.restingKilocalories != nil
    case .steps: m.steps != nil
    case .trainingLoad: m.acuteLoad != nil || m.trainingStatus != nil
    case .recovery:
      m.bodyBatteryHigh != nil || m.bodyBatteryLatest != nil || m.bodyBatteryCurve != nil
        || m.trainingReadiness != nil || m.recoveryHours != nil
    case .body:
      m.vo2Max != nil || m.fitnessAge != nil || m.enduranceScore != nil || m.spo2Average != nil
        || m.respirationWaking != nil
    case .activities, .workoutHeartRate: false
    }
  }

  /// Kopiert die ganze Gruppe einer Datenart.
  public static func copy(_ kind: DataKind, from m: DailyMetrics, into t: inout DailyMetrics) {
    switch kind {
    case .sleep:
      t.sleepSeconds = m.sleepSeconds
      t.sleepScore = m.sleepScore
      t.deepSleepSeconds = m.deepSleepSeconds
      t.lightSleepSeconds = m.lightSleepSeconds
      t.remSleepSeconds = m.remSleepSeconds
      t.awakeSleepSeconds = m.awakeSleepSeconds
      t.sleepStartMinutes = m.sleepStartMinutes
      t.sleepEndMinutes = m.sleepEndMinutes
      t.sleepStress = m.sleepStress
      t.respirationSleep = m.respirationSleep
    case .hrv:
      t.hrvLastNightAverage = m.hrvLastNightAverage
      t.hrvWeeklyAverage = m.hrvWeeklyAverage
      t.hrvStatus = m.hrvStatus
      t.hrvBaselineLow = m.hrvBaselineLow
      t.hrvBaselineHigh = m.hrvBaselineHigh
    case .restingHeartRate:
      t.restingHeartRate = m.restingHeartRate
      t.minHeartRate = m.minHeartRate
      t.maxHeartRate = m.maxHeartRate
    case .stress:
      t.stressAverage = m.stressAverage
    case .calories:
      t.activeKilocalories = m.activeKilocalories
      t.totalKilocalories = m.totalKilocalories
      t.restingKilocalories = m.restingKilocalories
    case .steps:
      t.steps = m.steps
    case .trainingLoad:
      t.acuteLoad = m.acuteLoad
      t.chronicLoad = m.chronicLoad
      t.trainingStatus = m.trainingStatus
    case .recovery:
      t.bodyBatteryHigh = m.bodyBatteryHigh
      t.bodyBatteryLow = m.bodyBatteryLow
      t.bodyBatteryLatest = m.bodyBatteryLatest
      t.bodyBatteryCharged = m.bodyBatteryCharged
      t.bodyBatteryDrained = m.bodyBatteryDrained
      t.bodyBatteryAtWake = m.bodyBatteryAtWake
      t.bodyBatteryCurve = m.bodyBatteryCurve
      t.trainingReadiness = m.trainingReadiness
      t.trainingReadinessLevel = m.trainingReadinessLevel
      t.recoveryHours = m.recoveryHours
    case .body:
      t.vo2Max = m.vo2Max
      t.fitnessAge = m.fitnessAge
      t.enduranceScore = m.enduranceScore
      t.spo2Average = m.spo2Average
      t.spo2Lowest = m.spo2Lowest
      t.respirationWaking = m.respirationWaking
    case .activities, .workoutHeartRate:
      break
    }
  }
}

/// Aktivitäten mehrerer Anbieter ohne Doppelte: Dieselbe Einheit (gleiche Sportart, Start höchstens 10 Minuten
/// auseinander oder mehr als die Hälfte überlappend) bleibt nur von der bevorzugten Quelle – samt Kalorien,
/// Herzfrequenz und Trainingsbelastung. Doppelte werden nicht gelöscht, sondern als ersetzt markiert, damit ein
/// späterer Abruf sie nicht wieder anlegt.
public enum ActivityMerge {
  public struct Plan: Equatable, Sendable {
    /// Behaltene Aktivitäten.
    public var kept: [GarminActivity]
    /// Ersetzte Aktivität → die behaltene.
    public var superseded: [Int64: Int64]
  }

  /// Anbieter einer Aktivität. Ältere Einträge haben kein Feld: negative IDs kamen aus Apple Health.
  public static func provider(of activity: GarminActivity) -> DataProvider {
    activity.provider ?? (activity.id < 0 ? .appleHealth : .garmin)
  }

  public static func plan(
    _ activities: [GarminActivity], preferences: SourcePreferences, connected: Set<DataProvider>,
    timeZone: TimeZone = .current
  ) -> Plan {
    let order = preferences.order(for: .activities, connected: connected.union(activities.map(provider)))
    func rank(_ activity: GarminActivity) -> Int { order.firstIndex(of: provider(of: activity)) ?? order.count }
    // Bevorzugte Quelle zuerst, bei gleicher Quelle die längere (vollständigere) Aufzeichnung.
    let sorted = activities.sorted {
      (rank($0), -($0.durationSeconds ?? 0), $0.id) < (rank($1), -($1.durationSeconds ?? 0), $1.id)
    }
    var kept: [(GarminActivity, Date?, Date?)] = []
    var superseded: [Int64: Int64] = [:]
    for activity in sorted {
      let start = activity.startLocal.flatMap { HealthImport.date(localTimestamp: $0, timeZone: timeZone) }
      let end = start?.addingTimeInterval(activity.durationSeconds ?? 0)
      if let match = kept.first(where: { other in
        provider(of: other.0) != provider(of: activity) && sameSession(other, (activity, start, end))
      }) {
        superseded[activity.id] = match.0.id
      } else {
        kept.append((activity, start, end))
      }
    }
    return Plan(kept: kept.map(\.0), superseded: superseded)
  }

  static func sameSession(
    _ a: (GarminActivity, Date?, Date?), _ b: (GarminActivity, Date?, Date?)
  ) -> Bool {
    guard let aStart = a.1, let aEnd = a.2, let bStart = b.1, let bEnd = b.2 else { return false }
    let sportA = a.0.sport
    let sportB = b.0.sport
    guard sportA == sportB || sportA == .other || sportB == .other else { return false }
    if abs(aStart.timeIntervalSince(bStart)) <= 600 { return true }
    let overlap = min(aEnd, bEnd).timeIntervalSince(max(aStart, bStart))
    let shorter = min(aEnd.timeIntervalSince(aStart), bEnd.timeIntervalSince(bStart))
    return shorter > 0 && overlap > shorter / 2
  }

  /// Stabile, negative ID für Aktivitäten ohne Garmin-ID (Garmin-IDs sind positiv). Je Anbieter ein eigener
  /// Bereich, damit gleiche externe IDs verschiedener Anbieter nicht kollidieren.
  public static func localID(provider: DataProvider, externalID: String) -> Int64 {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in "\(provider.rawValue):\(externalID)".utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return -Int64(hash % 4_000_000_000_000_000_000) - 1
  }
}
