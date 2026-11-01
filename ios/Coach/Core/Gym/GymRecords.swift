import CoachCore
import Foundation
import SwiftData

/// Eine gespeicherte Krafteinheit. Die Übungen liegen als JSON (`GymSession`) vor, damit neue Felder keine
/// Datenbank-Migration brauchen.
@Model
final class GymSessionRecord {
  @Attribute(.unique) var id: UUID
  var dayKey: String
  var start: Date
  var payload: Data
  /// In Apple Health gespeichert.
  var savedToHealth: Bool
  /// Als Krafttraining nach Garmin Connect übertragen.
  var uploadedToGarmin: Bool = false

  init(session: GymSession, savedToHealth: Bool = false) {
    id = session.id
    dayKey = session.day.iso
    start = session.start
    payload = (try? JSONEncoder().encode(session)) ?? Data()
    self.savedToHealth = savedToHealth
  }

  /// Garmin-Verbindung setzen, ohne die übrigen gespeicherten Daten umzudeuten (roh lesen, nur `garmin` ändern).
  func setGarmin(_ link: GarminLink?) {
    guard var raw = try? JSONDecoder().decode(GymSession.self, from: payload) else { return }
    raw.garmin = link
    if let data = try? JSONEncoder().encode(raw) { payload = data }
  }

  var session: GymSession? {
    // Beim Lesen vereinheitlicht (`ExerciseAliases`); die gespeicherten Daten bleiben unverändert.
    (try? JSONDecoder().decode(GymSession.self, from: payload)).map(ExerciseAliases.normalized)
  }
}
