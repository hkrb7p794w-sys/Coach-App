import Foundation
import Testing

@testable import CoachCore

private let today = CalendarDay(year: 2026, month: 10, day: 22)

private func session(
  _ iso: String, _ exerciseID: String, weight: Double, reps: [Int], group: MuscleGroup = .chest
) -> GymSession {
  let day = CalendarDay(iso: iso) ?? today
  let name = ExerciseCatalog.rulesByID[exerciseID]?.name ?? exerciseID
  return GymSession(
    workoutKey: nil, title: "Test", start: day.localNoon,
    exercises: [
      LoggedExercise(
        exerciseID: exerciseID, name: name, group: group, sets: reps.map { LoggedSet(reps: $0, weightKg: weight) })
    ])
}

extension CalendarDay {
  fileprivate var localNoon: Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
  }
}

struct ExerciseCatalogTests {
  /// Erwartungswerte: `exercise_names.classify` im Altbestand mit dem Trainingsplan.
  @Test func standardPlanMapsLikeLegacy() {
    let ids = GymPlan.standard.workouts.flatMap(\.exercises).map(\.rule.id)
    #expect(
      ids == [
        "fliegende", "trizepsstrecken", "bankdruecken", "seitheben", "dips", "plank",
        "rudern_kabel", "bizeps_curl", "latziehen_einarmig", "hammer_curl", "face_pull", "crunch",
        "hammer_curl", "trizepsstrecken", "latziehen", "bankdruecken", "reverse_fly", "dips",
        "beinbeugen", "beinstrecken", "beinpresse", "wadenheben", "crunch_geraet",
      ])
    #expect(GymPlan.standard.repRanges["bankdruecken"] == 8...12)
    #expect(GymPlan.standard.repRanges["plank"] == nil)
  }

  @Test func classifyRespectsWeightAndFallback() {
    #expect(ExerciseCatalog.key("Row (SEATED_CABLE_ROW)") == "ROW_SEATED_CABLE_ROW")
    #expect(ExerciseCatalog.classify("PULL_UP", hasWeight: true).id == "latziehen")
    #expect(ExerciseCatalog.classify("PULL_UP", hasWeight: false).id == "klimmzug")
    #expect(ExerciseCatalog.classify("PULL_UP").id == "klimmzug")
    let unknown = ExerciseCatalog.classify("Meine Übung")
    #expect(unknown.id == "meine_uebung")
    #expect(unknown.group == .other)
  }

  @Test func flexibleLegDayMovesToThursday() {
    let monday = CalendarDay(year: 2026, month: 10, day: 19)
    let plan = GymPlan.standard
    let early = plan.plannedDays(monday: monday, today: monday, doneDays: [])
    #expect(early[monday] == "push")
    #expect(early[monday.adding(days: 1)] == "legs")
    #expect(early[monday.adding(days: 3)] == nil)
    let late = plan.plannedDays(monday: monday, today: monday.adding(days: 2), doneDays: [])
    #expect(late[monday.adding(days: 3)] == "legs")
    let done = plan.plannedDays(monday: monday, today: monday.adding(days: 2), doneDays: [monday.adding(days: 1)])
    #expect(!done.values.contains("legs"))
  }
}

struct GymProgressionTests {
  private func evaluate(_ sessions: [GymSession], recovered: Bool? = nil) -> ExerciseProgress? {
    GymProgression.evaluate(sessions: sessions, plan: .standard, today: today, recovered: recovered).first
  }

