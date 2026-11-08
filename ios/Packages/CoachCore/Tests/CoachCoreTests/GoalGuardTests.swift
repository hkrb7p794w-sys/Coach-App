import Foundation
import Testing

@testable import CoachCore

/// Schutzgrenzen für Gewichtsziele: Sie gelten in jedem Pfad, nicht nur beim Speichern des Profils (Phase 74).
private let day = CalendarDay(year: 2026, month: 11, day: 3)

private func settings(
  weight: Double, height: Double, age: Int, female: Bool, goal: NutritionGoal = .maintain
) -> NutritionSettings {
  var settings = NutritionSettings()
  settings.weightKilograms = weight
  settings.heightCentimeters = height
  settings.age = age
  settings.isFemale = female
  settings.goal = goal
  return settings
}

private func targets(_ settings: NutritionSettings, activities: [GarminActivity] = []) -> NutritionTargets {
  NutritionPlanner.compute(
    activities: activities, planItems: [], settings: settings, garminProfile: nil, day: day, hasGarminData: true)
}

private func hardRun() -> GarminActivity {
  var run = GarminActivity(id: 1)
  run.typeKey = "running"
  run.durationSeconds = 100 * 60
  run.calories = 1_100
  run.startLocal = "\(day.iso) 07:00:00"
  return run
}

private func weighIn(_ offset: Int, _ kilograms: Double) -> WeightEntry {
  WeightEntry(day: day.adding(days: offset), kilograms: kilograms, source: .manual)
}

struct GoalGuardTests {
  private let gaining = WeightTrend.Result(trendKilograms: 60, weeklyPercent: 1, entries: 10, spanDays: 20)

  // MARK: - Tagesziele

  /// Mann 55 kg, 170 cm, 30 J., KF 12 %, PAL 1,2: Bedarf 1.761 kcal; −500 kcal → 1.261 kcal.
  /// Fettfreie Masse 48,4 kg → Untergrenze 1.452 kcal.
  @Test func energyFloorAppliesToNegativeAdjustment() {
    var value = settings(weight: 55, height: 170, age: 30, female: false)
    value.activityFactor = 1.2
    value.bodyFatPercent = 12
    value.energyAdjustmentKilocalories = -500
    let result = targets(value)
    #expect(result.energyAvailabilityFloorApplied)
    #expect((result.values[.kcal] ?? 0) >= 1_452)
  }

  /// Harter Tag: Das Ziel-Defizit ruht (`goalScale` 0), die Anpassung gilt, die Untergrenze muss also greifen.
  @Test func energyFloorAppliesOnHardDay() {
    var value = settings(weight: 55, height: 170, age: 30, female: false, goal: .lose)
    value.activityFactor = 1.2
    value.bodyFatPercent = 12
    value.energyAdjustmentKilocalories = -500
    let result = targets(value, activities: [hardRun()])
    #expect(result.dayType == .hard)
    #expect(result.energyAvailabilityFloorApplied)
    #expect((result.values[.kcal] ?? 0) >= 2_450)
  }

  @Test func deficitStaysAtMostAQuarterWithAdjustment() {
    var value = settings(weight: 90, height: 180, age: 35, female: false, goal: .lose)
    value.weeklyWeightChangePercent = -1
    let plain = targets(value)
    value.energyAdjustmentKilocalories = -500
    let adjusted = targets(value)
    var maintain = settings(weight: 90, height: 180, age: 35, female: false)
    maintain.weeklyWeightChangePercent = nil
    let need = targets(maintain).values[.kcal] ?? 0
    #expect((plain.values[.kcal] ?? 0) >= 0.75 * need - 1)
    #expect((adjusted.values[.kcal] ?? 0) >= 0.75 * need - 1)
  }

