import CoachCore
import Foundation
import SwiftData

/// Ergebnis eines Abrufs für die Anzeige in den Einstellungen.
struct SyncReport: Equatable {
  var range: DateRange
  var daysUpdated = 0
  var activitiesUpdated = 0
  /// Fehler einzelner Endpunkte; der Rest des Abrufs läuft trotzdem durch.
  var errors: [String] = []
  var finishedAt = Date.now

  var summary: String {
    var text = "\(daysUpdated) Tage, \(activitiesUpdated) Aktivitäten (\(range.start.iso) – \(range.end.iso))"
    if !errors.isEmpty { text += ", \(errors.count) Fehler" }
    return text
  }
}

/// Holt Garmin-Daten und speichert sie in SwiftData.
///
/// Jeder Endpunkt ist einzeln abgesichert (wie `_safe` im Altbestand): Fällt einer aus – die Uhr kann
/// etwas nicht oder Garmin ändert ein Format –, laufen die anderen weiter.
final class GarminSyncService {
  private let client: GarminClient
  private let context: ModelContext
  private let defaults: UserDefaults
  static let lastSyncKey = "garmin.lastSync"
  static let profileKey = "garmin.profile"
  static let profileDateKey = "garmin.profileDate"

  init(client: GarminClient, context: ModelContext, defaults: UserDefaults = .standard) {
    self.client = client
    self.context = context
    self.defaults = defaults
  }

  var lastSync: Date? {
    defaults.object(forKey: Self.lastSyncKey) as? Date
  }

  var profile: GarminProfile? {
    defaults.data(forKey: Self.profileKey).flatMap { try? JSONDecoder().decode(GarminProfile.self, from: $0) }
  }

  func sync(now: Date = .now) async throws -> SyncReport {
    guard client.hasKey else { throw GarminAPIError.missingKey }
    // Schlägt schon der Token-Tausch fehl, ist der Key das Problem – dann nicht jeden Endpunkt einzeln melden.
    _ = try await client.validToken()

    let today = CalendarDay(date: now)
    let range = SyncPlan.range(latestStored: latestStoredDay(), today: today)
    var report = SyncReport(range: range)

    typealias Parser = (JSONValue) -> GarminMetricsParser.DayMap
    var sources: [(GarminEndpoint, Parser)] = []
    for chunk in range.chunks(maxDays: 180) {
      sources.append((.dailySummaries(chunk), GarminMetricsParser.dailySummaries))
      sources.append((.hrvSummaries(chunk), GarminMetricsParser.hrv))
    }
    for chunk in range.chunks(maxDays: 28) {
      sources.append((.sleepSummaries(chunk), GarminMetricsParser.sleep))
      sources.append((.bodyBattery(chunk), GarminMetricsParser.bodyBattery))
    }
    // Einzeltage für heute: Zusammenfassungen hängen teils hinterher.
    sources.append((.hrv(today), GarminMetricsParser.hrv))
    sources.append((.dailySleep(today), GarminMetricsParser.sleep))

    var maps: [GarminMetricsParser.DayMap] = []
    for (endpoint, parse) in sources {
      if let json = await fetch(endpoint, report: &report) {
        maps.append(parse(json))
      }
    }
    let merged = GarminMetricsParser.merge(maps).filter { range.start <= $0.key && $0.key <= range.end }
    report.daysUpdated = store(merged, at: now)
    report.activitiesUpdated = await syncActivities(since: range.start, report: &report)
    await refreshProfileIfNeeded(today: today, report: &report)

    try context.save()
    defaults.set(now, forKey: Self.lastSyncKey)
    report.finishedAt = now
    return report
  }

  // MARK: - Schritte

  private func fetch(_ endpoint: GarminEndpoint, report: inout SyncReport) async -> JSONValue? {
    do {
      let data = try await client.data(endpoint)
      saveRaw(endpoint, data)
      return data.isEmpty ? .null : try JSONValue(data: data)
    } catch let error as GarminAPIError {
      report.errors.append("\(endpoint.request.path): \(error.message)")
    } catch {
      report.errors.append("\(endpoint.request.path): \(error.localizedDescription)")
    }
    return nil
  }

  private func store(_ metrics: GarminMetricsParser.DayMap, at date: Date) -> Int {
    let existing = (try? context.fetch(FetchDescriptor<DailyMetricsRecord>())) ?? []
    let byKey = Dictionary(existing.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
    for (day, value) in metrics {
      if let record = byKey[day.iso] {
        record.update(value, at: date)
      } else {
        context.insert(DailyMetricsRecord(metrics: value, updatedAt: date))
      }
    }
    return metrics.count
  }

  private func syncActivities(since start: CalendarDay, report: inout SyncReport) async -> Int {
    let existing = (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []
    var byID = Dictionary(existing.map { ($0.garminID, $0) }, uniquingKeysWith: { first, _ in first })
    let knownIDs = Set(byID.keys)
    let pageSize = GarminEndpoint.maxActivitiesPerPage
    var updated = 0
    var pages = 0

    while true {
      guard let json = await fetch(.activities(start: pages * pageSize, limit: pageSize), report: &report) else {
        break
      }
      pages += 1
      let page = GarminActivityParser.activities(json)
      for activity in page where (activity.day ?? start) >= start || !knownIDs.contains(activity.id) {
        if let record = byID[activity.id] {
          record.update(activity)
        } else {
          let record = ActivityRecord(activity: activity)
          context.insert(record)
          byID[activity.id] = record
        }
        updated += 1
      }
      let more = SyncPlan.shouldLoadNextPage(
        page: page, pageSize: pageSize, knownIDs: knownIDs, rangeStart: start, pagesLoaded: pages)
      if !more { break }
    }
    return updated
  }

  private func refreshProfileIfNeeded(today: CalendarDay, report: inout SyncReport) async {
    guard defaults.string(forKey: Self.profileDateKey) != today.iso else { return }
    guard let json = await fetch(.profileSettings, report: &report) else { return }
    if let data = try? JSONEncoder().encode(GarminProfile(settings: json)) {
      defaults.set(data, forKey: Self.profileKey)
      defaults.set(today.iso, forKey: Self.profileDateKey)
    }
  }

  private func latestStoredDay() -> CalendarDay? {
    var descriptor = FetchDescriptor<DailyMetricsRecord>(sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first.flatMap { CalendarDay(iso: $0.dayKey) }
  }

  private func saveRaw(_ endpoint: GarminEndpoint, _ data: Data) {
    let name = endpoint.request.path
    let descriptor = FetchDescriptor<RawResponseRecord>(predicate: #Predicate { $0.endpoint == name })
    if let record = try? context.fetch(descriptor).first {
      record.body = data
      record.fetchedAt = .now
    } else {
      context.insert(RawResponseRecord(endpoint: name, body: data))
    }
  }
}
