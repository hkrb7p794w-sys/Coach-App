import Foundation
import Testing

@testable import CoachCore

struct AppRouteTests {
  @Test func urlRoundTrip() {
    for route in AppRoute.allCases {
      #expect(AppRoute(url: route.url) == route)
    }
    #expect(AppRoute.logMeal.url.absoluteString == "coach://open/logMeal")
  }

  @Test func foreignLinksAreIgnored() throws {
    let invite = try #require(URL(string: "coach://join?worker=https://x&token=a&league=abcdef"))
    #expect(AppRoute(url: invite) == nil)
    let unknown = try #require(URL(string: "coach://open/somethingNew"))
    #expect(AppRoute(url: unknown) == nil)
    let other = try #require(URL(string: "https://open/logMeal"))
    #expect(AppRoute(url: other) == nil)
  }

  @Test func gymRoutesFallBackWithoutStrength() {
    #expect(AppRoute.startWorkout.tab(trainsStrength: true) == .gym)
    #expect(AppRoute.startWorkout.tab(trainsStrength: false) == .training)
    #expect(AppRoute.health.tab(trainsStrength: true) == .training)
    #expect(AppRoute.logMeal.tab(trainsStrength: false) == .nutrition)
  }

  @Test func quickActionsOnlyOfferWorkingEntries() {
    let all = QuickActions.routes(trainsStrength: true, aiAvailable: true)
    #expect(all == [.startWorkout, .logMeal, .health, .aiAnalysis])
    #expect(QuickActions.routes(trainsStrength: false, aiAvailable: false) == [.logMeal, .health])
    #expect(QuickActions.routes(trainsStrength: true, aiAvailable: true).count <= QuickActions.limit)
  }
}
