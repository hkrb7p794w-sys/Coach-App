import Foundation
import Testing

@testable import CoachCore

private let day = CalendarDay(year: 2026, month: 11, day: 4)

/// Mittag des Tages in der aktuellen Zeitzone (wie `CalendarDay(date:)`).
private func noon(_ day: CalendarDay) -> Date {
  let components = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
  return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
}

private func snapshot() -> WidgetSnapshot {
  WidgetSnapshot(
    createdAt: Date(timeIntervalSince1970: 1_800_000_000), day: day,
    today: .init(
      level: .normal, headline: "Normal trainieren",
      sessions: [
        .init(title: "Lauf", target: "45 min", done: true, symbol: "figure.run"),
        .init(title: "Push", target: "6 Übungen", done: false, symbol: "dumbbell"),
      ], week: "2/5 Einheiten · 90 min", weekFraction: 0.4),
    nutrition: .init(
      kcal: 1_500, kcalTarget: 2_400, protein: 90, proteinTarget: 150, waterMilliliters: 1_000, waterTarget: 2_500,
      lastMeal: .init(title: "Mittagessen", at: Date(timeIntervalSince1970: 1_800_000_000), kcal: 700)),
    gym: .init(
      next: "Push", nextDetail: "6 Übungen", running: true, runningTitle: "Push", last: nil, weekDone: 2,
      weekPlanned: 3),
    health: [.init(metric: .bodyBattery, value: "78", gauge: 78, status: .good, note: "über üblich")])
}

struct WidgetSnapshotTests {
  @Test func roundTripsAsJSON() throws {
    let original = snapshot()
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data) == original)
  }

  @Test func sameDayShowsValuesPlusPendingWater() {
    var queue = WidgetActionQueue()
    queue.addWater(250, at: noon(day))
    let display = snapshot().display(on: day, queue: queue)
    #expect(display.isCurrent)
    #expect(display.snapshot.nutrition?.waterMilliliters == 1_250)
    #expect(display.snapshot.nutrition?.kcalRemaining == 900)
    #expect(display.snapshot.today.nextSession?.title == "Push")
    #expect(!display.healthIsOld)
  }

  @Test func newDayDoesNotCarryOverMealsOrPlan() {
    let display = snapshot().display(on: day.adding(days: 1))
    #expect(!display.isCurrent)
    #expect(display.snapshot.nutrition?.kcal == 0)
    #expect(display.snapshot.nutrition?.kcalTarget == nil)
    #expect(display.snapshot.nutrition?.lastMeal == nil)
    #expect(display.snapshot.today.sessions.isEmpty)
    #expect(display.snapshot.today.level == nil)
    #expect(display.snapshot.gym?.running == false)
    // Gleiche Woche (Mi → Do): Zählung bleibt.
    #expect(display.snapshot.gym?.weekDone == 2)
    // Der Stand von gestern enthält nicht die letzte Nacht (R3C-02).
    #expect(display.healthIsOld)
    #expect(snapshot().display(on: day.adding(days: 2)).healthIsOld)
  }

  @Test func newWeekResetsGymCount() {
    // 04.11.2026 ist ein Mittwoch; Montag darauf ist der 09.11.
    let display = snapshot().display(on: CalendarDay(year: 2026, month: 11, day: 9))
    #expect(display.snapshot.gym?.weekDone == 0)
    #expect(display.snapshot.gym?.weekText == "0/3 diese Woche")
  }

  @Test func fractionsAreClampedAndNeedTargets() {
    let over = WidgetSnapshot.Nutrition(
      kcal: 3_000, kcalTarget: 2_000, protein: 10, proteinTarget: nil, waterMilliliters: 0, waterTarget: 0,
      lastMeal: nil)
    #expect(over.kcalFraction == 1)
    #expect(over.kcalRemaining == -1_000)
    #expect(over.proteinFraction == nil)
    #expect(over.waterFraction == nil)
  }

  @Test func queueKeepsOnlyRecentEntriesAndRemovesTaken() {
    var queue = WidgetActionQueue()
    queue.addWater(250, at: noon(day))
    queue.addWater(0, at: noon(day))
    queue.entries.append(.init(day: day.adding(days: -10), at: .distantPast, waterMilliliters: 250))
    #expect(queue.entries.count == 2)
    let pending = queue.pending(today: day)
    #expect(pending.count == 1)
    queue.addWater(500, at: noon(day))
    queue.remove(Set(pending.map(\.id)))
    #expect(queue.water(on: day) == 500)
  }

  @Test func healthComesFromMorningReport() {
    let report = MorningReport(
      day: day, dataDay: day,
      items: [
        .init(metric: .bodyBattery, value: "78", status: .good, note: "gut"),
        .init(metric: .sleepDuration, value: "7,5 h", status: .normal, note: "üblich"),
        .init(metric: .hrv, value: nil, status: .missing, note: "keine Daten"),
      ], level: .normal, headline: "Gut erholt", findings: [], recommendation: "", sleepAdvice: nil, sessions: [],
      missing: [])
    let health = WidgetSnapshot.health(from: report, bodyBattery: 78)
    #expect(health.map(\.metric) == [.bodyBattery, .sleep, .hrv])
    #expect(health.first?.gauge == 78)
    #expect(health.last?.gauge == nil)
    #expect(health.last?.status == .missing)
  }

  @Test func appGroupFromProfileWithTeamSuffix() {
    let plist = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>Entitlements</key><dict>
      <key>com.apple.security.application-groups</key>
      <array><string>group.io.github.hkrb7p794w.coach.ABCDE12345</string><string>group.other</string></array>
      </dict></dict></plist>
      """
    var data = Data([0x30, 0x82, 0x01])
    data.append(Data(plist.utf8))
    data.append(Data([0x00, 0xA0]))
    let groups = AppGroupProfile.groups(fromProfile: data)
    #expect(groups == ["group.io.github.hkrb7p794w.coach.ABCDE12345", "group.other"])
    #expect(
      AppGroupProfile.candidates(profileGroups: groups)
        == ["group.io.github.hkrb7p794w.coach.ABCDE12345", "group.io.github.hkrb7p794w.coach"])
    #expect(AppGroupProfile.groups(fromProfile: Data("kein Profil".utf8)).isEmpty)
    #expect(AppGroupProfile.candidates(profileGroups: []) == ["group.io.github.hkrb7p794w.coach"])
    #expect(AppGroupProfile.candidates(profileGroups: ["group.io.github.hkrb7p794w.coachX"]).count == 1)
  }

  @Test func streakHeadlineAndDayChange() throws {
    typealias Streak = WidgetSnapshot.Streak
    #expect(Streak(days: 34, activeToday: true).headline == "Serie läuft – weiter so!")
    #expect(Streak(days: 1, activeToday: true).headline == "Guter Start – dranbleiben!")
    #expect(Streak(days: 5, activeToday: false).headline == "Heute noch etwas erfassen")
    #expect(Streak(days: 0, activeToday: false).headline == "Heute starten – erster Tag!")

    var value = snapshot()
    value.streak = Streak(days: 12, activeToday: true)
    let day = value.day
    #expect(value.display(on: day).snapshot.streak == Streak(days: 12, activeToday: true))
    #expect(value.display(on: day.adding(days: 1)).snapshot.streak == Streak(days: 12, activeToday: false))
    #expect(value.display(on: day.adding(days: 3)).snapshot.streak == nil)
    // Ältere Stände ohne Serie bleiben lesbar.
    var old = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    old["streak"] = nil
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
    #expect(decoded.streak == nil)
  }
}
