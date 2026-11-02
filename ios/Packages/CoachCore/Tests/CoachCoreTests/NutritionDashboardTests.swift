import Foundation
import Testing

@testable import CoachCore

struct NutritionDashboardTests {
  @Test func defaultsMoveAndHide() {
    var dashboard = NutritionDashboard()
    #expect(dashboard.visible.first == .budget)
    #expect(!dashboard.visible.contains(.summary))
    dashboard.set(.summary, visible: true)
    dashboard.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)
    #expect(dashboard.order.first == .meals)
    #expect(dashboard.visible.contains(.summary))
    dashboard.set(.nutrients, visible: false)
    #expect(!dashboard.visible.contains(.nutrients))
    #expect(dashboard.order.count == NutritionDashboard.Card.allCases.count)
  }

  @Test func decodesUnknownAndAddsNewCards() throws {
    let json = #"{"order": ["meals", "unbekannt", "meals", "budget"], "hidden": ["water", "x"]}"#
    let decoded = try JSONDecoder().decode(NutritionDashboard.self, from: Data(json.utf8))
    #expect(decoded.order.prefix(2) == [.meals, .budget])
    #expect(decoded.order.count == NutritionDashboard.Card.allCases.count)
    #expect(decoded.hidden == [.water])
    let roundTrip = try JSONDecoder().decode(NutritionDashboard.self, from: JSONEncoder().encode(decoded))
    #expect(roundTrip == decoded)
  }

  @Test func summaryNumbers() {
    let summary = NutritionDaySummary(eaten: 1_500, goal: 2_000, meals: 3)
    #expect(summary.remaining == 500)
    #expect(summary.percent == 75)
    #expect(NutritionDaySummary(eaten: 100, goal: nil, meals: 1).percent == nil)
  }
}
