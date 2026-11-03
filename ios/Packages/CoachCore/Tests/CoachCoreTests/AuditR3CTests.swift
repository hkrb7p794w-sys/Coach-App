import Foundation
import Testing

@testable import CoachCore

/// Audit Runde 3 (R3C): Systemintegration (Widgets, Live-Aktivität). Beide Tests schlagen mit dem aktuellen Stand fehl.
struct AuditR3CTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 3_600) ?? .current
    return calendar
  }()

  /// R3C-02: Der Stand vom 04.11. enthält die Werte der Nacht zum 04.11. Am 05.11. (Mitternachts-Eintrag der
  /// Zeitleiste, App noch nicht geöffnet) zeigt das Health-Widget sie trotzdem als „letzte Nacht“, weil
  /// `healthIsOld` erst ab dem übernächsten Tag greift (`day.adding(days: -1) > self.day`). Erwartet: ab dem
  /// Folgetag gilt der Stand als alt („Kein Wert von letzter Nacht“). Hinweis: `WidgetSnapshotTests`
  /// (`newDayDoesNotCarryOverMealsOrPlan`, `#expect(!display.healthIsOld)`) schreibt das heutige Verhalten fest und
  /// muss mit dem Fix angepasst werden.
  @Test func healthOfPreviousSnapshotDayIsOldOnNextDay() {
    let day = CalendarDay(year: 2026, month: 11, day: 4)
    let snapshot = WidgetSnapshot(
      createdAt: Date(timeIntervalSince1970: 1_800_000_000), day: day,
      today: .init(level: .normal, headline: "Normal trainieren"), nutrition: nil, gym: nil,
      health: [
        .init(metric: .sleep, value: "7,4 h", gauge: nil, status: .good, note: "Über deinem Bedarf"),
        .init(metric: .bodyBattery, value: "18", gauge: 18, status: .attention, note: "Niedrig"),
      ])
    let nextDay = snapshot.display(on: day.adding(days: 1))
    #expect(!nextDay.isCurrent)
    #expect(nextDay.healthIsOld)
  }

  /// R3C-06: Laut decisions.md (2026-11-02) heißt „gestartet“: erster Satz abgehakt. Aufwärmsätze zählen aber nicht
  /// (`doneSetCount` nutzt `doneSets` ohne `.warmup`). Wer mit den eingefügten Aufwärmsätzen beginnt, bekommt in den
  /// Aufwärmpausen keine Live-Aktivität (Pausentimer, „Satz erledigt“ auf dem Sperrbildschirm), und nach 2 h gilt
  /// die Einheit als „nie begonnen“ und wird still verworfen.
  @Test func warmupSetStartsTheSession() throws {
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17)))
    let sets = [
      LoggedSet(reps: 10, weightKg: 20, done: true, kind: .warmup),
      LoggedSet(reps: 5, weightKg: 40, done: false, kind: .warmup),
      LoggedSet(reps: 8, weightKg: 80, done: false),
    ]
    let session = GymSession(
      workoutKey: nil, title: "Push", start: start,
      exercises: [LoggedExercise(exerciseID: "bench", name: "Bankdrücken", group: .chest, sets: sets)])
    let state = ActiveSessionState.of(session, now: start.addingTimeInterval(300), calendar: calendar)
    #expect(state == .running)
    #expect(state.showsLiveActivity)
    // Volumen und Rekorde bleiben ohne Aufwärmen (decisions.md 2026-10-28).
    #expect(session.doneSetCount == 0)
  }
}
