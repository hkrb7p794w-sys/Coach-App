import CoachCore
import Foundation
import Testing

@testable import Coach

@MainActor
struct ReminderAppTests {
  private func settings() throws -> (CoachSettings, UserDefaults) {
    let store = try #require(UserDefaults(suiteName: "test-\(UUID().uuidString)"))
    let settings = CoachSettings(defaults: store)
    var profile = UserProfile(mode: .personal, onboardingDone: true, sports: [.run, .strength], goal: .loseWeight)
    // Jeden Tag eine Einheit, damit der Test unabhängig vom heutigen Wochentag ist.
    for weekday in Weekday.allCases { profile.schedule.set([SessionSlot(.run)], on: weekday) }
    settings.profile = profile
    return (settings, store)
  }

  private func date(hour: Int) throws -> Date {
    try #require(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now))
  }

  @Test func todayOnlyBeforeReminderTime() throws {
    let (settings, _) = try settings()
    let service = ReminderService(settings: settings, center: nil)
    let today = CalendarDay(date: .now)
    #expect(service.reminders(seasonSchedule: nil, now: try date(hour: 6)).first?.day == today)
    #expect(service.reminders(seasonSchedule: nil, now: try date(hour: 9)).first?.day == today.adding(days: 1))
    settings.reminders.hour = 10
    #expect(service.reminders(seasonSchedule: nil, now: try date(hour: 9)).first?.day == today)
  }

  @Test func skipAndMoveAreStoredForThisWeekOnly() throws {
    let (settings, store) = try settings()
    let service = ReminderService(settings: settings, center: nil)
    let today = CalendarDay(date: .now)
    service.skip(today)
    #expect(settings.schedule(inWeekOf: today).slots(on: Weekday(day: today)).isEmpty)
    #expect(!service.reminders(seasonSchedule: nil, now: try date(hour: 6)).contains { $0.day == today })
    #expect(settings.schedule(inWeekOf: today.adding(days: 7)) == settings.profile.schedule)

    // Nach einem Neustart noch da.
    let reloaded = CoachSettings(defaults: store)
    #expect(reloaded.planAdjustments == settings.planAdjustments)

    settings.planAdjustments.undo(Weekday(day: today), inWeekOf: today)
    #expect(settings.schedule(inWeekOf: today) == settings.profile.schedule)
  }

  @Test func reminderSettingsDecodeTolerantly() throws {
    let decoded = try JSONDecoder().decode(ReminderSettings.self, from: Data(#"{"hour":30}"#.utf8))
    #expect(decoded.enabled)
    #expect(decoded.hour == 23)
    #expect(decoded.minute == 30)
  }
}
