import Foundation

/// Apple Health (Apple Watch, iPhone, andere Apps) als zweite Datenquelle neben Garmin. Die App liest die
/// Rohwerte aus HealthKit und reicht sie hier in einfachen Strukturen herein; die Zuordnung zu Tageswerten,
/// Nächten und Aktivitäten ist ohne Apple-Frameworks formuliert und getestet.
///
/// Grundsätze:
/// - Garmin hat Vorrang. Health füllt nur Lücken (`fill`), damit sich die Werte einer Uhr nicht mit denen
///   einer anderen mischen.
/// - Die Herzfrequenzvariabilität misst Apple als SDNN, Garmin als RMSSD in der Nacht. Die Werte sind nicht
///   vergleichbar; Health-HRV wird deshalb nur übernommen, wenn Garmin nicht verbunden ist.
/// - Workouts, die Garmin schon kennt (gleiche Zeit, gleiche Sportart) oder die die App selbst geschrieben hat,
///   werden nicht doppelt übernommen.
public enum HealthImport {
  // MARK: - Tageswerte

  /// Tageswerte, wie die App sie aus HealthKit-Statistiken je Kalendertag berechnet.
  public struct DayValues: Equatable, Sendable {
    public var day: CalendarDay
    public var restingHeartRate: Double?
    /// SDNN in ms (Apple), nicht RMSSD (Garmin).
    public var hrvSDNN: Double?
    public var steps: Double?
    public var activeKilocalories: Double?
    public var basalKilocalories: Double?
    /// Atemzüge pro Minute
    public var respiratoryRate: Double?
    /// Sauerstoffsättigung als Anteil (0,97) oder Prozent (97).
    public var oxygenSaturation: Double?
    public var oxygenSaturationLowest: Double?
    public var vo2Max: Double?

    public init(day: CalendarDay) {
      self.day = day
    }
  }

  public static func metrics(_ values: DayValues, includeHRV: Bool) -> DailyMetrics {
    var metrics = DailyMetrics(day: values.day)
    metrics.restingHeartRate = within(values.restingHeartRate, 25...120)
    if includeHRV { metrics.hrvLastNightAverage = within(values.hrvSDNN, 5...300) }
    metrics.steps = within(values.steps, 0...150_000)
    metrics.activeKilocalories = within(values.activeKilocalories, 0...10_000)
    if let active = metrics.activeKilocalories, let basal = within(values.basalKilocalories, 500...5_000) {
      metrics.totalKilocalories = active + basal
    }
    metrics.respirationWaking = within(values.respiratoryRate, 4...40)
    metrics.spo2Average = within(percent(values.oxygenSaturation), 70...100)
    metrics.spo2Lowest = within(percent(values.oxygenSaturationLowest), 50...100)
    metrics.vo2Max = within(values.vo2Max, 15...95)
    return metrics
  }

  /// Ergänzt fehlende Werte von `base` (Garmin) aus `health`; vorhandene Werte bleiben unverändert.
  public static func fill(_ base: DailyMetrics?, with health: DailyMetrics) -> DailyMetrics {
    guard let base else { return health }
    return health.merging(base)
  }

  static func percent(_ value: Double?) -> Double? {
    guard let value else { return nil }
    return value <= 1 ? value * 100 : value
  }

  static func within(_ value: Double?, _ range: ClosedRange<Double>) -> Double? {
    guard let value, value.isFinite, range.contains(value) else { return nil }
    return (value * 10).rounded() / 10
  }

  // MARK: - Schlaf

  public enum SleepStage: String, Codable, Sendable {
    case inBed, asleep, awake, core, deep, rem

    var isAsleep: Bool { [.asleep, .core, .deep, .rem].contains(self) }
  }

  public struct SleepSample: Equatable, Sendable {
    public var start: Date
    public var end: Date
    public var stage: SleepStage
    /// Quelle (Bundle-ID), damit Uhr und iPhone nicht doppelt zählen.
    public var source: String

    public init(start: Date, end: Date, stage: SleepStage, source: String) {
      self.start = start
      self.end = end
      self.stage = stage
      self.source = source
    }
  }

