import CoachCore
import Foundation
import Observation

/// Freunde und Feed über den Worker (`worker/src/social.ts`). Nur mit eigenem Konto; geteilt wird nur, was die
/// Person ausdrücklich teilt (Training ohne Körperwerte, Mahlzeit, Meilenstein).
@Observable
final class SocialService {
  private(set) var friends = SocialFriends()
  private(set) var feed: [SocialPost] = []
  private(set) var hasMore = true
  private(set) var isLoading = false
  private(set) var lastError: String?

  private let ai: AIClient
  private let account: AccountService

  init(ai: AIClient, account: AccountService) {
    self.ai = ai
    self.account = account
  }

  var isAvailable: Bool { account.isSignedIn }
  var incomingCount: Int { friends.incoming.count }

  private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as: T.Type) async throws -> T {
    let data = try await ai.send(path: "v1/social/\(path)", method: "GET", query: query, auth: .session)
    return try JSONDecoder().decode(T.self, from: data)
  }

  @discardableResult
  private func send(_ path: String, method: String, body: (any Encodable)? = nil) async throws -> Data {
    let data = try body.map { try JSONEncoder().encode($0) } ?? Data("{}".utf8)
    return try await ai.send(
      path: "v1/social/\(path)", method: method, body: method == "GET" ? nil : data, auth: .session)
  }

  private static func escape(_ username: String) -> String {
    username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
  }

  // MARK: - Laden

  /// Freunde und erste Seite des Feeds.
  func refresh() async {
    guard isAvailable, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      friends = try await get("friends", as: SocialFriends.self)
      let page = try await get("feed", as: FeedPage.self).posts
      feed = page
      hasMore = page.count >= 30
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  func loadMore() async {
    guard isAvailable, hasMore, !isLoading, let last = feed.last?.date else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let before = String(Int64(last.timeIntervalSince1970 * 1000))
      let page = try await get("feed", query: [URLQueryItem(name: "before", value: before)], as: FeedPage.self).posts
      feed += page.filter { post in !feed.contains { $0.id == post.id } }
      hasMore = page.count >= 30
    } catch {
      lastError = error.localizedDescription
    }
  }

  private struct FeedPage: Decodable { let posts: [SocialPost] }
  private struct People: Decodable { let people: [SocialPerson] }
  private struct Created: Decodable { let post: SocialPost }
  private struct Comments: Decodable { let comments: [SocialComment] }

  func search(_ text: String) async throws -> [SocialPerson] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return [] }
    return try await get("search", query: [URLQueryItem(name: "q", value: query)], as: People.self).people
  }

  struct Profile: Decodable {
    let username: String
    let displayName: String
    let relation: SocialRelation
    let posts: [SocialPost]
  }

  func profile(_ username: String) async throws -> Profile {
    try await get("people/\(Self.escape(username))", as: Profile.self)
  }

  // MARK: - Freunde

  /// Anfragen oder eingehende Anfrage annehmen.
  func addFriend(_ username: String) async throws {
    try await send("friends/\(Self.escape(username))", method: "POST")
    await refresh()
  }

  /// Entfernen, ablehnen oder eigene Anfrage zurückziehen.
  func removeFriend(_ username: String) async throws {
    try await send("friends/\(Self.escape(username))", method: "DELETE")
    await refresh()
  }

  func block(_ username: String) async throws {
    try await send("blocks/\(Self.escape(username))", method: "POST")
    await refresh()
  }

  func unblock(_ username: String) async throws {
    try await send("blocks/\(Self.escape(username))", method: "DELETE")
  }

  // MARK: - Beiträge

  func share(workout: WorkoutShare) async throws {
    let data = try await send("posts", method: "POST", body: workout)
    insert(try JSONDecoder().decode(Created.self, from: data).post)
  }

  func share(meal: MealPostShare) async throws {
    let data = try await send("posts", method: "POST", body: meal)
    insert(try JSONDecoder().decode(Created.self, from: data).post)
  }

  private func insert(_ post: SocialPost) {
    feed.removeAll { $0.id == post.id }
    feed.insert(post, at: 0)
  }

  func delete(_ post: SocialPost) async throws {
    try await send("posts/\(post.id)", method: "DELETE")
    feed.removeAll { $0.id == post.id }
  }

  /// Gleiche Reaktion nochmals: zurücknehmen. Der Feed zeigt die Änderung sofort.
  func react(_ post: SocialPost, with reaction: SocialReaction) async {
    guard let index = feed.firstIndex(where: { $0.id == post.id }) else { return }
    let previous = feed[index]
    let removing = previous.myReaction == reaction.rawValue
    feed[index].myReaction = removing ? nil : reaction.rawValue
    feed[index].reactions += previous.myReaction == nil ? 1 : removing ? -1 : 0
    do {
      if removing {
        try await send("posts/\(post.id)/reaction", method: "DELETE")
      } else {
        try await send("posts/\(post.id)/reaction", method: "PUT", body: ["emoji": reaction.rawValue])
      }
    } catch {
      if let restore = feed.firstIndex(where: { $0.id == post.id }) { feed[restore] = previous }
      lastError = error.localizedDescription
    }
  }

  func comments(_ post: SocialPost) async throws -> [SocialComment] {
    try await get("posts/\(post.id)/comments", as: Comments.self).comments
  }

  func comment(_ post: SocialPost, text: String) async throws {
    try await send("posts/\(post.id)/comments", method: "POST", body: ["text": text])
    if let index = feed.firstIndex(where: { $0.id == post.id }) { feed[index].comments += 1 }
  }

  func deleteComment(_ comment: SocialComment, on post: SocialPost) async throws {
    try await send("comments/\(comment.id)", method: "DELETE")
    if let index = feed.firstIndex(where: { $0.id == post.id }) {
      feed[index].comments = max(0, feed[index].comments - 1)
    }
  }
}
