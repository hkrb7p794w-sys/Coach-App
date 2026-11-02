import Foundation
import Testing

@testable import CoachCore

struct GymFlowTests {
  func exercise(_ id: String, sets: Int = 2, done: Int = 0, weight: Double = 50) -> LoggedExercise {
    LoggedExercise(
      exerciseID: id, name: id.capitalized, group: .chest,
      sets: (0..<sets).map { LoggedSet(reps: 8, weightKg: weight, done: $0 < done) })
  }

  func session(_ exercises: [LoggedExercise], start: Date = Date(timeIntervalSince1970: 0)) -> GymSession {
    GymSession(workoutKey: nil, title: "Test", start: start, exercises: exercises)
  }

  @Test func skippedExerciseIsPassedOverAndNotForgotten() {
    var session = session([exercise("bank"), exercise("schulter"), exercise("curl")])
    WorkoutEdits.setSkipped(true, exerciseID: session.exercises[0].id, in: &session)
    #expect(WorkoutFlow.current(in: session) == .init(exercise: 1, set: 0))
    #expect(WorkoutFlow.nextExercise(after: 1, in: session) == 2)
    // Ausdrücklich gewählt, steht die übersprungene Übung trotzdem auf der Fokus-Karte.
    #expect(WorkoutFlow.current(in: session, preferring: session.exercises[0].id) == .init(exercise: 0, set: 0))
    #expect(WorkoutFlow.skippedCount(session) == 1)

    session.exercises[0].sets[0].reps = 8
    // Offene Sätze der übersprungenen Übung zählen nicht als vergessen und werden nicht abgehakt.
    #expect(WorkoutFlow.summary(of: session).openSets == 4)
    #expect(WorkoutFlow.completingOpenSets(session).exercises[0].sets.allSatisfy { !$0.done })
  }

  @Test func planCompletesWhenOnlySkippedRemain() {
    var session = session([exercise("bank", done: 2), exercise("schulter", done: 1)])
    #expect(!WorkoutFlow.isComplete(session))
    WorkoutEdits.setSkipped(true, exerciseID: session.exercises[1].id, in: &session)
    #expect(WorkoutFlow.isComplete(session))
    WorkoutEdits.setSkipped(false, exerciseID: session.exercises[1].id, in: &session)
    #expect(!WorkoutFlow.isComplete(session))
    #expect(!WorkoutFlow.isComplete(self.session([])))
  }

