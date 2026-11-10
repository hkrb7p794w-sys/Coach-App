import CoachCore
import Foundation

/// Vollständige Aktivitätsberichte (Runden, Splits, Verlauf) als JSON-Datei im App-Support-Ordner sowie die
/// Dateien der Uhr (FIT) im Cache-Ordner. Die Berichte bleiben erhalten, auch wenn iOS den Cache leert.
final class ActivityReportStore {
  /// Ältere Berichte bleiben nicht liegen (rund 15 KB je Aktivität).
  static let keepDays = 180

  private let url: URL?
  private var memory: [Int64: ActivityReport] = [:]
  private var cache: [Int64: ActivityReport]?

  /// `inMemory` für Vorschauen und Tests.
  init(inMemory: Bool = false) {
    if inMemory {
      url = nil
    } else {
      let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      url = folder?.appendingPathComponent("activity-reports.json")
    }
  }

  func load() -> [Int64: ActivityReport] {
    if let cache { return cache }
    guard let url else { return memory }
    guard let data = try? Data(contentsOf: url),
      let list = try? JSONDecoder().decode([ActivityReport].self, from: data)
    else { return [:] }
    let loaded = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    cache = loaded
    return loaded
  }

  func report(_ id: Int64) -> ActivityReport? { load()[id] }

  func save(_ reports: [Int64: ActivityReport], today: CalendarDay) {
    let cutoff = today.adding(days: -Self.keepDays)
    let kept = reports.filter { $0.value.day >= cutoff }
    cache = kept
    guard let url else {
      memory = kept
      return
    }
    let list = kept.values.sorted { $0.id < $1.id }
    guard let data = try? JSONEncoder().encode(list) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }

  /// Einen Bericht ergänzen (z. B. nach dem Öffnen einer älteren Aktivität).
  func store(_ report: ActivityReport, today: CalendarDay) {
    var all = load()
    all[report.id] = report
    save(all, today: today)
  }

  // MARK: - Dateien der Uhr

  static func fileURL(_ id: Int64) -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("fit", isDirectory: true).appendingPathComponent("\(id).fit")
  }

  static func cachedFile(_ id: Int64) -> Data? {
    fileURL(id).flatMap { try? Data(contentsOf: $0) }
  }

  static func cache(_ data: Data, id: Int64) {
    guard let url = fileURL(id) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url)
  }
}
