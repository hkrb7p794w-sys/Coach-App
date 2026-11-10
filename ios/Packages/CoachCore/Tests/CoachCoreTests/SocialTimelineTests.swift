import Foundation
import Testing

@testable import CoachCore

struct SocialTimelineTests {
  let utc = TimeZone(identifier: "UTC") ?? .gmt
  /// 10.11.2026, 12:00 UTC.
  let now = Date(timeIntervalSince1970: 1_794_312_000)

  private func run(_ id: Int64, _ start: String) -> GarminActivity {
    var activity = GarminActivity(id: id)
    activity.typeKey = "running"
    activity.name = "Lauf \(id)"
    activity.startLocal = start
    return activity
  }

  private func posts(_ rows: [(id: String, at: String, mine: Bool)]) throws -> [SocialPost] {
    let items = rows.map { row in
      """
      {"id": "\(row.id)", "kind": "workout", "createdAt": "\(row.at)",
       "author": {"username": "u", "displayName": "U"}, "mine": \(row.mine),
       "payload": {"sport": "run", "title": "Lauf"}, "reactions": 1, "myReaction": null,
       "topReactions": "🔥", "comments": 0}
      """
    }
    return try JSONDecoder().decode([SocialPost].self, from: Data("[\(items.joined(separator: ","))]".utf8))
  }

  @Test func ownAndFriendsNewestFirstWithoutDuplicates() throws {
    let gym = ActivityFeed.GymItem(
      id: UUID(), title: "Push", start: now.addingTimeInterval(-3600), minutes: 50, sets: 12, volumeKg: 4000)
    let entries = ActivityFeed.entries(
      activities: [run(1, "2026-11-09 18:00:00"), run(2, "2026-11-08 07:00:00")], gym: [gym], timeZone: utc)
    let feed = try posts([
      (id: "friend", at: "2026-11-09T20:00:00.000Z", mine: false),
      (id: "mine", at: "2026-11-09T18:30:00.000Z", mine: true),
    ])
    let items = SocialTimeline.merge(entries: entries, posts: feed, shared: ["a1": "mine"], timeZone: utc)
    #expect(items.map(\.id) == ["g\(gym.id.uuidString)", "pfriend", "a1", "a2"])
    // Der eigene geteilte Lauf steht einmal da und trägt die Reaktionen seines Beitrags.
    #expect(items[2].post?.id == "mine")
    #expect(items[3].post == nil)
    #expect(items[1].entry == nil)
  }

  @Test func ownEntriesStopAtOldestLoadedPost() throws {
    let entries = ActivityFeed.entries(
      activities: [run(1, "2026-11-09 18:00:00"), run(2, "2026-10-01 07:00:00")], gym: [], timeZone: utc)
    let feed = try posts([(id: "friend", at: "2026-11-05T20:00:00.000Z", mine: false)])
    let oldest = try #require(feed[0].date)
    let items = SocialTimeline.merge(entries: entries, posts: feed, shared: [:], oldest: oldest, timeZone: utc)
    #expect(items.map(\.id) == ["a1", "pfriend"])
    #expect(SocialTimeline.merge(entries: entries, posts: feed, shared: [:], timeZone: utc).count == 3)
  }

  @Test func autoShareOnlyNewUnsharedTrainings() {
    let gym = ActivityFeed.GymItem(
      id: UUID(), title: "Pull", start: now.addingTimeInterval(-2 * 3600), minutes: 45, sets: 10, volumeKg: 3000)
    let entries = ActivityFeed.entries(
      activities: [
        run(1, "2026-11-10 08:00:00"), run(2, "2026-11-09 08:00:00"), run(3, "2026-11-08 08:00:00"),
        run(4, "2026-11-01 08:00:00"),
      ], gym: [gym], timeZone: utc)
    // Eingeschaltet am 08.11. um 12 Uhr: der Lauf vom Morgen davor und der alte bleiben privat.
    let since = now.addingTimeInterval(-2 * 24 * 3600)
    let candidates = SocialTimeline.autoShareCandidates(
      entries: entries, shared: ["a2": "p"], since: since, now: now, timeZone: utc)
    #expect(candidates.map(\.id) == ["a1", "g\(gym.id.uuidString)"])
    // Die Gym-Einheit gilt auch dann als geteilt, wenn sie später mit der Uhr-Aufzeichnung verschmilzt.
    let shared = ["g\(gym.id.uuidString)": "p2", "a1": "p3", "a2": "p"]
    #expect(
      SocialTimeline.autoShareCandidates(entries: entries, shared: shared, since: since, now: now, timeZone: utc)
        .isEmpty)
    let many = (10..<20).map { run($0, "2026-11-10 09:\($0):00") }
    let limited = SocialTimeline.autoShareCandidates(
      entries: ActivityFeed.entries(activities: many, gym: [], timeZone: utc), shared: [:], since: since, now: now,
      timeZone: utc)
    #expect(limited.map(\.id) == ["a10", "a11", "a12"])
  }
}