  /// Nächte je Aufwachtag. Schlaf, der zwischen 10 und 18 Uhr beginnt, gilt als Nickerchen und zählt nicht.
  /// Je Nacht zählt eine Quelle: die mit Schlafphasen (Apple Watch), sonst die mit dem meisten Schlaf.
  public static func sleep(_ samples: [SleepSample], timeZone: TimeZone = .current) -> [CalendarDay: DailyMetrics] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var byNight: [CalendarDay: [SleepSample]] = [:]
    for sample in samples where sample.end > sample.start {
      let hour = calendar.component(.hour, from: sample.start)
      if (10..<18).contains(hour) { continue }
      // Aufwachtag: Ende plus sechs Stunden, damit Schlaf nach Mitternacht und bis in den Vormittag passt.
      let night = CalendarDay(date: sample.end.addingTimeInterval(6 * 3_600), timeZone: timeZone)
      byNight[night, default: []].append(sample)
    }
    var result: [CalendarDay: DailyMetrics] = [:]
    for (day, samples) in byNight {
      let bySource = Dictionary(grouping: samples, by: \.source)
      let chosen = bySource.values.max { lhs, rhs in
        let lhsStages = lhs.contains { [.core, .deep, .rem].contains($0.stage) }
        let rhsStages = rhs.contains { [.core, .deep, .rem].contains($0.stage) }
        if lhsStages != rhsStages { return !lhsStages }
        return asleepSeconds(lhs) < asleepSeconds(rhs)
      }
      guard let chosen else { continue }
      let asleep = chosen.filter(\.stage.isAsleep)
      let total = asleepSeconds(chosen)
      guard total >= 1_800, let first = asleep.map(\.start).min(), let last = asleep.map(\.end).max() else {
        continue
      }
      var metrics = DailyMetrics(day: day)
      metrics.sleepSeconds = total
      let stageSeconds = { (stage: SleepStage) -> Double? in
        let sum = chosen.filter { $0.stage == stage }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return sum > 0 ? sum : nil
      }
      metrics.deepSleepSeconds = stageSeconds(.deep)
      metrics.remSleepSeconds = stageSeconds(.rem)
      metrics.lightSleepSeconds = stageSeconds(.core)
      metrics.awakeSleepSeconds = stageSeconds(.awake)
      metrics.sleepStartMinutes = minutes(first, calendar)
      metrics.sleepEndMinutes = minutes(last, calendar)
      result[day] = metrics
    }
    return result
  }

  /// Geschlafene Sekunden ohne Überlappungen (mehrere Einträge derselben Quelle können sich überschneiden).
  static func asleepSeconds(_ samples: [SleepSample]) -> Double {
    let intervals = samples.filter(\.stage.isAsleep).map { ($0.start, $0.end) }.sorted { $0.0 < $1.0 }
    var total = 0.0
    var current: (Date, Date)?
    for interval in intervals {
      if let open = current, interval.0 <= open.1 {
        current = (open.0, max(open.1, interval.1))
      } else {
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        current = interval
      }
    }
    if let open = current { total += open.1.timeIntervalSince(open.0) }
    return total
  }

  static func minutes(_ date: Date, _ calendar: Calendar) -> Double {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
  }

  // MARK: - Workouts

  public struct Workout: Equatable, Sendable {
    public var uuid: UUID
    /// Schlüssel im Stil von Garmin (`running`, `cycling`, `lap_swimming`, `strength_training`, …).
    public var typeKey: String
    public var start: Date
    public var end: Date
    public var distanceMeters: Double?
    public var kilocalories: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var elevationGain: Double?
    public var sourceName: String
    public var sourceBundle: String

    public init(
      uuid: UUID, typeKey: String, start: Date, end: Date, distanceMeters: Double? = nil,
      kilocalories: Double? = nil, averageHeartRate: Double? = nil, maxHeartRate: Double? = nil,
      elevationGain: Double? = nil, sourceName: String, sourceBundle: String
    ) {
      self.uuid = uuid
      self.typeKey = typeKey
      self.start = start
      self.end = end
      self.distanceMeters = distanceMeters
      self.kilocalories = kilocalories
      self.averageHeartRate = averageHeartRate
      self.maxHeartRate = maxHeartRate
      self.elevationGain = elevationGain
      self.sourceName = sourceName
      self.sourceBundle = sourceBundle
    }
  }

  /// Stabile, negative ID aus der Workout-UUID; Garmin-IDs sind positiv, so gibt es keine Kollision.
  public static func activityID(_ uuid: UUID) -> Int64 {
    let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0.prefix(8)) }
    let value = bytes.reduce(UInt64(0)) { $0 << 8 | UInt64($1) } & 0x3FFF_FFFF_FFFF_FFFF
    return -Int64(value) - 1
  }

  public static func activity(_ workout: Workout, timeZone: TimeZone = .current) -> GarminActivity {
    var activity = GarminActivity(id: activityID(workout.uuid))
    activity.typeKey = workout.typeKey
    activity.name = "\(label(workout.typeKey)) · \(workout.sourceName)"
    activity.startLocal = localTimestamp(workout.start, timeZone: timeZone)
    let duration = workout.end.timeIntervalSince(workout.start)
    activity.durationSeconds = duration > 0 ? duration : nil
    activity.elapsedSeconds = activity.durationSeconds
    activity.distanceMeters = within(workout.distanceMeters, 1...500_000)
    activity.calories = within(workout.kilocalories, 1...10_000)
    activity.activeKilocalories = activity.calories
    activity.averageHeartRate = within(workout.averageHeartRate, 30...230)
    activity.maxHeartRate = within(workout.maxHeartRate, 30...240)
    activity.elevationGain = within(workout.elevationGain, 0...10_000)
    if let distance = activity.distanceMeters, duration > 0 { activity.averageSpeed = distance / duration }
    return activity
  }

  /// Workouts, die übernommen werden: nicht von der App selbst geschrieben und nicht schon als
  /// Garmin-Aktivität vorhanden (Start höchstens 10 Minuten auseinander oder mehr als die Hälfte überlappend).
  public static func newActivities(
    _ workouts: [Workout], existing: [GarminActivity], ownBundle: String, timeZone: TimeZone = .current
  ) -> [GarminActivity] {
    let others = existing.filter { $0.id >= 0 }.compactMap { activity -> (GarminActivity.Sport, Date, Date)? in
      guard let start = activity.startLocal.flatMap({ date(localTimestamp: $0, timeZone: timeZone) }) else {
        return nil
      }
      return (activity.sport, start, start.addingTimeInterval(activity.durationSeconds ?? 0))
    }
    return workouts.filter { workout in
      guard workout.sourceBundle != ownBundle, !workout.sourceBundle.hasPrefix(ownBundle + ".") else {
        return false
      }
      let sport = GarminActivity.Sport(typeKey: workout.typeKey)
      return !others.contains { other in
        guard other.0 == sport || other.0 == .other || sport == .other else { return false }
        if abs(other.1.timeIntervalSince(workout.start)) <= 600 { return true }
        let overlap = min(other.2, workout.end).timeIntervalSince(max(other.1, workout.start))
        let shorter = min(other.2.timeIntervalSince(other.1), workout.end.timeIntervalSince(workout.start))
        return shorter > 0 && overlap > shorter / 2
      }
    }
    .map { activity($0, timeZone: timeZone) }
  }

  public static func label(_ typeKey: String) -> String {
    switch typeKey {
    case "running": "Laufen"
    case "cycling": "Radfahren"
    case "lap_swimming": "Schwimmen (Becken)"
    case "open_water_swimming": "Freiwasserschwimmen"
    case "strength_training": "Krafttraining"
    case "walking": "Gehen"
    case "hiking": "Wandern"
    case "hiit": "HIIT"
    case "yoga": "Yoga"
    case "indoor_rowing": "Rudern"
    case "elliptical": "Crosstrainer"
    default: "Training"
    }
  }

  static func localTimestamp(_ date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return String(
      format: "%04d-%02d-%02d %02d:%02d:%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0,
      c.second ?? 0)
  }

  static func date(localTimestamp text: String, timeZone: TimeZone) -> Date? {
    let parts = text.replacingOccurrences(of: "T", with: " ").split(separator: " ")
    guard parts.count >= 2, let day = CalendarDay(iso: String(parts[0])) else { return nil }
    let time = parts[1].split(separator: ":").compactMap { Int(Double($0) ?? -1) }
    guard time.count >= 2 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(
      from: DateComponents(
        year: day.year, month: day.month, day: day.day, hour: time[0], minute: time[1],
        second: time.count > 2 ? time[2] : 0))
  }

  // MARK: - Gewicht

  /// Letzte Wägung je Tag.
  public static func weights(_ samples: [(date: Date, kilograms: Double)], timeZone: TimeZone = .current)
    -> [WeightEntry]
  {
    var byDay: [CalendarDay: (Date, Double)] = [:]
    for sample in samples where (25...300).contains(sample.kilograms) {
      let day = CalendarDay(date: sample.date, timeZone: timeZone)
      if let existing = byDay[day], existing.0 > sample.date { continue }
      byDay[day] = (sample.date, sample.kilograms)
    }
    return byDay.map { WeightEntry(day: $0.key, kilograms: ($0.value.1 * 10).rounded() / 10, source: .health) }
      .sorted { $0.day < $1.day }
  }
}
