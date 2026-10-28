import Foundation
import Testing

@testable import CoachCore

struct GymToolsTests {
  @Test func platesPerSide() throws {
    let result = try #require(PlateCalculator.plates(total: 102.5))
    #expect(result.perSide == [25, 15, 1.25])
    #expect(result.remainder == 0)
    #expect(PlateCalculator.text(result) == "Je Seite: 25 + 15 + 1,25 kg")
    #expect(PlateCalculator.plates(total: 15) == nil)
    #expect(PlateCalculator.text(try #require(PlateCalculator.plates(total: 20))) == "Nur die Stange")
    let odd = try #require(PlateCalculator.plates(total: 21))
    #expect(odd.perSide.isEmpty)
    #expect(odd.remainder == 1)
  }

  @Test func warmUpForHeavyBarbellLift() {
    let steps = WarmUp.steps(working: 100, equipment: [.barbell], compound: true)
    #expect(steps.map(\.weightKg) == [20, 50, 70, 85])
    #expect(steps.map(\.reps) == [10, 5, 3, 2])
    #expect(WarmUp.text(Array(steps.prefix(2))) == "Aufwärmen: 20 kg × 10 · 50 kg × 5")
  }

  @Test func noWarmUpForLightOrIsolation() {
    #expect(WarmUp.steps(working: 30, equipment: [.barbell], compound: true).isEmpty)
    #expect(WarmUp.steps(working: 100, equipment: [.barbell], compound: false).isEmpty)
    #expect(WarmUp.steps(working: 20, equipment: [.dumbbell], compound: true).map(\.weightKg) == [10, 15])
    #expect(WarmUp.steps(working: 0, equipment: [.bodyweight], compound: true).isEmpty)
  }
}

struct GymRestSettingsTests {
  @Test func warmUpSuggestionOnlyBeforeFirstSet() {
    let info = ExerciseLibrary.info("bankdruecken")
    let sets = (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 60, done: false) }
    var exercise = LoggedExercise(exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest, sets: sets)
    #expect(WarmUp.suggestion(for: exercise, info: info, bar: 20).map(\.weightKg) == [20, 30, 42.5, 50])
    exercise.sets[0].done = true
    #expect(WarmUp.suggestion(for: exercise, info: info, bar: 20).isEmpty)
    exercise.sets[0].done = false
    exercise.sets.insert(LoggedSet(reps: 10, weightKg: 20, done: false, kind: .warmup), at: 0)
    #expect(WarmUp.suggestion(for: exercise, info: info, bar: 20).isEmpty)
    #expect(WarmUp.suggestion(for: exercise, info: nil, bar: 20).isEmpty)
  }

  @Test func restDefaultsAndDecoding() throws {
    var gym = GymSettings()
    #expect(gym.rest(for: "bankdruecken", compound: true) == 120)
    #expect(gym.rest(for: "seitheben", compound: false) == 90)
    gym.restIsolation = 75
    gym.restOverrides["bankdruecken"] = 180
    #expect(gym.rest(for: "bankdruecken", compound: true) == 180)
    #expect(gym.rest(for: "seitheben", compound: false) == 75)

    // Ältere Daten ohne die neuen Felder bleiben lesbar.
    let old = try JSONDecoder().decode(GymSettings.self, from: Data(#"{"routines":[]}"#.utf8))
    #expect(old.restWarmup == 60)
    #expect(old.autoStartsRest)
    #expect(old.suggestsWarmUp)
    #expect(old.completeOnEdit == .off)
    let round = try JSONDecoder().decode(GymSettings.self, from: JSONEncoder().encode(gym))
    #expect(round == gym)

    #expect(!CompleteOnEdit.off.completes(afterEditingReps: true))
    #expect(CompleteOnEdit.afterReps.completes(afterEditingReps: true))
    #expect(!CompleteOnEdit.afterReps.completes(afterEditingReps: false))
    #expect(CompleteOnEdit.always.completes(afterEditingReps: false))
    #expect(RestText.format(45) == "45 s")
    #expect(RestText.format(90) == "1:30 min")
    #expect(RestText.format(180) == "3 min")
  }
}
