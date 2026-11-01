import Foundation
import Testing

@testable import CoachCore

struct MuscleLoadTests {
  let now = Date(timeIntervalSince1970: 1_793_500_000)

  func session(_ exercises: [LoggedExercise], hoursAgo: Double) -> GymSession {
    let start = now.addingTimeInterval(-hoursAgo * 3_600)
    return GymSession(
      workoutKey: nil, title: "Test", start: start, end: start.addingTimeInterval(3_600), exercises: exercises)
  }

  func exercise(_ id: String, group: MuscleGroup = .chest, sets: [LoggedSet]) -> LoggedExercise {
    LoggedExercise(exerciseID: id, name: id, group: group, sets: sets)
  }

  @Test func compoundCountsAssistingMusclesHalf() {
    let bench = exercise("bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 80) })
    let load = MuscleLoad.session(session([bench], hoursAgo: 1))
    #expect(load[.chest] == 3)
    #expect(load[.triceps] == 1.5)
    #expect(load[.frontDelts] == 1.5)
    #expect(load[.lats] == nil)
  }

  @Test func warmUpsDropSetsAndEasySetsCountLess() {
    let sets = [
      LoggedSet(reps: 10, weightKg: 40, kind: .warmup),
      LoggedSet(reps: 8, weightKg: 80, rir: 2),
      LoggedSet(reps: 8, weightKg: 80, rir: 4),
      LoggedSet(reps: 12, weightKg: 60, kind: .drop),
      LoggedSet(reps: 8, weightKg: 80, done: false),
    ]
    let load = MuscleLoad.session(session([exercise("beinstrecken", group: .legs, sets: sets)], hoursAgo: 1))
    #expect(load[.quads] == 2)
  }

  @Test func eachSetCountsOncePerMuscleAcrossExercises() {
    // Kniebeuge und Hüftstoß: Gesäß zählt je Satz einmal, nicht doppelt über „Beine“ und „Gesäß“.
    let squat = exercise("kniebeuge", group: .legs, sets: [LoggedSet(reps: 5, weightKg: 100)])
    let thrust = exercise("hueftstoss", group: .legs, sets: [LoggedSet(reps: 10, weightKg: 80)])
    let load = MuscleLoad.session(session([squat, thrust], hoursAgo: 1))
    #expect(load[.glutes] == 2)
    #expect(load[.quads] == 1)
    #expect(load[.hamstrings] == 0.5)
  }

  @Test func customExerciseUsesGroups() {
    let custom = ExerciseInfo.custom(name: "Meine Presse", group: .shoulders, equipment: .machine, tracking: .weightReps)
    let involvement = MuscleMap.involvement(custom.id, group: .shoulders, custom: [custom])
    #expect(involvement[.sideDelts] == 1)
    #expect(MuscleMap.involvement("unbekannt", group: .back) == [.lats: 1])
  }

  @Test func statusShowsRecoveryAndNeglect() {
    let legs = exercise("kniebeuge", group: .legs, sets: (0..<4).map { _ in LoggedSet(reps: 5, weightKg: 100) })
    let chest = exercise("bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 80) })
    let single = exercise("seitheben", group: .shoulders, sets: [LoggedSet(reps: 12, weightKg: 8)])
    let sessions = [
      session([legs], hoursAgo: 20),
      session([chest, single], hoursAgo: 24 * 5),
      session([chest], hoursAgo: 24 * 20),
    ]
    let status = Dictionary(
      uniqueKeysWithValues: MuscleLoad.status(sessions: sessions, now: now).map { ($0.muscle, $0) })
    #expect(status[.quads]?.recovery == .recovering)
    #expect(status[.quads]?.weeklySets == 4)
    #expect(status[.chest]?.recovery == .ready)
    #expect(status[.chest]?.weeklySets == 3)
    #expect(status[.chest]?.averageWeeklySets == 1.5)
    #expect(status[.chest]?.isLow == true)
    // Ein einzelner Satz ist keine nennenswerte Belastung.
    #expect(status[.sideDelts]?.recovery == .neglected)
    #expect(status[.calves]?.lastLoaded == nil)
  }

  @Test func routineLoadFromPlannedSets() {
    let routine = Routine(
      name: "Push",
      items: [
        RoutineItem(
          exerciseID: "bankdruecken", name: "Bankdrücken", sets: 3, lowerReps: 6, upperReps: 10, restSeconds: 120),
        RoutineItem(
          exerciseID: "trizeps_pushdown", name: "Pushdown", sets: 2, lowerReps: 8, upperReps: 12, restSeconds: 90),
      ])
    let load = MuscleLoad.routine(routine)
    #expect(load[.chest] == 3)
    #expect(load[.triceps] == 3.5)
    #expect(MuscleLoad.intensity(3, full: 6) == 0.5)
    #expect(MuscleLoad.intensity(9, full: 6) == 1)
  }

  @Test func everyLibraryExerciseHasAMuscle() {
    for exercise in ExerciseLibrary.all {
      #expect(!MuscleMap.involvement(exercise.id, group: exercise.group).isEmpty, "\(exercise.id)")
      #expect(MuscleMap.table[exercise.id] != nil, "\(exercise.id) fehlt in der Muskeltabelle")
    }
  }
}
