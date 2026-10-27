import CoachCore
import Foundation
import SwiftData

/// Ergebnis eines Abrufs für die Anzeige in den Einstellungen.
struct SyncReport: Equatable {
  var range: DateRange
  var daysUpdated = 0
  var activitiesUpdated = 0
  /// Per FIT-Datei ausgewertete Läufe und Fahrten (aerobe Kopplung, Pace-Check).
  var activitiesAnalyzed = 0
  /// Fehler einzelner Endpunkte; der Rest des Abrufs läuft trotzdem durch.
  var errors: [String] = []
  /// Beantwortete Abrufe je Quelle (Garmin-Konto, Personal API).
  var sources: [String: Int] = [:]
  /// Grund, warum die Personal API einspringen musste.
  var connectProblem: String?
  var finishedAt = Date.now

  var summary: String {
    var text = "\(daysUpdated) Tage, \(activitiesUpdated) Aktivitäten (\(range.start.iso) – \(range.end.iso))"
    if activitiesAnalyzed > 0 { text += ", \(activitiesAnalyzed) ausgewertet" }
    if !errors.isEmpty { text += ", \(errors.count) Fehler" }
    if !sources.isEmpty {
      text += " · " + sources.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
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
  let analysisStore: ActivityAnalysisStore
  static let lastSyncKey = "garmin.lastSync"
  static let profileKey = "garmin.profile"
  static let profileDateKey = "garmin.profileDate"
  static let activityBackfillKey = "garmin.activityBackfill"
  static let racePredictionsKey = "garmin.racePredictions"
  static let weightsKey = "garmin.weights"

  init(
    client: GarminClient, context: ModelContext, defaults: UserDefaults = .standard,
    analysisStore: ActivityAnalysisStore = ActivityAnalysisStore()
  ) {
    self.client = client
    self.context = context
    self.defaults = defaults
    self.analysisStore = analysisStore
  }

  var lastSync: Date? {
    defaults.object(forKey: Self.lastSyncKey) as? Date
  }

  /// Wettkampfprognosen der Uhr (nur über das Garmin-Konto).
  var racePredictions: RacePredictions? {
    defaults.data(forKey: Self.racePredictionsKey).flatMap { try? JSONDecoder().decode(RacePredictions.self, from: $0) }
  }

  /// Wägungen aus Garmin Connect (letzte 120 Tage).
  var weights: [WeightEntry] {
    defaults.data(forKey: Self.weightsKey).flatMap { try? JSONDecoder().decode([WeightEntry].self, from: $0) } ?? []
  }

  var profile: GarminProfile? {
    defaults.data(forKey: Self.profileKey).flatMap { try? JSONDecoder().decode(GarminProfile.self, from: $0) }
  }

  func sync(now: Date = .now) async throws -> SyncReport {
    guard client.isConfigured else { throw GarminAPIError.missingKey }
    client.resetSources()
    if client.connect?.isLoggedIn ?? false {
      // Token früh erneuern: Ist die Anmeldung abgelaufen und kein Key da, gleich klar melden.
      do {
        _ = try await client.connect?.validToken()
      } catch {
        if !client.hasKey { throw error }
      }
    } else {
      // Schlägt schon der Token-Tausch fehl, ist der Key das Problem – dann nicht jeden Endpunkt einzeln melden.
      _ = try await client.validToken()
    }

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
    sources.append((.spo2(today.adding(days: -1)), GarminMetricsParser.spo2))
    sources.append((.spo2(today), GarminMetricsParser.spo2))
    sources.append((.fitnessAge(today), { GarminMetricsParser.fitnessAge($0, day: today) }))

    var maps: [GarminMetricsParser.DayMap] = []
    for (endpoint, parse) in sources {
      if let json = await fetch(endpoint, report: &report) {
        maps.append(parse(json))
      }
    }
    if client.connect?.isLoggedIn ?? false {
      maps += await connectExtras(today: today, report: &report)
    }
    let merged = GarminMetricsParser.merge(maps).filter { range.start <= $0.key && $0.key <= range.end }
    report.daysUpdated = store(merged, at: now)
    report.activitiesUpdated = await syncActivities(since: range.start, report: &report)
    if defaults.string(forKey: Self.activityBackfillKey) == nil {
      // Einmalig 13 Wochen Aktivitäten für die Wochenbalken und die HFmax nachladen.
      let errorsBefore = report.errors.count
      report.activitiesUpdated += await syncActivities(
        since: today.adding(days: -SyncPlan.activityHistoryDays), ignoreKnown: true, report: &report)
      if report.errors.count == errorsBefore { defaults.set(today.iso, forKey: Self.activityBackfillKey) }
    }
    await refreshProfileIfNeeded(today: today, report: &report)
    try context.save()
    report.activitiesAnalyzed = await analyzeActivities(today: today, report: &report)

    defaults.set(now, forKey: Self.lastSyncKey)
    report.sources = Dictionary(uniqueKeysWithValues: client.sources.map { ($0.key.rawValue, $0.value) })
    report.connectProblem = client.lastConnectError
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

  private func syncActivities(
    since start: CalendarDay, ignoreKnown: Bool = false, report: inout SyncReport
  ) async -> Int {
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
        page: page, pageSize: pageSize, knownIDs: ignoreKnown ? [] : knownIDs, rangeStart: start,
        pagesLoaded: pages)
      if !more { break }
    }
    return updated
  }

  /// Werte, die nur das Garmin-Konto liefert, plus Tageswerte und Schlaf in der Connect-Form.
  private func connectExtras(today: CalendarDay, report: inout SyncReport) async -> [GarminMetricsParser.DayMap] {
    var maps: [GarminMetricsParser.DayMap] = []
    for day in [today.adding(days: -1), today] {
      if let json = await fetchConnect(.trainingReadiness(day), report: &report) {
        maps.append(GarminMetricsParser.trainingReadiness(json, day: day))
      }
    }
    if let json = await fetchConnect(.trainingStatus(today), report: &report) {
      maps.append(GarminMetricsParser.trainingStatus(json, day: today))
    }
    if let json = await fetchConnect(.enduranceScore(today), report: &report) {
      maps.append(GarminMetricsParser.enduranceScore(json, day: today))
    }
    if let name = client.connect?.displayName {
      for day in [today.adding(days: -1), today] {
        if let json = await fetchConnect(.userSummary(displayName: name, day: day), report: &report) {
          maps.append(GarminMetricsParser.dailySummaries(json))
        }
        if let json = await fetchConnect(.dailySleepData(displayName: name, day: day), report: &report) {
          maps.append(GarminMetricsParser.sleep(json))
        }
      }
      if let json = await fetchConnect(.racePredictions(displayName: name), report: &report),
        let predictions = RacePredictions(json: json), let data = try? JSONEncoder().encode(predictions)
      {
        defaults.set(data, forKey: Self.racePredictionsKey)
      }
    }
    if let json = await fetchConnect(.weightRange(start: today.adding(days: -27), end: today), report: &report) {
      let start = today.adding(days: -119)
      let fresh = WeightTrend.garminEntries(json)
      let freshDays = Set(fresh.map(\.day))
      let kept = weights.filter { $0.day >= start && !freshDays.contains($0.day) }
      if let data = try? JSONEncoder().encode((kept + fresh).sorted { $0.day < $1.day }) {
        defaults.set(data, forKey: Self.weightsKey)
      }
    }
    return maps
  }

  private func fetchConnect(_ endpoint: ConnectEndpoint, report: inout SyncReport) async -> JSONValue? {
    do {
      return try await client.json(endpoint)
    } catch let error as GarminAPIError {
      report.errors.append("Konto \(endpoint.path): \(error.message)")
    } catch {
      report.errors.append("Konto \(endpoint.path): \(error.localizedDescription)")
    }
    return nil
  }

  /// FIT-Dateien neuer Läufe und Fahrten auswerten (höchstens sechs je Abruf, der Rest folgt beim nächsten).
  private func analyzeActivities(today: CalendarDay, report: inout SyncReport) async -> Int {
    // Nur Garmin-Aktivitäten (positive IDs) haben eine FIT-Datei; Workouts aus Apple Health nicht.
    let activities = ((try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []).compactMap(\.activity)
      .filter { $0.id >= 0 }
    var analyzed = analysisStore.load()
    var fetches = 0
    var count = 0
    for activity in ActivityAnalysisPlanner.pending(activities, analyzed: analyzed, today: today) {
      var fit: FitActivity?
      var rpe: Double?
      if ActivityAnalysisPlanner.needsFile(activity) {
        guard fetches < ActivityAnalysisPlanner.maxFetchesPerSync else { continue }
        fetches += 1
        do {
          let data = try await client.data(.activityFile(id: activity.id))
          fit = try? await Self.decodeFit(data)
        } catch let error as GarminAPIError {
          report.errors.append("FIT \(activity.id): \(error.message)")
          continue
        } catch {
          report.errors.append("FIT \(activity.id): \(error.localizedDescription)")
          continue
        }
        if ActivityAnalysisPlanner.paceKind(activity) != nil { rpe = await self.rpe(activity.id) }
      }
      analyzed[activity.id] = ActivityAnalysisPlanner.analyze(activity, fit: fit, rpe: rpe)
      count += 1
    }
    for id in ActivityAnalysisPlanner.needsRPE(Array(analyzed.values), today: today) {
      if let value = await rpe(id) { analyzed[id]?.rpe = value }
    }
    analysisStore.save(analyzed, today: today)
    return count
  }

  /// Selbsteinschätzung (RPE) von der Uhr; fehlt sie, bleibt es still.
  private func rpe(_ id: Int64) async -> Double? {
    guard let json = try? await client.json(.activity(id: id)) else { return nil }
    return ActivityAnalysisPlanner.rpe(fromActivityDetail: json)
  }

  /// Entpacken und Lesen im Hintergrund, damit die Oberfläche flüssig bleibt.
  nonisolated static func decodeFit(_ data: Data) async throws -> FitActivity {
    try await Task.detached(priority: .utility) {
      try FitDecoder.decode(ZipArchive.fitData(from: data))
    }.value
  }

  private func refreshProfileIfNeeded(today: CalendarDay, report: inout SyncReport) async {
    guard defaults.string(forKey: Self.profileDateKey) != today.iso else { return }
    // Uhr-Zonen: Die Rohantwort genügt, die App liest sie aus `RawResponseRecord`.
    _ = await fetch(.heartRateZones, report: &report)
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

  /// Letzte gespeicherte Rohantwort eines Endpunkts.
  func raw(_ endpoint: GarminEndpoint) -> JSONValue? {
    let name = endpoint.request.path
    let descriptor = FetchDescriptor<RawResponseRecord>(predicate: #Predicate { $0.endpoint == name })
    return (try? context.fetch(descriptor).first).flatMap { try? JSONValue(data: $0.body) }
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
