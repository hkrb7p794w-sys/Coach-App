import CoachCore
import Foundation
import SwiftData

/// Tageswerte eines Kalendertags. Die Werte liegen als JSON (`DailyMetrics`) vor, damit neue Felder
/// keine Datenbank-Migration brauchen.
@Model
final class DailyMetricsRecord {
  @Attribute(.unique) var dayKey: String
  var payload: Data
  var updatedAt: Date

  init(metrics: DailyMetrics, updatedAt: Date = .now) {
    dayKey = metrics.day.iso
    payload = (try? JSONEncoder().encode(metrics)) ?? Data()
    self.updatedAt = updatedAt
  }

  var metrics: DailyMetrics? {
    try? JSONDecoder().decode(DailyMetrics.self, from: payload)
  }

  func update(_ metrics: DailyMetrics, at date: Date = .now) {
    let merged = self.metrics.map { $0.merging(metrics) } ?? metrics
    payload = (try? JSONEncoder().encode(merged)) ?? payload
    updatedAt = date
  }

  /// Ersetzt die Werte (nach dem Zusammenführen aller Quellen, `SourceStore.rebuild`).
  func replace(_ metrics: DailyMetrics, at date: Date = .now) {
    payload = (try? JSONEncoder().encode(metrics)) ?? payload
    updatedAt = date
  }
}

/// Eine Garmin-Aktivität (Zusammenfassung).
@Model
final class ActivityRecord {
  @Attribute(.unique) var garminID: Int64
  var dayKey: String
  var startLocal: String
  var payload: Data

  init(activity: GarminActivity) {
    garminID = activity.id
    dayKey = activity.day?.iso ?? ""
    startLocal = activity.startLocal ?? ""
    payload = (try? JSONEncoder().encode(activity)) ?? Data()
  }

  var activity: GarminActivity? {
    try? JSONDecoder().decode(GarminActivity.self, from: payload)
  }

  func update(_ activity: GarminActivity) {
    dayKey = activity.day?.iso ?? dayKey
    startLocal = activity.startLocal ?? startLocal
    payload = (try? JSONEncoder().encode(activity)) ?? payload
  }
}

/// Letzte Rohantwort je Endpunkt – für die Diagnose und um die Zuordnung später ohne neuen Abruf
/// anpassen zu können.
@Model
final class RawResponseRecord {
  @Attribute(.unique) var endpoint: String
  var fetchedAt: Date
  var body: Data

  init(endpoint: String, body: Data, fetchedAt: Date = .now) {
    self.endpoint = endpoint
    self.body = body
    self.fetchedAt = fetchedAt
  }
}

/// Ein importierter Datensatz eines Anbieters mit Herkunft (`SourceEntry`). Bei Tageswerten liegt hier zusätzlich
/// der Rohwert des Anbieters (`payload`), aus dem `DailyMetricsRecord` je nach Quellen-Einstellung neu berechnet
/// wird. Neues Modell: SwiftData legt die Tabelle beim ersten Start ohne Migration an.
@Model
final class SourceRecord {
  /// `provider|kind|externalID`
  @Attribute(.unique) var key: String
  var provider: String
  var kind: String
  var externalID: String
  var dayKey: String
  var start: Date?
  var importedAt: Date
  var updatedAt: Date
  var contentHash: String
  var status: String
  /// Tageswerte des Anbieters (`DailyMetrics`), bei Aktivitäten leer (die liegen in `ActivityRecord`).
  var payload: Data?

  static let dailyKind = "daily"

  init(entry: SourceEntry, payload: Data? = nil) {
    key = entry.id
    provider = entry.provider.rawValue
    kind = entry.kind?.rawValue ?? Self.dailyKind
    externalID = entry.externalID
    dayKey = entry.day.iso
    start = entry.start
    importedAt = entry.importedAt
    updatedAt = entry.updatedAt
    contentHash = entry.contentHash
    status = entry.status.rawValue
    self.payload = payload
  }

  var entry: SourceEntry? {
    guard let provider = DataProvider(rawValue: provider), let day = CalendarDay(iso: dayKey) else { return nil }
    let kind = DataKind(rawValue: kind)
    return SourceEntry(
      provider: provider, kind: kind, externalID: externalID, day: day, start: start, importedAt: importedAt,
      updatedAt: updatedAt, contentHash: contentHash, status: SourceEntry.Status(rawValue: status) ?? .active)
  }

  func apply(_ entry: SourceEntry) {
    dayKey = entry.day.iso
    start = entry.start
    updatedAt = entry.updatedAt
    contentHash = entry.contentHash
    status = entry.status.rawValue
  }

  var metrics: DailyMetrics? {
    payload.flatMap { try? JSONDecoder().decode(DailyMetrics.self, from: $0) }
  }
}

enum CoachSchema {
  static let models: [any PersistentModel.Type] = [
    DailyMetricsRecord.self, ActivityRecord.self, RawResponseRecord.self, MealRecord.self, FoodRecord.self,
    GymSessionRecord.self, SourceRecord.self,
  ]

  static func makeContainer(inMemory: Bool = false) -> ModelContainer {
    let schema = Schema(models)
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
    do {
      return try ModelContainer(for: schema, configurations: [configuration])
    } catch {
      // Lieber mit leerem Speicher starten als abstürzen; Daten kommen beim nächsten Abruf von Garmin.
      let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
      do {
        return try ModelContainer(for: schema, configurations: [fallback])
      } catch {
        fatalError("SwiftData ist nicht verfügbar: \(error)")
      }
    }
  }
}