  /// 150 kg, 180 cm, 40 J.: Das Ziel „Abnehmen“ lag mit 3.900 kcal über dem Erhaltungsbedarf von 3.600 kcal.
  @Test func losingStaysBelowMaintenanceForHeavyPerson() {
    let maintain = targets(settings(weight: 150, height: 180, age: 40, female: false))
    var losing = settings(weight: 150, height: 180, age: 40, female: false, goal: .lose)
    losing.weeklyWeightChangePercent = -0.5
    let lose = targets(losing)
    #expect((lose.values[.kcal] ?? 0) < (maintain.values[.kcal] ?? 0))
    #expect(!lose.energyAvailabilityFloorApplied)
  }

  /// Ab BMI 30 zählt für Protein das Gewicht bei BMI 25 (81 kg bei 180 cm), darunter das Körpergewicht.
  @Test func proteinUsesReferenceWeightOnlyFromObesity() {
    let heavy = targets(settings(weight: 120, height: 180, age: 40, female: false, goal: .lose))
    #expect(abs(heavy.referenceWeightKilograms - 81) < 0.01)
    #expect(abs((heavy.values[.protein] ?? 0) - (2.2 * 81).rounded()) <= 1)
    let normal = targets(settings(weight: 90, height: 180, age: 40, female: false, goal: .lose))
    #expect(normal.referenceWeightKilograms == 90)
  }

  /// Kleine, ältere Person: Protein und Mindest-Kohlenhydrate allein lägen über dem Bedarf.
  @Test func minimumMacrosDoNotExceedMaintenanceInDeficit() {
    var maintain = settings(weight: 50, height: 155, age: 70, female: true)
    maintain.activityFactor = 1.2
    var losing = maintain
    losing.goal = .lose
    losing.weeklyWeightChangePercent = -0.5
    let need = NutritionPlanner.mifflinStJeor(targets(losing).profile) * 1.2
    #expect((targets(losing).values[.kcal] ?? 0) <= need + 1)
  }

  // MARK: - Grenzen im laufenden Betrieb

  /// Das Gewicht sinkt nach dem Speichern unter BMI 18,5: kein Defizit mehr, auch ohne neues Speichern des Profils.
  @Test func noDeficitBelowMinimumBMI() {
    let maintain = targets(settings(weight: 50, height: 170, age: 30, female: false))
    var losing = settings(weight: 50, height: 170, age: 30, female: false, goal: .lose)
    losing.weeklyWeightChangePercent = -0.5
    #expect(GoalRules.weightGuard(settings: losing, body: targets(losing).profile) == .noDeficit)
    #expect((targets(losing).values[.kcal] ?? 0) >= (maintain.values[.kcal] ?? 0) - 1)
  }

  @Test func minorGetsNoDeficitOrSurplus() {
    let maintain = targets(settings(weight: 70, height: 175, age: 16, female: false))
    var losing = settings(weight: 70, height: 175, age: 16, female: false, goal: .lose)
    losing.weeklyWeightChangePercent = -0.5
    losing.energyAdjustmentKilocalories = -300
    #expect(targets(losing).values[.kcal] == maintain.values[.kcal])
    var gaining = settings(weight: 70, height: 175, age: 16, female: false, goal: .gain)
    gaining.weeklyWeightChangePercent = 0.25
    #expect(targets(gaining).values[.kcal] == maintain.values[.kcal])
  }

  @Test func withheldTargetsIgnoreGoalAndAdjustment() {
    let maintain = targets(settings(weight: 70, height: 170, age: 30, female: true))
    var value = settings(weight: 70, height: 170, age: 30, female: true, goal: .lose)
    value.weeklyWeightChangePercent = -0.5
    value.energyAdjustmentKilocalories = -500
    value.weightTargetsWithheld = true
    #expect(targets(value).values[.kcal] == maintain.values[.kcal])
  }

