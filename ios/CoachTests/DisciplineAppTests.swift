import CoachCore
import Foundation
import Testing

@testable import Coach

@MainActor
struct DisciplineAppTests {
  @Test func timeTextParsesMinutesAndHours() {
    #expect(TimeText.seconds("8:40") == 520)
    #expect(TimeText.seconds(" 1:45:00 ") == 6300)
    #expect(TimeText.seconds("4:75") == nil)
    #expect(TimeText.seconds("abc") == nil)
    #expect(TimeText.hms(6300) == "1:45:00")
  }

  @Test func recordingATestUpdatesSeasonAndHistory() throws {
    let defaults = try #require(UserDefaults(suiteName: "tests-\(UUID().uuidString)"))
    let settings = CoachSettings(defaults: defaults)
    let day = CalendarDay(year: 2026, month: 12, day: 7)
    settings.record(.ftp, value: 185, on: day)
    settings.record(.css, value: 128, on: day)
    settings.record(.halfMarathon, value: 6300, on: day)
    #expect(settings.season.ftpWatts == 185)
    #expect(settings.season.cssSecondsPer100m == 128)
    #expect(settings.halfMarathonSeconds == 6300)
    #expect(CoachSettings(defaults: defaults).tests.count == 3)
  }
}
