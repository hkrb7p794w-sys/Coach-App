import Foundation
import Testing

@testable import CoachCore

struct DataExportTests {
  let monday = CalendarDay(year: 2026, month: 10, day: 26)

  func input(empty: Bool = false) -> CoachExport.Input {
    let profile = UserProfile(mode: .personal, sports: [.run, .strength])
    guard !empty else {
      return CoachExport.Input(
        profile: profile, schedule: WeekSchedule(), routines: [], custom: [], equipment: Equipment.gym, metrics: [],
        activities: [], gym: [], meals: [], weights: [])
    }
    var metrics = DailyMetrics(day: monday)
    metrics.restingHeartRate = 48
    metrics.sleepSeconds = 7.5 * 3_600
    metrics.steps = 9_000
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.startLocal = "2026-10-27 07:00:00"
    run.durationSeconds = 2_700
    run.distanceMeters = 8_420
    var strength = GarminActivity(id: 2)
    strength.typeKey = "strength_training"
    strength.startLocal = "2026-10-26 18:00:00"
    let start = monday.referenceDate
    let session = GymSession(
      workoutKey: nil, title: "Push, A", start: start, end: start.addingTimeInterval(3_000),
      exercises: [
        LoggedExercise(
          exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
          sets: [LoggedSet(reps: 10, weightKg: 52.5), LoggedSet(reps: 9, weightKg: 52.5, rir: 1)])
      ])
    let item = MealItem(
      name: "Haferflocken", grams: 80, source: .manual, per100g: NutrientValues([.kcal: 370, .protein: 13]))
    return CoachExport.Input(
      profile: profile, schedule: WeekSchedule(), routines: [], custom: [], equipment: Equipment.gym,
      metrics: [metrics], activities: [run, strength], gym: [session],
      meals: [CoachExport.Meal(day: monday, category: "Frühstück", title: "Porridge", items: [item])],
      weights: [WeightEntry(day: monday, kilograms: 80.4, source: .manual)])
  }

  var range: (CalendarDay, CalendarDay) { (monday.adding(days: -6), monday.adding(days: 1)) }

  @Test func markdownOnlySelectedCategories() {
    let text = DataExport.markdown(input(), from: range.0, to: range.1, categories: [.recovery, .gym])
    #expect(text.contains("## Erholung"))
    #expect(text.contains("| 2026-10-26 | 48 | – | – | – | – |"))
    #expect(text.contains("Bankdrücken"))
    #expect(!text.contains("## Schlaf"))
    #expect(!text.contains("Haferflocken"))
    #expect(!text.contains("```ironludi"))
    let withImport = DataExport.markdown(
      input(), from: range.0, to: range.1, categories: [.gym], withImportFormat: true)
    #expect(withImport.contains("```ironludi"))
  }

  @Test func jsonMarksMissingAsNull() throws {
    let text = DataExport.json(input(), from: range.0, to: range.1, categories: Set(ExportCategory.allCases))
    let value = try JSONValue(data: Data(text.utf8))
    #expect(value["erholung"]?.arrayValue?.first?["ruhepuls"]?.doubleValue == 48)
    #expect(value["erholung"]?.arrayValue?.first?["hrv_ms"] == .null)
    // Krafttraining der Uhr steht nicht unter Ausdauer.
    #expect(value["ausdauer"]?.arrayValue?.count == 1)
    #expect(value["ausdauer"]?.arrayValue?.first?["distanz_km"]?.doubleValue == 8.42)
    #expect(value["gym"]?.arrayValue?.first?["uebungen"]?.arrayValue?.first?["saetze"]?.arrayValue?.count == 2)
    #expect(value["ernaehrung"]?.arrayValue?.first?["kcal"]?.doubleValue == 296)
    #expect(value["verlauf_wochen"]?.arrayValue?.isEmpty == false)
    #expect(value["export"]?["kategorien"]?.arrayValue?.count == 8)
  }

  @Test func csvOneFilePerCategoryWithQuoting() throws {
    let files = DataExport.csv(input(), from: range.0, to: range.1, categories: [.gym, .weight, .sleep])
    #expect(files.count == 3)
    let gym = try #require(files.first { $0.name.contains("-gym-") })
    #expect(gym.content.hasPrefix("datum,einheit,uebung_id"))
    #expect(gym.content.contains("\"Push, A\""))
    #expect(gym.content.contains(",52.5,9,1,"))
    let sleep = try #require(files.first { $0.name.contains("-schlaf-") })
    #expect(sleep.content.contains("2026-10-26,7.5,,,,"))
  }

  @Test func emptyDataStillExports() throws {
    let all = Set(ExportCategory.allCases)
    let text = DataExport.markdown(input(empty: true), from: range.0, to: range.1, categories: all)
    #expect(text.contains("# IronLudi"))
    #expect(!text.contains("## Erholung"))
    let jsonText = DataExport.json(input(empty: true), from: range.0, to: range.1, categories: all)
    let json = try JSONValue(data: Data(jsonText.utf8))
    #expect(json["gym"]?.arrayValue?.isEmpty == true)
    let counts = DataExport.counts(input(empty: true), from: range.0, to: range.1)
    #expect(counts.values.allSatisfy { $0 == 0 })
    #expect(DataExport.counts(input(), from: range.0, to: range.1)[.endurance] == 1)
  }

  @Test func promptsFillPlaceholdersAndAttachData() {
    let template = PromptLibrary.builtIn[0]
    let text = PromptLibrary.compose(template, input: input(), from: range.0, to: range.1)
    #expect(text.hasPrefix("Analysiere meine Trainingsdaten der letzten 8 Tage"))
    #expect(!text.contains("{"))
    #expect(text.contains("Arbeitsweise:"))
    #expect(text.contains("Bankdrücken"))
    let json = PromptLibrary.compose(template, input: input(), from: range.0, to: range.1, format: .json)
    #expect(json.contains("```json"))
    #expect(Set(PromptLibrary.builtIn.map(\.id)).count == PromptLibrary.builtIn.count)
    #expect(PromptLibrary.builtIn.allSatisfy { !$0.categories.isEmpty && !$0.isCustom })
    let custom = PromptTemplate(title: "Eigen", text: "Ziel {ziel}", categories: [.weight], days: 999)
    #expect(custom.days == 365)
    #expect(PromptLibrary.filled(custom, profile: input().profile, from: range.0, to: range.1).hasPrefix("Ziel "))
  }
}
