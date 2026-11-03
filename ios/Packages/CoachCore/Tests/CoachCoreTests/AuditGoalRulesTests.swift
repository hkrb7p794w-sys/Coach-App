import Foundation
import Testing

@testable import CoachCore

/// Audit CORE1-04: Zielgewicht schon erreicht – `weeklyLossPercent`/`weeklyGainPercent` fallen dann auf das
/// Standardtempo zurück (GoalRules.swift:37–39, 47–49), und `assess` plant weiter ab- bzw. zunehmen.
struct AuditGoalRulesTests {
  private let body = BodyProfile(weightKilograms: 69, heightCentimeters: 175, age: 35, isFemale: false)

  /// Ziel 70 kg, aktuell 69 kg: erwartet halten (`weeklyChangePercent == nil`); tatsächlich −0,5 %/Woche.
  @Test func reachedLossTargetHoldsWeight() {
    var profile = UserProfile(goal: .loseWeight)
    profile.targets = ImprovementTargets(targetWeightKilograms: 70, weeksToTargetWeight: 10)
    let result = GoalRules.assess(profile: profile, body: body)
    #expect(result.weeklyChangePercent == nil)
    #expect(result.nutritionGoal == .maintain)
  }

  /// Ziel 68 kg bei „Muskeln aufbauen“, aktuell 69 kg: erwartet kein Überschuss; tatsächlich +0,25 %/Woche.
  @Test func reachedGainTargetHoldsWeight() {
    var profile = UserProfile(goal: .buildMuscle)
    profile.targets = ImprovementTargets(targetWeightKilograms: 68, weeksToTargetWeight: 10)
    let result = GoalRules.assess(profile: profile, body: body)
    #expect((result.weeklyChangePercent ?? 0) <= 0)
  }
}
