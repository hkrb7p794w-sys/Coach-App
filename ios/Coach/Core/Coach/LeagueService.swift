import CoachCore
import Foundation
import Observation
import UIKit

/// Rangliste über den eigenen Worker (`worker/src/league.ts`). Gesendet werden nur Anzeigename, Symbol und Punkte.
@Observable
final class LeagueService {
  private(set) var members: [LeagueEntry] = []
  private(set) var lastError: String?
  private(set) var isLoading = false
  private(set) var lastUpdate: Date?

  private let ai: AIClient
  private let settings: CoachSettings

  init(ai: AIClient, settings: CoachSettings) {
    self.ai = ai
    self.settings = settings
  }

  var canUse: Bool { ai.isConfigured }

  /// Einladungslink mit Worker-Adresse, App-Token und Code.
  var inviteURL: URL? {
    guard settings.league.isJoined, let token = ai.appToken, let base = AIClient.normalizedURL(ai.workerURL)
    else { return nil }
    return LeagueInvite(workerURL: base.absoluteString, token: token, code: settings.league.code).url
  }

  /// Eigenen Stand hochladen und die Rangliste holen.
  func sync(summary: MotivationSummary) async {
    let league = settings.league
    guard league.isJoined, ai.isConfigured, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    let name = league.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let avatar = settings.companion.isActive ? settings.companion.kind.symbol : "person.fill"
    let entry = LeagueEntry(
      id: league.memberID, name: name.isEmpty ? "Ich" : name, avatar: avatar, summary: summary)
    do {
      let body = try JSONEncoder().encode(entry)
      _ = try await ai.send(path: "v1/league/\(league.code)/members/\(league.memberID)", method: "PUT", body: body)
      let data = try await ai.send(
        path: "v1/league/\(league.code)", method: "GET",
        query: [URLQueryItem(name: "week", value: summary.week.monday.iso)])
      members = try JSONDecoder().decode(Response.self, from: data).members
      lastError = nil
      lastUpdate = .now
    } catch {
      lastError = error.localizedDescription
    }
  }

  func create() {
    settings.league.code = LeagueCode.generate()
    members = []
  }

  func join(code: String) {
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard LeagueCode.isValid(trimmed) else { return }
    settings.league.code = trimmed
    members = []
  }

  /// Einladung annehmen: Worker übernehmen (falls angegeben) und beitreten.
  func accept(_ invite: LeagueInvite) throws {
    try ai.configure(url: invite.workerURL, token: invite.token)
    join(code: invite.code)
  }

  func leave() async {
    let league = settings.league
    if league.isJoined, ai.isConfigured {
      _ = try? await ai.send(path: "v1/league/\(league.code)/members/\(league.memberID)", method: "DELETE")
    }
    settings.league.code = ""
    members = []
  }

  private struct Response: Decodable {
    let members: [LeagueEntry]
  }
}

/// Foto des Begleiters, lokal in Application Support (nicht in der Cloud).
enum CompanionPhoto {
  static var url: URL? {
    try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    )
    .appending(path: "companion.jpg")
  }

  static func load() -> UIImage? {
    guard let url, let data = try? Data(contentsOf: url) else { return nil }
    return UIImage(data: data)
  }

  /// Verkleinert auf höchstens 600 Pixel und speichert als JPEG.
  static func save(_ data: Data) throws {
    guard let url, let image = UIImage(data: data) else { return }
    let scale = min(1, 600 / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    try resized.jpegData(compressionQuality: 0.8)?.write(to: url, options: .atomic)
  }

  static func remove() {
    if let url { try? FileManager.default.removeItem(at: url) }
  }
}
