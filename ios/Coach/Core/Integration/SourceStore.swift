import CoachCore
import Foundation
import SwiftData

/// Gemeinsame Ablage aller Datenquellen. Jeder Anbieter liefert seine Tageswerte und Aktivitäten hier ab; die App
/// liest weiter `DailyMetricsRecord` und `ActivityRecord`, die daraus nach den Quellen-Einstellungen entstehen:
/// je Datenart eine Quelle (`MetricsMerge`), Aktivitäten ohne Doppelte (`ActivityMerge`). Jeder Datensatz behält
/// seine Herkunft (`SourceRecord`).
@MainActor
final class SourceStore {
  private let context: ModelContext
  private let defaults: UserDefaults
  /// Aktuelle Einstellungen (aus `CoachSettings`).
  var preferences: () -> SourcePreferences = { SourcePreferences() }
  static let migratedKey = "sources.migrated"
  static let statesKey = "sources.syncStates"

  init(context: ModelContext, defaults: UserDefaults = .standard) {
    self.context = context
    self.defaults = defaults
  }

  // MARK: - Synchronisierungsstatus

  var syncStates: [DataProvider: ProviderSyncState] {
    get {
      guard let data = defaults.data(forKey: Self.statesKey),
        let raw = try? JSONDecoder().decode([String: ProviderSyncState].self, from: data)
      else { return [:] }
      return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
        DataProvider(rawValue: key).map { ($0, value) }
      })
    }
    set {
      let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
      defaults.set(try? JSONEncoder().encode(raw), forKey: Self.statesKey)
    }
  }

  func recordSuccess(_ provider: DataProvider, now: Date = .now) {
    var states = syncStates
    states[provider, default: ProviderSyncState()].recordSuccess(now: now, day: CalendarDay(date: now))
    syncStates = states
  }

  func recordFailure(_ provider: DataProvider, error: String, now: Date = .now) {
    var states = syncStates
    states[provider, default: ProviderSyncState()].recordFailure(now: now, error: error)
    syncStates = states
  }

  // MARK: - Altbestand

  /// Einmalig: Bisherige Tageswerte gelten als Garmin-Werte (vorher gab es nur Garmin, Apple Health füllte Lücken).
  /// Ohne diesen Schritt würde das erste Neuberechnen Werte ohne Herkunft verwerfen.
  func migrateIfNeeded(now: Date = .now) {
    guard !defaults.bool(forKey: Self.migratedKey) else { return }
    let existing = (try? context.fetch(FetchDescriptor<DailyMetricsRecord>())) ?? []
    let known = Set(((try? context.fetch(FetchDescriptor<SourceRecord>())) ?? []).map(\.key))
    for record in existing {
      guard let metrics = record.metrics else { continue }
      let entry = SourceEntry(
        provider: .garmin, kind: nil, externalID: metrics.day.iso, day: metrics.day, importedAt: record.updatedAt,
        contentHash: SyncLedger.hash(metrics))
      guard !known.contains(entry.id) else { continue }
      context.insert(SourceRecord(entry: entry, payload: record.payload))
    }
    try? context.save()
    defaults.set(true, forKey: Self.migratedKey)
  }

  // MARK: - Tageswerte

  /// Tageswerte eines Anbieters übernehmen: mit dem bisher Gespeicherten dieses Anbieters zusammengeführt (vorhandene
  /// Felder bleiben, neue überschreiben), danach die betroffenen Tage neu berechnen. Gibt die Zahl der Tage zurück,
  /// deren Werte sich geändert haben.
  @discardableResult
  func ingestDays(_ map: [CalendarDay: DailyMetrics], from provider: DataProvider, now: Date = .now) -> Int {
    guard !map.isEmpty else { return 0 }
    let records = (try? context.fetch(FetchDescriptor<SourceRecord>())) ?? []
    let byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    var touched = Set<String>()
    for (day, incoming) in map {
      let key = SourceEntry.key(provider, nil, day.iso)
      if let record = byKey[key] {
        let merged = record.metrics.map { $0.merging(incoming) } ?? incoming
        let hash = SyncLedger.hash(merged)
        guard hash != record.contentHash || record.status != SourceEntry.Status.active.rawValue else { continue }
        record.payload = try? JSONEncoder().encode(merged)
        record.contentHash = hash
        record.updatedAt = now
        record.status = SourceEntry.Status.active.rawValue
      } else {
        let entry = SourceEntry(
          provider: provider, kind: nil, externalID: day.iso, day: day, importedAt: now,
          contentHash: SyncLedger.hash(incoming))
        context.insert(SourceRecord(entry: entry, payload: try? JSONEncoder().encode(incoming)))
      }
      touched.insert(day.iso)
    }
    return rebuild(days: touched, now: now)
  }

  /// `DailyMetricsRecord` der Tage aus den Werten aller Anbieter neu berechnen (`nil` = alle Tage mit Herkunft,
  /// z. B. nach geänderten Einstellungen). Tage ohne Herkunft (Beispieldaten) bleiben unberührt.
  @discardableResult
  func rebuild(days: Set<String>? = nil, now: Date = .now) -> Int {
    let records = ((try? context.fetch(FetchDescriptor<SourceRecord>())) ?? []).filter {
      $0.kind == SourceRecord.dailyKind && $0.status == SourceEntry.Status.active.rawValue
        && (days?.contains($0.dayKey) ?? true)
    }
    let grouped = Dictionary(grouping: records, by: \.dayKey)
    let existing = (try? context.fetch(FetchDescriptor<DailyMetricsRecord>())) ?? []
    let byDay = Dictionary(existing.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })
    let preferences = preferences()
    var changed = 0
    for (dayKey, dayRecords) in grouped {
      guard let day = CalendarDay(iso: dayKey) else { continue }
      var perProvider: [DataProvider: DailyMetrics] = [:]
      for record in dayRecords {
        if let provider = DataProvider(rawValue: record.provider), let metrics = record.metrics {
          perProvider[provider] = metrics
        }
      }
      let merged = MetricsMerge.merge(perProvider, day: day, preferences: preferences).metrics
      if let record = byDay[dayKey] {
        guard record.metrics != merged else { continue }
        record.replace(merged, at: now)
      } else {
        context.insert(DailyMetricsRecord(metrics: merged, updatedAt: now))
      }
      changed += 1
    }
    return changed
  }

  /// Welche Quelle je Datenart an einem Tag gewonnen hat (für „Herkunft“ in den Einstellungen).
  func sources(on day: CalendarDay) -> [DataKind: DataProvider] {
    let key = day.iso
    let query = FetchDescriptor<SourceRecord>(predicate: #Predicate { $0.dayKey == key })
    var perProvider: [DataProvider: DailyMetrics] = [:]
    for record in (try? context.fetch(query)) ?? []
    where record.kind == SourceRecord.dailyKind && record.status == SourceEntry.Status.active.rawValue {
      if let provider = DataProvider(rawValue: record.provider), let metrics = record.metrics {
        perProvider[provider] = metrics
      }
    }
    return MetricsMerge.merge(perProvider, day: day, preferences: preferences()).sources
  }

  // MARK: - Aktivitäten

  /// Herkunft der gelieferten Aktivitäten festhalten. `complete`: Der Abruf hat alle Aktivitäten im Zeitraum
  /// geliefert – dann gelten fehlende als beim Anbieter gelöscht und werden entfernt. Gibt zurück, welche IDs neu
  /// angelegt werden dürfen (nicht als ersetzt markiert).
  @discardableResult
  func recordActivities(
    _ activities: [GarminActivity], from provider: DataProvider, window: DateRange?, complete: Bool,
    now: Date = .now
  ) -> Set<Int64> {
    let records = (try? context.fetch(FetchDescriptor<SourceRecord>())) ?? []
    let mine = records.filter { $0.provider == provider.rawValue && $0.kind == DataKind.activities.rawValue }
    let byKey = Dictionary(mine.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    let incoming = activities.compactMap { activity -> SyncLedger.Incoming? in
      guard let day = activity.day else { return nil }
      return SyncLedger.Incoming(
        externalID: Self.externalID(activity), day: day, contentHash: SyncLedger.hash(activity))
    }
    let changes = SyncLedger.reconcile(
      known: mine.compactMap(\.entry), incoming: incoming, provider: provider, kind: .activities, window: window,
      complete: complete, now: now)
    for entry in changes.new { context.insert(SourceRecord(entry: entry)) }
    for entry in changes.changed + changes.deleted { byKey[entry.id]?.apply(entry) }
    if !changes.deleted.isEmpty {
      let gone = Set(changes.deleted.map(\.externalID))
      for record in (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? [] {
        if let activity = record.activity, ActivityMerge.provider(of: activity) == provider,
          gone.contains(Self.externalID(activity))
        {
          context.delete(record)
        }
      }
    }
    let skipped = Set(changes.skipped)
    return Set(activities.filter { !skipped.contains(Self.externalID($0)) }.map(\.id))
  }

  /// Doppelte Einheiten verschiedener Anbieter entfernen: Nur die bevorzugte Quelle bleibt als `ActivityRecord`,
  /// die anderen werden im Herkunftsverzeichnis als ersetzt markiert. Gibt die Zahl entfernter Doppelter zurück.
  @discardableResult
  func deduplicateActivities(connected: Set<DataProvider>, now: Date = .now) -> Int {
    let records = (try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []
    let activities = records.compactMap(\.activity)
    let plan = ActivityMerge.plan(activities, preferences: preferences(), connected: connected)
    guard !plan.superseded.isEmpty else { return 0 }
    let sourceRecords = (try? context.fetch(FetchDescriptor<SourceRecord>())) ?? []
    let byKey = Dictionary(sourceRecords.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    for record in records where plan.superseded[record.garminID] != nil {
      guard let activity = record.activity, let day = activity.day else { continue }
      let provider = ActivityMerge.provider(of: activity)
      var entry = SourceEntry(
        provider: provider, kind: .activities, externalID: Self.externalID(activity), day: day, importedAt: now,
        contentHash: SyncLedger.hash(activity), status: .superseded)
      if let existing = byKey[entry.id] {
        entry.importedAt = existing.importedAt
        existing.apply(entry)
      } else {
        context.insert(SourceRecord(entry: entry))
      }
      context.delete(record)
    }
    return plan.superseded.count
  }

  /// Externe ID: beim Anbieter vergebene, sonst die lokale Aktivitäts-ID.
  static func externalID(_ activity: GarminActivity) -> String {
    activity.externalID ?? String(activity.id)
  }
}
