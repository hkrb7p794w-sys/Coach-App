import Foundation
import Testing

@testable import CoachCore

struct MealHeadlineTests {
  typealias Streak = WidgetSnapshot.Streak

  private func meals(_ kcal: [Double]) -> [WidgetSnapshot.MealPart] {
    zip(MealSplit.order, kcal).map { WidgetSnapshot.MealPart(category: $0, kcal: $1, target: 500) }
  }

  private func text(
    _ kcal: [Double], remaining: Double? = 1_000, streak: Streak? = Streak(days: 1, activeToday: true), hour: Int = 13
  ) -> String {
    MealHeadline.text(meals: meals(kcal), kcalRemaining: remaining, kcalTarget: 2_000, streak: streak, hour: hour)
  }

  @Test func beforeTheFirstEntryFollowsTheTimeOfDay() {
    let none = Streak(days: 0, activeToday: false)
    #expect(text([0, 0, 0, 0], streak: none, hour: 7) == "Guten Morgen – Frühstück eintragen?")
    #expect(text([0, 0, 0, 0], streak: none, hour: 12) == "Mittagessen eintragen?")
    #expect(text([0, 0, 0, 0], streak: none, hour: 18) == "Heute noch nichts eingetragen")
    #expect(text([0, 0, 0, 0], streak: none, hour: 22) == "Noch kurz den Tag eintragen?")
    // Mit Serie von gestern: der nächste Tag, ohne Drohung.
    let yesterday = Streak(days: 4, activeToday: false)
    #expect(text([0, 0, 0, 0], streak: yesterday, hour: 7) == "Tag 5 der Serie – los geht’s")
  }

  @Test func changesWithEveryMeal() {
    #expect(text([400, 0, 0, 0]) == "Guter Start – Mittagessen steht an")
    let running = Streak(days: 6, activeToday: true)
    #expect(text([400, 0, 0, 0], streak: running) == "Tag 6 der Serie – Mittagessen steht an")
    #expect(text([400, 500, 0, 0], remaining: 640.4) == "Noch 640 kcal – Abendessen fehlt")
    #expect(text([400, 500, 0, 0], remaining: -50) == "Fast komplett – Abendessen fehlt noch")
    // Frühstück ausgelassen: als Nächstes das Abendessen, nicht rückwirkend das Frühstück.
    #expect(text([0, 500, 0, 0]) == "Guter Start – Abendessen steht an")
    #expect(text([0, 0, 0, 150]) == "Snack notiert – Frühstück eintragen?")
  }

  @Test func dayBalanceWhenAllMainMealsAreLogged() {
    #expect(text([400, 500, 600, 0], remaining: 60) == "Tagesziel getroffen – stark!")
    #expect(text([400, 500, 600, 0], remaining: 420) == "Alles eingetragen · noch 420 kcal frei")
    #expect(text([400, 500, 900, 100], remaining: -310) == "Alles eingetragen · 310 kcal über Ziel")
    // Ohne Kalorienziel (z. B. gesperrte Gewichtsziele) keine Kalorien im Satz.
    #expect(text([400, 500, 600, 0], remaining: nil) == "Alles eingetragen – stark!")
    #expect(
      text([400, 500, 600, 0], remaining: nil, streak: Streak(days: 9, activeToday: true))
        == "Alles eingetragen – Tag 9 der Serie")
  }
}