  @Test func applyClearsAdjustmentWhenBlocked() {
    var value = NutritionSettings()
    value.energyAdjustmentKilocalories = -500
    var profile = UserProfile(goal: .loseWeight)
    profile.health = [.pregnantOrPostpartum]
    let body = BodyProfile(weightKilograms: 70, heightCentimeters: 170, age: 30, isFemale: true)
    GoalRules.apply(GoalRules.assess(profile: profile, body: body), to: &value)
    #expect(value.energyAdjustmentKilocalories == 0)
    #expect(value.weightTargetsWithheld)

    var thin = NutritionSettings()
    thin.energyAdjustmentKilocalories = -500
    let lowBMI = BodyProfile(weightKilograms: 50, heightCentimeters: 175, age: 30, isFemale: true)
    GoalRules.apply(GoalRules.assess(profile: UserProfile(goal: .loseWeight), body: lowBMI), to: &thin)
    #expect(thin.energyAdjustmentKilocalories == 0)
    #expect(!thin.weightTargetsWithheld)
  }

  @Test func settingsDecodeWithoutNewFields() throws {
    let decoded = try JSONDecoder().decode(NutritionSettings.self, from: Data(#"{"goal":"abnehmen"}"#.utf8))
    #expect(!decoded.weightTargetsWithheld)
    #expect(decoded.lastAppliedWeighInDay == nil)
  }

  // MARK: - Vorschläge

  @Test func adviceNeverSuggestsEatingLessWhenGuarded() {
    let free = WeightTrend.advice(result: gaining, plannedPercent: nil, currentAdjustment: 0)
    #expect(free.kind == .eatLess)
    let noDeficit = WeightTrend.advice(result: gaining, plannedPercent: nil, currentAdjustment: 0, safety: .noDeficit)
    #expect(noDeficit.kilocalories == 0)
    let withheld = WeightTrend.advice(result: gaining, plannedPercent: nil, currentAdjustment: 0, safety: .noTargets)
    #expect(withheld.kilocalories == 0)
    #expect(!withheld.message.contains("kcal"))
  }

  @Test func expenditureProposesNoCutWhenGuarded() {
    let result = Expenditure.Result(
      kilocalories: 2_000, averageIntake: 2_000, loggedDays: 20, excludedDays: 0, kilogramsPerWeek: 0, plausible: true)
    #expect(Expenditure.adjustment(result, formulaMaintenance: 2_400, current: 0) == -400)
    #expect(Expenditure.adjustment(result, formulaMaintenance: 2_400, current: 0, safety: .noDeficit) == nil)
    #expect(Expenditure.adjustment(result, formulaMaintenance: 2_400, current: 0, safety: .noTargets) == nil)
    let higher = Expenditure.Result(
      kilocalories: 2_800, averageIntake: 2_800, loggedDays: 20, excludedDays: 0, kilogramsPerWeek: 0, plausible: true)
    #expect(Expenditure.adjustment(higher, formulaMaintenance: 2_400, current: 0, safety: .noDeficit) == 400)
  }

  // MARK: - Zielgewicht und Wägungen

  private let reached = BodyProfile(weightKilograms: 69, heightCentimeters: 175, age: 35, isFemale: false)

  @Test func reachedLossTargetHoldsWeight() {
    var profile = UserProfile(goal: .loseWeight)
    profile.targets = ImprovementTargets(targetWeightKilograms: 70, weeksToTargetWeight: 10)
    let result = GoalRules.assess(profile: profile, body: reached)
    #expect(result.weeklyChangePercent == nil)
    #expect(result.nutritionGoal == .maintain)
    #expect(!result.blocksWeightChange)
  }

  @Test func reachedGainTargetHoldsWeight() {
    var profile = UserProfile(goal: .buildMuscle)
    profile.targets = ImprovementTargets(targetWeightKilograms: 68, weeksToTargetWeight: 10)
    #expect(GoalRules.assess(profile: profile, body: reached).weeklyChangePercent == nil)
  }

  @Test func newestWeighInBecomesCurrentWeightOnce() {
    var value = NutritionSettings()
    value.weightKilograms = 80
    var changed = GoalRules.updateWeight(&value, entries: [weighIn(-3, 78.26), weighIn(-1, 77.94)], today: day)
    #expect(changed)
    #expect(value.weightKilograms == 77.9)
    // Eine Eingabe in den Einstellungen bleibt, bis eine neuere Wägung kommt.
    value.weightKilograms = 75
    changed = GoalRules.updateWeight(&value, entries: [weighIn(-3, 78.26), weighIn(-1, 77.94)], today: day)
    #expect(!changed)
    #expect(value.weightKilograms == 75)
    changed = GoalRules.updateWeight(&value, entries: [weighIn(0, 74.5)], today: day)
    #expect(changed)
    #expect(value.weightKilograms == 74.5)
  }

  @Test func oldWeighInsDoNotChangeWeight() {
    var value = NutritionSettings()
    value.weightKilograms = 80
    let changed = GoalRules.updateWeight(&value, entries: [weighIn(-40, 70)], today: day)
    #expect(!changed)
    #expect(value.weightKilograms == 80)
  }

  /// Ein laufendes Tempo bleibt unangetastet; nur beim Wechsel zwischen Halten und Ändern wird neu angewandt.
  @Test func holdChangesOnlyWhenStateFlips() {
    var running = NutritionSettings()
    running.weeklyWeightChangePercent = -0.5
    let loss = GoalAssessment(
      nutritionGoal: .lose, weeklyChangePercent: -0.3, notes: [], evidenceIDs: [], blocksWeightChange: false)
    let hold = GoalAssessment(
      nutritionGoal: .maintain, weeklyChangePercent: nil, notes: [], evidenceIDs: [], blocksWeightChange: true)
    #expect(!GoalRules.holdChanged(loss, settings: running))
    #expect(GoalRules.holdChanged(hold, settings: running))
    #expect(GoalRules.holdChanged(loss, settings: NutritionSettings()))
    #expect(!GoalRules.holdChanged(hold, settings: NutritionSettings()))
  }

  // MARK: - KI und Anzeige

  @Test func coachingProfileDropsBlockedWeightGoal() {
    var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .loseWeight)
    profile.goals = PersonalGoals(primary: .fatLoss, secondary: [.health, .fatLoss], priorities: [], since: day)
    var nutrition = NutritionSettings()
    nutrition.weightTargetsWithheld = true
    let safe = GoalRules.coachingProfile(profile, nutrition: nutrition)
    #expect(safe.goal == .maintain)
    #expect(safe.goals?.primary == .health)
    #expect(safe.goals?.secondary.isEmpty == true)
    let text = Personalization.contextLines(safe.effectiveGoals(today: day)).joined(separator: " ")
    #expect(!text.contains("Defizit"))
  }

  @Test func coachingProfileKeepsActiveWeightGoal() {
    let profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .loseWeight)
    var nutrition = NutritionSettings()
    nutrition.goal = .lose
    nutrition.weeklyWeightChangePercent = -0.5
    #expect(GoalRules.coachingProfile(profile, nutrition: nutrition).goal == .loseWeight)
  }

  @Test func chatForbidsWeightTargetsWhenWithheld() {
    var facts = ChatContext.Facts(profile: UserProfile(goal: .maintain), privacy: .reduced)
    #expect(!ChatContext.lines(facts).contains { $0.contains("nicht zum Abnehmen") })
    facts.withholdsWeightTargets = true
    #expect(ChatContext.lines(facts).contains { $0.contains("nicht zum Abnehmen") })
  }

  // MARK: - Mikronährstoffe

  /// DGE: Calcium 1.200 mg von 13 bis unter 19 Jahren, danach 1.000 mg.
  @Test func teenagersGetHigherCalciumTarget() {
    #expect(targets(settings(weight: 60, height: 170, age: 16, female: true)).values[.calcium] == 1_200)
    #expect(targets(settings(weight: 60, height: 170, age: 30, female: true)).values[.calcium] == 1_000)
  }
}
