import Foundation
import Testing

@testable import CoachCore

/// Audit Runde 4 (R4B): Garmin-Uhr + App, Detailansicht und eigene Quellen.
struct AuditR4BTests {
  /// R4B-07: `UserSources.inject` soll die Regeln der App behalten („damit diese Vorrang haben“). Der Chat schickt
  /// 13 App-Regeln; mit 8 eigenen Quellen schneidet `existing.prefix(20 - extra.count)` die 13. App-Regel ab.
  @Test func userSourcesNeverDropAppRules() throws {
    let appRules = try #require(CoachingNote.evidenceInput(ChatContext.evidence).arrayValue)
    try #require(appRules.count == 13)
    let sources = (0..<8).map { index in
      UserSource(
        citation: "Autor \(index) 2024", statement: "Eine ausreichend lange Kernaussage Nummer \(index)",
        topics: [.general])
    }
    let result = UserSources.inject(sources, into: ["evidence": .array(appRules)], task: "coach_chat")
    let ids = (result["evidence"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
    let appIDs = ids.filter { !UserSources.isUserID($0) }
    #expect(appIDs == ChatContext.evidence)
    #expect(ids.count <= 20)
  }

  /// R4B-08: Höhe unter dem Meeresspiegel (Almere, Flevoland: rund −4 m) verschwindet aus der Detailansicht,
  /// weil `row` nur Werte > 0 zeigt. 0 m (Meereshöhe) fehlt ebenso.
  @Test func negativeMinimumElevationIsShown() {
    var activity = GarminActivity(id: 7)
    activity.typeKey = "cycling"
    activity.minElevation = -4
    activity.maxElevation = 3
    let rows = ActivityDetails.sections(activity).flatMap(\.rows)
    #expect(rows.first { $0.label == "Min. Höhe" }?.value == "-4 m")
    #expect(rows.first { $0.label == "Max. Höhe" }?.value == "3 m")
  }

  /// R4B-09: Fehlt im letzten Punkt eines Abschnitts die Distanz, springt die x-Achse (km) auf 0 zurück; die
  /// Kurve läuft zum Start zurück, und `Sample.id` (= x) ist nicht mehr eindeutig.
  @Test func samplesStayMonotonicWhenDistanceMissing() {
    let fit = FitActivity(records: [
      FitRecord(timestamp: 0, heartRate: 120, speed: 3, distance: 100),
      FitRecord(timestamp: 60, heartRate: 130, speed: 3, distance: nil),
      FitRecord(timestamp: 120, heartRate: 140, speed: 3, distance: 400),
    ])
    let samples = ActivityDetails.samples(fit, sport: .run)
    let xs = samples.map(\.x)
    #expect(xs.count == 3)
    #expect(zip(xs, xs.dropFirst()).allSatisfy { pair in pair.0 <= pair.1 })
    #expect(Set(samples.map(\.id)).count == samples.count)
  }
}
