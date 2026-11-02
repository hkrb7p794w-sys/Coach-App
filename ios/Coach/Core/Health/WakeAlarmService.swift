import CoachCore
import Foundation
import Observation
import SwiftUI

#if canImport(AlarmKit)
  import AlarmKit
#endif

/// Wecker zur Aufstehzeit über AlarmKit (iOS 26): ein echter System-Wecker, der auch im Lautlos- und Fokus-Modus
/// klingelt und in der Uhr-/Sperrbildschirm-Ansicht erscheint. Die App fragt einmal nach Erlaubnis; ohne sie oder
/// unter iOS 18–25 gibt es keinen Wecker, nur den Hinweis auf die Uhr-App. Es gibt immer höchstens einen
/// IronLudi-Wecker: ein neuer ersetzt den alten.
@MainActor
@Observable
final class WakeAlarmService {
  struct Stored: Codable, Equatable {
    var id: UUID
    var time: WakePlan.Time
    var repeats: WakePlan.Repeat
  }

  enum State: Equatable {
    case unsupported
    case notDetermined
    case denied
    case authorized
  }

  static let storedKey = "coach.wakeAlarm"
  private let defaults: UserDefaults
  private(set) var stored: Stored?
  private(set) var state: State = .unsupported
  private(set) var lastError: String?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    stored = defaults.data(forKey: Self.storedKey).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
    refreshState()
  }

  var isSupported: Bool { state != .unsupported }

  func refreshState() {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        switch AlarmManager.shared.authorizationState {
        case .authorized: state = .authorized
        case .denied: state = .denied
        case .notDetermined: state = .notDetermined
        @unknown default: state = .notDetermined
        }
        // Vom System gelöschte oder abgelaufene einmalige Wecker nicht mehr als gestellt anzeigen.
        if let stored, let alarms = try? AlarmManager.shared.alarms, !alarms.contains(where: { $0.id == stored.id }) {
          clearStored()
        }
        return
      }
    #endif
    state = .unsupported
  }

  /// Stellt den Wecker (ersetzt einen vorhandenen IronLudi-Wecker). Fragt beim ersten Mal nach Erlaubnis.
  func schedule(_ time: WakePlan.Time, repeats: WakePlan.Repeat) async -> Bool {
    lastError = nil
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        do {
          if AlarmManager.shared.authorizationState != .authorized {
            let answer = try await AlarmManager.shared.requestAuthorization()
            guard answer == .authorized else {
              state = .denied
              lastError = "Wecker nicht erlaubt. Du kannst das in den iOS-Einstellungen unter IronLudi ändern."
              return false
            }
          }
          state = .authorized
          if let stored { try? AlarmManager.shared.cancel(id: stored.id) }
          let id = UUID()
          try await IronLudiAlarm.schedule(id: id, time: time, repeats: repeats)
          save(Stored(id: id, time: time, repeats: repeats))
          return true
        } catch {
          lastError = "Wecker konnte nicht gestellt werden: \(error.localizedDescription)"
          return false
        }
      }
    #endif
    lastError = "Wecker aus der App gibt es ab iOS 26."
    return false
  }

  func cancel() {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *), let stored {
        try? AlarmManager.shared.cancel(id: stored.id)
      }
    #endif
    clearStored()
  }

  private func save(_ value: Stored) {
    stored = value
    if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.storedKey) }
  }

  private func clearStored() {
    stored = nil
    defaults.removeObject(forKey: Self.storedKey)
  }
}

#if canImport(AlarmKit)
  /// Keine eigenen Daten am Wecker nötig.
  @available(iOS 26.0, *)
  nonisolated struct IronLudiAlarmMetadata: AlarmMetadata {}

  @available(iOS 26.0, *)
  enum IronLudiAlarm {
    static func schedule(id: UUID, time: WakePlan.Time, repeats: WakePlan.Repeat) async throws {
      let weekdays = repeats.weekdays.compactMap(localeWeekday)
      let schedule = Alarm.Schedule.relative(
        .init(
          time: .init(hour: time.hour, minute: time.minute),
          repeats: weekdays.isEmpty ? .never : .weekly(weekdays)))
      let stop = AlarmButton(text: "Aus", textColor: .white, systemImageName: "sun.max.fill")
      let alert = AlarmPresentation.Alert(title: "Guten Morgen – Zeit aufzustehen", stopButton: stop)
      let attributes = AlarmAttributes<IronLudiAlarmMetadata>(
        presentation: AlarmPresentation(alert: alert), metadata: IronLudiAlarmMetadata(), tintColor: .indigo)
      let configuration = AlarmManager.AlarmConfiguration<IronLudiAlarmMetadata>(
        countdownDuration: nil, schedule: schedule, attributes: attributes, stopIntent: nil, secondaryIntent: nil)
      _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    /// `Calendar`-Wochentag (1 = Sonntag) in `Locale.Weekday`.
    static func localeWeekday(_ weekday: Int) -> Locale.Weekday? {
      switch weekday {
      case 1: .sunday
      case 2: .monday
      case 3: .tuesday
      case 4: .wednesday
      case 5: .thursday
      case 6: .friday
      case 7: .saturday
      default: nil
      }
    }
  }
#endif
