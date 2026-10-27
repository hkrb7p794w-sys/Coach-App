import Foundation

/// Wochenbericht: was in der letzten Kalenderwoche passiert ist, im Vergleich zur Woche davor. Nur Zahlen aus
/// Garmin und der App; die Hinweise sind feste Regeln.
public struct WeeklyReport: Equatable, Sendable {
  public struct Totals: Equatable, Sendable {
    public var sessions = 0
    public var minutes = 0.0
    public var load = 0.0
    public var kilometers: [GarminActivity.Sport: Double] = [:]
    public var averageSleepHours: Double?
    public var averageHRV: Double?
    public var averageRestingHeartRate: Double?
  }

  /// Montag der berichteten Woche.
  public var monday: CalendarDay
  public var week: Totals
  public var previous: Totals
  public var fitnessChange: Double?
  public var highlights: [String]

  /// Bericht für die Woche vor der Woche, die `today` enthält.
  public static func lastWeek(
    activities: [GarminActivity], days: [DailyMetrics], gymDays: [CalendarDay], today: CalendarDay
  ) -> WeeklyReport {
    let thisMonday = today.adding(days: -Weekday(day: today).rawValue)
    let monday = thisMonday.adding(days: -7)
    let week = totals(activities: activities, days: days, gymDays: gymDays, from: monday)
    let previous = totals(activities: activities, days: days, gymDays: gymDays, from: monday.adding(days: -7))
    let form = FitnessForm.series(activities: activities, today: thisMonday.adding(days: -1))
    var fitnessChange: Double?
    if FitnessForm.isReliable(form), form.count > 7 {
      fitnessChange = ((form[form.count - 1].fitness - form[form.count - 8].fitness) * 10).rounded() / 10
    }
    return WeeklyReport(
      monday: monday, week: week, previous: previous, fitnessChange: fitnessChange,
      highlights: highlights(week: week, previous: previous, fitnessChange: fitnessChange))
  }

  static func totals(
    activities: [GarminActivity], days: [DailyMetrics], gymDays: [CalendarDay], from monday: CalendarDay
  ) -> Totals {
    let end = monday.adding(days: 6)
    let inWeek = activities.filter { activity in
      guard let day = activity.day else { return false }
      return monday <= day && day <= end
    }
    var totals = Totals()
    let activityDays = Set(inWeek.compactMap(\.day))
    // Gym-Einheiten, die nicht schon als Garmin-Aktivität zählen.
    let extraGym = gymDays.filter { monday <= $0 && $0 <= end && !activityDays.contains($0) }
    totals.sessions = inWeek.count + Set(extraGym).count
    totals.minutes = (inWeek.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60).rounded()
    totals.load = inWeek.reduce(0) { $0 + ($1.trainingLoad ?? 0) }.rounded()
    for activity in inWeek where activity.sport != .other && activity.sport != .strength {
      totals.kilometers[activity.sport, default: 0] += (activity.distanceMeters ?? 0) / 1000
    }
    for (sport, kilometers) in totals.kilometers { totals.kilometers[sport] = (kilometers * 10).rounded() / 10 }
    let metrics = days.filter { monday <= $0.day && $0.day <= end }
    func average(_ values: [Double]) -> Double? {
      values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
    }
    totals.averageSleepHours = average(metrics.compactMap { $0.sleepSeconds.map { $0 / 3_600 } })
    totals.averageHRV = average(metrics.compactMap(\.hrvLastNightAverage))
    totals.averageRestingHeartRate = average(metrics.compactMap(\.restingHeartRate))
    return totals
  }

  static func highlights(week: Totals, previous: Totals, fitnessChange: Double?) -> [String] {
    var lines: [String] = []
    if week.sessions == 0 {
      lines.append("Keine Einheit aufgezeichnet. Eine kurze lockere Einheit hilft, wieder reinzukommen.")
    } else if previous.minutes > 0 {
      let change = (week.minutes / previous.minutes - 1) * 100
      if change > 30 {
        lines.append(
          "Deutlich mehr Trainingszeit als in der Vorwoche (+\(Int(change.rounded())) %). Achte diese Woche auf "
            + "Erholung.")
      } else if change < -30 {
        lines.append("Deutlich weniger Trainingszeit als in der Vorwoche (\(Int(change.rounded())) %).")
      }
    }
    if let fitnessChange {
      if fitnessChange > 0.5 {
        lines.append("Deine Fitness ist gestiegen (+\(GermanFormat.number(fitnessChange))).")
      } else if fitnessChange < -0.5 {
        lines.append("Deine Fitness ist leicht gesunken (\(GermanFormat.number(fitnessChange))).")
      }
    }
    if let sleep = week.averageSleepHours, sleep < 7 {
      lines.append(
        "Im Schnitt \(GermanFormat.number(sleep)) Stunden Schlaf – Erwachsene brauchen regelmäßig mindestens 7.")
    }
    if let pulse = week.averageRestingHeartRate, let before = previous.averageRestingHeartRate, pulse - before >= 3 {
      lines.append(
        "Der Ruhepuls lag im Schnitt \(GermanFormat.number(pulse - before)) Schläge höher als in der Vorwoche – ein "
          + "Hinweis auf Belastung, Stress oder einen Infekt.")
    }
    return lines
  }
}
