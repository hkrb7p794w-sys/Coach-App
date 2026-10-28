import Foundation

/// Mahlzeit, die ohne Netz nicht ausgewertet werden konnte: Beschreibung in den UserDefaults, Foto als Datei im
/// Ordner „Application Support/pending-meals“. Wird ausgewertet, sobald die App wieder online ist.
struct PendingAnalysis: Codable, Equatable, Identifiable {
  static let key = "nutrition.pendingAnalyses"

  var id = UUID()
  var created = Date.now
  var text: String
  var hasPhoto: Bool

  init(text: String, photo: Data?) {
    self.text = text
    hasPhoto = photo != nil
    if let photo {
      try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
      try? photo.write(to: photoURL, options: .atomic)
    }
  }

  static var folder: URL {
    URL.applicationSupportDirectory.appending(path: "pending-meals", directoryHint: .isDirectory)
  }

  var photoURL: URL { Self.folder.appending(path: "\(id.uuidString).jpg") }

  var photo: Data? { hasPhoto ? try? Data(contentsOf: photoURL) : nil }

  func deletePhoto() {
    try? FileManager.default.removeItem(at: photoURL)
  }

  static func load(defaults: UserDefaults = .standard) -> [PendingAnalysis] {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingAnalysis].self, from: $0) } ?? []
  }

  static func save(_ items: [PendingAnalysis], defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
  }
}
