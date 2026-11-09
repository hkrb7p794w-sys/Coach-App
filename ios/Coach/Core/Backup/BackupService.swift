import CoachCore
import Foundation
import SwiftData

/// Datensicherung: erstellt eine `AppBackup`-Datei aus UserDefaults und SwiftData, spielt sie zusammenführend ein
/// und sichert auf Wunsch einmal am Tag automatisch in einen selbst gewählten Ordner (z. B. iCloud Drive). Der Ordner
/// liegt außerhalb der App, deshalb überlebt die Sicherung auch das Löschen der App.
@MainActor
enum BackupService {
  static let folderBookmarkKey = "backup.folderBookmark"
  static let lastAutoKey = "backup.lastAuto"
  static let lastErrorKey = "backup.lastError"

  struct RestoreResult: Equatable {
    var gym = 0
    var meals = 0
    var foods = 0
    var settings = 0

    var text: String {
      "\(gym) Krafteinheiten, \(meals) Mahlzeiten und \(foods) Lebensmittel ergänzt, "
        + "\(settings) Einstellungen übernommen."
    }
  }

  // MARK: - Erstellen

  static func make(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) throws -> AppBackup {
    var settings: [String: AppBackup.Value] = [:]
    for (key, object) in defaults.dictionaryRepresentation() where AppBackup.isBackedUp(key: key) {
      if let value = value(of: object) { settings[key] = value }
    }
    let gym = try context.fetch(FetchDescriptor<GymSessionRecord>()).map {
      AppBackup.Gym(
        id: $0.id, payload: $0.payload, savedToHealth: $0.savedToHealth, uploadedToGarmin: $0.uploadedToGarmin)
    }
    let meals = try context.fetch(FetchDescriptor<MealRecord>()).map {
      AppBackup.Meal(
        id: $0.id, dayKey: $0.dayKey, createdAt: $0.createdAt, category: $0.categoryRaw, title: $0.title,
        hint: $0.hint, items: $0.itemsPayload)
    }
    let foods = try context.fetch(FetchDescriptor<FoodRecord>()).map {
      AppBackup.Food(key: $0.key, name: $0.name, payload: $0.payload, lastUsed: $0.lastUsed, useCount: $0.useCount)
    }
    return AppBackup(createdAt: now, settings: settings, gym: gym, meals: meals, foods: foods)
  }

  /// Wert aus UserDefaults in eine typisierte Form (Wahrheitswerte und Zahlen sind beide `NSNumber`).
  private static func value(of object: Any) -> AppBackup.Value? {
    switch object {
    case let data as Data: return .data(data)
    case let string as String: return .string(string)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
      return CFNumberIsFloatType(number) ? .double(number.doubleValue) : .int(number.intValue)
    default: return nil
    }
  }

  /// Sicherung als Datei im temporären Ordner (zum Teilen bzw. Sichern in „Dateien“).
  static func temporaryFile(context: ModelContext, defaults: UserDefaults = .standard) throws -> URL {
    let backup = try make(context: context, defaults: defaults)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let url = FileManager.default.temporaryDirectory
      .appending(path: "IronLudi-Sicherung-\(formatter.string(from: backup.createdAt)).json")
    try backup.encoded().write(to: url, options: .atomic)
    return url
  }

  /// Schreibt in den Ordner; die bisherige Sicherung bleibt als „…-vorher.json“ erhalten.
  @discardableResult
  static func write(_ backup: AppBackup, to folder: URL) throws -> URL {
    let manager = FileManager.default
    let file = folder.appending(path: AppBackup.fileName)
    let previous = folder.appending(path: AppBackup.previousFileName)
    if manager.fileExists(atPath: file.path) {
      try? manager.removeItem(at: previous)
      try? manager.moveItem(at: file, to: previous)
    }
    try backup.encoded().write(to: file, options: .atomic)
    return file
  }

  // MARK: - Einspielen

  static func read(_ url: URL) throws -> AppBackup {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    return try AppBackup.decode(try Data(contentsOf: url))
  }

