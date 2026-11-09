import Foundation

/// Prüft, ob der Laufumfang zu schnell steigt: letzte 7 Tage gegenüber dem Wochenschnitt der drei Wochen davor.
/// Über 30 % Steigerung sah eine Kohortenstudie tendenziell mehr Überlastungsverletzungen (Nielsen et al. 2014);
/// die feste 10-%-Regel schützte dagegen nicht (Buist et al. 2007).
public enum LoadCheck {
  public static let maxIncrease = 0.30
  /// Einzellauf gegen den längsten Lauf der letzten 30 Tage (Frandsen et al. 2025).
  public static let singleRunLimit = 1.10
  /// Unter diesem bisher längsten Lauf (km) wird nicht gewarnt: Aus 2 km werden schnell 4 km, ohne dass es etwas heißt.
  public static let minimumLongestKilometers = 3.0
  /// Unter dieser Differenz (km) wird nicht gewarnt: kleine Umfänge schwanken stark.
  public static let minimumDifferenceKilometers = 5.0

  public struct Result: Equatable, Sendable {
    public var lastWeekKilometers: Double
    public var baselineKilometers: Double
    public var increase: Double?
    public var warning: String?
  }

  public static func running(activities: [GarminActivity], today: CalendarDay) -> Result {
    func kilometers(from start: CalendarDay, days: Int) -> Double {
      let end = start.adding(days: days - 1)
      return activities.filter { activity in
        guard activity.sport == .run, let day = activity.day else { return false }
        return start <= day && day <= end
      }.reduce(0) { $0 + ($1.distanceMeters ?? 0) / 1000 }
    }
    let last = kilometers(from: today.adding(days: -6), days: 7)
    let baseline = kilometers(from: today.adding(days: -27), days: 21) / 3
    var result = Result(
      lastWeekKilometers: (last * 10).rounded() / 10, baselineKilometers: (baseline * 10).rounded() / 10)
    result.warning = singleRunWarning(activities: activities, today: today)
    guard baseline > 0 else { return result }
    let increase = last / baseline - 1
    result.increase = (increase * 100).rounded() / 100
    // Die Warnung zum Einzellauf ist besser belegt und hat Vorrang.
    if result.warning == nil, increase > maxIncrease, last - baseline >= minimumDifferenceKilometers {
      result.warning =
        "In den letzten 7 Tagen bist du \(GermanFormat.number(result.lastWeekKilometers)) km gelaufen, "
        + "\(Int((increase * 100).rounded())) % mehr als im Schnitt der drei Wochen davor "
        + "(\(GermanFormat.number(result.baselineKilometers)) km). Halte den Umfang diese Woche eher gleich."
    }
    return result
  }

  /// Der längste Lauf der letzten drei Tage gegen den längsten der 30 Tage davor.
  public static func singleRunWarning(activities: [GarminActivity], today: CalendarDay) -> String? {
    let runs = activities.compactMap { activity -> (day: CalendarDay, meters: Double)? in
      guard activity.sport == .run, let day = activity.day, let meters = activity.distanceMeters, meters > 0 else {
        return nil
      }
      return (day, meters)
    }
    let recent = runs.filter { $0.day >= today.adding(days: -2) && $0.day <= today }
    guard let latest = recent.max(by: { $0.meters < $1.meters }) else { return nil }
    let start = latest.day.adding(days: -30)
    guard let longest = runs.filter({ $0.day >= start && $0.day < latest.day }).map(\.meters).max(),
      longest >= minimumLongestKilometers * 1_000, latest.meters > longest * singleRunLimit
    else { return nil }
    return
      "Dein letzter Lauf war mit \(GermanFormat.number(latest.meters / 1_000)) km deutlich länger als dein längster "
      + "der letzten 30 Tage (\(GermanFormat.number(longest / 1_000)) km). Lass die nächsten Läufe locker und kürzer."
  }
}
