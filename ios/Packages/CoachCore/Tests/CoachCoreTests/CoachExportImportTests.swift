import Foundation
import Testing

@testable import CoachCore

struct CoachExportImportTests {
  let monday = CalendarDay(year: 2026, month: 10, day: 26)

  func input(mode: UserProfile.Mode = .personal) -> CoachExport.Input {
    var profile = UserProfile(mode: mode, sports: [.run, .strength])
    var week = WeekSchedule()
    week.set([SessionSlot(.run)], on: .tuesday)
    profile.schedule = week
    var metrics = DailyMetrics(day: monday)
    metrics.restingHeartRate = 48
    metrics.sleepSeconds = 7.5 * 3_600
    var old = DailyMetrics(day: monday.adding(days: -40))
    old.restingHeartRate = 99
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.startLocal = "2026-10-27 07:00:00"
    run.durationSeconds = 2_700
    run.distanceMeters = 8_420
    let start = monday.referenceDate
    let session = GymSession(
      workoutKey: nil, title: "Push A", start: start, end: start.addingTimeInterval(3_000),
      exercises: [
        LoggedExercise(
          exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
          sets: [LoggedSet(reps: 10, weightKg: 52.5), LoggedSet(reps: 9, weightKg: 52.5, rir: 1)])
      ])
    let item = MealItem(
      name: "Haferflocken", grams: 80, source: .manual, per100g: NutrientValues([.kcal: 370, .protein: 13]))
    return CoachExport.Input(
      profile: profile, schedule: week, routines: RoutineTemplates.gymBook, custom: [], equipment: Equipment.gym,
      metrics: [metrics, old], activities: [run], gym: [session],
      meals: [CoachExport.Meal(day: monday, category: "Frühstück", title: "Porridge", items: [item])],
      weights: [WeightEntry(day: monday, kilograms: 80.4, source: .manual)])
  }

  @Test func exportContainsRangeAndInstructions() {
    let text = CoachExport.markdown(input(), from: monday.adding(days: -6), to: monday.adding(days: 1))
    #expect(text.contains("```ironludi"))
    #expect(text.contains("| 2026-10-26 | 48 | – | 7.5 |"))
    #expect(!text.contains("| 99 |"))
    #expect(text.contains("| 2026-10-27 07:00:00 | running | – | 45 | 8.42 |"))
    #expect(text.contains("- Bankdrücken [bankdruecken]: 52.5×10, 52.5×9 (RIR 1)"))
    #expect(text.contains("### 2026-10-26: 296 kcal, Protein 10 g"))
    #expect(text.contains("- 2026-10-26: 80.4 kg"))
    #expect(text.contains("- Dienstag: Lockerer Lauf"))
    #expect(text.contains("- dips_barren – Dips am Barren – Trizeps"))
    #expect(text.contains("\"wochenplan\""))
    #expect(!CoachExport.markdown(input(mode: .season), from: monday, to: monday).contains("\"wochenplan\""))
  }

  @Test func importChecksRoutinesAndSchedule() throws {
    let answer = """
      Hier meine Analyse … Dein Ruhepuls ist stabil.

      ```ironludi
      {
        "routinen": {"modus": "ersetzen", "liste": [
          {"name": "Push neu", "uebungen": [
            {"id": "bankdruecken", "saetze": 8, "wdh_min": 6, "wdh_max": 10, "pause": 120, "gewicht": 55},
            {"name": "Dips am Barren", "saetze": 3},
            {"id": "fantasie", "saetze": 3}
          ]}
        ]},
        "wochenplan": {"gilt_fuer": "naechste_woche", "tage": {
          "mo": [{"sport": "kraft", "intensitaet": "intensiv"}], "di": [], "mi": [{"sport": "tanzen"}]
        }},
        "hinweise": ["Schlaf vor harten Tagen priorisieren."]
      }
      ```
      """
    let profile = input().profile
    let preview = try CoachImport.preview(answer, profile: profile, equipment: Equipment.gym, custom: [])
    #expect(preview.routineMode == .replace)
    #expect(preview.routines.first?.items.map(\.exerciseID) == ["bankdruecken", "dips_barren"])
    #expect(preview.routines.first?.items.first?.sets == 5)
    #expect(preview.routines.first?.items.first?.weightKg == 55)
    #expect(preview.corrections.contains("Unbekannte Übung „fantasie“ entfernt."))
    #expect(preview.corrections.contains { $0.hasPrefix("Mittwoch: Sportart „tanzen“") })
    #expect(preview.scheduleScope == .nextWeek)
    #expect(preview.schedule?.slots(on: .monday) == [SessionSlot(.strength, .hard)])
    #expect(preview.schedule?.slots(on: .tuesday).isEmpty == true)
    #expect(preview.notes == ["Schlaf vor harten Tagen priorisieren."])

    // Saisonplan: Wochenplan wird nicht übernommen.
    let season = try CoachImport.preview(
      answer, profile: input(mode: .season).profile, equipment: Equipment.gym, custom: [])
    #expect(season.schedule == nil)
  }

  @Test func importNeedsBlock() {
    #expect(throws: CoachImport.ImportError.noBlock) {
      try CoachImport.preview("Nur Text", profile: UserProfile(), equipment: Equipment.gym, custom: [])
    }
    #expect(throws: CoachImport.ImportError.invalidJSON) {
      try CoachImport.preview("```ironludi\n{kaputt\n```", profile: UserProfile(), equipment: [], custom: [])
    }
    let plain = "```json\n{\"hinweise\": [\"Mehr trinken\"]}\n```"
    let notes = try? CoachImport.preview(plain, profile: UserProfile(), equipment: [], custom: []).notes
    #expect(notes == ["Mehr trinken"])
  }
}
