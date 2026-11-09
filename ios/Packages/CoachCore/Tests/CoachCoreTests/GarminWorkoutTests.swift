import Foundation
import Testing

@testable import CoachCore

struct GarminWorkoutTests {
  @Test func intervalsFromPlanText() {
    let plan = GarminWorkout.plan(name: "Schwelle 4×2 km", sport: .run, text: "4×2 km @ 4:20 /km, 90 s Trab")
    #expect(plan.steps.count == 3)
    guard case .repeats(let count, let inner) = plan.steps[1] else {
      Issue.record("keine Wiederholung")
      return
    }
    #expect(count == 4)
    #expect(inner.first == .interval(.meters(2_000), note: "4×2 km @ 4:20 /km, 90 s Trab"))
    #expect(inner.last == .recovery(.seconds(90)))
    let minutes = GarminWorkout.plan(name: "4×4", sport: .run, text: "4×4 min bei 90–95 % HFmax, 3 min Trab")
    guard case .repeats(4, let steps) = minutes.steps[1] else {
      Issue.record("keine Wiederholung")
      return
    }
    #expect(steps.first == .interval(.seconds(240), note: "4×4 min bei 90–95 % HFmax, 3 min Trab"))
    #expect(steps.last == .recovery(.seconds(180)))
  }

  @Test func singleStepsFromDurationOrDistance() {
    #expect(GarminWorkout.plan(name: "Z2", sport: .run, text: "50 min Zone 2").steps == [
      .interval(.seconds(3_000), note: "50 min Zone 2")
    ])
    #expect(GarminWorkout.plan(name: "Z2", sport: .run, text: "60–75 min Z2").steps == [
      .interval(.seconds(3_600), note: "60–75 min Z2")
    ])
    #expect(GarminWorkout.plan(name: "Long", sport: .run, text: "16 km locker").steps == [
      .interval(.meters(16_000), note: "16 km locker")
    ])
    #expect(GarminWorkout.plan(name: "Frei", sport: .bike, text: "nach Gefühl").steps == [
      .interval(.lapButton, note: "nach Gefühl")
    ])
  }

  @Test func payloadMatchesGarminFields() throws {
    let plan = GarminWorkout.plan(name: "Schwelle", sport: .run, text: "3×3 km @ 4:20 /km, 2 min Trab")
    let payload = GarminWorkout.payload(plan)
    #expect(payload["sportType"]?["sportTypeKey"]?.stringValue == "running")
    let steps = try #require(payload["workoutSegments"]?.arrayValue?.first?["workoutSteps"]?.arrayValue)
    #expect(steps.count == 3)
    #expect(steps[0]["endCondition"]?["conditionTypeKey"]?.stringValue == "lap.button")
    let group = steps[1]
    #expect(group["type"]?.stringValue == "RepeatGroupDTO")
    #expect(group["numberOfIterations"]?.intValue == 3)
    let inner = try #require(group["workoutSteps"]?.arrayValue)
    #expect(inner[0]["endCondition"]?["conditionTypeKey"]?.stringValue == "distance")
    #expect(inner[0]["endConditionValue"]?.intValue == 3_000)
    #expect(inner[0]["childStepId"]?.intValue == 1)
    #expect(inner[1]["endCondition"]?["conditionTypeKey"]?.stringValue == "time")
    #expect(steps[2]["stepOrder"]?.intValue == 5)
    // Gültiges JSON für den Versand.
    let data = try JSONEncoder().encode(payload)
    #expect(!data.isEmpty)
  }

  @Test func swimPlanUsesPoolAndRestSteps() throws {
    let steps = [
      SwimStep(t: "warmup", m: 200),
      SwimStep(t: "rep", n: 4, steps: [SwimStep(t: "int", m: 100), SwimStep(t: "rest", s: 20)]),
      SwimStep(t: "cool", m: 100),
    ]
    let plan = GarminWorkout.swimPlan(name: "CSS", text: "4×100", steps: steps)
    let payload = GarminWorkout.payload(plan)
    #expect(payload["poolLength"]?.intValue == 25)
    let all = try #require(payload["workoutSegments"]?.arrayValue?.first?["workoutSteps"]?.arrayValue)
    let rest = try #require(all[1]["workoutSteps"]?.arrayValue?.last)
    #expect(rest["endCondition"]?["conditionTypeKey"]?.stringValue == "fixed.rest")
    #expect(rest["endConditionValue"]?.intValue == 20)
  }

  @Test func responseAndSchedule() throws {
    let response = try JSONValue(data: Data(#"{"workoutId": 123456789, "workoutName": "x"}"#.utf8))
    #expect(GarminWorkout.workoutID(from: response) == 123_456_789)
    let day = CalendarDay(year: 2026, month: 11, day: 10)
    #expect(GarminWorkout.scheduleBody(day: day)["date"]?.stringValue == "2026-11-10")
    #expect(GarminWorkout.schedulePath(workoutID: 5) == "/workout-service/schedule/5")
    #expect(GarminWorkout.Sport(.strength) == nil)
  }

  @Test func sentWorkoutsArePruned() {
    let today = CalendarDay(year: 2026, month: 11, day: 9)
    var sent = SentWorkouts()
    sent.ids[SentWorkouts.key(name: "A", day: today)] = 1
    sent.ids[SentWorkouts.key(name: "B", day: today.adding(days: -90))] = 2
    sent.prune(today: today)
    #expect(sent.ids.count == 1)
  }

  @Test func summaryForPreview() {
    let plan = GarminWorkout.plan(name: "S", sport: .run, text: "4×2 km @ 4:20 /km, 90 s Trab")
    #expect(
      GarminWorkout.summary(plan.steps) == [
        "Aufwärmen: bis Runden-Taste", "4 × (Belastung: 2 km, Erholung: 90 s)", "Ausklang: bis Runden-Taste",
      ])
  }
}
