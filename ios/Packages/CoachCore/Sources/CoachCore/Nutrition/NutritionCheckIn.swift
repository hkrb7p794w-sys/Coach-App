import Foundation

/// Wöchentlicher Ernährungs-Check-in (Anregung: MacroFactor, Paket 13): Einmal pro Kalenderwoche erinnert die App
/// daran, Gewichtstrend und gemessenen Verbrauch anzusehen und die Tagesziele bei Bedarf anzupassen. Die Anpassung
/// selbst bleibt eine Entscheidung der Person (`Expenditure.adjustment`, `WeightTrend`); die App ändert nichts
/// von allein.
public enum NutritionCheckIn {
  /// Daten der letzten Tage, ohne die der Check-in nichts zeigen könnte.
  public static let dataWindowDays = 14

  /// Fällig, wenn in dieser Woche (ab Montag) noch kein Check-in war, Gewichtsziele erlaubt sind und es in den
  /// letzten zwei Wochen Wägungen oder Mahlzeiten gibt.
  public static func isDue(
    today: CalendarDay, last: CalendarDay?, withheld: Bool, weighIns: [CalendarDay], mealDays: [CalendarDay]
  ) -> Bool {
    guard !withheld else { return false }
    let monday = PlanAdjustments.monday(of: today)
    if let last, last >= monday { return false }
    let start = today.adding(days: -dataWindowDays)
    let recent = { (day: CalendarDay) in day >= start && day <= today }
    return weighIns.contains(where: recent) || mealDays.contains(where: recent)
  }
}
