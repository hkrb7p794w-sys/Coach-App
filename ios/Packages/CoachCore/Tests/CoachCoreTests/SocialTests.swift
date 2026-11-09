import Foundation
import Testing

@testable import CoachCore

struct SocialTests {
  @Test func decodesWorkerFeed() throws {
    let json = #"""
      {"posts": [{"id": "p1", "kind": "workout", "createdAt": "2026-11-09T12:00:00.000Z",
        "author": {"username": "lena", "displayName": "Lena"}, "mine": false,
        "payload": {"sport": "run", "title": "Lockerer Lauf", "durationMin": 45, "distanceKm": 8.2},
        "reactions": 2, "myReaction": "🔥", "topReactions": "🔥💪", "comments": 1},
        {"id": "p2", "kind": "zukunft", "createdAt": "2026-11-09T11:00:00.000Z",
        "author": {"username": "tom", "displayName": "Tom"}, "mine": true, "payload": {},
        "reactions": 0, "myReaction": null, "topReactions": "", "comments": 0}]}
      """#
    struct Feed: Decodable { let posts: [SocialPost] }
    let posts = try JSONDecoder().decode(Feed.self, from: Data(json.utf8)).posts
    #expect(posts[0].headline == "Lockerer Lauf")
    #expect(posts[0].facts == "45 min · 8,2 km")
    #expect(posts[0].symbol == "figure.run")
    #expect(posts[0].date != nil)
    #expect(posts[1].kind == .unknown)
  }

  @Test func gymShareHasNoBodyValues() throws {
    let start = Date(timeIntervalSince1970: 1_793_500_000)
    let squat = LoggedExercise(
      exerciseID: "kniebeuge", name: "Kniebeuge", group: .legs,
      sets: (0..<3).map { _ in LoggedSet(reps: 5, weightKg: 100, done: true) })
    let session = GymSession(
      workoutKey: nil, title: "Beine", start: start, end: start.addingTimeInterval(3_000), exercises: [squat])
    let share = WorkoutShare.gym(session, records: ["Kniebeuge: 100 kg × 5"])
    #expect(share.sport == "strength")
    #expect(share.durationMin == 50)
    #expect(share.sets == 3)
    #expect(share.volumeKg == 1_500)
    #expect(share.exercises == ["Kniebeuge"])
    let text = String(decoding: try JSONEncoder().encode(share), as: UTF8.self)
    #expect(!text.contains("weight\""))
    #expect(!text.contains("heart"))
  }

  @Test func activityShareDropsHeartRateAndCalories() throws {
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.name = "Morgenlauf"
    run.durationSeconds = 2_710
    run.distanceMeters = 8_249
    run.averageHeartRate = 150
    run.calories = 600
    run.elevationGain = 42
    let share = WorkoutShare.activity(run)
    #expect(share == {
      var expected = WorkoutShare(sport: "run", title: "Morgenlauf")
      expected.durationMin = 45
      expected.distanceKm = 8.2
      expected.elevationM = 42
      return expected
    }())
    let text = String(decoding: try JSONEncoder().encode(share), as: UTF8.self)
    #expect(!text.contains("150"))
    #expect(!text.contains("600"))
    var walk = GarminActivity(id: 2)
    walk.typeKey = "walking"
    #expect(WorkoutShare.activity(walk).title == "Spaziergang")
  }

  @Test func relativeTimes() {
    let now = Date(timeIntervalSince1970: 1_793_500_000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    #expect(SocialFormat.relative(now.addingTimeInterval(-30), now: now, calendar: calendar) == "gerade eben")
    #expect(SocialFormat.relative(now.addingTimeInterval(-300), now: now, calendar: calendar) == "vor 5 Min.")
  }
}