  @Test func nextTextNamesTheNextExercise() {
    var session = session([exercise("bankdrücken", sets: 2, done: 2), exercise("schulterdrücken")])
    let bench = session.exercises[0].id
    #expect(
      WorkoutFlow.nextText(in: session, focus: nil, previous: bench) == "Weiter mit Schulterdrücken")
    session.exercises[1].sets[0].done = true
    let shoulder = session.exercises[1].id
    #expect(
      WorkoutFlow.nextText(in: session, focus: shoulder, previous: shoulder)
        == "Weiter mit Satz 2 · Schulterdrücken")
    session.exercises[1].sets[1].done = true
    #expect(WorkoutFlow.nextText(in: session, focus: nil, previous: shoulder) == nil)
  }

  @Test func skippedFlagDecodesFromOlderData() throws {
    let old = """
      {"id":"00000000-0000-0000-0000-000000000001","exerciseID":"bank","name":"Bank","group":"Brust",
      "sets":[{"reps":8,"weightKg":60}],"restSeconds":90}
      """
    let decoded = try JSONDecoder().decode(LoggedExercise.self, from: Data(old.utf8))
    #expect(!decoded.skipped)
    #expect(decoded.sets.first?.done == true)
    var skipped = decoded
    skipped.skipped = true
    let roundTrip = try JSONDecoder().decode(LoggedExercise.self, from: JSONEncoder().encode(skipped))
    #expect(roundTrip.skipped)
  }

  @Test func recentPerformancesNewestFirstWithBestSet() {
    let day = 86_400.0
    let sessions = (0..<7).map { index in
      session(
        [
          LoggedExercise(
            exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
            sets: [
              LoggedSet(reps: 10, weightKg: 75 + Double(index)),
              LoggedSet(reps: 8, weightKg: 75 + Double(index)),
              LoggedSet(reps: 12, weightKg: 40, kind: .warmup),
            ])
        ], start: Date(timeIntervalSince1970: day * Double(index) + 3_600 * 12))
    }
    let recent = GymStats.recentPerformances(of: "bankdruecken", sessions: sessions)
    #expect(recent.count == 5)
    #expect(recent.first?.weightKg == 81)
    #expect(recent.first?.reps == 10)
    #expect(recent.first?.text() == "81 kg × 10")
    #expect(recent.last?.weightKg == 77)
    #expect(GymStats.Performance(day: recent[0].day, weightKg: 0, reps: 12).text() == "12 Wdh.")
    #expect(
      GymStats.Performance(day: recent[0].day, weightKg: 10, reps: 8).text(allowsAssistance: true) == "+10 kg × 8")
    #expect(GymStats.Performance(day: recent[0].day, weightKg: 0, reps: 45).text(isTime: true) == "45 s")
  }

  @Test func cableCrunchIsMachineWeight() {
    #expect(ExerciseCatalog.classify("CRUNCH (KNEELING_CABLE_CRUNCH)", hasWeight: true).id == "crunch_kabel")
    #expect(ExerciseCatalog.classify("CRUNCH (WEIGHTED_CRUNCH)", hasWeight: true).id == "crunch_geraet")
    #expect(ExerciseCatalog.classify("CRUNCH", hasWeight: false).id == "crunch")
    let cable = ExerciseLibrary.info("crunch_kabel")
    #expect(!ExerciseUnits.allowsAssistance(cable))
    #expect(ExerciseUnits.weightText(65, info: cable).value == "65")
    #expect(ExerciseUnits.weightText(65, info: cable).unit == "kg")

    // Ältere Einheiten aus dem Saisonplan: beim Lesen Kabel-Crunch, gespeicherte Daten bleiben unverändert.
    let old = session([
      LoggedExercise(
        exerciseID: "crunch", name: "Crunches am Kabel kniend", group: .core, sets: [LoggedSet(reps: 12, weightKg: 65)]),
      LoggedExercise(exerciseID: "crunch", name: "Crunch", group: .core, sets: [LoggedSet(reps: 20, weightKg: 0)]),
    ])
    let normalized = ExerciseAliases.normalized(old)
    #expect(normalized.exercises.map(\.exerciseID) == ["crunch_kabel", "crunch"])
    #expect(old.exercises[0].exerciseID == "crunch")
  }
}

struct ActiveSessionStateTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 3_600) ?? .current
    return calendar
  }()

  private func session(start: Date, doneSets: Int) -> GymSession {
    let sets = (0..<3).map { LoggedSet(reps: 10, weightKg: 50, done: $0 < doneSets) }
    return GymSession(
      workoutKey: nil, title: "Push", start: start,
      exercises: [LoggedExercise(exerciseID: "bench", name: "Bankdrücken", group: .chest, sets: sets)])
  }

  @Test func openedButNotStartedHasNoLiveActivity() throws {
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17)))
    let state = ActiveSessionState.of(
      session(start: start, doneSets: 0), now: start.addingTimeInterval(600), calendar: calendar)
    #expect(state == .notStarted)
    #expect(!state.showsLiveActivity)
    #expect(state.suppressesReminders)
    #expect(!state.countsAsTrained)
  }

  @Test func firstSetMakesItRunning() throws {
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17)))
    let state = ActiveSessionState.of(
      session(start: start, doneSets: 1), now: start.addingTimeInterval(1_200), calendar: calendar)
    #expect(state == .running)
    #expect(state.showsLiveActivity && state.suppressesReminders && state.countsAsTrained)
  }

  @Test func oldSessionsAreAbandonedOrUnfinished() throws {
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 18)))
    let next = start.addingTimeInterval(15 * 3_600)
    let empty = ActiveSessionState.of(session(start: start, doneSets: 0), now: next, calendar: calendar)
    #expect(empty == .abandoned)
    #expect(!empty.suppressesReminders)
    let withSets = ActiveSessionState.of(session(start: start, doneSets: 2), now: next, calendar: calendar)
    #expect(withSets == .unfinished)
    #expect(!withSets.showsLiveActivity)
    #expect(ActiveSessionState.of(nil, now: next) == .none)
    // Geöffnet vor drei Stunden, nichts gemacht: Erinnerung darf wieder kommen.
    let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9)))
    let late = today.addingTimeInterval(3 * 3_600)
    #expect(ActiveSessionState.of(session(start: today, doneSets: 0), now: late, calendar: calendar) == .abandoned)
  }
}
