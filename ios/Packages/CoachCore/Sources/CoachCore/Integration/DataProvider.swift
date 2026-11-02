import Foundation

/// Datenarten, die Anbieter liefern können. Herstellerunabhängig: Jede Art wird intern immer gleich abgebildet
/// (`DailyMetrics`, `GarminActivity` als allgemeines Aktivitätsmodell), egal woher sie kommt.
public enum DataKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case activities, workoutHeartRate, sleep, hrv, restingHeartRate, stress, calories, steps, trainingLoad
  case recovery, body

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .activities: "Sportaktivitäten"
    case .workoutHeartRate: "Herzfrequenz im Training"
    case .sleep: "Schlaf"
    case .hrv: "HRV"
    case .restingHeartRate: "Ruhepuls"
    case .stress: "Stress"
    case .calories: "Kalorien"
    case .steps: "Schritte"
    case .trainingLoad: "Trainingsbelastung"
    case .recovery: "Erholung (Recovery)"
    case .body: "Körperwerte"
    }
  }
}

/// Externe Datenquellen. Jeder Anbieter ist ein eigenes Modul; zentrale Modelle hängen nicht davon ab.
public enum DataProvider: String, Codable, CaseIterable, Sendable, Identifiable {
  case garmin, appleHealth, whoop, polar, fitbit

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .garmin: "Garmin"
    case .appleHealth: "Apple Health"
    case .whoop: "WHOOP"
    case .polar: "Polar"
    case .fitbit: "Fitbit"
    }
  }

  /// Stand der Anbindung in dieser App – nur was wirklich funktioniert, gilt als verfügbar.
  public enum Availability: String, Codable, Sendable {
    /// Eingebaut und nutzbar.
    case available
    /// Offizielle API vorhanden, Anbindung in der App noch nicht gebaut.
    case planned
    /// Derzeit nicht anbindbar (z. B. API abgeschaltet).
    case unavailable
  }

  public var availability: Availability {
    switch self {
    case .garmin, .appleHealth: .available
    case .whoop, .polar: .planned
    case .fitbit: .unavailable
    }
  }

  /// Kurz, warum (für die Einstellungen).
  public var availabilityNote: String {
    switch self {
    case .garmin: "Garmin-Konto (Connect) oder Personal API."
    case .appleHealth: "Über HealthKit auf dem iPhone, sofern SideStore die Berechtigung erhält."
    case .whoop:
      "Offizielle API (v2, OAuth). Noch nicht eingebaut; braucht eine eigene WHOOP-App im Developer-Dashboard und "
        + "den Worker für den Token-Tausch. Bis dahin: WHOOP schreibt Schlaf, Ruhepuls und Workouts in Apple Health "
        + "(keine HRV)."
    case .polar:
      "Offizielle AccessLink-API (OAuth). Noch nicht eingebaut; braucht einen eigenen Polar-Client und den Worker. "
        + "Bis dahin: Polar Flow schreibt Trainings in Apple Health."
    case .fitbit:
      "Die Fitbit Web API wurde laut Google am 30.10.2026 abgeschaltet; Nachfolger ist die Google Health API "
        + "(Google-OAuth, Prüfung durch Google). Fitbit schreibt nicht in Apple Health."
    }
  }

  /// Was der Anbieter grundsätzlich liefern kann (über seine API bzw. bei Apple Health über HealthKit).
  public var capabilities: Set<DataKind> {
    switch self {
    case .garmin: Set(DataKind.allCases)
    case .appleHealth: [.activities, .workoutHeartRate, .sleep, .hrv, .restingHeartRate, .calories, .steps, .body]
    case .whoop: [.activities, .workoutHeartRate, .sleep, .hrv, .restingHeartRate, .calories, .recovery, .body]
    case .polar:
      [.activities, .workoutHeartRate, .sleep, .hrv, .restingHeartRate, .calories, .steps, .trainingLoad, .recovery]
    case .fitbit: [.activities, .sleep, .hrv, .restingHeartRate, .calories, .steps, .body]
    }
  }

  /// Stärken: Hier ist der Anbieter als primäres Gerät auch die bevorzugte Quelle. Für andere Arten zählt die
  /// allgemeine Rangfolge – das primäre Gerät ist nicht automatisch überall die beste Quelle.
  public var strengths: Set<DataKind> {
    switch self {
    case .garmin: [.activities, .workoutHeartRate, .trainingLoad, .stress, .recovery, .steps, .calories]
    case .appleHealth: [.steps, .calories]
    case .whoop: [.sleep, .hrv, .restingHeartRate, .recovery]
    case .polar: [.activities, .workoutHeartRate, .trainingLoad]
    case .fitbit: [.steps, .sleep]
    }
  }

  /// Allgemeine Rangfolge je Datenart (beste zuerst). Apple Health steht hinten, weil es meist nur weitergibt, was
  /// ein Gerät geschrieben hat (Gefahr doppelter Werte), und HRV dort SDNN statt RMSSD ist.
  public static func defaultOrder(for kind: DataKind) -> [DataProvider] {
    switch kind {
    case .hrv, .recovery: [.whoop, .garmin, .polar, .fitbit, .appleHealth]
    case .sleep: [.whoop, .garmin, .polar, .fitbit, .appleHealth]
    case .restingHeartRate: [.garmin, .whoop, .polar, .fitbit, .appleHealth]
    case .activities, .workoutHeartRate, .trainingLoad: [.garmin, .polar, .whoop, .fitbit, .appleHealth]
    case .stress: [.garmin, .appleHealth, .whoop, .polar, .fitbit]
    case .calories, .steps, .body: [.garmin, .polar, .fitbit, .whoop, .appleHealth]
    }
  }
}

