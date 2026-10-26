import Foundation
import Testing

@testable import CoachCore

struct PlanScheduleTests {
  private func schedule() throws -> SeasonSchedule {
    try #require(SeasonSchedule.load())
  }

  @Test func loadsAllWeeksWithSwimSteps() throws {
    let plan = try schedule()
    #expect(plan.weeks.count == 48)
    #expect(plan.weeks.first?.w == "2026-10-12")
    #expect(plan.weeks.allSatisfy { $0.ss?.isEmpty == false })
    #expect(plan.zw.count >= 16)
    #expect(plan.phases["Grundlage"]?.mw.hasPrefix("Mo Push") == true)
    let thursday = CalendarDay(year: 2026, month: 10, day: 29)
    #expect(plan.week(containing: thursday)?.w == "2026-10-26")
    #expect(plan.index(of: thursday) == 2)
  }

  /// Erwartungswerte wie im HA-Dashboard (Stand 14.10.2026): Intervall 4:32–4:37, locker 6:00–6:35.
  @Test func tokensUseTestValues() {
    let tokens = PlanTokens(config: .standard)
    #expect(tokens.fill("§T§ /km") == "4:55 /km")
    #expect(tokens.fill("§I§") == "4:32–4:37")
    #expect(tokens.fill("§E§") == "6:00–6:35")
    #expect(tokens.fill("§S0§ · §S+2§ · §S-4§") == "2:10 · 2:12 · 2:06")
    #expect(tokens.fill("§W88§–§W92§ W") == "157–164 W")
    #expect(tokens.fill("§MP§ und §R§") == "5:25 und 5:42")
    #expect(tokens.fill("§X§ bleibt") == "§X§ bleibt")
    #expect(tokens.fill("ohne Platzhalter") == "ohne Platzhalter")
  }

  @Test func unitsOfAWeek() throws {
    let plan = try schedule()
    let week = try #require(plan.weeks.first { $0.w == "2026-10-26" })
    let units = plan.units(for: week, config: .standard)
    #expect(units.map(\.kind) == [.bike, .bikeOptional, .swim, .quality, .easyRun, .gym, .gym, .gym, .gym])
    #expect(units[0].title == "Z03 Sweet Spot 2×20")
    #expect(units[0].detail.contains("157–164 W"))
    #expect(units[3].title == "Schwelle 3×2,5 km")
    #expect(units[3].detail.contains("4:55 /km"))
    #expect(units[2].swimMeters == 2000)
    #expect(SwimStepText.equipment(in: units[2].swimSteps) == ["Pull-Buoy"])
    let lines = SwimStepText.lines(units[2].swimSteps, tokens: PlanTokens(config: .standard))
    #expect(lines.first == "Ein 200 m · locker einschwimmen")
    #expect(lines.contains("400 m · @ 2:14–2:16 /100 m · mit Pull-Buoy, nur Arme · (Pull-Buoy)"))
  }

  @Test func competitionRunCanBeRejected() throws {
    let plan = try schedule()
    let week = try #require(plan.weeks.first { $0.w == "2027-01-11" })
    let open = try #require(plan.units(for: week, config: .standard).first { $0.kind == .quality })
    #expect(open.title == "🏁 Marathontempo 2×4 km")
    #expect(open.decision == .open)
    #expect(open.detail.contains("5:25 /km"))
    let key = SeasonSchedule.decisionKey(week: week, kind: .quality)
    #expect(key == "wk-lauf-2027-01-11-q")
    let rejected = try #require(
      plan.units(for: week, config: .standard, decisions: [key: .rejected]).first { $0.kind == .quality })
    #expect(rejected.title == "Intervall 4×4 min")
    #expect(rejected.decision == .rejected)
    let longRun = try #require(plan.units(for: week, config: .standard).first { $0.kind == .longRun })
    #expect(longRun.title == "Longrun 18 km")
  }

  @Test func progressMarksDoneUnits() throws {
    let plan = try schedule()
    let week = try #require(plan.weeks.first { $0.w == "2027-01-11" })
    func activity(_ id: Int64, _ type: String, _ day: Int, km: Double) -> GarminActivity {
      var activity = GarminActivity(id: id)
      activity.typeKey = type
      activity.startLocal = String(format: "2027-01-%02d 08:00:00", day)
      activity.distanceMeters = km * 1000
      return activity
    }
    let activities = [
      activity(1, "running", 17, km: 17), activity(2, "running", 13, km: 9), activity(3, "lap_swimming", 12, km: 2),
      activity(4, "indoor_cycling", 12, km: 0), activity(5, "running", 20, km: 9),
    ]
    let units = PlanProgress.mark(
      plan.units(for: week, config: .standard), week: week, activities: activities,
      gymDays: [CalendarDay(year: 2027, month: 1, day: 11)])
    let done = Dictionary(units.map { ($0.kind, $0.done) }, uniquingKeysWith: { first, _ in first })
    #expect(done[.longRun] == true)
    #expect(done[.quality] == true)
    #expect(done[.easyRun] == false)
    #expect(done[.swim] == true)
    #expect(done[.bike] == false)
    #expect(units.filter { $0.kind == .gym && $0.done }.count == 1)
  }
}
