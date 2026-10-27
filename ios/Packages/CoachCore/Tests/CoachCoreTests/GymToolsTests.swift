import Foundation
import Testing

@testable import CoachCore

struct GymToolsTests {
  @Test func platesPerSide() throws {
    let result = try #require(PlateCalculator.plates(total: 102.5))
    #expect(result.perSide == [25, 15, 1.25])
    #expect(result.remainder == 0)
    #expect(PlateCalculator.text(result) == "Je Seite: 25 + 15 + 1,25 kg")
    #expect(PlateCalculator.plates(total: 15) == nil)
    #expect(PlateCalculator.text(try #require(PlateCalculator.plates(total: 20))) == "Nur die Stange")
    let odd = try #require(PlateCalculator.plates(total: 21))
    #expect(odd.perSide.isEmpty)
    #expect(odd.remainder == 1)
  }

  @Test func warmUpForHeavyBarbellLift() {
    let steps = WarmUp.steps(working: 100, equipment: [.barbell], compound: true)
    #expect(steps.map(\.weightKg) == [20, 50, 70, 85])
    #expect(steps.map(\.reps) == [10, 5, 3, 2])
    #expect(WarmUp.text(Array(steps.prefix(2))) == "Aufwärmen: 20 kg × 10 · 50 kg × 5")
  }

  @Test func noWarmUpForLightOrIsolation() {
    #expect(WarmUp.steps(working: 30, equipment: [.barbell], compound: true).isEmpty)
    #expect(WarmUp.steps(working: 100, equipment: [.barbell], compound: false).isEmpty)
    #expect(WarmUp.steps(working: 20, equipment: [.dumbbell], compound: true).map(\.weightKg) == [10, 15])
    #expect(WarmUp.steps(working: 0, equipment: [.bodyweight], compound: true).isEmpty)
  }
}
