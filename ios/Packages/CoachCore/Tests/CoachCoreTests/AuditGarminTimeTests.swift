import Foundation
import Testing

@testable import CoachCore

/// Audit CORE2-09: `GarminMetricsParser.bodyBatterySamples` rechnet den Versatz zur Ortszeit einmal aus
/// `startTimestampLocal − startTimestampGMT` (Mitternacht) und wendet ihn auf den ganzen Tag an. An den Tagen der
/// Zeitumstellung (23-/25-Stunden-Tag) liegen alle Werte nach 2 bzw. 3 Uhr um eine Stunde falsch.
struct AuditGarminTimeTests {
  private let berlin = TimeZone(identifier: "Europe/Berlin") ?? .current

  private func json(_ text: String) throws -> JSONValue {
    try JSONValue(data: Data(text.utf8))
  }

  /// 29.03.2026: Mitternacht MEZ (+1 h), um 10:00 UTC gilt MESZ (+2 h) → 12:00 Ortszeit = Minute 720.
  @Test func springForwardDayKeepsLocalClock() throws {
    let response = try json(
      """
      [{"date": "2026-03-29", "startTimestampGMT": "2026-03-28T23:00:00.0",
        "startTimestampLocal": "2026-03-29T00:00:00.0", "bodyBatteryValuesArray": [[1774778400000, 60]]}]
      """)
    let day = CalendarDay(year: 2026, month: 3, day: 29)
    let metrics = try #require(GarminMetricsParser.bodyBattery(response, timeZone: berlin)[day])
    #expect(metrics.bodyBatteryCurve == [BodyBatterySample(minute: 720, value: 60)])
  }

  /// 25.10.2026: Mitternacht MESZ (+2 h), um 10:00 UTC gilt MEZ (+1 h) → 11:00 Ortszeit = Minute 660.
  @Test func fallBackDayKeepsLocalClock() throws {
    let response = try json(
      """
      [{"date": "2026-10-25", "startTimestampGMT": "2026-10-24T22:00:00.0",
        "startTimestampLocal": "2026-10-25T00:00:00.0", "bodyBatteryValuesArray": [[1792922400000, 40]]}]
      """)
    let day = CalendarDay(year: 2026, month: 10, day: 25)
    let metrics = try #require(GarminMetricsParser.bodyBattery(response, timeZone: berlin)[day])
    #expect(metrics.bodyBatteryCurve == [BodyBatterySample(minute: 660, value: 40)])
  }
}