/// Primäres Gerät und bevorzugte Quelle je Datenart.
public struct SourcePreferences: Codable, Equatable, Hashable, Sendable {
  public var primary: DataProvider?
  public var overrides: [DataKind: DataProvider]

  public init(primary: DataProvider? = nil, overrides: [DataKind: DataProvider] = [:]) {
    self.primary = primary
    self.overrides = overrides
  }

  private enum CodingKeys: String, CodingKey { case primary, overrides }

  /// Tolerant: unbekannte Anbieter oder Datenarten (aus neueren Versionen) werden übersprungen.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let primaryRaw = try? container.decodeIfPresent(String.self, forKey: .primary)
    primary = primaryRaw.flatMap(DataProvider.init(rawValue:))
    let raw = (try? container.decodeIfPresent([String: String].self, forKey: .overrides)) ?? [:]
    var overrides: [DataKind: DataProvider] = [:]
    for (kind, provider) in raw {
      if let kind = DataKind(rawValue: kind), let provider = DataProvider(rawValue: provider) {
        overrides[kind] = provider
      }
    }
    self.overrides = overrides
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encodeIfPresent(primary?.rawValue, forKey: .primary)
    try container.encode(
      Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value.rawValue) }), forKey: .overrides)
  }

  /// Reihenfolge der verbundenen Quellen für eine Datenart: gewählte Quelle, dann das primäre Gerät (nur bei seinen
  /// Stärken), dann die allgemeine Rangfolge. Nur Anbieter, die die Art liefern können.
  public func order(for kind: DataKind, connected: Set<DataProvider>) -> [DataProvider] {
    var result: [DataProvider] = []
    func add(_ provider: DataProvider?) {
      guard let provider, connected.contains(provider), provider.capabilities.contains(kind),
        !result.contains(provider)
      else { return }
      result.append(provider)
    }
    add(overrides[kind])
    if let primary, primary.strengths.contains(kind) { add(primary) }
    DataProvider.defaultOrder(for: kind).forEach(add)
    return result
  }

  /// Bevorzugte Quelle (erste der Reihenfolge).
  public func preferred(for kind: DataKind, connected: Set<DataProvider>) -> DataProvider? {
    order(for: kind, connected: connected).first
  }
}
