import Foundation
import Testing

@testable import CoachCore

struct MealReminderTests {
  let today = CalendarDay(year: 2026, month: 11, day: 2)

  var settings: MealReminderSettings {
    var settings = MealReminderSettings()
    settings.breakfast.enabled = true
    settings.lunch.enabled = true
    settings.dinner.enabled = true
    return settings
  }

  @Test func skipsPastLoggedAndDisabled() {
    // 10:00 Uhr, Mittagessen heute schon erfasst.
    let logged: Set<String> = [ReminderPlanner.loggedKey(day: today, category: .lunch)]
    let notes = ReminderPlanner.meals(settings, today: today, minutesNow: 600, logged: logged)
    let ids = notes.map(\.id)
    #expect(
      ids == [
        "coach.reminder.meal.2026-11-02.abendessen",
        "coach.reminder.meal.2026-11-03.fruehstueck",
        "coach.reminder.meal.2026-11-03.mittagessen",
        "coach.reminder.meal.2026-11-03.abendessen",
      ])
    #expect(notes.first?.hour == 19)
    #expect(notes.first?.title == "Abendessen eintragen")
    // Alles aus: keine Mitteilung.
    #expect(ReminderPlanner.meals(MealReminderSettings(), today: today, minutesNow: 0, logged: []).isEmpty)
  }

  @Test func changedTimesAndDecoding() throws {
    var changed = settings
    changed.dinner = .init(enabled: true, hour: 20, minute: 15)
    let note = ReminderPlanner.meals(changed, today: today, minutesNow: 1_200, logged: []).first
    #expect(note?.hour == 20 && note?.minute == 15)
    let decoded = try JSONDecoder().decode(MealReminderSettings.self, from: Data(#"{"lunch": {"enabled": true}}"#.utf8))
    #expect(decoded == MealReminderSettings())
    #expect(!decoded.anyEnabled)
    #expect(MealReminderSettings.Slot(hour: 30, minute: -5).hour == 23)
  }
}
