import Foundation
import Testing

@testable import CoachCore

private let gymToday = CalendarDay(year: 2026, month: 10, day: 22)

private func gymSession(_ iso: String, _ id: String, weight: Double, reps: [Int], group: MuscleGroup) -> GymSession {
  let day = CalendarDay(iso: iso) ?? gymToday
  return GymSession(
    workoutKey: nil, title: "Audit", start: day.referenceDate,
    exercises: [
      LoggedExercise(
        exerciseID: id, name: id, group: group, sets: reps.map { LoggedSet(reps: $0, weightKg: weight) })
    ])
}

struct AuditGymTests {
  /// CORE1-05: Unterstützter Klimmzug (−30 kg Hilfe, 3 × 10, Ziel 5–10). `workingSets` setzt negative Gewichte auf 0
  /// (GymProgression.swift:78), danach greift der Körpergewichts-Zweig (Zeile 158–163): „Zusatzgewicht beginnen“.
  /// Erwartet: Hilfe verringern, Gewicht −30 bleibt sichtbar; tatsächlich weightKg 0 und Zusatzgewicht-Empfehlung.
  @Test func assistedPullUpDoesNotSuggestAddedWeight() throws {
    let result = try #require(
      GymProgression.evaluate(
        sessions: [gymSession("2026-10-20", "klimmzug", weight: -30, reps: [10, 10, 10], group: .back)],
        ranges: [:], today: gymToday
      ).first)
    #expect(result.weightKg == -30)
    #expect(result.headline != "Zusatzgewicht beginnen")
  }

  /// CORE1-06: „2 für 2“ (ACSM 2009) verlangt zwei Wiederholungen über dem Ziel im letzten Satz in zwei Einheiten in
  /// Folge; Regel B prüft nur `high + 1` (GymProgression.swift:181). 2 × [10, 10, 13] bei Ziel 8–12:
  /// erwartet „bleiben“ (13 < 14); tatsächlich „erhöhen“. (Abweichung vom zitierten Kriterium, Literaturprüfung.)
  @Test func twoForTwoNeedsTwoExtraReps() throws {
    let result = try #require(
      GymProgression.evaluate(
        sessions: [
          gymSession("2026-10-16", "bankdruecken", weight: 60, reps: [10, 10, 13], group: .chest),
          gymSession("2026-10-20", "bankdruecken", weight: 60, reps: [10, 10, 13], group: .chest),
        ], ranges: ["bankdruecken": 8...12], today: gymToday
      ).first)
    #expect(result.status != .increase)
  }

  /// CORE1-07: GymBook-Import ignoriert `ZQUANTITYUNIT` (GymBookImport.swift:124). 100 lb → erwartet 45,36 kg;
  /// tatsächlich 100 kg.
  @Test func gymBookPoundsAreConverted() throws {
    let rows = [
      GymBookImport.LogRow(
        day: "2026-10-23", secondsOfDay: 30_000, exercise: "Bankdrücken mit Langhantel", frequency: 8, quantity: 100,
        quantityUnit: "lb", workout: "A")
    ]
    let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
    let result = GymBookImport.sessions(rows, custom: [], timeZone: berlin)
    let weight = try #require(result.sessions.first?.exercises.first?.sets.first?.weightKg)
    #expect(abs(weight - 45.359) < 0.01)
  }

  /// CORE1-08 (Annahme: ZTIME = Uhrzeit in Sekunden): Am Tag der Zeitumstellung (29.3.2026) wird 23:30 Uhr als
  /// Mitternacht + 84.600 s gerechnet (GymBookImport.swift:134) → 00:30 Uhr am 30.3.; die Einheit landet am Folgetag.
  @Test func gymBookTimeOnSpringForwardDay() throws {
    let rows = [
      GymBookImport.LogRow(
        day: "2026-03-29", secondsOfDay: 84_600, exercise: "Beinstrecken", frequency: 10, quantity: 50,
        workout: "Lower")
    ]
    let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
    let session = try #require(GymBookImport.sessions(rows, custom: [], timeZone: berlin).sessions.first)
    #expect(CalendarDay(date: session.start, timeZone: berlin) == CalendarDay(year: 2026, month: 3, day: 29))
  }
}
