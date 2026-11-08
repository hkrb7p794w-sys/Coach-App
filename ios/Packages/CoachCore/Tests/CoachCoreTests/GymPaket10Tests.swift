import Foundation
import Testing

@testable import CoachCore

/// Aufwärmsätze, Einstellungen des KI-Plans und Pausenton (Paket 10).
struct GymPaket10Tests {
  private func exercise(_ group: MuscleGroup, weight: Double, done: Bool = false) -> LoggedExercise {
    var set = LoggedSet(reps: 8, weightKg: weight)
    set.done = done
    return LoggedExercise(exerciseID: "bench_press", name: "Übung", group: group, sets: [set])
  }

  @Test func heavyCompoundGetsSeveralProgressiveSets() {
    let steps = WarmUp.steps(working: 120, equipment: [.barbell], compound: true)
    #expect(steps.count == 4)
    #expect(steps.map(\.weightKg) == steps.map(\.weightKg).sorted())
    #expect(steps.allSatisfy { $0.weightKg < 120 })
  }

  @Test func beginnersSkipTheHeaviestWarmUpSet() {
    let beginner = WarmUp.steps(working: 100, equipment: [.barbell], compound: true, level: .beginner)
    #expect(beginner.map(\.weightKg) == [20, 50, 70])
  }

  @Test func heavyIsolationGetsOneSetLightNone() {
    #expect(WarmUp.steps(working: 40, equipment: [.machine], compound: false) == [.init(weightKg: 24, reps: 10)])
    #expect(WarmUp.steps(working: 10, equipment: [.dumbbell], compound: false).isEmpty)
    #expect(WarmUp.steps(working: 50, equipment: [.bodyweight], compound: false).isEmpty)
  }

  @Test func warmedUpMuscleNeedsOnlyOneFeelerSet() {
    let steps = WarmUp.steps(working: 80, equipment: [.barbell], compound: true, warmedUp: true)
    #expect(steps == [.init(weightKg: 55, reps: 3)])
    #expect(WarmUp.steps(working: 40, equipment: [.machine], compound: false, warmedUp: true).isEmpty)
  }

  @Test func earlierSameMuscleCountsAsWarmedUp() throws {
    let info = try #require(ExerciseLibrary.info("bankdruecken"))
    let done = exercise(info.group, weight: 60, done: true)
    let next = exercise(info.group, weight: 40)
    let session = GymSession(workoutKey: nil, title: "A", start: .now, exercises: [done, next])
    #expect(WarmUp.isWarmedUp(next, info: info, in: session))
    let fresh = GymSession(workoutKey: nil, title: "A", start: .now, exercises: [next])
    #expect(!WarmUp.isWarmedUp(next, info: info, in: fresh))
  }

  @Test func warmUpSetsDoNotCountAsWork() {
    var warmUp = LoggedSet(reps: 5, weightKg: 50)
    warmUp.kind = .warmup
    warmUp.done = true
    var work = LoggedSet(reps: 8, weightKg: 100)
    work.done = true
    let logged = LoggedExercise(exerciseID: "bench_press", name: "Bank", group: .chest, sets: [warmUp, work])
    #expect(logged.doneSets.count == 1)
  }

  // MARK: - KI-Plan

  @Test func planInputUsesChosenExperienceAndEquipment() {
    var request = GymCoach.PlanRequest()
    request.experience = .advanced
    let all = GymCoach.planInput(
      request: request, profile: UserProfile(), equipment: Equipment.gym, routines: [], sessions: [], custom: [],
      today: CalendarDay(year: 2026, month: 11, day: 9))
    request.equipment = [.bodyweight]
    let limited = GymCoach.planInput(
      request: request, profile: UserProfile(), equipment: Equipment.gym, routines: [], sessions: [], custom: [],
      today: CalendarDay(year: 2026, month: 11, day: 9))
    #expect(all["experience"] == .string(ExperienceLevel.advanced.label))
    #expect((limited["library"]?.arrayValue?.count ?? 0) < (all["library"]?.arrayValue?.count ?? 0))
  }

  @Test func emptyEquipmentBlocksAndOddCombinationsAreExplained() {
    var request = GymCoach.PlanRequest()
    request.equipment = []
    #expect(!GymCoach.planIssues(request, equipment: Equipment.gym).blocking.isEmpty)
    request.equipment = nil
    #expect(GymCoach.planIssues(request, equipment: Equipment.gym).blocking.isEmpty)
    request.goal = .strength
    request.minutesPerSession = 30
    #expect(!GymCoach.planIssues(request, equipment: Equipment.gym).hints.isEmpty)
  }

  // MARK: - Pausenton

  @Test func oldSettingsGetDefaultSoundAndNewOnesSurvive() throws {
    let old = try JSONDecoder().decode(GymSettings.self, from: Data("{}".utf8))
    #expect(old.restSound == .chime)
    #expect(old.restHaptic)
    var changed = old
    changed.restSound = .off
    changed.restHaptic = false
    let again = try JSONDecoder().decode(GymSettings.self, from: JSONEncoder().encode(changed))
    #expect(again.restSound == .off)
    #expect(!again.restHaptic)
  }

  @Test func onlyOwnSoundsHaveFiles() {
    #expect(RestSound.off.fileName == nil)
    #expect(RestSound.system.fileName == nil)
    #expect(RestSound.allCases.compactMap(\.fileName).allSatisfy { $0.hasSuffix(".wav") })
  }
}
