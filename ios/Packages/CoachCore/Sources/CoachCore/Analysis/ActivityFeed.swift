import Foundation

/// Woher eine Aktivität stammt; mehrere Quellen = zusammengeführte Doppelung.
public enum ActivitySource: String, Codable, Sendable, CaseIterable {
  case garmin, health, manual, app

  public var label: String {
    switch self {
    case .garmin: "Garmin"
    case .health: "Apple Health"
    case .manual: "nachgetragen"
    case .app: "Gym-App"
    }
  }

  /// Garmin-IDs sind positiv, Apple Health negativ, nachgetragene liegen darunter (`ManualActivity`).
  public static func of(_ id: Int64) -> ActivitySource {
    if id >= 0 { return .garmin }
    return ManualActivity.isManual(id) ? .manual : .health
  }
}

extension SessionKind {
  public var label: String {
    switch self {
    case .easy: "locker"
    case .test: "Test"
    case .vo2: "Intervalle"
    case .threshold: "Schwelle"
    case .hard: "intensiv"
    case .gym: "Kraft"
    }
  }
}

/// Ein gemeinsamer Verlauf für Garmin, Apple Health, Nachgetragenes und die Gym-Einheiten der App:
/// eine Zeile je Training, mit Kernwerten, Intensität und Bezug zum Plan.
public enum ActivityFeed {
  /// Gym-Einheit aus der App, ohne SwiftData.
  public struct GymItem: Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var start: Date
    public var minutes: Int?
    public var sets: Int
    public var volumeKg: Double

    public init(id: UUID, title: String, start: Date, minutes: Int?, sets: Int, volumeKg: Double) {
      self.id = id
      self.title = title
      self.start = start
      self.minutes = minutes
      self.sets = sets
      self.volumeKg = volumeKg
    }

