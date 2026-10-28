import Foundation

/// Fitness, Ermüdung und Form aus der Trainingsbelastung der Uhr (Garmin „Training Load“ je Aktivität), nach dem
/// Impulse-Response-Modell von Banister (Übersicht: Clarke & Skiba 2013): Fitness ist der gleitende Mittelwert
/// über 42 Tage, Ermüdung über 7 Tage, Form die Differenz. Die Kurven beschreiben den Verlauf; als Vorhersage von
/// Verletzungen taugen solche Verhältnisse nicht (Impellizzeri et al. 2020), daher warnt die App damit nicht; nur bei
/// sehr negativer Form rät die Tagesampel zu lockerem Training (`Recommendation.limited(byForm:)`).
public enum FitnessForm {
  public static let fitnessDays = 42.0
  public static let fatigueDays = 7.0
  /// Erst nach so vielen Tagen mit Daten ist die Fitness-Kurve eingeschwungen.
  public static let warmUpDays = 42

  public struct Point: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var load: Double
    public var fitness: Double
    public var fatigue: Double
    /// Fitness minus Ermüdung am Morgen des Tages (vor der Belastung des Tages).
    public var form: Double

    public var id: String { day.iso }

    /// Form in % der Fitness; unabhängig davon, wie groß die Belastungswerte der Uhr sind.
    public var formPercent: Double? {
      fitness > 1 ? form / fitness * 100 : nil
    }
  }

  /// Einordnung der Form in % der Fitness. Die Grenzen sind Praxiswerte aus Trainingssoftware (intervals.icu),
  /// keine Studienergebnisse.
  public enum Zone: String, Sendable {
    case fresh, neutral, productive, high

    public var label: String {
      switch self {
      case .fresh: "Erholt"
      case .neutral: "Ausgeglichen"
      case .productive: "Im Aufbau"
      case .high: "Sehr hohe Belastung"
      }
    }

    public var explanation: String {
      switch self {
      case .fresh: "Die Ermüdung ist deutlich unter deiner Fitness – gut für einen Wettkampf oder einen Test."
      case .neutral: "Belastung und Fitness halten sich die Waage."
      case .productive: "Du trainierst mehr, als du gewohnt bist. So steigt die Fitness; plane Erholung ein."
      case .high:
        "Die Ermüdung liegt weit über deiner Fitness. Achte besonders auf Schlaf, Erholungswerte und Ruhetage."
      }
    }

    public static func of(_ percent: Double) -> Zone {
      if percent > 5 { return .fresh }
      if percent >= -10 { return .neutral }
      if percent >= -30 { return .productive }
      return .high
    }
  }

  /// Tageswerte von `start` bis `end`; Tage ohne Aktivität zählen mit Belastung 0.
  public static func series(activities: [GarminActivity], from start: CalendarDay, to end: CalendarDay) -> [Point] {
    var loads: [CalendarDay: Double] = [:]
    for activity in activities {
      guard let day = activity.day, let load = activity.trainingLoad, load > 0 else { continue }
      loads[day, default: 0] += load
    }
    var fitness = 0.0
    var fatigue = 0.0
    var points: [Point] = []
    var day = start
    while day <= end {
      let load = loads[day] ?? 0
      let form = fitness - fatigue
      fitness += (load - fitness) / fitnessDays
      fatigue += (load - fatigue) / fatigueDays
      points.append(
        Point(
          day: day, load: load, fitness: (fitness * 10).rounded() / 10, fatigue: (fatigue * 10).rounded() / 10,
          form: (form * 10).rounded() / 10))
      day = day.adding(days: 1)
    }
    return points
  }

  /// Verlauf ab der ersten Aktivität mit Belastung (höchstens 180 Tage zurück) bis heute.
  public static func series(activities: [GarminActivity], today: CalendarDay) -> [Point] {
    let earliest = today.adding(days: -180)
    let first = activities.compactMap { $0.trainingLoad ?? 0 > 0 ? $0.day : nil }.filter { $0 >= earliest }.min()
    guard let first else { return [] }
    return series(activities: activities, from: first, to: today)
  }

  /// Ob die Kurve schon aussagekräftig ist.
  public static func isReliable(_ points: [Point]) -> Bool {
    points.count >= warmUpDays
  }
}
