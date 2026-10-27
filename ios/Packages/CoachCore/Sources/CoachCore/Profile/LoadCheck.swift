import Foundation

/// Prüft, ob der Laufumfang zu schnell steigt: letzte 7 Tage gegenüber dem Wochenschnitt der drei Wochen davor.
/// Über 30 % Steigerung sah eine Kohortenstudie tendenziell mehr Überlastungsverletzungen (Nielsen et al. 2014);
/// die feste 10-%-Regel schützte dagegen nicht (Buist et al. 2007).
public enum LoadCheck {
  public static let maxIncrease = 0.30
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
    var result = Result(lastWeekKilometers: (last * 10).rounded() / 10, baselineKilometers: (baseline * 10).rounded() / 10)
    guard baseline > 0 else { return result }
    let increase = last / baseline - 1
    result.increase = (increase * 100).rounded() / 100
    if increase > maxIncrease, last - baseline >= minimumDifferenceKilometers {
      result.warning =
        "In den letzten 7 Tagen bist du \(GermanFormat.number(result.lastWeekKilometers)) km gelaufen, "
        + "\(Int((increase * 100).rounded())) % mehr als im Schnitt der drei Wochen davor "
        + "(\(GermanFormat.number(result.baselineKilometers)) km). Halte den Umfang diese Woche eher gleich."
    }
    return result
  }
}
