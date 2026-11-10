import Foundation

/// Reiter „Aktivitäten“: eigene Trainings (vom Gerät, mit allen Details) und Beiträge der Freunde in einer Liste,
/// neueste oben. Ein eigenes Training, das geteilt wurde, erscheint einmal – mit den Reaktionen seines Beitrags.
public enum SocialTimeline {
  public struct Item: Equatable, Sendable, Identifiable {
    public var id: String
    public var date: Date
    /// Eigenes Training vom Gerät.
    public var entry: ActivityFeed.Entry?
    /// Beitrag aus dem Feed; bei `entry != nil` der dazugehörige eigene Beitrag.
    public var post: SocialPost?
  }

  /// Schlüssel, unter denen ein geteiltes Training gemerkt wird. Eine Gym-Einheit behält ihren Schlüssel, auch wenn
  /// sie später mit der Aufzeichnung der Uhr zu einer Zeile verschmilzt – sonst würde sie doppelt geteilt.
  public static func keys(_ entry: ActivityFeed.Entry) -> [String] {
    var keys = [entry.id]
    if let gym = entry.gym {
      let key = "g\(gym.id.uuidString)"
      if !keys.contains(key) { keys.append(key) }
    }
    return keys
  }

  public static func date(_ entry: ActivityFeed.Entry, timeZone: TimeZone = .current) -> Date {
    if entry.activity == nil, let gym = entry.gym { return gym.start }
    if let activity = entry.activity, let start = ActivityFeed.start(activity, timeZone: timeZone) { return start }
    if let gym = entry.gym { return gym.start }
    return ActivityFeed.localFormatter(timeZone).date(from: "\(entry.day.iso) 12:00:00") ?? .distantPast
  }

  /// - Parameters:
  ///   - shared: Schlüssel eines eigenen Trainings → ID des Beitrags dazu.
  ///   - oldest: Solange der Feed noch ältere Seiten hat, enden die eigenen Trainings am ältesten geladenen
  ///     Beitrag; sonst stünden sie vor Beiträgen, die erst nachgeladen werden.
  public static func merge(
    entries: [ActivityFeed.Entry], posts: [SocialPost], shared: [String: String], oldest: Date? = nil,
    timeZone: TimeZone = .current
  ) -> [Item] {
    let byID = Dictionary(posts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var used: Set<String> = []
    var items: [Item] = []
    for entry in entries {
      let when = date(entry, timeZone: timeZone)
      if let oldest, when < oldest { continue }
      let post = keys(entry).lazy.compactMap { shared[$0] }.compactMap { byID[$0] }.first
      if let post { used.insert(post.id) }
      items.append(Item(id: entry.id, date: when, entry: entry, post: post))
    }
    for post in posts where !used.contains(post.id) {
      items.append(Item(id: "p\(post.id)", date: post.date ?? .distantPast, entry: nil, post: post))
    }
    return items.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
  }

  /// Trainings, die „automatisch teilen“ jetzt teilt: nach dem Einschalten begonnen, höchstens drei Tage alt, noch
  /// nicht geteilt. Älteste zuerst, damit der Feed die richtige Reihenfolge behält; begrenzt je Durchlauf.
  public static func autoShareCandidates(
    entries: [ActivityFeed.Entry], shared: [String: String], since: Date, now: Date = .now, limit: Int = 3,
    timeZone: TimeZone = .current
  ) -> [ActivityFeed.Entry] {
    let earliest = max(since, now.addingTimeInterval(-3 * 24 * 3600))
    let fresh = entries.filter { entry in
      let when = date(entry, timeZone: timeZone)
      return when >= earliest && when <= now && !keys(entry).contains { shared[$0] != nil }
    }
    return Array(fresh.sorted { date($0, timeZone: timeZone) < date($1, timeZone: timeZone) }.prefix(limit))
  }
}
