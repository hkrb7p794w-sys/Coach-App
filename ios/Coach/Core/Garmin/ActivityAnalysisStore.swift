import CoachCore
import Foundation

/// Ergebnisse der FIT-Auswertung als JSON-Datei im App-Support-Ordner (wenige KB, kein SwiftData-Modell nötig).
final class ActivityAnalysisStore {
  /// Einträge älter als das bleiben nicht liegen (Kopplung zeigt 60 Tage, Pace-Check 6 Wochen).
  static let keepDays = 90

  private let url: URL?
  private var memory: [Int64: ActivityAnalysis] = [:]

  /// `inMemory` für Vorschauen und Tests.
  init(inMemory: Bool = false) {
    if inMemory {
      url = nil
    } else {
      let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      url = folder?.appendingPathComponent("activity-analysis.json")
    }
  }

  func load() -> [Int64: ActivityAnalysis] {
    guard let url else { return memory }
    guard let data = try? Data(contentsOf: url),
      let list = try? JSONDecoder().decode([ActivityAnalysis].self, from: data)
    else { return [:] }
    return Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
  }

  func save(_ analyses: [Int64: ActivityAnalysis], today: CalendarDay) {
    let cutoff = today.adding(days: -Self.keepDays)
    let kept = analyses.filter { $0.value.day >= cutoff }
    guard let url else {
      memory = kept
      return
    }
    let list = kept.values.sorted { $0.id < $1.id }
    guard let data = try? JSONEncoder().encode(list) else { return }
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
  }
}
