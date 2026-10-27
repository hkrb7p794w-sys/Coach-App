import Foundation
import Testing

@testable import CoachCore

struct GymBookImportTests {
  let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

  @Test func mappingPointsToLibraryExercises() {
    for (name, id) in GymBookImport.mapping {
      #expect(ExerciseLibrary.info(id) != nil, "\(name) → \(id)")
    }
  }

  @Test func rowsBecomeSessionsWithSets() {
    let rows = [
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 28_340, exercise: "Curls in Hammerhaltung am Kabel", frequency: 10,
        quantity: 22.5, workout: "Push & Pull B"),
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 28_613, exercise: "Curls in Hammerhaltung am Kabel", frequency: 9,
        quantity: 22.5, workout: "Push & Pull B"),
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 29_000, exercise: "Bankdrücken an Multipresse", region: "020.chest",
        equipment: "010.flatBench|050.smithMachine", frequency: 8, quantity: 40, workout: "Push & Pull B"),
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 31_290, exercise: "Planks", frequency: 60, frequencyUnit: "s",
        quantity: nil, workout: "Push & Pull B"),
      // ausgelassen, Ausdauer und ohne Wiederholungen: nicht übernehmen
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 31_300, exercise: "Dips am Barren", frequency: 5, quantity: 79,
        skipped: true, workout: "Push & Pull B"),
      GymBookImport.LogRow(
        day: "2024-02-06", secondsOfDay: 30_000, exercise: "Stationäres Radfahren", frequency: 5,
        frequencyUnit: "m", quantity: 10, quantityUnit: "km"),
      GymBookImport.LogRow(
        day: "2026-10-21", secondsOfDay: 30_000, exercise: "Einarmiges Lat-Ziehen", frequency: nil, quantity: 50,
        workout: "Pull A"),
    ]
    let result = GymBookImport.sessions(rows, custom: [], timeZone: berlin)
    #expect(result.ignoredRows == 3)
    #expect(result.sessions.count == 1)
    let session = result.sessions[0]
    #expect(session.title == "Push & Pull B")
    #expect(session.workoutKey == "gymbook:2026-10-23:Push & Pull B")
    #expect(session.exercises.map(\.exerciseID) == ["hammer_curl_kabel", "eigen_bankdruecken_an_multipresse", "plank"])
    #expect(session.exercises[0].sets.map(\.reps) == [10, 9])
    #expect(session.exercises[0].sets.allSatisfy { $0.weightKg == 22.5 && $0.done })
    #expect(session.exercises[2].sets.first?.reps == 60)
    #expect(session.end.map { $0.timeIntervalSince(session.start) } == 3_010)
    #expect(session.day == CalendarDay(year: 2026, month: 10, day: 23))

    let multipresse = result.newCustom.first
    #expect(multipresse?.group == .chest)
    #expect(multipresse?.equipment == [.machine])

    // Zweiter Import: gleiche ID, keine neue eigene Übung.
    let again = GymBookImport.sessions(rows, custom: result.newCustom, timeZone: berlin)
    #expect(again.sessions.first?.id == session.id)
    #expect(again.newCustom.isEmpty)
  }

  @Test func armRegionSplitsIntoBicepsAndTriceps() {
    #expect(GymBookImport.group(region: "040.arms", muscles: "041.armFlexors") == .biceps)
    #expect(GymBookImport.group(region: "040.arms", muscles: "040.armExtensors") == .triceps)
    #expect(GymBookImport.group(region: "060.buttocks", muscles: "060.glutes") == .legs)
    #expect(GymBookImport.equipment("078.cablesMachine") == .cable)
    #expect(GymBookImport.equipment("031.dumbbells") == .dumbbell)
  }
}
