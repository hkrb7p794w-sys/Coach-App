import Foundation
import Testing

@testable import CoachCore

struct GymOverviewTests {
  let today = CalendarDay(year: 2026, month: 10, day: 28)

  func progress(_ status: ExerciseProgress.Status, weight: Double = 60, next: Double? = 62.5) -> ExerciseProgress {
    ExerciseProgress(
      exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest, lastDay: today.adding(days: -3), daysSince: 3,
      weightKg: weight, reps: [10, 10, 10], target: 6...10, sessions: 4, nextWeightKg: next, increasePercent: 4.2,
      status: status, headline: "", detail: "")
  }

  @Test func targetTextExplainsTheSuggestion() {
    #expect(
      GymTarget.text(for: progress(.increase), recovered: true)
        == "Ziel heute: 62,5 kg × 6–10 (+2,5 kg) – letztes Mal 60 × 10/10/10")
    // Schlechte Erholung: keine Steigerung, gleiches Gewicht.
    #expect(GymTarget.text(for: progress(.increase), recovered: false).hasPrefix("Ziel heute: 60 kg, mehr"))
    #expect(GymTarget.text(for: progress(.restart, next: 54), recovered: nil).hasPrefix("Wiedereinstieg: 54 kg"))
    #expect(GymTarget.text(for: progress(.build, weight: 0, next: nil), recovered: nil).contains("Wiederholungen"))
  }

  func noon(_ day: CalendarDay) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? .now
  }

  func session(_ key: String?, daysAgo: Int, weight: Double = 50) -> GymSession {
    GymSession(
      workoutKey: key, title: "x", start: noon(today.adding(days: -daysAgo)),
      exercises: [
        LoggedExercise(
          exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
          sets: [LoggedSet(reps: 10, weightKg: weight)])
      ])
  }

  @Test func rotationPicksTheRoutineAfterTheLastOne() {
    let squat = RoutineItem(
      exerciseID: "kniebeuge", name: "Kniebeuge", sets: 3, lowerReps: 6, upperReps: 10, restSeconds: 120)
    let a = Routine(name: "A", items: [squat])
    let b = Routine(name: "B", items: [])
    #expect(RoutineRotation.next(routines: [a, b], sessions: [])?.name == "A")
    let sessions = [session(RoutineRotation.key(a), daysAgo: 4), session(RoutineRotation.key(b), daysAgo: 2)]
    #expect(RoutineRotation.next(routines: [a, b], sessions: sessions)?.name == "A")
    #expect(RoutineRotation.next(routines: [a, b], sessions: [sessions[0]])?.name == "B")
    #expect(RoutineRotation.estimatedMinutes(a) == 10)
  }

  @Test func comparisonWithLastSameWorkout() {
    let old = session("routine-x", daysAgo: 7, weight: 50)
    let other = session("routine-y", daysAgo: 3, weight: 80)
    let new = session("routine-x", daysAgo: 0, weight: 55)
    let previous = SessionComparison.previous(of: new, in: [old, other, new])
    #expect(previous?.id == old.id)
    #expect(SessionComparison.volumeChangePercent(new, previous: previous) == 10)
    #expect(SessionComparison.volumeChangePercent(new, previous: nil) == nil)
  }

  @Test func calendarAndStreak() {
    // Mittwoch 28.10.: diese Woche nichts, letzte und vorletzte Woche je eine Einheit, davor Lücke.
    let sessions = [7, 8, 14, 30].map { session(nil, daysAgo: $0) }
    let weeks = GymCalendar.weeks(sessions: sessions, today: today, count: 4)
    #expect(weeks.map(\.sessions) == [0, 1, 2, 0])
    #expect(weeks.last?.monday == CalendarDay(year: 2026, month: 10, day: 26))
    #expect(GymCalendar.streak(sessions: sessions, today: today) == 2)
    #expect(GymCalendar.streak(sessions: sessions + [session(nil, daysAgo: 0)], today: today) == 3)
  }
}
