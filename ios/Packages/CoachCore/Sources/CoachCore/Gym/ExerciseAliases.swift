import Foundation

/// Korrekturen beim Lesen gespeicherter Einheiten, ohne die gespeicherten Daten zu ändern.
///
/// „Crunches am Kabel kniend“ aus dem Saisonplan wurde früher über den Garmin-Schlüssel `KNEELING_CABLE_CRUNCH` dem
/// Körpergewichts-Crunch zugeordnet; das Gewicht erschien dann als Zusatz zum Körpergewicht. Solche Einträge gelten
/// jetzt als Kabel-Crunch (Gerätegewicht), damit Anzeige, Volumen und Progression mit den neuen Einheiten
/// zusammenpassen.
public enum ExerciseAliases {
  public static func canonical(_ exercise: LoggedExercise) -> LoggedExercise {
    guard exercise.exerciseID == "crunch", exercise.name.lowercased().contains("kabel") else { return exercise }
    var copy = exercise
    copy.exerciseID = "crunch_kabel"
    return copy
  }

  public static func normalized(_ session: GymSession) -> GymSession {
    var copy = session
    copy.exercises = session.exercises.map(canonical)
    return copy
  }
}
