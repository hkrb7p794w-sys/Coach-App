import Foundation
import Testing

@testable import CoachCore

/// Donnerstag, 22.10.2026.
private let today = CalendarDay(year: 2026, month: 10, day: 22)

private func session(_ daysAgo: Int, _ exerciseID: String, sets: [LoggedSet]) -> GymSession {
  let day = today.adding(days: -daysAgo)
  return GymSession(
    workoutKey: nil, title: "Test", start: day.referenceDate,
    exercises: [
      LoggedExercise(
        exerciseID: exerciseID, name: ExerciseLibrary.byID[exerciseID]?.name ?? exerciseID,
        group: ExerciseLibrary.byID[exerciseID]?.group ?? .other, sets: sets)
    ])
}

struct ExerciseLibraryTests {
  @Test func idsAreUniqueAndEveryExerciseIsExplained() {
    #expect(Set(ExerciseLibrary.all.map(\.id)).count == ExerciseLibrary.all.count)
    for exercise in ExerciseLibrary.all {
      #expect(exercise.instructions.count >= 2, "\(exercise.id) ohne Anleitung")
      #expect(exercise.lowerReps <= exercise.upperReps)
      #expect(exercise.step > 0)
    }
  }

  @Test func garminCatalogKeepsItsProgressionValues() {
    for rule in ExerciseCatalog.rules {
      let viaLibrary = ExerciseLibrary.rule(rule.id, name: rule.name)
      #expect(viaLibrary.step == ExerciseCatalog.rulesByID[rule.id]?.step)
      #expect(ExerciseLibrary.info(rule.id) != nil, "\(rule.id) fehlt in der Bibliothek")
    }
    #expect(ExerciseLibrary.rule("goblet_squat", name: "Goblet Squat").reps == 8...12)
    #expect(ExerciseLibrary.rule("unbekannt", name: "Neu").name == "Neu")
  }

  @Test func equipmentFiltersAndCustomExercises() throws {
    let bench = try #require(ExerciseLibrary.byID["bankdruecken"])
    #expect(bench.isAvailable(with: Equipment.gym))
    #expect(!bench.isAvailable(with: Equipment.homeDumbbells))
    #expect(try #require(ExerciseLibrary.byID["liegestuetze"]).isAvailable(with: Equipment.none))

    let own = ExerciseInfo.custom(
      name: " Landmine Press ", group: .shoulders, equipment: .barbell, tracking: .weightReps)
    #expect(own.id == "eigen_landmine_press")
    #expect(own.name == "Landmine Press")
    var settings = GymSettings()
    settings.addCustom(own)
    settings.addCustom(own)
    #expect(settings.customExercises.count == 1)
    #expect(settings.exercise(own.id)?.group == .shoulders)
    #expect(ExerciseLibrary.search("landmine", custom: settings.customExercises).map(\.id) == [own.id])
    #expect(
      ExerciseLibrary.search("Rücken").allSatisfy { $0.group == .back || $0.name.lowercased().contains("rücken") })

    let decoded = try JSONDecoder().decode(GymSettings.self, from: Data(#"{"tracksRIR":false}"#.utf8))
    #expect(!decoded.tracksRIR)
    #expect(decoded.equipment == Equipment.gym)
  }
}

struct RoutineTemplateTests {
  private func profile(strengthDays: Int, level: ExperienceLevel = .intermediate) -> UserProfile {
    var profile = UserProfile(sports: [.strength], goal: .buildMuscle)
    profile.setLevel(level, for: .strength)
    for weekday in Weekday.allCases.prefix(strengthDays) {
      profile.schedule.set([SessionSlot(.strength, .hard)], on: weekday)
    }
    return profile
  }

  @Test func everyBigMuscleTwicePerWeek() {
    for days in 1...6 {
      for equipment in [Equipment.gym, Equipment.homeDumbbells] {
        let routines = RoutineTemplates.suggest(profile: profile(strengthDays: days), equipment: equipment)
        #expect(!routines.isEmpty)
        var sessionsPerGroup: [MuscleGroup: Int] = [:]
        for routine in routines {
          for group in Set(routine.items.compactMap { ExerciseLibrary.byID[$0.exerciseID]?.group }) {
            sessionsPerGroup[group, default: 0] += 1
          }
          #expect(
            routine.items.allSatisfy { ExerciseLibrary.byID[$0.exerciseID]?.isAvailable(with: equipment) == true })
          #expect(Set(routine.items.map(\.exerciseID)).count == routine.items.count)
        }
        for group in [MuscleGroup.chest, .back, .legs, .shoulders] {
          #expect(
            (sessionsPerGroup[group] ?? 0) >= 2, "\(group) bei \(days) Tagen nur \(sessionsPerGroup[group] ?? 0)×")
        }
      }
    }
  }

  @Test func splitDependsOnDaysAndLevel() {
    #expect(RoutineTemplates.suggest(profile: profile(strengthDays: 2), equipment: Equipment.gym).count == 2)
    #expect(
      RoutineTemplates.suggest(profile: profile(strengthDays: 4), equipment: Equipment.gym).first?.name
        == "Oberkörper A")
    #expect(RoutineTemplates.suggest(profile: profile(strengthDays: 5), equipment: Equipment.gym).count == 5)
    let beginner = RoutineTemplates.suggest(
      profile: profile(strengthDays: 2, level: .beginner), equipment: Equipment.gym)
    #expect(beginner.flatMap(\.items).allSatisfy { $0.sets == 2 })
    let none = RoutineTemplates.suggest(profile: profile(strengthDays: 2), equipment: Equipment.none)
    #expect(none.flatMap(\.items).contains { $0.exerciseID == "liegestuetze" })
    #expect(none.repRanges["liegestuetze"] == 8...20)
  }
}

