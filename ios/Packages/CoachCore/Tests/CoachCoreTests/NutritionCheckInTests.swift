import Foundation
import Testing

@testable import CoachCore

struct NutritionCheckInTests {
  /// Mittwoch, 11.11.2026; Montag dieser Woche ist der 9.11.
  let today = CalendarDay(year: 2026, month: 11, day: 11)

  @Test func dueOncePerWeekWithData() {
    let data = [today.adding(days: -2)]
    #expect(NutritionCheckIn.isDue(today: today, last: nil, withheld: false, weighIns: data, mealDays: []))
    // Letzte Woche erledigt → wieder fällig.
    #expect(
      NutritionCheckIn.isDue(today: today, last: today.adding(days: -5), withheld: false, weighIns: data, mealDays: []))
    // Am Montag dieser Woche erledigt → nicht mehr.
    #expect(
      !NutritionCheckIn.isDue(
        today: today, last: CalendarDay(year: 2026, month: 11, day: 9), withheld: false, weighIns: data, mealDays: []))
  }

  @Test func notDueWithoutDataOrWhenWithheld() {
    #expect(!NutritionCheckIn.isDue(today: today, last: nil, withheld: false, weighIns: [], mealDays: []))
    #expect(
      !NutritionCheckIn.isDue(
        today: today, last: nil, withheld: false, weighIns: [today.adding(days: -20)], mealDays: []))
    #expect(!NutritionCheckIn.isDue(today: today, last: nil, withheld: true, weighIns: [today], mealDays: [today]))
    #expect(NutritionCheckIn.isDue(today: today, last: nil, withheld: false, weighIns: [], mealDays: [today]))
  }

  @Test func oldSettingsDecodeWithoutCheckIn() throws {
    let settings = try JSONDecoder().decode(NutritionSettings.self, from: Data("{}".utf8))
    #expect(settings.lastCheckInDay == nil)
    var changed = settings
    changed.lastCheckInDay = today
    let decoded = try JSONDecoder().decode(NutritionSettings.self, from: JSONEncoder().encode(changed))
    #expect(decoded.lastCheckInDay == today)
  }
}
