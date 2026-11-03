import Foundation
import Testing

@testable import CoachCore

/// Audit CORE1: Energie-Untergrenze (REDs), BMI-Grenze und Defizit bei hohem Körpergewicht in `NutritionPlanner`.
private let auditDay = CalendarDay(year: 2026, month: 11, day: 3)

private func auditSettings(
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

private func auditTargets(_ settings: NutritionSettings, activities: [GarminActivity] = []) -> NutritionTargets {
  NutritionPlanner.compute(
    activities: activities, planItems: [], settings: settings, garminProfile: nil, day: auditDay, hasGarminData: true)
}

struct AuditNutritionTargetsTests {
  /// CORE1-01: Mit Ziel „halten“ und übernommener Anpassung −500 kcal greift die REDs-Untergrenze nicht
  /// (`goalPercent < 0` ist Bedingung, NutritionTargets.swift:330). Der Fußtext in WeightViews.swift:280 verspricht das
  /// Gegenteil. Handrechnung: Mann 55 kg, 170 cm, 30 J., KF 12 %, PAL 1,2 → Grundumsatz 1.467,5, Bedarf 1.761;
  /// −500 → 1.261. FFM 48,4 kg → Untergrenze 30 × 48,4 = 1.452 kcal. Erwartet ≥ 1.452 und Flag gesetzt;
  /// tatsächlich 1.320 kcal (nur durch die Makro-Untergrenzen), Flag false.
  @Test func energyAvailabilityFloorAlsoAppliesToNegativeAdjustment() {
    var settings = auditSettings(weight: 55, height: 170, age: 30, female: false)
    settings.activityFactor = 1.2
    settings.bodyFatPercent = 12
    settings.energyAdjustmentKilocalories = -500
    let result = auditTargets(settings)
    #expect(result.energyAvailabilityFloorApplied)
    #expect((result.values[.kcal] ?? 0) >= 1_452)
  }

  /// CORE1-01 (zweiter Pfad): Harter Tag (100 min Laufen, 1.100 kcal) mit Ziel Abnehmen und −500 kcal Anpassung.
  /// `goalScale` = 0 → `goalPercent` = 0 → keine Prüfung, die −500 kcal gelten trotzdem (Zeile 324).
  /// Handrechnung: Netto-Training 1.100 − 1.467,5/1.440 × 100 = 998,1; Tag 1.761 + 998 = 2.759; −500 → 2.259.
  /// Untergrenze 1.452 + 998 = 2.450. Erwartet ≥ 2.450; tatsächlich ≈ 2.259 (EA ≈ 26 kcal/kg FFM).
  @Test func energyAvailabilityFloorOnHardDayWithAdjustment() {
    var settings = auditSettings(weight: 55, height: 170, age: 30, female: false, goal: .lose)
    settings.activityFactor = 1.2
    settings.bodyFatPercent = 12
    settings.energyAdjustmentKilocalories = -500
    var run = GarminActivity(id: 1)
    run.typeKey = "running"
    run.durationSeconds = 100 * 60
    run.calories = 1_100
    run.startLocal = "\(auditDay.iso) 07:00:00"
    let result = auditTargets(settings, activities: [run])
    #expect(result.dayType == .hard)
    #expect(result.energyAvailabilityFloorApplied)
    #expect((result.values[.kcal] ?? 0) >= 2_450)
  }

  /// CORE1-02: 150 kg, 180 cm, 40 J., Mann, Ziel Abnehmen (−0,5 %/Woche). Protein 2,2 g/kg und Mindest-KH 3 g/kg
  /// auf das Gesamtgewicht plus Fettboden (Zeile 348) und die REDs-Untergrenze mit pauschal 15 % Körperfett
  /// (FFM 127,5 kg → 3.825 kcal, Zeile 327–333) heben das Ziel über den Erhaltungsbedarf.
  /// Handrechnung: halten = 3.600 kcal (P 270 g, KH 450 g, F 80 g); abnehmen = 3.900 kcal (P 330, KH 450, F 86,7).
  /// Erwartet: abnehmen < halten; tatsächlich 3.900 > 3.600.
  @Test func losingTargetStaysBelowMaintenanceForHeavyPerson() {
    let maintain = auditTargets(auditSettings(weight: 150, height: 180, age: 40, female: false))
    var losing = auditSettings(weight: 150, height: 180, age: 40, female: false, goal: .lose)
    losing.weeklyWeightChangePercent = -0.5
    let lose = auditTargets(losing)
    #expect((lose.values[.kcal] ?? 0) < (maintain.values[.kcal] ?? 0))
    // Die REDs-Untergrenze darf das Ziel nicht über den Erhaltungsbedarf heben.
    #expect(!lose.energyAvailabilityFloorApplied)
  }

  /// CORE1-03: GoalRules wird nur beim Speichern des Profils angewandt (CoachSettings.swift:314–322). Sinkt das
  /// Gewicht danach unter BMI 18,5 (Garmin-Sync, Eingabe in den Körperwerten), rechnet der Planer weiter mit Defizit;
  /// der Hinweis „stoppt bei BMI 18,5“ (GoalRules.swift:112) stimmt nicht. 50 kg / 170 cm = BMI 17,3.
  /// Handrechnung: halten 1.985 kcal, abnehmen (−0,5 %) 1.710 kcal. Erwartet: kein Defizit (abnehmen ≥ halten).
  @Test func noDeficitBelowMinimumBMI() {
    let maintain = auditTargets(auditSettings(weight: 50, height: 170, age: 30, female: false))
    var losing = auditSettings(weight: 50, height: 170, age: 30, female: false, goal: .lose)
    losing.weeklyWeightChangePercent = -0.5
    let lose = auditTargets(losing)
    #expect(GoalRules.bmi(lose.profile) < GoalRules.minimumBMI)
    #expect((lose.values[.kcal] ?? 0) >= (maintain.values[.kcal] ?? 0) - 1)
  }
}