    public init(_ session: GymSession) {
      self.init(
        id: session.id, title: session.title, start: session.start,
        minutes: session.end.map { Int(($0.timeIntervalSince(session.start) / 60).rounded()) },
        sets: session.doneSetCount, volumeKg: session.volumeKg)
    }
  }

  public struct Entry: Equatable, Sendable, Identifiable {
    public var id: String
    public var day: CalendarDay
    /// `yyyy-MM-dd HH:mm:ss` zum Sortieren.
    public var sortKey: String
    public var title: String
    public var sport: GarminActivity.Sport
    public var sources: [ActivitySource]
    public var activity: GarminActivity?
    public var gym: GymItem?
    public var values: [String]
    public var intensity: SessionKind?
    public var planned: SessionResult?
  }

  /// Garmin-Kraft und App-Einheit gelten als dieselbe Einheit, wenn sie am selben Tag höchstens so weit auseinander
  /// beginnen (Upload der App nach Garmin oder parallel auf der Uhr aufgezeichnet).
  public static let mergeWindow: TimeInterval = 2 * 3600

  public static func entries(
    activities: [GarminActivity], gym: [GymItem], results: [SessionResult] = [], timeZone: TimeZone = .current
  ) -> [Entry] {
    var gymLeft = gym
    let byActivity = Dictionary(
      results.compactMap { r in r.activityID.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
    var entries: [Entry] = activities.compactMap { activity in
      guard let day = activity.day else { return nil }
      var sources = [ActivitySource.of(activity.id)]
      var item: GymItem?
      if activity.sport == .strength, let start = start(activity, timeZone: timeZone),
        let index = gymLeft.firstIndex(where: {
          CalendarDay(date: $0.start, timeZone: timeZone) == day
            && abs($0.start.timeIntervalSince(start)) <= mergeWindow
        })
      {
        item = gymLeft.remove(at: index)
        sources.insert(.app, at: 0)
      }
      return Entry(
        id: "a\(activity.id)", day: day, sortKey: activity.startLocal ?? day.iso,
        title: item?.title ?? activity.name ?? activity.typeKey ?? "Aktivität", sport: activity.sport,
        sources: sources, activity: activity, gym: item, values: values(activity, gym: item),
        intensity: SessionKind.of(activity), planned: byActivity[activity.id])
    }
    let formatter = localFormatter(timeZone)
    let gymDayResults = results.filter { $0.activityID == nil && $0.planned.slot.sport == .strength }
    for item in gymLeft {
      let day = CalendarDay(date: item.start, timeZone: timeZone)
      entries.append(
        Entry(
          id: "g\(item.id.uuidString)", day: day, sortKey: formatter.string(from: item.start), title: item.title,
          sport: .strength, sources: [.app], activity: nil, gym: item, values: values(gym: item), intensity: .gym,
          planned: gymDayResults.first { $0.planned.day == day && $0.status.counts }))
    }
    return entries.sorted { $0.sortKey > $1.sortKey }
  }

  /// Bis zu vier Kernwerte für die Zeile: Dauer, Strecke, Tempo, Herzfrequenz oder Belastung.
  public static func values(_ activity: GarminActivity, gym: GymItem? = nil) -> [String] {
    var result: [String] = []
    if let seconds = activity.durationSeconds { result.append(ActivityDetails.duration(seconds)) }
    if let meters = activity.distanceMeters, meters > 0 {
      result.append(ActivityDetails.distance(meters, sport: activity.sport))
    }
    if let gym { result += Array(values(gym: gym).dropFirst(gym.minutes == nil ? 0 : 1)) }
    if let pace = pace(activity) { result.append(pace) }
    if let heartRate = activity.averageHeartRate { result.append("Ø \(Int(heartRate.rounded())) bpm") }
    if let load = activity.trainingLoad, result.count < 4 { result.append("Belastung \(Int(load.rounded()))") }
    return Array(result.prefix(4))
  }

  static func values(gym: GymItem) -> [String] {
    var result: [String] = []
    if let minutes = gym.minutes { result.append("\(minutes) min") }
    result.append("\(gym.sets) Sätze")
    if gym.volumeKg > 0 { result.append("\(GermanFormat.number((gym.volumeKg / 10).rounded() * 10)) kg") }
    return result
  }

  /// Laufen min/km, Schwimmen min/100 m, Rad km/h.
  public static func pace(_ activity: GarminActivity) -> String? {
    guard let meters = activity.distanceMeters, meters > 0,
      let seconds = activity.movingSeconds ?? activity.durationSeconds, seconds > 0
    else { return nil }
    switch activity.sport {
    case .run:
      return "\(PlanTokens.mmss(Int((seconds / (meters / 1000)).rounded()))) /km"
    case .swim:
      return "\(PlanTokens.mmss(Int((seconds / (meters / 100)).rounded()))) /100 m"
    case .bike:
      return "\(GermanFormat.decimal(meters / seconds * 3.6)) km/h"
    default:
      return nil
    }
  }

  /// Anteile der fünf Herzfrequenzzonen (Summe 1), wenn die Uhr sie liefert.
  public static func zoneShares(_ activity: GarminActivity) -> [Double]? {
    guard let zones = activity.secondsInZones, zones.count == 5 else { return nil }
    let total = zones.reduce(0, +)
    return total > 0 ? zones.map { $0 / total } : nil
  }

  /// Was fehlt und was das für die Auswertung heißt – statt leerer Felder.
  public static func missing(_ activity: GarminActivity) -> [String] {
    var notes: [String] = []
    let source = ActivitySource.of(activity.id)
    if source == .manual {
      notes.append("Nachgetragen: Belastung aus Dauer × Anstrengung, keine Herzfrequenz oder Strecke.")
      return notes
    }
    if activity.averageHeartRate == nil {
      notes.append("Keine Herzfrequenz – Intensität nur aus dem Namen der Einheit geschätzt.")
    } else if activity.secondsInZones == nil, activity.sport != .strength {
      notes.append("Keine Zeit in Zonen – die Intensitätsverteilung zählt diese Einheit nicht mit.")
    }
    if activity.trainingLoad == nil, activity.sport != .strength {
      notes.append(
        source == .health
          ? "Apple Health liefert keine Trainingsbelastung – Fitness & Form schätzen sie nicht."
          : "Keine Trainingsbelastung von der Uhr – zählt nicht für Fitness & Form.")
    }
    if activity.sport == .swim, activity.averageHeartRate != nil {
      notes.append("Herzfrequenz am Handgelenk ist im Wasser ungenau – Schwimmen gilt nie automatisch als hart.")
    }
    if (activity.sport == .run || activity.sport == .bike), (activity.distanceMeters ?? 0) == 0 {
      notes.append("Keine Strecke (Laufband, Rolle ohne Sensor?) – kein Tempo und keine Kilometer.")
    }
    return notes
  }

  static func start(_ activity: GarminActivity, timeZone: TimeZone) -> Date? {
    activity.startLocal.flatMap { localFormatter(timeZone).date(from: String($0.prefix(19))) }
  }

  static func localFormatter(_ timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
  }
}
