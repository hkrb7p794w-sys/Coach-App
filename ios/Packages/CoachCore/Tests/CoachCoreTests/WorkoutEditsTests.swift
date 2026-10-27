import Foundation
import Testing

@testable import CoachCore

struct WorkoutEditsTests {
  func exercise(_ id: String, sets: Int = 3, done: Int = 0, weight: Double = 50) -> LoggedExercise {
    LoggedExercise(
      exerciseID: id, name: id, group: .chest,
      sets: (0..<sets).map { LoggedSet(reps: 8, weightKg: weight, done: $0 < done) })
  }

  func session(_ exercises: [LoggedExercise]) -> GymSession {
    GymSession(workoutKey: nil, title: "Test", start: Date(timeIntervalSince1970: 0), exercises: exercises)
  }

  @Test func supersetAlternatesAndRestsAfterRound() {
    var session = session([exercise("bank"), exercise("rudern"), exercise("curl")])
    WorkoutEdits.toggleSuperset(session.exercises[0].id, in: &session)
    #expect(session.exercises[0].supersetID != nil)
    #expect(session.exercises[0].supersetID == session.exercises[1].supersetID)
    #expect(WorkoutFlow.supersetLabels(in: session)[session.exercises[1].id] == "A2")

    // A1 erledigt: ohne Pause zu A2.
    session.exercises[0].sets[0].done = true
    let afterA1 = WorkoutFlow.afterCompleting(exercise: 0, in: session)
    #expect(afterA1.focus == 1)
    #expect(afterA1.rest == false)
    // A2 erledigt: Pause, dann wieder A1.
    session.exercises[1].sets[0].done = true
    let afterA2 = WorkoutFlow.afterCompleting(exercise: 1, in: session)
    #expect(afterA2.focus == 0)
    #expect(afterA2.rest == true)
    #expect(WorkoutFlow.upcoming(after: .init(exercise: 0, set: 1), in: session) == .init(exercise: 1, set: 1))

    // Auflösen: beide wieder einzeln.
    WorkoutEdits.toggleSuperset(session.exercises[1].id, in: &session)
    #expect(session.exercises.allSatisfy { $0.supersetID == nil })
  }

  @Test func laterAndMove() {
    var session = session([exercise("a"), exercise("b"), exercise("c")])
    WorkoutEdits.moveToEnd(session.exercises[0].id, in: &session)
    #expect(session.exercises.map(\.exerciseID) == ["b", "c", "a"])
    WorkoutEdits.move(fromOffsets: [2], toOffset: 0, in: &session)
    #expect(session.exercises.map(\.exerciseID) == ["a", "b", "c"])
    WorkoutEdits.move(fromOffsets: [0], toOffset: 3, in: &session)
    #expect(session.exercises.map(\.exerciseID) == ["b", "c", "a"])
  }

  @Test func replaceKeepsDoneSetsWithOldExercise() throws {
    let info = try #require(ExerciseLibrary.byID["kurzhantel_bankdruecken"])
    var fresh = session([exercise("bankdruecken")])
    WorkoutEdits.replace(fresh.exercises[0].id, with: info, weightKg: 24, in: &fresh)
    #expect(fresh.exercises.count == 1)
    #expect(fresh.exercises[0].exerciseID == "kurzhantel_bankdruecken")
    #expect(fresh.exercises[0].sets.count == 3)
    #expect(fresh.exercises[0].sets.allSatisfy { $0.weightKg == 24 && !$0.done })

    var started = session([exercise("bankdruecken", sets: 4, done: 1)])
    WorkoutEdits.replace(started.exercises[0].id, with: info, weightKg: 24, in: &started)
    #expect(started.exercises.map(\.exerciseID) == ["bankdruecken", "kurzhantel_bankdruecken"])
    #expect(started.exercises[0].sets.count == 1)
    #expect(started.exercises[1].sets.count == 3)
  }

  @Test func alternativesMatchGroupAndEquipment() {
    let options = WorkoutEdits.alternatives(for: "bankdruecken", equipment: [.dumbbell, .bench])
    #expect(options.contains { $0.id == "kurzhantel_bankdruecken" })
    #expect(!options.contains { $0.id == "bankdruecken" || $0.id == "brustpresse" })
    #expect(options.allSatisfy { $0.group == .chest })
  }

