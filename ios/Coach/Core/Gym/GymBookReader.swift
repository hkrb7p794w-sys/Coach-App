import CoachCore
import Foundation
import SQLite3
import SwiftData

/// Liest ein GymBook-Backup (SQLite) nur lesend und übernimmt den Verlauf als Krafteinheiten.
enum GymBookReader {
  enum ReadError: LocalizedError {
    case open(String)
    case query(String)

    var errorDescription: String? {
      switch self {
      case .open(let message): "Die Datei ließ sich nicht öffnen (\(message)). Ist es ein GymBook-Backup?"
      case .query(let message): "Die Datei enthält kein GymBook-Protokoll (\(message))."
      }
    }
  }

  static let query = """
    SELECT l.ZDAY, l.ZTIME, e.ZNAME, e.ZTARGETREGION, e.ZTARGETMUSCLESPRIMARY, e.ZEQUIPMENT,
           l.ZFREQUENCYVALUE, l.ZFREQUENCYUNIT, l.ZQUANTITYVALUE, l.ZQUANTITYUNIT, l.ZSKIPPED, w.ZNAME
    FROM ZEXERCISELOG l
    JOIN ZEXERCISE e ON e.Z_PK = l.ZEXERCISE
    LEFT JOIN ZWORKOUT w ON w.Z_PK = l.ZWORKOUT
    """

  static func rows(at url: URL) throws -> [GymBookImport.LogRow] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
      throw ReadError.open(String(cString: sqlite3_errstr(SQLITE_CANTOPEN)))
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw ReadError.query(String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }

    func text(_ column: Int32) -> String? {
      guard sqlite3_column_type(statement, column) != SQLITE_NULL, let value = sqlite3_column_text(statement, column)
      else { return nil }
      return String(cString: value)
    }
    func number(_ column: Int32) -> Double? {
      sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    var rows: [GymBookImport.LogRow] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      guard let day = text(0), let name = text(2) else { continue }
      rows.append(
        GymBookImport.LogRow(
          day: day, secondsOfDay: number(1) ?? 0, exercise: name, region: text(3), muscles: text(4),
          equipment: text(5), frequency: number(6), frequencyUnit: text(7), quantity: number(8),
          quantityUnit: text(9), skipped: (number(10) ?? 0) != 0, workout: text(11)))
    }
    return rows
  }

  /// Übernimmt die Einheiten, die noch nicht da sind (gleiche GymBook-Einheit oder schon in der App erfasster Tag),
  /// und legt fehlende Übungen als eigene Übungen an. Gibt eine kurze Zusammenfassung zurück.
  static func importBackup(at url: URL, context: ModelContext, settings: CoachSettings) throws -> String {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    // Kopie im Temp-Ordner: SQLite braucht eine echte Datei, und das Original bleibt unberührt.
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent("gymbook-import.sqlite")
    try? FileManager.default.removeItem(at: copy)
    try FileManager.default.copyItem(at: url, to: copy)
    defer { try? FileManager.default.removeItem(at: copy) }

    let result = GymBookImport.sessions(try rows(at: copy), custom: settings.gym.customExercises)
    let existing = ((try? context.fetch(FetchDescriptor<GymSessionRecord>())) ?? []).compactMap(\.session)
    let knownKeys = Set(existing.compactMap(\.workoutKey))
    let appDays = Set(existing.filter { !($0.workoutKey ?? "").hasPrefix("gymbook:") }.map(\.day))
    let fresh = result.sessions.filter { !knownKeys.contains($0.workoutKey ?? "") && !appDays.contains($0.day) }
    for session in fresh { context.insert(GymSessionRecord(session: session)) }
    let added = fresh.count
    settings.gym.customExercises += result.newCustom
    try context.save()
    let sets = result.sessions.reduce(0) { $0 + $1.doneSetCount }
    var text = "\(added) Einheiten übernommen (\(result.sessions.count) im Backup, \(sets) Sätze)"
    if !result.newCustom.isEmpty { text += ", \(result.newCustom.count) Übungen neu angelegt" }
    if added < result.sessions.count { text += ", \(result.sessions.count - added) schon vorhanden" }
    return text + "."
  }
}
