import CoachCore
import Foundation
import SwiftData

/// Gym-Einheiten mit Garmin Connect abgleichen: Sätze in die Aufzeichnung der Uhr schreiben (eine Aktivität mit
/// Kalorien, Herzfrequenz und Sätzen) oder – ohne Aufzeichnung nach `GarminStrengthSync.fallbackDelay` – als eigene
/// Aktivität hochladen. Läuft nach dem Speichern einer Einheit und nach jedem Abruf.
enum GarminStrengthService {
  /// Ursprüngliche Sätze der Uhr je Aktivität, vor dem ersten Überschreiben gesichert.
  static var backupDirectory: URL {
    URL.applicationSupportDirectory.appending(path: "garmin-exercise-sets", directoryHint: .isDirectory)
  }

  static func backupURL(activityID: Int64) -> URL {
    backupDirectory.appending(path: "\(activityID).json")
  }

  static func hasBackup(activityID: Int64) -> Bool {
    FileManager.default.fileExists(atPath: backupURL(activityID: activityID).path)
  }

  /// Wartende Einheiten der letzten 3 Tage abgleichen; gibt eine Meldung für die zuletzt bearbeitete zurück.
  @discardableResult
  static func reconcile(
    context: ModelContext, garmin: GarminConnectSession, gym: GymSettings, now: Date = .now
  ) async -> String? {
    guard garmin.isLoggedIn else { return nil }
    let since = now.addingTimeInterval(-3 * 86_400)
    let records =
      (try? context.fetch(FetchDescriptor<GymSessionRecord>(predicate: #Predicate { $0.start >= since })))
      ?? []
    let pending = records.filter { $0.session?.garmin?.status == .pending }
    guard !pending.isEmpty else { return nil }

    // Aktivitäten: gespeicherte und die neuesten direkt von Connect (die Uhr-Aufzeichnung kommt oft erst später).
    var activities = ((try? context.fetch(FetchDescriptor<ActivityRecord>())) ?? []).compactMap(\.activity)
      .filter { ($0.day.map { $0 >= CalendarDay(date: since) }) ?? false }
    if let json = try? await garmin.json(.recentActivities(limit: 20)) {
      let known = Set(activities.map(\.id))
      activities += GarminActivityParser.activities(json).filter { !known.contains($0.id) }
    }
    var linked = Set(records.compactMap { $0.session?.garmin?.activityID })

    var message: String?
    for record in pending {
      guard let session = record.session else { continue }
      switch GarminStrengthSync.action(
        for: session, activities: activities, linked: linked, now: now, fallbackUpload: gym.garminFallbackUpload)
      {
      case .enrich(let activityID):
        message = await enrich(record, session: session, activityID: activityID, garmin: garmin, gym: gym, now: now)
        linked.insert(activityID)
      case .upload:
        message = await GymViewModel.uploadToGarmin(record, session: session, context: context, garmin: garmin)
        record.setGarmin(
          GarminLink(status: record.uploadedToGarmin ? .uploaded : .failed, note: message, updatedAt: now))
      case .wait:
        message = "Wartet auf die Aufzeichnung der Uhr – die Sätze werden ergänzt, sobald sie in Garmin Connect ist."
      case .none:
        break
      }
    }
    try? context.save()
    return message
  }

  /// Sätze in die Aufzeichnung schreiben: Original sichern, Nutzdaten bauen, PUT; bei abgelehntem Übungsnamen
  /// erneut nur mit Kategorien.
  static func enrich(
    _ record: GymSessionRecord, session: GymSession, activityID: Int64, garmin: GarminConnectSession,
    gym: GymSettings, now: Date
  ) async -> String {
    do {
      let path = GarminConnect.exerciseSetsPath(activityID: activityID)
      let original = try await garmin.data(path: path)
      let existing = try JSONValue(data: original)
      try backup(original, activityID: activityID)
      var result = GarminStrengthSync.payload(existing: existing, session: session, custom: gym.customExercises)
      do {
        _ = try await garmin.send(method: "PUT", path: path, json: JSONEncoder().encode(result.payload))
      } catch {
        result = GarminStrengthSync.payload(
          existing: existing, session: session, custom: gym.customExercises, useNames: false)
        _ = try await garmin.send(method: "PUT", path: path, json: JSONEncoder().encode(result.payload))
      }
      let text =
        "\(result.sets) Sätze in die Garmin-Aufzeichnung der Uhr geschrieben – eine Aktivität mit Kalorien, Puls und "
        + "Übungen."
      record.setGarmin(GarminLink(status: .enriched, activityID: activityID, note: text, updatedAt: now))
      return text
    } catch let error as GarminAPIError {
      record.setGarmin(GarminLink(status: .failed, activityID: activityID, note: error.message, updatedAt: now))
      return "Garmin: \(error.message)"
    } catch {
      record.setGarmin(
        GarminLink(status: .failed, activityID: activityID, note: error.localizedDescription, updatedAt: now))
      return "Garmin: \(error.localizedDescription)"
    }
  }

  /// Nur beim ersten Mal sichern – so bleibt die echte Aufzeichnung der Uhr wiederherstellbar.
  static func backup(_ data: Data, activityID: Int64) throws {
    let url = backupURL(activityID: activityID)
    guard !FileManager.default.fileExists(atPath: url.path) else { return }
    try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  /// Ursprüngliche Sätze der Uhr zurückschreiben.
  static func restore(_ record: GymSessionRecord, activityID: Int64, garmin: GarminConnectSession, now: Date = .now)
    async -> String
  {
    do {
      let data = try Data(contentsOf: backupURL(activityID: activityID))
      _ = try await garmin.send(
        method: "PUT", path: GarminConnect.exerciseSetsPath(activityID: activityID), json: data)
      // Ohne Verbindung: „Abgleichen“ steht wieder zur Wahl; die Sicherung bleibt erhalten.
      record.setGarmin(nil)
      return "Ursprüngliche Sätze der Uhr wiederhergestellt."
    } catch let error as GarminAPIError {
      return "Garmin: \(error.message)"
    } catch {
      return "Garmin: \(error.localizedDescription)"
    }
  }
}
