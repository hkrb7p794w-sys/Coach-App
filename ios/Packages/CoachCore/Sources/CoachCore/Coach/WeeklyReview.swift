import Foundation

/// Wochenrückblick am Sonntag (zusammen mit „Nächste Woche planen“): Soll/Ist, Belastung gegen die Wochen davor,
/// Höhepunkte der Woche und – über `PlanSuggestion.nextWeek` – der Vorschlag für die nächste Woche.
public struct WeeklyReview: Equatable, Sendable {
  public var monday: CalendarDay
  public var progress: TodayFocus.Progress
  /// Verpasste Einheiten („Di: Lockerer Lauf“).
  public var missed: [String]
  public var load: WeekLoad.Result
  public var highlights: [String]

  /// Sonntags auf „Heute“.
  public static func isDue(_ today: CalendarDay) -> Bool { Weekday(day: today) == .sunday }

  public static func make(
    progress: TodayFocus.Progress, week: SessionMatcher.Week?, activities: [GarminActivity],
    gym: [ActivityFeed.GymItem] = [], today: CalendarDay, timeZone: TimeZone = .current
  ) -> WeeklyReview {
    let monday = PlanAdjustments.monday(of: today)
    let missed = (week?.results ?? []).filter { $0.status == .missed }.map {
      "\(Weekday(day: $0.planned.day).short): \($0.planned.slot.title)"
    }
    let load = WeekLoad.check(activities: activities, gym: gym, today: today, timeZone: timeZone)
    let inWeek = activities.filter { ($0.day.map { $0 >= monday && $0 <= today }) ?? false }
    return WeeklyReview(
      monday: monday, progress: progress, missed: missed, load: load,
      highlights: highlights(activities: inWeek, gym: gym, progress: progress, monday: monday, today: today,
        timeZone: timeZone))
  }

  static func highlights(
    activities: [GarminActivity], gym: [ActivityFeed.GymItem], progress: TodayFocus.Progress, monday: CalendarDay,
    today: CalendarDay, timeZone: TimeZone
  ) -> [String] {
    var lines: [String] = []
    if progress.sessionsPlanned > 0, progress.sessionsDone >= progress.sessionsPlanned {
      lines.append("Alle \(progress.sessionsPlanned) geplanten Einheiten geschafft.")
    }
    for (sport, label) in [(GarminActivity.Sport.run, "Längster Lauf"), (.bike, "Längste Radfahrt")] {
      let longest = activities.filter { $0.sport == sport }.compactMap(\.distanceMeters).max() ?? 0
      if longest >= 1_000 { lines.append("\(label): \(GermanFormat.decimal(longest / 1_000)) km") }
    }
    if let swim = activities.filter({ $0.sport == .swim }).compactMap(\.distanceMeters).max(), swim > 0 {
      lines.append("Weitestes Schwimmen: \(GermanFormat.number(swim)) m")
    }
    let hard = activities.filter { SessionKind.isHard($0) && $0.sport != .strength }.count
    let endurance = activities.filter { $0.sport == .run || $0.sport == .bike || $0.sport == .swim }.count
    if endurance >= 3 {
      lines.append("\(endurance - hard) von \(endurance) Ausdauereinheiten locker.")
    }
    let gymWeek = gym.filter {
      let day = CalendarDay(date: $0.start, timeZone: timeZone)
      return day >= monday && day <= today
    }
    if !gymWeek.isEmpty {
      let volume = gymWeek.reduce(0) { $0 + $1.volumeKg }
      lines.append(
        "\(gymWeek.count) Krafteinheiten"
          + (volume > 0 ? ", \(GermanFormat.number((volume / 10).rounded() * 10)) kg bewegt" : ""))
    }
    return lines
  }
}

/// Trends auf einen Blick: Minuten je Sportart und Woche, aerobe Effizienz lockerer Läufe.
public enum TrainingTrends {
  public struct SportMinutes: Equatable, Sendable, Identifiable {
    public var monday: CalendarDay
    public var sport: TrainingSport
    public var minutes: Int
    public var id: String { "\(monday.iso)-\(sport.rawValue)" }
  }

  /// Minuten je Sportart für die letzten `weeks` Wochen bis einschließlich dieser (älteste zuerst). App-Krafteinheiten
  /// zählen, Doppelte mit Garmin nur einmal.
  public static func weeklyMinutes(
    activities: [GarminActivity], gym: [ActivityFeed.GymItem] = [], today: CalendarDay, weeks: Int,
    timeZone: TimeZone = .current
  ) -> [SportMinutes] {
    let thisMonday = PlanAdjustments.monday(of: today)
    let first = thisMonday.adding(days: -7 * (weeks - 1))
    var minutes: [CalendarDay: [TrainingSport: Double]] = [:]
    let entries = ActivityFeed.entries(
      activities: activities.filter { ($0.day.map { $0 >= first }) ?? false },
      gym: gym.filter { CalendarDay(date: $0.start, timeZone: timeZone) >= first }, timeZone: timeZone)
    for entry in entries where entry.day <= today {
      let value =
        entry.activity?.durationSeconds.map { $0 / 60 } ?? Double(entry.gym?.minutes ?? WeekLoad.defaultGymMinutes)
      minutes[PlanAdjustments.monday(of: entry.day), default: [:]][SessionMatcher.sport(entry.sport), default: 0] +=
        value
    }
    return (0..<weeks).flatMap { index -> [SportMinutes] in
      let monday = first.adding(days: 7 * index)
      return TrainingSport.allCases.compactMap { sport in
        let value = Int((minutes[monday]?[sport] ?? 0).rounded())
        return value > 0 ? SportMinutes(monday: monday, sport: sport, minutes: value) : nil
      }
    }
  }

  /// Ab dieser Dauer zählt ein lockerer Lauf für die Effizienz.
  public static let minimumEfficiencySeconds = 20.0 * 60

  /// Aerobe Effizienz lockerer Läufe: Meter je Herzschlag (Tempo in m/min geteilt durch die mittlere Herzfrequenz).
  /// Steigt sie bei gleicher Lockerheit, wird die Grundlage besser. Hitze, Hügel und Müdigkeit verschieben sie.
  public static func aerobicEfficiency(activities: [GarminActivity]) -> [DayValue] {
    activities.compactMap { activity in
      guard activity.sport == .run, SessionKind.of(activity) == .easy, let day = activity.day,
        let meters = activity.distanceMeters, meters > 0, let heartRate = activity.averageHeartRate, heartRate > 0,
        let seconds = activity.movingSeconds ?? activity.durationSeconds, seconds >= minimumEfficiencySeconds
      else { return nil }
      return DayValue(day: day, value: ((meters / (seconds / 60)) / heartRate * 100).rounded() / 100)
    }
    .sorted { $0.day < $1.day }
  }
}
