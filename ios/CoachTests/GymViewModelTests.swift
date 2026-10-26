import CoachCore
import Foundation
import SwiftData
import Testing

@testable import Coach

@MainActor
private final class StubWriter: WorkoutSaving {
  var isAvailable = true
  var saved: [GymSession] = []
  var error: (any Error)?

  func save(_ session: GymSession) async throws {
    if let error { throw error }
    saved.append(session)
  }
}

@MainActor
struct GymViewModelTests {
  /// Donnerstag, 22.10.2026: laut Plan flexible Beineinheit (Di/Do), wenn Dienstag nichts geloggt ist.
  private let now = CalendarDay(year: 2026, month: 10, day: 22).localDate

  private func makeViewModel() throws -> GymViewModel {
    let defaults = try #require(UserDefaults(suiteName: "gym-\(UUID().uuidString)"))
    return GymViewModel(defaults: defaults)
  }

  @Test func planPicksLegsAndPrefillsFromProgression() throws {
    let viewModel = try makeViewModel()
    let monday = CalendarDay(year: 2026, month: 10, day: 19)
    let press = LoggedExercise(
      exerciseID: "beinpresse", name: "Beinpresse", group: .legs,
      sets: [LoggedSet(reps: 12, weightKg: 149), LoggedSet(reps: 12, weightKg: 149)])
    let old = GymSession(
      workoutKey: "legs", title: "Lower", start: monday.adding(days: -6).localDate, exercises: [press])
    viewModel.update(sessions: [old], activities: [], days: [], now: now)

    #expect(viewModel.todayWorkout?.key == "legs")
    let workout = try #require(viewModel.todayWorkout)
    viewModel.start(workout, now: now)
    let active = try #require(viewModel.active)
    let legPress = try #require(active.exercises.first { $0.exerciseID == "beinpresse" })
    #expect(legPress.sets.count == 2)
    #expect(legPress.sets.allSatisfy { $0.weightKg == 154 && $0.reps == 8 && !$0.done })
    let curl = try #require(active.exercises.first { $0.exerciseID == "beinbeugen" })
    #expect(curl.sets.first?.weightKg == 110)
    #expect(curl.sets.first?.reps == 12)
  }

  @Test func finishSavesDoneSetsAndWritesHealth() async throws {
    let viewModel = try makeViewModel()
    let container = CoachSchema.makeContainer(inMemory: true)
    viewModel.update(sessions: [], activities: [], days: [], now: now)
    viewModel.startEmpty(now: now)
    let bench = try #require(ExerciseLibrary.byID["bankdruecken"])
    viewModel.addExercise(bench)
    let exercise = try #require(viewModel.active?.exercises.first)
    viewModel.setWeight(50, set: 0, of: exercise.id)
    #expect(viewModel.active?.exercises.first?.sets.map(\.weightKg) == [50, 50, 50])
    viewModel.toggleDone(set: 0, of: exercise.id, now: now)
    #expect(viewModel.restEndsAt == now.addingTimeInterval(120))

    let writer = StubWriter()
    await viewModel.finish(context: container.mainContext, writer: writer, now: now.addingTimeInterval(1800))

    #expect(viewModel.active == nil)
    let records = try container.mainContext.fetch(FetchDescriptor<GymSessionRecord>())
    #expect(records.count == 1)
    #expect(records.first?.savedToHealth == true)
    #expect(records.first?.session?.exercises.first?.sets.count == 1)
    #expect(writer.saved.count == 1)
    #expect(viewModel.message == "Gespeichert und in Apple Health eingetragen.")
  }

  @Test func activeSessionSurvivesRestart() throws {
    let defaults = try #require(UserDefaults(suiteName: "gym-\(UUID().uuidString)"))
    let first = GymViewModel(defaults: defaults)
    first.startEmpty(now: now)
    #expect(GymViewModel(defaults: defaults).active?.title == "Krafttraining")
    first.cancelActive()
    #expect(GymViewModel(defaults: defaults).active == nil)
  }

  @Test func nothingToSaveWithoutDoneSets() async throws {
    let viewModel = try makeViewModel()
    let container = CoachSchema.makeContainer(inMemory: true)
    viewModel.startEmpty(now: now)
    await viewModel.finish(context: container.mainContext, writer: StubWriter(), now: now)
    #expect(viewModel.message?.contains("Noch kein Satz") == true)
    #expect(viewModel.active != nil)
  }

  @Test func routineStartsWithLastValuesAndStoresRIR() throws {
    let viewModel = try makeViewModel()
    let last = GymSession(
      workoutKey: nil, title: "Ganzkörper A", start: now.addingTimeInterval(-3 * 86_400),
      exercises: [
        LoggedExercise(
          exerciseID: "goblet_squat", name: "Goblet Squat", group: .legs,
          sets: [LoggedSet(reps: 10, weightKg: 16), LoggedSet(reps: 9, weightKg: 16)])
      ])
    let routine = Routine(
      name: "Ganzkörper A",
      items: [
        RoutineItem(
          exerciseID: "goblet_squat", name: "Goblet Squat", sets: 3, lowerReps: 8, upperReps: 12, restSeconds: 120)
      ])
    var gym = GymSettings()
    gym.routines = [routine]
    viewModel.update(sessions: [last], activities: [], days: [], gym: gym, now: now)
    #expect(viewModel.lastTime(of: "goblet_squat")?.hasSuffix("16×10, 16×9") == true)

    viewModel.start(routine, now: now)
    let exercise = try #require(viewModel.active?.exercises.first)
    #expect(exercise.sets.count == 3)
    #expect(exercise.sets.allSatisfy { $0.weightKg == 16 })
    #expect(exercise.group == .legs)
    #expect(exercise.restSeconds == 120)
    viewModel.toggleDone(set: 0, of: exercise.id, now: now)
    viewModel.setRIR(2, set: 0, of: exercise.id)
    #expect(viewModel.active?.exercises.first?.sets.first?.rir == 2)
    #expect(viewModel.hints.isEmpty == false)
  }
}