  /// Führt zusammen: Krafteinheiten und Mahlzeiten über ihre ID, Lebensmittel über ihren Schlüssel – Vorhandenes
  /// bleibt unverändert. Einstellungen werden ersetzt; sie gelten erst nach einem Neustart der App.
  static func restore(
    _ backup: AppBackup, context: ModelContext, defaults: UserDefaults = .standard
  ) throws -> RestoreResult {
    var result = RestoreResult()

    let gymIDs = Set(try context.fetch(FetchDescriptor<GymSessionRecord>()).map(\.id))
    for entry in AppBackup.missing(backup.gym, key: \.id, existing: gymIDs) {
      guard let session = try? JSONDecoder().decode(GymSession.self, from: entry.payload) else { continue }
      let record = GymSessionRecord(session: session, savedToHealth: entry.savedToHealth)
      record.id = entry.id
      record.payload = entry.payload
      record.uploadedToGarmin = entry.uploadedToGarmin
      context.insert(record)
      result.gym += 1
    }

    let mealIDs = Set(try context.fetch(FetchDescriptor<MealRecord>()).map(\.id))
    for entry in AppBackup.missing(backup.meals, key: \.id, existing: mealIDs) {
      guard let day = CalendarDay(iso: entry.dayKey),
        let items = try? JSONDecoder().decode([MealItem].self, from: entry.items)
      else { continue }
      let record = MealRecord(
        day: day, category: MealCategory(rawValue: entry.category) ?? .other, title: entry.title, hint: entry.hint,
        items: items, at: entry.createdAt)
      record.id = entry.id
      record.itemsPayload = entry.items
      context.insert(record)
      result.meals += 1
    }

    let foodKeys = Set(try context.fetch(FetchDescriptor<FoodRecord>()).map(\.key))
    for entry in AppBackup.missing(backup.foods, key: \.key, existing: foodKeys) {
      guard let item = try? JSONDecoder().decode(MealItem.self, from: entry.payload) else { continue }
      let record = FoodRecord(item: item)
      record.key = entry.key
      record.name = entry.name
      record.payload = entry.payload
      record.lastUsed = entry.lastUsed
      record.useCount = entry.useCount
      context.insert(record)
      result.foods += 1
    }
    try context.save()

    for (key, value) in backup.settings where AppBackup.isBackedUp(key: key) {
      switch value {
      case .data(let data): defaults.set(data, forKey: key)
      case .string(let string): defaults.set(string, forKey: key)
      case .bool(let bool): defaults.set(bool, forKey: key)
      case .int(let int): defaults.set(int, forKey: key)
      case .double(let double): defaults.set(double, forKey: key)
      }
      result.settings += 1
    }
    return result
  }

  // MARK: - Automatisch

  static func setFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    defaults.set(bookmark, forKey: folderBookmarkKey)
    defaults.removeObject(forKey: lastAutoKey)
    defaults.removeObject(forKey: lastErrorKey)
  }

  static func clearFolder(defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: folderBookmarkKey)
    defaults.removeObject(forKey: lastAutoKey)
    defaults.removeObject(forKey: lastErrorKey)
  }

  static func folder(defaults: UserDefaults = .standard) -> URL? {
    guard let bookmark = defaults.data(forKey: folderBookmarkKey) else { return nil }
    var stale = false
    guard
      let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    else { return nil }
    if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      defaults.set(fresh, forKey: folderBookmarkKey)
    }
    return url
  }

  /// Sichert in den gewählten Ordner. `force`: auch wenn die letzte Sicherung noch frisch ist.
  @discardableResult
  static func backupToFolder(
    context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now, force: Bool = false
  ) -> Bool {
    guard let folder = folder(defaults: defaults) else { return false }
    guard force || AppBackup.isDue(last: defaults.object(forKey: lastAutoKey) as? Date, now: now) else {
      return false
    }
    let access = folder.startAccessingSecurityScopedResource()
    defer { if access { folder.stopAccessingSecurityScopedResource() } }
    do {
      try write(make(context: context, defaults: defaults, now: now), to: folder)
      defaults.set(now, forKey: lastAutoKey)
      defaults.removeObject(forKey: lastErrorKey)
      return true
    } catch {
      defaults.set(error.localizedDescription, forKey: lastErrorKey)
      return false
    }
  }
}
