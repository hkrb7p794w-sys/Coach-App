import Foundation

/// Ergebnis der FIT-Auswertung einer Aktivität (aerobe Kopplung und Runden für den Pace-Check).
public struct ActivityAnalysis: Codable, Equatable, Sendable, Identifiable {
  public let id: Int64
  public var day: CalendarDay
  public var name: String?
  /// Version der Kopplungs-Methode; ältere Einträge werden neu bewertet.
  public var method: Int
  public var decouplingSport: AerobicDecoupling.Sport?
  public var decoupling: AerobicDecoupling.Result?
  /// Warum keine Kopplung berechnet wurde (für die Anzeige „nicht gewertet“).
  public var skipReason: String?
  /// Anteil der Zeit in Zone 4–5 in Prozent.
  public var highZonePercent: Double?
  public var paceKind: PaceCheck.Kind?
  public var laps: [PaceCheck.Lap]?
  /// Selbsteinschätzung auf der Uhr (1–10).
  public var rpe: Double?

  public init(id: Int64, day: CalendarDay, name: String?) {
    self.id = id
    self.day = day
    self.name = name
    method = AerobicDecoupling.methodVersion
  }
}

/// Welche Aktivitäten ausgewertet werden und wie die Ergebnisse in Kopplung und Pace-Check einfließen
/// (Altbestand: `app._update_decoupling_cache`, `app._run_pace_check`).
public enum ActivityAnalysisPlanner {
  /// FIT-Abrufe je Synchronisierung (Garmin-Rate-Limit schonen; der Rest folgt beim nächsten Abruf).
  public static let maxFetchesPerSync = 6
  public static let decouplingDays = 60
  /// Kürzere Einheiten zählen im Altbestand nicht als Trainingseinheit (`tagesform.MIN_DURATION_MIN`).
  public static let minSessionMinutes = 15.0

  /// Lauf mit Schwellen- oder Intervall-Charakter für den Pace-Check.
  public static func paceKind(_ activity: GarminActivity) -> PaceCheck.Kind? {
    guard activity.sport == .run, (activity.durationSeconds ?? 0) / 60 >= minSessionMinutes else { return nil }
    switch SessionKind.of(activity) {
    case .threshold: return .threshold
    case .vo2: return .vo2
    default: return nil
    }
  }

  /// Ob für die Aktivität die FIT-Datei nötig ist.
  public static func needsFile(_ activity: GarminActivity) -> Bool {
    AerobicDecoupling.classify(activity) != nil || paceKind(activity) != nil
  }

  /// Noch nicht (oder mit alter Methode) ausgewertete Aktivitäten der letzten 60 Tage, jüngste zuerst.
  /// Läufe und Fahrten ohne Aussage (z. B. HF-Zweitaufzeichnung der Uhr) fallen weg.
  public static func pending(
    _ activities: [GarminActivity], analyzed: [Int64: ActivityAnalysis], today: CalendarDay
  ) -> [GarminActivity] {
    let start = today.adding(days: -decouplingDays)
    return
      activities
      .filter { activity in
        guard let day = activity.day, day >= start, day <= today else { return false }
        if let known = analyzed[activity.id], known.method == AerobicDecoupling.methodVersion { return false }
        return needsFile(activity) || AerobicDecoupling.skipReason(activity) != nil
      }
      .sorted { ($0.startLocal ?? "") > ($1.startLocal ?? "") }
  }

  /// Auswertung einer Aktivität; `fit` ist `nil`, wenn keine Datei nötig war oder sie nicht lesbar war.
  public static func analyze(_ activity: GarminActivity, fit: FitActivity?, rpe: Double?) -> ActivityAnalysis {
    var analysis = ActivityAnalysis(
      id: activity.id, day: activity.day ?? CalendarDay(year: 2000, month: 1, day: 1),
      name: activity.name)
    analysis.highZonePercent = AerobicDecoupling.highZoneShare(activity).map { AerobicDecoupling.round1($0 * 100) }
    analysis.rpe = rpe
    if let sport = AerobicDecoupling.classify(activity) {
      analysis.decouplingSport = sport
      if let fit, let result = AerobicDecoupling.compute(fit, sport: sport) {
        analysis.decoupling = result
      } else {
        analysis.skipReason = fit == nil ? "FIT-Datei nicht lesbar" : "keine verwertbare Zeitreihe/Runden"
      }
    } else {
      analysis.skipReason = AerobicDecoupling.skipReason(activity)
    }
    if let kind = paceKind(activity) {
      analysis.paceKind = kind
      analysis.laps = fit.map { PaceCheck.Lap.from($0.laps) } ?? []
    }
    return analysis
  }

  /// RPE aus `/activity-service/activity/{id}` (`summaryDTO.directWorkoutRpe`, 10–100).
  public static func rpe(fromActivityDetail json: JSONValue) -> Double? {
    guard let raw = json["summaryDTO"]?["directWorkoutRpe"]?.doubleValue, raw > 0 else { return nil }
    return (raw / 10 * 10).rounded(.toNearestOrEven) / 10
  }

  /// Harte Läufe der letzten zwei Tage ohne RPE: Die Selbsteinschätzung wird oft erst später eingetragen,
  /// also erneut fragen (`tagesform.RPE_REFRESH_DAYS`).
  public static func needsRPE(_ analyses: [ActivityAnalysis], today: CalendarDay) -> [Int64] {
    analyses.filter { $0.paceKind != nil && $0.rpe == nil && $0.day >= today.adding(days: -2) }.map(\.id)
  }

  /// Sitzungen für den Pace-Check (letzte 6 Wochen, älteste zuerst).
  public static func paceSessions(_ analyses: [ActivityAnalysis], today: CalendarDay) -> [PaceCheck.Session] {
    let start = today.adding(days: -PaceCheck.lookbackDays)
    return analyses.compactMap { analysis in
      guard let kind = analysis.paceKind, analysis.day >= start else { return nil }
      return PaceCheck.Session(
        id: analysis.id, day: analysis.day, name: analysis.name, kind: kind, rpe: analysis.rpe,
        laps: analysis.laps ?? [])
    }
    .sorted { ($0.day, $0.id) < ($1.day, $1.id) }
  }

  /// Gewertete Einheiten einer Sportart, älteste zuerst.
  public static func decoupled(_ analyses: [ActivityAnalysis], sport: AerobicDecoupling.Sport) -> [ActivityAnalysis] {
    analyses.filter { $0.decouplingSport == sport && $0.decoupling != nil }.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
  }

  /// Nicht gewertete Läufe/Fahrten mit Grund, die letzten zehn.
  public static func skipped(_ analyses: [ActivityAnalysis]) -> [ActivityAnalysis] {
    Array(
      analyses.filter { $0.decoupling == nil && $0.skipReason != nil }.sorted { ($0.day, $0.id) < ($1.day, $1.id) }
        .suffix(10))
  }

  /// Schnitt der letzten fünf Werte (`avg_recent_pct`).
  public static func recentAverage(_ sessions: [ActivityAnalysis]) -> Double? {
    let values = sessions.compactMap(\.decoupling?.percent).suffix(5)
    guard !values.isEmpty else { return nil }
    return AerobicDecoupling.round1(values.reduce(0, +) / Double(values.count))
  }
}
