import Foundation
import Testing

@testable import CoachCore

struct WorkoutFlowTests {
  func exercise(_ id: String, done: [Bool]) -> LoggedExercise {
    LoggedExercise(
      exerciseID: id, name: id, group: .chest,
      sets: done.map { LoggedSet(reps: 8, weightKg: 50, done: $0) })
  }

  var session: GymSession {
    GymSession(
      workoutKey: nil, title: "Push", start: Date(timeIntervalSince1970: 0),
      exercises: [
        exercise("bank", done: [true, false, false]), exercise("rudern", done: [false, false]),
        exercise("curl", done: [true]),
      ])
  }

  @Test func currentFollowsChosenExerciseAndWraps() {
    let session = session
    #expect(WorkoutFlow.current(in: session) == .init(exercise: 0, set: 1))
    #expect(WorkoutFlow.current(in: session, preferring: session.exercises[1].id) == .init(exercise: 1, set: 0))
    // Fertige Übung gewählt: weiter mit der nächsten offenen, am Ende von vorn.
    #expect(WorkoutFlow.current(in: session, preferring: session.exercises[2].id) == .init(exercise: 0, set: 1))
  }

  @Test func upcomingStaysInExerciseThenMovesOn() {
    let session = session
    #expect(WorkoutFlow.upcoming(after: .init(exercise: 0, set: 1), in: session) == .init(exercise: 0, set: 2))
    #expect(WorkoutFlow.upcoming(after: .init(exercise: 0, set: 2), in: session) == .init(exercise: 0, set: 1))
    var last = session
    last.exercises[0].sets[1].done = true
    #expect(WorkoutFlow.upcoming(after: .init(exercise: 0, set: 2), in: last) == .init(exercise: 1, set: 0))
  }

  @Test func summaryCountsForgottenSets() {
    var session = session
    session.exercises[1].sets[1].reps = 0
    let summary = WorkoutFlow.summary(of: session, now: Date(timeIntervalSince1970: 3_000))
    #expect(summary.minutes == 50)
    #expect(summary.doneSets == 2)
    #expect(summary.exercises == 2)
    #expect(summary.openSets == 3)
    let completed = WorkoutFlow.completingOpenSets(session)
    #expect(completed.doneSetCount == 5)
    #expect(completed.exercises[1].sets[1].done == false)
  }

  @Test func numberPadInput() {
    var text = ""
    for key: NumberPad.Key in [.digit(6), .digit(2), .comma, .digit(5), .digit(0), .digit(1)] {
      text = NumberPad.apply(key, to: text, allowsDecimals: true)
    }
    #expect(text == "62,50")
    #expect(NumberPad.value(text) == 62.5)
    #expect(NumberPad.apply(.comma, to: "", allowsDecimals: true) == "0,")
    #expect(NumberPad.apply(.comma, to: "8", allowsDecimals: false) == "8")
    #expect(NumberPad.apply(.digit(5), to: "0", allowsDecimals: false) == "5")
    #expect(NumberPad.apply(.digit(1), to: "100", allowsDecimals: false) == "100")
    #expect(NumberPad.apply(.delete, to: "62,5", allowsDecimals: true) == "62,")
    #expect(NumberPad.value("") == nil)
    #expect(NumberPad.text(for: 0) == "")
    #expect(NumberPad.text(for: 62.5) == "62,5")
  }
}
