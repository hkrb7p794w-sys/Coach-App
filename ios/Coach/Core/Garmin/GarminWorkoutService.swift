import CoachCore
import Foundation

/// Sendet eine Einheit als Workout in den Garmin-Connect-Kalender; von dort kommt sie beim nächsten Synchronisieren
/// auf die Uhr. Nur auf ausdrücklichen Wunsch je Einheit. Schickt man dieselbe Einheit für denselben Tag erneut,
/// wird das alte Workout gelöscht und ersetzt.
@MainActor
enum GarminWorkoutService {
  static func send(_ plan: GarminWorkout.Plan, day: CalendarDay, model: AppModel) async -> String {
    guard let connect = model.garmin.connect, connect.isLoggedIn else {
      return "Dafür ist die Anmeldung mit dem Garmin-Konto nötig (Einstellungen › Garmin)."
    }
    let key = SentWorkouts.key(name: plan.name, day: day)
    do {
      if let old = model.settings.sentWorkouts.ids[key] {
        // Altes Workout entfernen (samt Kalendereintrag); scheitert das, bleibt es eben stehen.
        _ = try? await connect.send(method: "DELETE", path: GarminWorkout.workoutPath(workoutID: old), json: Data())
      }
      let body = try JSONEncoder().encode(GarminWorkout.payload(plan))
      let response = try JSONValue(
        data: try await connect.send(method: "POST", path: GarminWorkout.createPath, json: body))
      guard let id = GarminWorkout.workoutID(from: response) else {
        return "Garmin hat das Workout nicht angenommen."
      }
      let schedule = try JSONEncoder().encode(GarminWorkout.scheduleBody(day: day))
      _ = try await connect.send(method: "POST", path: GarminWorkout.schedulePath(workoutID: id), json: schedule)
      var sent = model.settings.sentWorkouts
      sent.prune(today: CalendarDay(date: .now))
      sent.ids[key] = id
      model.settings.sentWorkouts = sent
      return "Im Garmin-Kalender am \(GermanFormat.date(day)). Auf die Uhr kommt es beim nächsten Synchronisieren."
    } catch {
      return "Senden hat nicht geklappt: \(error.localizedDescription)"
    }
  }
}
