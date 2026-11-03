import CoachCore
import Foundation
import Testing

@testable import Coach

// Audit IOS2: Befunde IOS2-03 (Pause geht bei App-Neustart verloren) und IOS2-06 (Rückgängig verwirft spätere
// Sätze). Beide Tests schlagen mit dem Stand 8baa407 fehl.
@MainActor
struct AuditGymViewModelTests {
  private func bench() throws -> ExerciseInfo {
    try #require(ExerciseLibrary.byID["bankdruecken"])
  }

  /// iOS beendet die App in der Pause (Speicherdruck, Absturz): Nach dem Neustart muss die laufende Pause noch da
  /// sein – die Einheit selbst wird schon wiederhergestellt (`activeSessionSurvivesRestart`).
  @Test func runningRestSurvivesRestart() throws {
    let defaults = try #require(UserDefaults(suiteName: "audit-gym-\(UUID().uuidString)"))
    let first = GymViewModel(defaults: defaults)
    first.update(sessions: [], activities: [], days: [], now: .now)
    first.startEmpty(now: .now)
    first.addExercise(try bench())
    let exercise = try #require(first.active?.exercises.first)
    first.complete(set: 0, of: exercise.id, now: .now)
    let rest = try #require(first.restEndsAt)

    let restarted = GymViewModel(defaults: defaults)

    #expect(restarted.active?.doneSetCount == 1)
    #expect(restarted.restEndsAt == rest)
    first.cancelActive()
  }

  /// Satz gelöscht (Rückgängig erscheint), dann sofort den nächsten Satz abgehakt; ein Tipp auf „Rückgängig“ darf
  /// den eben erledigten Satz nicht wieder öffnen.
  @Test func undoDoesNotDropLaterCompletedSet() throws {
    let defaults = try #require(UserDefaults(suiteName: "audit-gym-\(UUID().uuidString)"))
    let viewModel = GymViewModel(defaults: defaults)
    let now = CalendarDay(year: 2026, month: 10, day: 22).localDate
    viewModel.update(sessions: [], activities: [], days: [], now: now)
    viewModel.startEmpty(now: now)
    viewModel.addExercise(try bench())
    let exercise = try #require(viewModel.active?.exercises.first)
    viewModel.removeSet(2, from: exercise.id)
    #expect(viewModel.undoLabel == "Satz 3 gelöscht")

    viewModel.complete(set: 0, of: exercise.id, now: now)
    viewModel.undo()

    #expect(viewModel.active?.exercises.first?.sets.first?.done == true)
  }
}
