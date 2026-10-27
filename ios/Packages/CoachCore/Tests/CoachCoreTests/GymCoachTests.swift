import Foundation
import Testing

@testable import CoachCore

struct GymCoachTests {
  let monday = Date(timeIntervalSince1970: 1_792_000_000)

  func session(daysAgo: Int, weight: Double, reps: Int, sets: Int = 3, id: String = "bankdruecken") -> GymSession {
    GymSession(
      workoutKey: nil, title: "Push", start: monday.addingTimeInterval(Double(-daysAgo) * 86_400),
      exercises: [
        LoggedExercise(
          exerciseID: id, name: "Bankdrücken", group: .chest,
          sets: (0..<sets).map { _ in LoggedSet(reps: reps, weightKg: weight) })
      ])
  }

  @Test func plateauAndLowVolumeAreReported() {
    let sessions = [
      session(daysAgo: 14, weight: 60, reps: 8), session(daysAgo: 7, weight: 60, reps: 8),
      session(daysAgo: 1, weight: 60, reps: 8),
    ]
    let lines = GymCoach.observations(sessions: sessions, today: CalendarDay(date: monday))
    #expect(lines.contains { $0.hasPrefix("Bankdrücken: seit drei Einheiten 60 kg") })
    #expect(lines.contains { $0.hasPrefix("Brust: 3 Sätze in 7 Tagen") })
    #expect(lines.contains { $0.hasPrefix("Brust: nur an einem Tag") })
    #expect(lines.contains { $0.hasPrefix("Beine: 0 Sätze") })
  }

  @Test func progressingExerciseIsNoPlateau() {
    let sessions = [
      session(daysAgo: 14, weight: 60, reps: 8), session(daysAgo: 7, weight: 60, reps: 9),
      session(daysAgo: 1, weight: 60, reps: 10),
    ]
    let lines = GymCoach.observations(sessions: sessions, today: CalendarDay(date: monday))
    #expect(!lines.contains { $0.contains("Stillstand") })
    #expect(GymCoach.observations(sessions: [], today: CalendarDay(date: monday)).isEmpty)
  }

  @Test func planIsCheckedAgainstLibraryEquipmentAndLimits() throws {
    let json = """
      {"routinen": [
        {"name": "Oberkörper", "uebungen": [
          {"id": "bankdruecken", "saetze": 9, "wdh_min": 6, "wdh_max": 10, "pause": 600},
          {"id": "erfunden", "saetze": 3},
          {"id": "bankdruecken", "saetze": 3},
          {"id": "plank", "saetze": 2, "wdh_min": 30, "wdh_max": 500}
        ]},
        {"name": "Beine", "uebungen": [{"id": "kniebeuge", "saetze": 3}]},
        {"name": "Zu viel", "uebungen": [{"id": "latziehen", "saetze": 3}]}
      ], "hinweise": ["Zweimal pro Woche je Muskel."]}
      """
    let output = try JSONValue(data: Data(json.utf8))
    var request = GymCoach.PlanRequest()
    request.daysPerWeek = 2
    let result = GymCoach.validatePlan(
      output, request: request, equipment: [.machine, .cable, .bench, .barbell], custom: [],
      lastWeights: ["bankdruecken": 52.5])
    #expect(result.routines.map(\.name) == ["Oberkörper", "Beine"])
    let upper = result.routines[0].items
    #expect(upper.map(\.exerciseID) == ["bankdruecken", "plank"])
    #expect(upper[0].sets == 5)
    #expect(upper[0].restSeconds == 240)
    #expect(upper[0].weightKg == 52.5)
    #expect(upper[1].upperReps == 120)
    #expect(result.corrections.contains("Unbekannte Übung „erfunden“ entfernt."))
    #expect(result.corrections.contains("Bankdrücken: Sätze auf 5 begrenzt."))
    #expect(result.notes.first == "Zweimal pro Woche je Muskel.")
    #expect(result.notes.contains { $0.hasPrefix("Rücken: 0 Sätze pro Woche") })

    // Ohne Langhantel fällt die Kniebeuge weg.
    let home = GymCoach.validatePlan(output, request: request, equipment: Equipment.homeDumbbells, custom: [])
    #expect(home.routines.map(\.name) == ["Oberkörper"])
    #expect(home.corrections.contains { $0.hasPrefix("Kniebeuge braucht Ausstattung") })
  }

  @Test func planInputListsOnlyAvailableExercises() {
    var request = GymCoach.PlanRequest()
    request.daysPerWeek = 9
    request.focus = [.chest]
    let input = GymCoach.planInput(
      request: request, profile: UserProfile(), equipment: Equipment.none, routines: RoutineTemplates.gymBook,
      sessions: [session(daysAgo: 1, weight: 52.5, reps: 12)], custom: [], today: CalendarDay(date: monday))
    #expect(input["days"] == .number(6))
    let library = input["library"]?.arrayValue?.compactMap(\.stringValue) ?? []
    #expect(library.contains { $0.hasPrefix("plank |") })
    #expect(!library.contains { $0.hasPrefix("bankdruecken |") })
    #expect(input["lastWeights"] == .array([.string("bankdruecken: 52,5 kg × 12")]))
    #expect(input["focus"] == .array([.string("Brust")]))
  }
}