  /// Erwartungswerte aus `gym_progress.evaluate_exercise` des Altbestands (Zielbereich 8–12 laut Plan).
  @Test func increaseWhenAllSetsAtTop() throws {
    let result = try #require(
      evaluate([
        session("2026-10-16", "bankdruecken", weight: 52.5, reps: [12, 11]),
        session("2026-10-20", "bankdruecken", weight: 52.5, reps: [12, 12]),
      ], recovered: false))
    #expect(result.status == .increase)
    #expect(result.nextWeightKg == 55)
    #expect(result.increasePercent == 4.8)
    #expect(result.headline == "Erhöhen auf 55 kg (+4,8 %)")
    #expect(result.detail.contains("Erholung aktuell eingeschränkt"))
  }

  @Test func increaseWhenTwiceCloseToTop() {
    let result = evaluate([
      session("2026-10-16", "bankdruecken", weight: 52.5, reps: [11, 12]),
      session("2026-10-20", "bankdruecken", weight: 52.5, reps: [12, 11]),
    ])
    #expect(result?.status == .increase)
    #expect(result?.nextWeightKg == 55)
  }

  @Test func buildCheckRestartBaselineBodyweight() {
    let build = evaluate([
      session("2026-10-13", "beinpresse", weight: 149, reps: [10, 9], group: .legs),
      session("2026-10-20", "beinpresse", weight: 149, reps: [11, 9], group: .legs),
    ])
    #expect(build?.status == .build)
    #expect(build?.nextWeightKg == 154)
    #expect(build?.increasePercent == 3.4)
    #expect(build?.headline == "Bei 149 kg bleiben")

    let check = evaluate([
      session("2026-10-13", "rudern_kabel", weight: 110, reps: [6, 5], group: .back),
      session("2026-10-20", "rudern_kabel", weight: 110, reps: [6, 6], group: .back),
    ])
    #expect(check?.status == .check)

    let restart = evaluate([session("2026-09-20", "latziehen", weight: 85, reps: [12, 12], group: .back)])
    #expect(restart?.status == .restart)
    #expect(restart?.nextWeightKg == 77.5)
    #expect(restart?.headline == "Wiedereinstieg mit ca. 77,5 kg")

    let baseline = evaluate([session("2026-10-20", "seitheben", weight: 13.75, reps: [12, 10])])
    #expect(baseline?.headline == "Ausgangswert 13,75 kg")

    let bodyweight = evaluate([session("2026-10-20", "dips", weight: 0, reps: [12, 12])])
    #expect(bodyweight?.status == .increase)
    #expect(bodyweight?.headline == "Zusatzgewicht beginnen")

    #expect(evaluate([session("2026-08-01", "dips", weight: 0, reps: [12, 12])]) == nil)
  }

  @Test func nextWeightMatchesLegacy() {
    func next(_ weight: Double, _ step: Double, _ percent: Double) -> [Double] {
      GymProgression.nextWeight(weight, step: step, percent: percent).map { [$0.0, $0.1] } ?? []
    }
    #expect(next(149, 5, 5) == [154, 3.4])
    #expect(next(22.5, 1.25, 2.5) == [23.75, 5.6])
    #expect(next(110, 2.5, 2.5) == [112.5, 2.3])
    #expect(next(7.5, 1, 2.5) == [8.5, 13.3])
    #expect(next(0, 1, 2.5).isEmpty)
  }

  @Test func warmupSetsAreIgnored() {
    let entry = GymProgression.summary(
      day: today,
      sets: [LoggedSet(reps: 10, weightKg: 20), LoggedSet(reps: 12, weightKg: 50), LoggedSet(reps: 10, weightKg: 52.5)])
    #expect(entry?.weight == 52.5)
    #expect(entry?.reps == [10])
    #expect(GymProgression.summary(day: today, sets: [LoggedSet(reps: 10, weightKg: 50, done: false)]) == nil)
  }

  @Test func muscleVolumeCountsDoneSets() {
    var sessions = [
      session("2026-10-20", "bankdruecken", weight: 52.5, reps: [12, 12, 10]),
      session("2026-10-10", "beinpresse", weight: 149, reps: [12, 12], group: .legs),
    ]
    sessions[0].exercises[0].sets[2].done = false
    let counts = MuscleVolume.setsPerGroup(sessions: sessions, today: today)
    #expect(counts[.chest] == 2)
    #expect(counts[.legs] == 0)
    #expect(MuscleVolume.daysSinceLegs(sessions: sessions, today: today) == 12)
    #expect(sessions[0].volumeKg == 52.5 * 24)
    #expect(GermanFormat.number(13.75) == "13,75")
    #expect(GermanFormat.number(55) == "55")
  }
}
