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

  init(session: GymSession, savedToHealth: Bool = false) {
    id = session.id
    dayKey = session.day.iso
    start = session.start
    payload = (try? JSONEncoder().encode(session)) ?? Data()
    self.savedToHealth = savedToHealth
  }

  var session: GymSession? {
    try? JSONDecoder().decode(GymSession.self, from: payload)
  }
}
