import Foundation

/// Stufe der Tagesempfehlung. Reihenfolge = Schwere.
public enum RecoveryLevel: String, Codable, Sendable, Comparable, CaseIterable {
  case normal
  case locker
  case pause

  private var severity: Int {
    switch self {
    case .normal: 0
    case .locker: 1
    case .pause: 2
    }
  }

  public static func < (lhs: RecoveryLevel, rhs: RecoveryLevel) -> Bool {
    lhs.severity < rhs.severity
  }

  public var label: String {
    switch self {
    case .normal: "Normal trainieren"
    case .locker: "Locker / verkürzt"
    case .pause: "Ruhetag oder sehr locker"
    }
  }

  public var advice: String {
    switch self {
    case .normal: "Geplante Einheit wie vorgesehen durchziehen."
    case .locker:
      "Einheit machen, aber Intensität raus: harte Intervalle durch lockeres Training ersetzen oder um ein "
        + "Drittel kürzen."
    case .pause: "Heute Ruhetag – höchstens 20–30 min sehr locker bewegen."
    }
  }
}

/// Regelbasierte Tagesempfehlung – deterministisch, ohne Netzwerk. Die KI formuliert nur den Text dazu
/// und darf die Entscheidung nicht ändern.
public struct Recommendation: Codable, Equatable, Sendable {
  public let level: RecoveryLevel
  public let reasons: [String]

  public var label: String { level.label }
  public var advice: String { level.advice }
}

/// Portierung von `garmin_ai_coach/recommendation.py` (Altbestand).
///
/// Grundlagen der Regeln:
/// - HRV: maßgeblich ist der 7-Tage-Schnitt relativ zur persönlichen Baseline (Garmin „HRV-Status“),
///   nicht die Einzelnacht (Plews et al. 2012/2013; Garmin-Handbuch „Heart Rate Variability Status“).
/// - Readiness: Garmins Stufen (1–24 Poor, 25–49 Low, …), nur nach unten genutzt, weil die akute
///   Belastung selbst in den Score einfließt. Nur über den Garmin-Connect-Zugang; ohne Wert entfällt die Regel.
/// - Ruhepuls: mindestens 5 bpm über dem eigenen 7-Tage-Schnitt als Warnsignal.
/// - Schlaf: unter 5 h rot, unter 6 h gelb.
public enum RecoveryEvaluator {
  public static let hrvStatusGerman = [
    "BALANCED": "ausgeglichen",
    "UNBALANCED": "unausgeglichen",
    "LOW": "niedrig",
    "POOR": "schlecht",
    "NONE": "noch kein Status",
  ]

  public static func evaluate(
    _ metrics: DailyMetrics,
    restingHeartRate7DayAverage: Double?,
    readinessScore: Double? = nil
  ) -> Recommendation {
    var level = RecoveryLevel.normal
    var reasons: [String] = []
    func worsen(to candidate: RecoveryLevel) { level = max(level, candidate) }

    switch metrics.hrvStatus?.uppercased() {
    case let status? where status == "LOW" || status == "POOR":
      worsen(to: .pause)
      reasons.append(
        "HRV-Status \(hrvStatusGerman[status] ?? status) (7-Tage-Schnitt deutlich unter deiner Baseline)")
    case "UNBALANCED"?:
      if let weekly = metrics.hrvWeeklyAverage, let low = metrics.hrvBaselineLow, weekly < low {
        worsen(to: .locker)
        reasons.append("HRV-Status unausgeglichen, 7-Tage-Schnitt unter deiner Baseline")
      } else {
        // Über der Baseline ist nicht automatisch gut (kann bei viel lockerem Umfang auf Überlastung
        // hindeuten) – nur benennen, nicht herabstufen.
        reasons.append("HRV-Status unausgeglichen (über der Baseline) – im Blick behalten")
      }
    case "BALANCED"?:
      reasons.append("HRV-Status ausgeglichen")
    default:
      break
    }

    if let score = readinessScore ?? metrics.trainingReadiness {
      if score < 25 {
        worsen(to: .pause)
        reasons.append("Readiness \(Int(score.rounded())) (Garmin-Stufe „Poor“)")
      } else if score < 50 {
        worsen(to: .locker)
        reasons.append("Readiness \(Int(score.rounded())) (Garmin-Stufe „Low“)")
      }
    }

    if let restingHR = metrics.restingHeartRate, let average = restingHeartRate7DayAverage,
      restingHR >= average + 5
    {
      worsen(to: .locker)
      reasons.append(
        "Ruhepuls \(Int(restingHR.rounded())) bpm, \(Int((restingHR - average).rounded())) über deinem "
          + "7-Tage-Schnitt")
    }

    if let hours = metrics.sleepHours {
      if hours < 5 {
        worsen(to: .pause)
        reasons.append("nur \(GermanFormat.decimal(hours)) h Schlaf")
      } else if hours < 6 {
        worsen(to: .locker)
        reasons.append("kurzer Schlaf (\(GermanFormat.decimal(hours)) h)")
      }
    }

    if reasons.isEmpty { reasons.append("keine Erholungswerte auffällig") }
    return Recommendation(level: level, reasons: reasons)
  }

  /// Mittelwert eines Werts über die Tage `offsets` vor `today` (wie `_history_avg` im Altbestand).
  public static func average(
    _ value: (DailyMetrics) -> Double?,
    in history: [DailyMetrics],
    daysBefore offsets: ClosedRange<Int>,
    today: CalendarDay
  ) -> Double? {
    let values = history.filter { offsets.contains($0.day.days(until: today)) }.compactMap(value)
    guard !values.isEmpty else { return nil }
    return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
  }
}

public enum GermanFormat {
  /// Eine Nachkommastelle mit Komma, ohne „,0“ bei ganzen Zahlen: 4,5 / 6.
  public static func decimal(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
  }

  /// Bis zu zwei Nachkommastellen mit Komma, ohne Nullen am Ende: 52,5 / 13,75 / 55 (wie `%g`).
  public static func number(_ value: Double) -> String {
    let rounded = (value * 100).rounded() / 100
    if rounded == rounded.rounded() { return String(Int(rounded)) }
    var text = String(format: "%.2f", rounded)
    while text.hasSuffix("0") { text.removeLast() }
    return text.replacingOccurrences(of: ".", with: ",")
  }

  /// `dd.MM.yyyy`
  public static func date(_ day: CalendarDay) -> String {
    String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
  }

  /// `m:ss`
  public static func minutesSeconds(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}
