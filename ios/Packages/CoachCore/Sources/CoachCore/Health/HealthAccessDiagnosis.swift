/// Bewertet, ob HealthKit in dieser Installation nutzbar ist.
///
/// Hintergrund: SideStore übernimmt beim Signieren mit kostenloser Apple-ID nur
/// Entitlements, die im Provisioning-Profil stehen, und schaltet HealthKit für
/// die App-ID nicht frei. Dann fehlt `com.apple.developer.healthkit` und jeder
/// HealthKit-Aufruf scheitert. Die App muss das erkennen und HealthKit-Funktionen
/// abschalten, statt Fehler anzuzeigen.
///
/// Leserechte meldet HealthKit aus Datenschutzgründen nie zurück. Verlässlich ist
/// nur der Schreibstatus (`authorizationStatus(for:)`) – er belegt, dass das
/// Entitlement wirkt.
public enum HealthAccessDiagnosis: Equatable, Sendable {
  /// Gerät ohne Health-Datenbank (z. B. manche iPads).
  case unavailable
  /// Signatur ohne HealthKit-Entitlement (typisch für SideStore mit kostenloser Apple-ID).
  case missingEntitlement
  /// Nutzer hat das Schreiben von Workouts abgelehnt.
  case denied
  /// Noch nicht gefragt.
  case notDetermined
  /// HealthKit funktioniert; `readableWorkouts` = gelesene Workouts der letzten 30 Tage.
  case working(readableWorkouts: Int?)
  /// Sonstiger Fehler mit Originaltext.
  case failed(String)

  public var isUsable: Bool {
    if case .working = self { return true }
    return false
  }

  public var title: String {
    switch self {
    case .unavailable: "Nicht verfügbar"
    case .missingEntitlement: "Berechtigung fehlt in der Signatur"
    case .denied: "Zugriff abgelehnt"
    case .notDetermined: "Noch nicht angefragt"
    case .working: "HealthKit funktioniert"
    case .failed: "Fehler"
    }
  }

  public var detail: String {
    switch self {
    case .unavailable:
      return "Auf diesem Gerät gibt es keine Health-Daten."
    case .missingEntitlement:
      return
        "Die installierte App hat kein HealthKit-Entitlement (SideStore mit kostenloser Apple-ID "
        + "entfernt es). Die App läuft ohne HealthKit weiter; Garmin-Daten kommen über das Backend."
    case .denied:
      return "Bitte in Einstellungen › Apps › Health › Datenzugriff › Coach freigeben."
    case .notDetermined:
      return "Tippe auf „HealthKit prüfen“."
    case .working(let count?):
      return "Schreiben erlaubt, \(count) Workouts der letzten 30 Tage lesbar."
    case .working(nil):
      return "Schreiben erlaubt."
    case .failed(let message):
      return message
    }
  }
}

/// Schreibstatus für Workouts, unabhängig von `HKAuthorizationStatus`.
public enum WorkoutShareStatus: Sendable {
  case notDetermined
  case denied
  case authorized
}

/// Fehler, den HealthKit geliefert hat (Domain, Code, Text).
public struct HealthErrorInfo: Equatable, Sendable {
  public let domain: String
  public let code: Int
  public let message: String

  public init(domain: String, code: Int, message: String) {
    self.domain = domain
    self.code = code
    self.message = message
  }

  /// HealthKit meldet ein fehlendes Entitlement als
  /// `com.apple.healthkit` Code 4 mit „Missing com.apple.developer.healthkit entitlement.“
  var isMissingEntitlement: Bool {
    message.lowercased().contains("entitlement")
  }
}

extension HealthAccessDiagnosis {
  /// Leitet die Diagnose aus den Rohergebnissen der HealthKit-Aufrufe ab.
  public static func evaluate(
    isHealthDataAvailable: Bool,
    authorizationError: HealthErrorInfo?,
    workoutShareStatus: WorkoutShareStatus?,
    readableWorkouts: Int?,
    queryError: HealthErrorInfo? = nil
  ) -> HealthAccessDiagnosis {
    guard isHealthDataAvailable else { return .unavailable }

    for error in [authorizationError, queryError].compactMap({ $0 }) where error.isMissingEntitlement {
      return .missingEntitlement
    }
    if let authorizationError {
      return .failed("\(authorizationError.message) (\(authorizationError.domain) \(authorizationError.code))")
    }

    switch workoutShareStatus {
    case .authorized: return .working(readableWorkouts: queryError == nil ? readableWorkouts : nil)
    case .denied: return .denied
    case .notDetermined, nil: return .notDetermined
    }
  }
}
