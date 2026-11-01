import Foundation
import Testing

@testable import CoachCore

struct GarminStrengthSyncTests {
  let utc = TimeZone(identifier: "UTC") ?? .current
  /// 01.11.2026, 10:00 UTC.
  let start = Date(timeIntervalSince1970: 1_793_527_200)

  func activity(_ id: Int64, minutesAfter: Double, heartRate: Double? = 120, sport: String = "strength_training")
    -> GarminActivity
  {
    var activity = GarminActivity(id: id)
    activity.typeKey = sport
    let date = start.addingTimeInterval(minutesAfter * 60)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = utc
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    activity.startLocal = formatter.string(from: date)
    activity.durationSeconds = 3_600
    activity.averageHeartRate = heartRate
    activity.calories = 300
    return activity
  }

  var session: GymSession {
    var session = GymSession(
      workoutKey: nil, title: "Push", start: start, end: start.addingTimeInterval(3_600),
      exercises: [
        LoggedExercise(
          exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
          sets: [
            LoggedSet(reps: 10, weightKg: 40, kind: .warmup),
            LoggedSet(reps: 8, weightKg: 80),
            LoggedSet(reps: 8, weightKg: 80, done: false),
          ]),
        LoggedExercise(
          exerciseID: "plank", name: "Plank", group: .core, sets: [LoggedSet(reps: 45, weightKg: 0)]),
        LoggedExercise(
          exerciseID: "klimmzug", name: "Klimmzug", group: .back, sets: [LoggedSet(reps: 6, weightKg: -20)]),
      ])
    session.garmin = GarminLink(status: .pending, updatedAt: start)
    return session
  }

  func watchSets(_ count: Int) -> JSONValue {
    .object([
      "activityId": .number(123),
      "exerciseSets": .array(
        (0..<count).flatMap { index -> [JSONValue] in
          [
            .object([
              "setType": .string("ACTIVE"), "duration": .number(40),
              "startTime": .string("2026-11-01T10:0\(index):00.0"), "repetitionCount": .null,
              "exercises": .array([]), "weight": .null,
            ]),
            .object(["setType": .string("REST"), "duration": .number(20), "startTime": .string("2026-11-01T10:0\(index):40.0")]),
          ]
        }),
    ])
  }

  @Test func fillsWatchSetsInOrder() throws {
    let result = GarminStrengthSync.payload(existing: watchSets(5), session: session)
    #expect(result.mode == .fill)
    #expect(result.sets == 4)
    let sets = try #require(result.payload["exerciseSets"]?.arrayValue)
    #expect(sets.count == 10)
    #expect(result.payload["activityId"]?.doubleValue == 123)
    // Aufwärmsatz, Arbeitssatz, Plank (ohne Wiederholungen), Klimmzug mit Unterstützung (ohne Gewicht).
    #expect(sets[0]["repetitionCount"]?.doubleValue == 10)
    #expect(sets[0]["weight"]?.doubleValue == 40_000)
    #expect(sets[0]["exercises"]?.arrayValue?.first?["category"]?.stringValue == "BENCH_PRESS")
    #expect(sets[0]["exercises"]?.arrayValue?.first?["name"]?.stringValue == "BARBELL_BENCH_PRESS")
    #expect(sets[1]["setType"]?.stringValue == "REST")
    #expect(sets[2]["weight"]?.doubleValue == 80_000)
    #expect(sets[4]["repetitionCount"] == .null)
    #expect(sets[4]["exercises"]?.arrayValue?.first?["name"]?.stringValue == "PLANK")
    #expect(sets[6]["weight"] == .null)
    #expect(sets[6]["repetitionCount"]?.doubleValue == 6)
    // Überzählige Abschnitte der Uhr bleiben, wie sie sind; die Zeit der Uhr bleibt erhalten.
    #expect(sets[8]["repetitionCount"] == .null)
    #expect(sets[0]["duration"]?.doubleValue == 40)
  }

