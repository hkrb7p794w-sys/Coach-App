import Foundation
import Testing

@testable import CoachCore

struct GymBookTests {
  @Test func gymBookPlansUseKnownExercises() {
    let routines = RoutineTemplates.gymBook
    #expect(routines.map(\.name) == ["Lower", "Push & Pull B", "Pull A", "Push A"])
    for item in routines.flatMap(\.items) {
      #expect(ExerciseLibrary.info(item.exerciseID) != nil, "\(item.exerciseID)")
      #expect(item.sets == 2)
    }
    let bench = routines[3].items.first { $0.exerciseID == "bankdruecken" }
    #expect(bench?.weightKg == 52.5)
    #expect(routines[3].items.last?.upperReps == 60)
    // Ältere gespeicherte Routinen ohne Startgewicht bleiben lesbar.
    let old =
      #"{"id":"6F2C1C4E-9A57-4B4B-9E6D-6F0B2C8C2B11","exerciseID":"plank","name":"Plank","sets":2,"#
      + #""lowerReps":20,"upperReps":60,"restSeconds":60}"#
    let decoded = try? JSONDecoder().decode(RoutineItem.self, from: Data(old.utf8))
    #expect(decoded?.weightKg == nil)
  }

  @Test func everyLibraryExerciseHasAGarminCategory() {
    for exercise in ExerciseLibrary.all {
      #expect(GarminExerciseMapping.code(for: exercise.id).category != GarminExerciseMapping.unknown, "\(exercise.id)")
    }
  }

  @Test func strengthFitRoundTrip() throws {
    let start = Date(timeIntervalSince1970: 1_793_000_000)
    let session = GymSession(
      workoutKey: nil, title: "Push A", start: start, end: start.addingTimeInterval(45 * 60),
      exercises: [
        LoggedExercise(
          exerciseID: "bankdruecken", name: "Bankdrücken mit Langhantel", group: .chest,
          sets: [LoggedSet(reps: 12, weightKg: 52.5), LoggedSet(reps: 11, weightKg: 52.5)]),
        LoggedExercise(
          exerciseID: "plank", name: "Planks", group: .core, sets: [LoggedSet(reps: 60, weightKg: 0)]),
        LoggedExercise(
          exerciseID: "dips_barren", name: "Dips am Barren", group: .triceps,
          sets: [LoggedSet(reps: 12, weightKg: 79, done: false)]),
      ])
    let data = StrengthFitExport.fit(session)
    // Prüfsumme über die ganze Datei inklusive CRC ergibt 0.
    #expect(FitEncoder.crc([UInt8](data)) == 0)
    let decoded = try FitDecoder.decode(data)
    let active = decoded.sets.filter(\.active)
    #expect(active.count == 3)
    #expect(active[0].repetitions == 12)
    #expect(active[0].weightKg == 52.5)
    #expect(active[0].category == 0)
    #expect(active[0].subtype == 1)
    #expect(active[2].category == 19)
    #expect(active[2].repetitions == nil)
    #expect(active[2].durationSeconds == 60)
    #expect(decoded.sets.filter { !$0.active }.count == 2)
    #expect(decoded.laps.count == 1)
  }
}
