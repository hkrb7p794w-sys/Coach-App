import Foundation

/// Plant, welchen Zeitraum ein Garmin-Abruf holt.
///
/// Beim ersten Abruf 60 Tage (die HRV-Baseline des Altbestands nutzt einen 60-Tage-Korridor),
/// danach ab dem zuletzt gespeicherten Tag mit zwei Tagen Überlappung: Garmin trägt Schlaf und HRV
/// oft erst Stunden später nach.
public enum SyncPlan {
  public static let initialDays = 60
  public static let overlapDays = 2
  /// Abrufe kürzer hintereinander als dieser Abstand werden beim App-Start übersprungen.
  public static let minimumInterval: TimeInterval = 15 * 60

  public static func range(latestStored: CalendarDay?, today: CalendarDay) -> DateRange {
    guard let latestStored, latestStored <= today else {
      return DateRange.last(initialDays, endingOn: today)
    }
    let start = max(latestStored.adding(days: -overlapDays), today.adding(days: -(initialDays - 1)))
    return DateRange(start: start, end: today)
  }

  public static func isDue(lastSync: Date?, now: Date) -> Bool {
    guard let lastSync else { return true }
    return now.timeIntervalSince(lastSync) >= minimumInterval || now < lastSync
  }

  /// Weiterblättern in der Aktivitätsliste (neueste zuerst), bis eine Seite unvollständig ist,
  /// eine schon bekannte Aktivität auftaucht oder die Aktivitäten vor dem Zeitraum liegen.
  public static func shouldLoadNextPage(
    page: [GarminActivity],
    pageSize: Int,
    knownIDs: Set<Int64>,
    rangeStart: CalendarDay,
    pagesLoaded: Int,
    maxPages: Int = 6
  ) -> Bool {
    guard page.count >= pageSize, pagesLoaded < maxPages else { return false }
    if page.contains(where: { knownIDs.contains($0.id) }) { return false }
    if let oldest = page.compactMap(\.day).min(), oldest < rangeStart { return false }
    return true
  }
}
