import Foundation
import Testing

@testable import CoachCore

private let today = CalendarDay(year: 2026, month: 10, day: 26)

/// Erwartungswerte wie im HA-Dashboard (Stand 14.10.2026: Rad Z2 100–134 W, Sweet Spot 157–167 W,
/// Schwelle 169–187 W, Renntempo 134–139 W).
struct DisciplineTests {
  @Test func swimPacesAndCSSTest() {
    let rows = SwimPaces.rows(css: 130)
    #expect(rows.map(\.value) == ["2:06–2:08", "2:10", "2:11–2:12", "2:13–2:14", "2:14–2:16", "2:10–2:13"])
    #expect(SwimPaces.css(time400: 520, time200: 260) == 130)
    #expect(SwimPaces.css(time400: 200, time200: 260) == nil)
    #expect(SwimPaces.css(time400: 1000, time200: 100) == nil)
  }

  @Test func bikeZonesMatchDashboard() {
    let rows = Dictionary(uniqueKeysWithValues: BikeZones.rows(ftp: 178).map { ($0.label, $0.value) })
    #expect(rows["Z2 Grundlage"] == "100–134 W")
    #expect(rows["Sweet Spot"] == "157–167 W")
    #expect(rows["Z4 Schwelle"] == "169–187 W")
    #expect(rows["Renntempo"] == "134–139 W")
  }

  @Test func runPaces() {
    let rows = RunPaces.rows(config: .standard).map(\.value)
    #expect(rows == ["6:00–6:35", "5:25", "5:42", "4:55", "4:32–4:37"])
  }

  @Test func raceEstimate() {
    let tests = [TestRecord(kind: .css, value: 130, day: today.adding(days: -10))]
    let estimate = RaceEstimate(config: .standard, tests: tests, today: today)
    #expect(RaceEstimate.hoursMinutes(estimate.totalMinutes) == "5:54")
    #expect(estimate.corridorText == "Im Zielkorridor 5:30–6:00.")
    #expect(estimate.freshness.map(\.isFresh) == [true, false, false])
    #expect(!estimate.allFresh)
    #expect(abs(estimate.savings.bike - 6.06) < 0.01)
    #expect(abs(estimate.savings.swim - 1.58) < 0.01)
  }

  @Test func marathonOutlook() {
    var config = SeasonConfig.standard
    let outlook = MarathonOutlook(
      config: config, halfMarathonSeconds: 6300, schedule: SeasonSchedule.load(), today: today)
    #expect(outlook.daysToRace == 188)
    #expect(MarathonOutlook.hoursMinutes(seconds: outlook.targetSeconds) == "3:48")
    #expect(outlook.predicted == 13545...13860)
    #expect(!outlook.targetTooFast)
    #expect(outlook.ladder.count == 17)
    #expect(outlook.ladder.first?.longRun == "16 km")
    #expect(outlook.ladder.first { $0.longRun == "Halbmarathon-Test" } != nil)
    #expect(outlook.ladder.last?.longRun == "🏁 Marathon")
    config.marathonPaceSecondsPerKm = 310
    #expect(MarathonOutlook(config: config, halfMarathonSeconds: 6300, schedule: nil, today: today).targetTooFast)
  }

  @Test func testHistoryKeepsOnePerDayAndKind() {
    var records: [TestRecord] = []
    records = TestHistory.adding(TestRecord(kind: .ftp, value: 170, day: today.adding(days: -30)), to: records)
    records = TestHistory.adding(TestRecord(kind: .ftp, value: 175, day: today), to: records)
    records = TestHistory.adding(TestRecord(kind: .ftp, value: 178, day: today), to: records)
    #expect(records.count == 2)
    #expect(TestHistory.latest(.ftp, in: records)?.value == 178)
    #expect(TestHistory.values(.ftp, in: records).map(\.value) == [170, 178])
  }
}
