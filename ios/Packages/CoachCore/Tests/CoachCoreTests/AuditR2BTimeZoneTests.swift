import Foundation
import Testing

@testable import CoachCore

/// R2B-03: Der Tag einer Krafteinheit wird bei jedem Lesen aus `start` mit der *aktuellen* Zeitzone berechnet
/// (`GymSession.day`, GymSession.swift:163). Die App speichert den Tag beim Sichern zusätzlich als `dayKey`
/// (GymRecords.swift:20) und nutzt beide nebeneinander (AppModel.swift:102 vs. Verlauf/Statistik). Nach einer
/// Reise wandern alte Einheiten auf einen anderen Kalendertag.
///
/// Fix-Vorschlag: `day` als gespeichertes Feld (beim Start in der Ortszeit festgelegt, `decodeIfPresent`,
/// Rückfall auf `CalendarDay(date: start)` für alte Daten).
struct AuditR2BTimeZoneTests {
  /// Einheit in Tokio am 3.11.2026 um 0:30 Uhr Ortszeit gestartet (= 2.11.2026 15:30 UTC).
  private static let tokyoStart: Date = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    return calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 0, minute: 30)) ?? .now
  }()

  @Test func storedDaySurvivesTimeZoneChange() throws {
    let session = GymSession(
      workoutKey: nil, title: "Reise", start: Self.tokyoStart,
      exercises: [
        LoggedExercise(
          exerciseID: "bench_press", name: "Bankdrücken", group: .chest,
          sets: [LoggedSet(reps: 8, weightKg: 60)])
      ])
    // So läge die Einheit gespeichert vor, wenn der Tag beim Start in Tokio festgehalten würde.
    var json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
    json["day"] = ["year": 2026, "month": 11, "day": 3]
    let data = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(GymSession.self, from: data)

    // Zurück in Europa (bzw. CI in UTC): Die Einheit gehört weiter zum 3.11., nicht zum 2.11.
    #expect(decoded.day == CalendarDay(year: 2026, month: 11, day: 3))
  }
}
