import Foundation
import Testing

@testable import CoachCore

// Audit SCI: Schutzgrenzen der Ernährungsziele. Beide Tests schlagen mit dem Stand 8baa407 fehl.

private let auditDay = CalendarDay(year: 2026, month: 10, day: 23)

private func auditRun(minutes: Double, kcal: Double) -> GarminActivity {
  var activity = GarminActivity(id: 9_001)
  activity.typeKey = "running"
  activity.durationSeconds = minutes * 60
  activity.calories = kcal
  activity.startLocal = "\(auditDay.iso) 07:00:00"
  return activity
}

struct AuditSCINutritionSafetyTests {
  /// SCI-01: Die übernommene Anpassung (−500 kcal aus dem Gewichtsverlauf) gilt auch an harten Tagen, an denen das
  /// Ziel-Defizit ausgesetzt ist (`goalScale` 0). Die REDs-Untergrenze greift aber nur bei `goalPercent < 0`
  /// (NutritionTargets.swift:330) – die Energieverfügbarkeit fällt so unter 30 kcal/kg fettfreie Masse.
  @Test func energyAvailabilityFloorAlsoAppliesToNegativeAdjustment() {
    var settings = NutritionSettings()
    settings.weightKilograms = 50
    settings.heightCentimeters = 160
    settings.age = 30
    settings.isFemale = true
    settings.bodyFatPercent = 25
    settings.activityFactor = 1.2
    settings.goal = .lose
    settings.weeklyWeightChangePercent = -0.5
    settings.energyAdjustmentKilocalories = -500

    let targets = NutritionPlanner.compute(
      activities: [auditRun(minutes: 100, kcal: 1_100)], planItems: [], settings: settings, garminProfile: nil,
      day: auditDay, hasGarminData: true)

    #expect(targets.dayType == .hard)
    let fatFreeMass = 50 * (1 - 0.25)
    let floor = 30 * fatFreeMass + targets.exerciseKilocalories
    let kcal = targets.values[.kcal] ?? 0
    // Energieverfügbarkeit = (Zufuhr − Trainingsverbrauch) / fettfreie Masse ≥ 30 kcal/kg (Mountjoy et al. 2023).
    #expect(kcal >= floor - 1, "Zufuhr \(kcal) kcal liegt unter der REDs-Untergrenze \(floor) kcal")
    #expect(targets.energyAvailabilityFloorApplied)
  }

  /// SCI-03: „Die App … stoppt bei BMI 18,5“ (GoalRules.swift:112). `GoalRules.assess` läuft aber nur beim Speichern
  /// des Profils; `NutritionPlanner.compute` wendet das Defizit auch an, wenn das aktuelle Gewicht schon unter BMI 18,5
  /// liegt. Erwartet: kein Defizit (Ziel wie „halten“) bei BMI < 18,5.
  @Test func noDeficitBelowMinimumBMI() {
    var losing = NutritionSettings()
    losing.weightKilograms = 55
    losing.heightCentimeters = 175  // BMI 18,0
    losing.age = 30
    losing.isFemale = true
    losing.goal = .lose
    losing.weeklyWeightChangePercent = -0.5
    var holding = losing
    holding.goal = .maintain
    holding.weeklyWeightChangePercent = nil

    let lose = NutritionPlanner.compute(
      activities: [], planItems: [], settings: losing, garminProfile: nil, day: auditDay, hasGarminData: true)
    let maintain = NutritionPlanner.compute(
      activities: [], planItems: [], settings: holding, garminProfile: nil, day: auditDay, hasGarminData: true)

    #expect(GoalRules.bmi(lose.profile) < GoalRules.minimumBMI)
    #expect((lose.values[.kcal] ?? 0) >= (maintain.values[.kcal] ?? 0) - 1)
  }
}