  @Test func warmUpsDoNotCountOrDragWorkingSets() {
    var session = session([exercise("kniebeuge", weight: 100)])
    let id = session.exercises[0].id
    let steps = WarmUp.steps(working: 100, equipment: [.barbell], compound: true)
    WorkoutEdits.insertWarmUp(steps, into: id, in: &session)
    #expect(session.exercises[0].sets.prefix(steps.count).allSatisfy { $0.kind == .warmup })

    // Aufwärmsatz leichter machen: Arbeitssätze bleiben bei 100 kg.
    let moved = WorkoutEdits.setWeight(30, set: 0, of: id, in: &session)
    #expect(moved == 0)
    #expect(session.exercises[0].sets.filter { $0.kind == .working }.allSatisfy { $0.weightKg == 100 })
    // Erster Arbeitssatz schwerer: die folgenden ziehen mit.
    let first = steps.count
    #expect(WorkoutEdits.setWeight(105, set: first, of: id, in: &session) == 2)

    for index in session.exercises[0].sets.indices { session.exercises[0].sets[index].done = true }
    #expect(session.exercises[0].doneSets.count == 3)
    #expect(session.exercises[0].loggedSets.count == 3 + steps.count)
    #expect(session.volumeKg == 2_520)
  }

  @Test func assistanceIsNegativeButNeverCountsAsLoad() {
    var session = session([exercise("klimmzug", weight: 0)])
    let id = session.exercises[0].id
    WorkoutEdits.setWeight(-20, set: 0, of: id, allowsNegative: true, in: &session)
    #expect(session.exercises[0].sets.allSatisfy { $0.weightKg == -20 })
    WorkoutEdits.setWeight(-20, set: 0, of: id, in: &session)
    #expect(session.exercises[0].sets[0].weightKg == 0)
    #expect(LoggedSet(reps: 8, weightKg: -20).loadKg == 0)
    let pullUp = ExerciseLibrary.byID["klimmzug"]
    #expect(ExerciseUnits.weightText(-20, info: pullUp).value == "20")
    #expect(ExerciseUnits.weightText(-20, info: pullUp).unit == "kg Hilfe")
    #expect(ExerciseUnits.weightText(10, info: pullUp).value == "+10")
    #expect(ExerciseUnits.weightText(20, info: ExerciseLibrary.byID["kurzhantel_curl"]).unit == "kg je Hantel")
    #expect(ExerciseUnits.repsUnit("ausfallschritt", isTime: false) == "Wdh. je Seite")
  }

  @Test func plausibilityAndRest() {
    #expect(SetCheck.warning(weightKg: 625, reps: 0, isTime: false, previousBestKg: 62.5) != nil)
    #expect(SetCheck.warning(weightKg: 105, reps: 0, isTime: false, previousBestKg: 62.5) != nil)
    #expect(SetCheck.warning(weightKg: 65, reps: 0, isTime: false, previousBestKg: 62.5) == nil)
    #expect(SetCheck.warning(weightKg: 0, reps: 80, isTime: false, previousBestKg: nil) != nil)
    #expect(SetCheck.warning(weightKg: 0, reps: 90, isTime: true, previousBestKg: nil) == nil)
    #expect(RestAdvisor.seconds(base: 120, compound: true, rir: 0) == 150)
    #expect(RestAdvisor.seconds(base: 120, compound: true, rir: 3) == 120)
    #expect(RestAdvisor.seconds(base: 90, compound: false, rir: 0) == 90)
  }

  @Test func oldSetsDecodeAsWorkingSets() throws {
    let json = Data(#"{"reps":8,"weightKg":60,"done":true}"#.utf8)
    let set = try JSONDecoder().decode(LoggedSet.self, from: json)
    #expect(set.kind == .working)
    #expect(set.reps == 8)
    let routine =
      #"{"id":"6F1C2D1E-0000-4000-8000-000000000001","exerciseID":"kniebeuge","name":"Kniebeuge","sets":3,"#
      + #""lowerReps":6,"upperReps":10,"restSeconds":120}"#
    let item = try JSONDecoder().decode(RoutineItem.self, from: Data(routine.utf8))
    #expect(item.supersetWithNext == false)
    let settings = try JSONDecoder().decode(GymSettings.self, from: Data("{}".utf8))
    #expect(settings.barKg == 20)
    #expect(settings.keepsScreenOn)
  }
}
