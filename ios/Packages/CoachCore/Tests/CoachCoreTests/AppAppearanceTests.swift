import Testing

@testable import CoachCore

struct AppAppearanceTests {
  @Test func storedValuesRoundTrip() {
    for appearance in AppAppearance.allCases {
      #expect(AppAppearance(stored: appearance.rawValue) == appearance)
    }
  }

  @Test func unknownValuesFollowSystem() {
    #expect(AppAppearance(stored: nil) == .system)
    #expect(AppAppearance(stored: "sepia") == .system)
  }
}