struct GymStatsTests {
  @Test func epleyOnlyUpToTwelveReps() throws {
    #expect(GymStats.estimatedOneRepMax(weightKg: 100, reps: 1) == 100)
    #expect(abs(try #require(GymStats.estimatedOneRepMax(weightKg: 60, reps: 10)) - 80) < 0.001)
    #expect(GymStats.estimatedOneRepMax(weightKg: 60, reps: 15) == nil)
    #expect(GymStats.estimatedOneRepMax(weightKg: 0, reps: 10) == nil)
  }

  @Test func historyRecordsAndNewBests() {
    let old = session(7, "bankdruecken", sets: [LoggedSet(reps: 10, weightKg: 60), LoggedSet(reps: 8, weightKg: 60)])
    let warmup = LoggedSet(reps: 12, weightKg: 20, done: false)
    let new = session(0, "bankdruecken", sets: [warmup, LoggedSet(reps: 8, weightKg: 62.5)])
    let points = GymStats.history(of: "bankdruecken", sessions: [new, old])
    #expect(points.map(\.topWeightKg) == [60, 62.5])
    #expect(points.last?.sets.count == 1)
    let records = GymStats.records(points)
    #expect(records.heaviestKg == 62.5)
    #expect(records.mostReps == 10)
    #expect(GymStats.newRecords(in: new, before: [old, new]) == ["Bankdrücken: neues Höchstgewicht 62,5 kg"])
    #expect(GymStats.newRecords(in: old, before: [old]).isEmpty)
  }
}

struct RIRProgressionTests {
  private func evaluate(_ sessions: [GymSession]) -> ExerciseProgress? {
    GymProgression.evaluate(sessions: sessions, ranges: [:], today: today).first
  }

  @Test func plentyInReserveMeansIncreaseNow() throws {
    let easy = session(
      2, "kurzhantel_bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 20, rir: 4) })
    let result = try #require(evaluate([easy]))
    #expect(result.status == .increase)
    #expect(result.nextWeightKg == 22.5)
    #expect(result.detail.contains("Reserve"))
  }

  @Test func closeToFailureKeepsBuildingReps() throws {
    let hard = session(
      2, "kurzhantel_bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 20, rir: 1) })
    let earlier = session(5, "kurzhantel_bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 7, weightKg: 20) })
    let result = try #require(evaluate([earlier, hard]))
    #expect(result.status == .build)
    // Ohne RIR-Angabe greift die neue Regel nicht.
    let unknown = session(2, "kurzhantel_bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 20) })
    #expect(try #require(evaluate([earlier, unknown])).status == .build)
  }

  @Test func customExercisesUseTheirOwnRange() throws {
    let own = ExerciseInfo.custom(name: "Landmine Press", group: .shoulders, equipment: .barbell, tracking: .weightReps)
    let done = session(1, own.id, sets: (0..<3).map { _ in LoggedSet(reps: 12, weightKg: 30) })
    let result = try #require(
      GymProgression.evaluate(sessions: [done], ranges: [:], custom: [own], today: today).first)
    #expect(result.status == .increase)
    #expect(result.target == 8...12)
  }
}

struct GymHintsTests {
  @Test func inputCarriesDecisionsAndEvidence() throws {
    let easy = session(
      2, "kurzhantel_bankdruecken", sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 20, rir: 4) })
    let progress = GymProgression.evaluate(sessions: [easy], ranges: [:], today: today)
    let input = GymHints.input(progress: progress, recovered: true, volume: [.chest: 3], goal: .buildMuscle)
    let line = try #require(input["exercises"]?.arrayValue?.first?.stringValue)
    #expect(line.hasPrefix("Kurzhantel-Bankdrücken: zuletzt 20 kg × 8/8/8 Wdh., Ziel 6–10 → Erhöhen auf 22,5 kg"))
    #expect(input["recovery"]?.stringValue == "gut")
    #expect(input["goal"]?.stringValue == "Muskeln aufbauen")
    #expect(input["volume"]?.arrayValue?.first?.stringValue == "Brust: 3 Sätze in 7 Tagen")
    #expect(input["evidence"]?.arrayValue?.count == GymHints.evidence.count)
    #expect(GymHints.fallback(progress) == ["Kurzhantel-Bankdrücken: Erhöhen auf 22,5 kg (+12,5 %)."])
  }
}
