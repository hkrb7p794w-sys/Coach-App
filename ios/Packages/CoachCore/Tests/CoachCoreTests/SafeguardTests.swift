import Foundation
import Testing

@testable import CoachCore

/// Montag, 2.11.2026.
private let monday = CalendarDay(year: 2026, month: 11, day: 2)

struct InputCheckTests {
  private let body = BodyProfile(weightKilograms: 72, heightCentimeters: 170, age: 30, isFemale: true)

  @Test func implausibleBodyValues() {
    #expect(InputCheck.body(body).isEmpty)
    let typo = BodyProfile(weightKilograms: 720, heightCentimeters: 17, age: 300, isFemale: true)
    #expect(Set(InputCheck.body(typo).map(\.id)) == ["weight", "height", "age"])
  }

  @Test func contradictoryWeightTargets() {
    var profile = UserProfile(goal: .loseWeight)
    profile.targets.targetWeightKilograms = 75
    let issues = InputCheck.goals(profile: profile, body: body, predictions: nil, today: monday)
    #expect(issues.first?.id == "target-weight-direction")
    profile.targets.targetWeightKilograms = 65
    #expect(InputCheck.goals(profile: profile, body: body, predictions: nil, today: monday).isEmpty)
  }

  @Test func eventTimeAgainstWatchPrediction() throws {
    var predictions = RacePredictions()
    predictions.tenK = 3_000
    predictions.halfMarathon = 6_600
    var profile = UserProfile(goal: .improveFitness)
    profile.event = EventGoal(name: "HM", date: monday.adding(days: 70), kind: .halfMarathon, targetSeconds: 5_700)
    let veryFast = try #require(
      InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first)
    #expect(veryFast.severity == .warning)
    #expect(veryFast.message.contains("14 % schneller"))
    #expect(veryFast.message.contains("10 Wochen"))
    profile.event?.targetSeconds = 6_200
    #expect(
      InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first?.severity == .tip)
    profile.event?.targetSeconds = 6_700
    #expect(
      InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday).first?.severity == .info)
    profile.event?.date = monday.adding(days: -1)
    let past = InputCheck.goals(profile: profile, body: body, predictions: predictions, today: monday)
    #expect(past.first?.id == "event-past")
  }

  @Test func predictionInterpolatesBetweenDistances() throws {
    var predictions = RacePredictions()
    predictions.fiveK = 1_500
    predictions.tenK = 3_120
    let fifteen = try #require(InputCheck.predictedSeconds(distanceKilometers: 7.5, predictions: predictions))
    #expect(fifteen > 1_500 && fifteen < 3_120)
    #expect(InputCheck.predictedSeconds(distanceKilometers: 10, predictions: predictions) == 3_120)
    #expect(InputCheck.predictedSeconds(distanceKilometers: 3, predictions: predictions) == nil)
    #expect(InputCheck.predictedSeconds(distanceKilometers: 5, predictions: nil) == nil)
  }
}

struct WeightTrendTests {
  /// Täglich gewogen mit leichtem Rauschen: `perWeek` kg Änderung pro Woche.
  private func entries(start: Double, perWeek: Double, days: Int = 28) -> [WeightEntry] {
    (0..<days).map { offset in
      let noise = offset.isMultiple(of: 2) ? 0.3 : -0.3
      return WeightEntry(
        day: monday.adding(days: offset - days + 1), kilograms: start + perWeek * Double(offset) / 7 + noise,
        source: .manual)
    }
  }

  @Test func needsEnoughWeighIns() {
    #expect(WeightTrend.trend(entries(start: 80, perWeek: -0.4, days: 7), today: monday) == nil)
    #expect(WeightTrend.trend(Array(entries(start: 80, perWeek: -0.4).prefix(5)), today: monday) == nil)
  }

  @Test func onTrackFasterAndSlower() throws {
    // 80 kg, −0,4 kg pro Woche ≈ −0,5 % → wie geplant.
    let onTrack = try #require(WeightTrend.trend(entries(start: 80, perWeek: -0.4), today: monday))
    #expect(abs(onTrack.weeklyPercent + 0.5) < 0.1)
    #expect(WeightTrend.advice(result: onTrack, plannedPercent: -0.5, currentAdjustment: 0).kind == .onTrack)

    // −1 kg pro Woche ≈ −1,3 % → zu schnell, mehr essen.
    let fast = try #require(WeightTrend.trend(entries(start: 80, perWeek: -1.0), today: monday))
    let fastAdvice = WeightTrend.advice(result: fast, plannedPercent: -0.5, currentAdjustment: 0)
    #expect(fastAdvice.kind == .tooFast)
    #expect(fastAdvice.kilocalories > 0 && fastAdvice.kilocalories <= WeightTrend.maxStepKilocalories)

    // Gewicht steigt trotz Abnehmziel → weniger essen, in 50er-Schritten.
    let gaining = try #require(WeightTrend.trend(entries(start: 80, perWeek: 0.2), today: monday))
    let less = WeightTrend.advice(result: gaining, plannedPercent: -0.5, currentAdjustment: 0)
    #expect(less.kind == .eatLess)
    #expect(less.kilocalories < 0)
    #expect(less.kilocalories.truncatingRemainder(dividingBy: 50) == 0)
    // Gesamtgrenze ±500 kcal.
    #expect(WeightTrend.advice(result: gaining, plannedPercent: -0.5, currentAdjustment: -500).kilocalories == 0)
  }

