import Foundation
import Testing

@testable import CoachCore

struct GameTests {
  let today = CalendarDay(year: 2026, month: 11, day: 11)  // Mittwoch

  @Test func streakCountsUntilYesterdayWhenTodayIsOpen() {
    let days = Set((1...5).map { today.adding(days: -$0) })
    let streak = DailyStreak.compute(activeDays: days, today: today)
    #expect(streak.current == 5)
    #expect(!streak.activeToday)
    let withToday = DailyStreak.compute(activeDays: days.union([today]), today: today)
    #expect(withToday.current == 6)
    #expect(withToday.activeToday)
  }

  @Test func oneJokerPerWeekBridgesAGap() {
    // Mo 09., Di 10. aktiv; So 08. fehlt (Joker der Vorwoche), Sa 07., Fr 06. aktiv.
    let days = Set([9, 10, 7, 6].map { CalendarDay(year: 2026, month: 11, day: $0) })
    let streak = DailyStreak.compute(activeDays: days, today: today)
    #expect(streak.current == 5)
    #expect(streak.jokerDays == [CalendarDay(year: 2026, month: 11, day: 8)])
    // Je Woche ein Joker: 09.11. (diese Woche) und 07.11. (Vorwoche); die zweite Lücke der Vorwoche beendet die Serie.
    let gaps = Set([10, 8, 6, 4].map { CalendarDay(year: 2026, month: 11, day: $0) })
    let bridged = DailyStreak.compute(activeDays: gaps, today: today)
    #expect(bridged.current == 5)
    #expect(bridged.jokerDays == [9, 7].map { CalendarDay(year: 2026, month: 11, day: $0) })
  }

  @Test func withoutJokersOnlyGaplessDaysCount() {
    // Di 10. und Mo 09. aktiv, So 08. fehlt: ohne Joker endet die Serie dort.
    let days = Set([10, 9, 7, 6].map { CalendarDay(year: 2026, month: 11, day: $0) })
    let strict = DailyStreak.compute(activeDays: days, today: today, jokers: 0)
    #expect(strict.current == 2)
    #expect(strict.jokerDays.isEmpty)
    #expect(DailyStreak.compute(activeDays: days, today: today).current == 5)
    // Vorgestern zuletzt eingetragen: keine Serie mehr.
    let stale = DailyStreak.compute(activeDays: [today.adding(days: -2)], today: today, jokers: 0)
    #expect(stale.current == 0)
  }

  @Test func noStreakWithoutActivity() {
    let streak = DailyStreak.compute(activeDays: [], today: today)
    #expect(streak.current == 0)
    #expect(streak.best == 0)
    let old = DailyStreak.compute(activeDays: Set((20...29).map { today.adding(days: -$0) }), today: today)
    #expect(old.current == 0)
    #expect(old.best == 10)
  }

  @Test func badgesRewardConsistencyNotVolume() {
    var stats = GameStats()
    stats.workouts = 12
    stats.bestDayStreak = 8
    stats.friends = 1
    let earned = Set(BadgeRules.earned(stats).map(\.id))
    #expect(earned == ["workout.1", "workout.10", "streak.7", "friends.1"])
    #expect(BadgeRules.next(stats) != nil)
    #expect(Set(BadgeRules.all.map(\.id)).count == BadgeRules.all.count)
  }

  @Test func challengeValuesAreCapped() {
    let monday = CalendarDay(year: 2026, month: 11, day: 9)
    let minutes: [CalendarDay: Int] = [monday: 200, monday.adding(days: 1): 45, monday.adding(days: 5): 60]
    let meals: Set<CalendarDay> = [monday, monday.adding(days: 2)]
    func value(_ metric: ChallengeMetric) -> Int {
      metric.value(monday: monday, today: today, minutesByDay: minutes, mealDays: meals, adherence: nil)
    }
    // Samstag liegt nach heute (Mittwoch) und zählt noch nicht.
    #expect(value(.minutes) == 90 + 45)
    #expect(value(.sessions) == 2)
    #expect(value(.meals) == 2)
    #expect(value(.plan) == 0)
    #expect(ChallengeMetric.minutes.max == 630)
  }

  @Test func decodesWorkerChallenge() throws {
    let json = #"""
      {"id": "c1", "title": "Minuten-Duell", "metric": "minutes", "metricTitle": "Trainingsminuten", "max": 630,
       "week": "2026-11-09", "finished": true, "status": "joined", "mineCreated": false,
       "members": [{"username": "lena", "displayName": "Lena", "status": "joined", "progress": 240, "me": true,
                    "winner": true}]}
      """#
    let challenge = try JSONDecoder().decode(Challenge.self, from: Data(json.utf8))
    #expect(challenge.kind == .minutes)
    #expect(challenge.iWon)
    #expect(challenge.monday == CalendarDay(year: 2026, month: 11, day: 9))
  }

  @Test func levelProgress() {
    let progress = GameLevel.progress(totalPoints: 345)
    #expect(progress.inLevel == 45)
    #expect(progress.level == ScoreRules.level(totalPoints: 345))
  }
}