  @Test func replacesWhenWatchGroupedSets() throws {
    let result = GarminStrengthSync.payload(existing: watchSets(2), session: session, useNames: false)
    #expect(result.mode == .replace)
    let sets = try #require(result.payload["exerciseSets"]?.arrayValue)
    #expect(sets.count == 4)
    #expect(sets.allSatisfy { $0["setType"]?.stringValue == "ACTIVE" })
    #expect(sets[0]["startTime"]?.stringValue == "2026-11-01T10:00:00.0")
    #expect(sets[3]["messageIndex"]?.doubleValue == 3)
    #expect(sets[2]["duration"]?.doubleValue == 45)
    #expect(sets[0]["exercises"]?.arrayValue?.first?["name"] == .null)
    #expect(!GarminStrengthSync.isEnriched(watchSets(2)))
    #expect(GarminStrengthSync.isEnriched(result.payload))
  }

  @Test func replaceWithoutWatchSetsUsesSessionTime() throws {
    let result = GarminStrengthSync.payload(existing: .object(["exerciseSets": .array([])]), session: session)
    let sets = try #require(result.payload["exerciseSets"]?.arrayValue)
    #expect(sets.first?["startTime"]?.stringValue == "2026-11-01T10:00:00.0")
    #expect(sets.last?["startTime"]?.stringValue == "2026-11-01T10:45:00.0")
  }

  @Test func matchesWatchRecordingNotUploadOrLinked() {
    let upload = activity(1, minutesAfter: 2, heartRate: nil)
    let watch = activity(2, minutesAfter: 20)
    let far = activity(3, minutesAfter: 200)
    let run = activity(4, minutesAfter: 1, sport: "running")
    let match = GarminStrengthSync.match(
      session: session, activities: [upload, watch, far, run], linked: [], timeZone: utc)
    #expect(match?.id == 2)
    #expect(
      GarminStrengthSync.match(session: session, activities: [watch, far], linked: [2], timeZone: utc) == nil)
    #expect(
      GarminStrengthSync.match(session: session, activities: [upload], linked: [], timeZone: utc)?.id == 1)
    var health = activity(-5, minutesAfter: 0)
    health.typeKey = "strength_training"
    #expect(GarminStrengthSync.match(session: session, activities: [health], linked: [], timeZone: utc) == nil)
  }

  @Test func actionWaitsThenFallsBack() {
    let watch = activity(2, minutesAfter: 5)
    let end = start.addingTimeInterval(3_600)
    #expect(
      GarminStrengthSync.action(
        for: session, activities: [watch], linked: [], now: end, fallbackUpload: true, timeZone: utc)
        == .enrich(activityID: 2))
    #expect(
      GarminStrengthSync.action(for: session, activities: [], linked: [], now: end, fallbackUpload: true) == .wait)
    let later = end.addingTimeInterval(GarminStrengthSync.fallbackDelay)
    #expect(
      GarminStrengthSync.action(for: session, activities: [], linked: [], now: later, fallbackUpload: true) == .upload)
    #expect(
      GarminStrengthSync.action(for: session, activities: [], linked: [], now: later, fallbackUpload: false) == .wait)
    var old = session
    old.garmin = nil
    #expect(
      GarminStrengthSync.action(for: old, activities: [watch], linked: [], now: end, fallbackUpload: true) == .none)
  }

  @Test func namesForEveryExercise() {
    #expect(GarminStrengthSync.garminName(for: "crunch_kabel").category == "CRUNCH")
    #expect(GarminStrengthSync.garminName(for: "crunch_kabel").name == "CABLE_CRUNCH")
    #expect(GarminStrengthSync.garminName(for: "beinstrecken").category == "UNKNOWN")
    for exercise in ExerciseLibrary.all {
      #expect(GarminStrengthSync.names[exercise.id] != nil, "\(exercise.id)")
    }
  }

  @Test func duplicateUploadIsIgnored() {
    let upload = activity(1, minutesAfter: 3, heartRate: nil)
    let watch = activity(2, minutesAfter: 0)
    let lone = activity(3, minutesAfter: 600, heartRate: nil)
    #expect(StrengthDuplicates.redundant([upload, watch, lone], timeZone: utc) == [1])
    let entries = ActivityFeed.entries(activities: [upload, watch], gym: [], timeZone: utc)
    #expect(entries.map(\.id) == ["a2"])
  }

  @Test func linkSurvivesCodingAndOldDataDecodes() throws {
    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(GymSession.self, from: data)
    #expect(decoded.garmin?.status == .pending)
    var old = session
    old.garmin = nil
    let oldDecoded = try JSONDecoder().decode(GymSession.self, from: JSONEncoder().encode(old))
    #expect(oldDecoded.garmin == nil)
  }
}