  @Test func manualBeatsGarminAndGarminParses() {
    let day = monday
    let merged = WeightTrend.merged([
      WeightEntry(day: day, kilograms: 70, source: .garmin), WeightEntry(day: day, kilograms: 71, source: .manual),
      WeightEntry(day: day.adding(days: 1), kilograms: 900, source: .manual),
    ])
    #expect(merged == [WeightEntry(day: day, kilograms: 71, source: .manual)])
    let json = JSONValue.object([
      "dailyWeightSummaries": .array([
        .object([
          "summaryDate": .string("2026-11-01"),
          "latestWeight": .object(["weight": .number(72_360), "calendarDate": .string("2026-11-01")]),
        ])
      ])
    ])
    let expected = [WeightEntry(day: monday.adding(days: -1), kilograms: 72.4, source: .garmin)]
    #expect(WeightTrend.garminEntries(json) == expected)
  }

  @Test func adjustmentChangesTargets() {
    var settings = NutritionSettings()
    settings.weightKilograms = 80
    settings.heightCentimeters = 180
    settings.age = 35
    settings.isFemale = false
    let base = NutritionPlanner.compute(
      activities: [], planItems: [], settings: settings, garminProfile: nil, day: monday, hasGarminData: false)
    settings.energyAdjustmentKilocalories = 200
    let more = NutritionPlanner.compute(
      activities: [], planItems: [], settings: settings, garminProfile: nil, day: monday, hasGarminData: false)
    #expect((more.values[.kcal] ?? 0) - (base.values[.kcal] ?? 0) >= 150)
  }
}

struct LoadCheckTests {
  private func run(_ daysAgo: Int, km: Double) -> GarminActivity {
    var activity = GarminActivity(id: Int64(daysAgo * 10 + Int(km)))
    activity.typeKey = "running"
    activity.startLocal = "\(monday.adding(days: -daysAgo).iso) 08:00:00"
    activity.distanceMeters = km * 1000
    return activity
  }

  @Test func warnsAboutSteepIncrease() {
    let baseline = [8, 12, 15, 19, 22, 26].map { run($0, km: 10) }
    let calm = LoadCheck.running(activities: baseline + [run(1, km: 10), run(3, km: 10)], today: monday)
    #expect(calm.warning == nil)
    let steep = LoadCheck.running(
      activities: baseline + [run(1, km: 12), run(3, km: 12), run(5, km: 12)], today: monday)
    #expect(steep.warning != nil)
    #expect(steep.baselineKilometers == 20)
    #expect(steep.lastWeekKilometers == 36)
  }

  @Test func noWarningForSmallVolumes() {
    let result = LoadCheck.running(activities: [run(10, km: 2), run(1, km: 4)], today: monday)
    #expect(result.warning == nil)
  }
}

struct StricterRecipeTests {
  @Test func hiddenAllergens() {
    #expect(RecipePlanner.violations("Basilikumpesto", diet: .vegan, allergens: []) == ["Milchprodukte"])
    let nuts = RecipePlanner.violations("Basilikumpesto", diet: .omnivore, allergens: [.nuts])
    #expect(nuts == ["Schalenfrüchte (Nüsse)"])
    #expect(RecipePlanner.violations("Worcestersauce", diet: .vegetarian, allergens: []) == ["Fisch"])
    #expect(RecipePlanner.violations("Mayonnaise", diet: .omnivore, allergens: [.egg]) == ["Ei"])
    #expect(RecipePlanner.violations("Sojasauce", diet: .vegan, allergens: [.gluten]) == ["Gluten"])
    #expect(RecipePlanner.violations("Vegane Mayonnaise", diet: .vegan, allergens: []).isEmpty)
  }

  @Test func implausibleNutrients() {
    func item(_ values: [Nutrient: Double]) -> MealItem {
      MealItem(name: "X", grams: 100, source: .ai, per100g: NutrientValues(values))
    }
    #expect(!RecipePlanner.implausible(item([.kcal: 370, .protein: 13, .carbs: 59, .fat: 7])))
    #expect(RecipePlanner.implausible(item([.kcal: 1_200])))
    #expect(RecipePlanner.implausible(item([.kcal: 100, .protein: 30, .carbs: 30, .fat: 10])))
    #expect(RecipePlanner.implausible(item([.kcal: 400, .protein: 60, .carbs: 60])))
    #expect(!RecipePlanner.implausible(item([.kcal: 25, .protein: 1, .carbs: 4, .fat: 0.2])))
  }
}

struct PersonaTests {
  @Test func allPersonasKeepEverySafeguard() {
    for persona in PersonaReport.personas {
      let result = PersonaReport.evaluate(persona)
      for check in result.checks {
        #expect(check.passed, "\(persona.name): \(check.rule) – \(check.detail)")
      }
      #expect(result.checks.count >= 4)
    }
  }

  @Test func reportMentionsEveryPersona() {
    let report = PersonaReport.run()
    #expect(report.contains("Alle Schutzregeln eingehalten."))
    for persona in PersonaReport.personas { #expect(report.contains("## \(persona.name)")) }
    #expect(report.contains("💡"))
  }
}
