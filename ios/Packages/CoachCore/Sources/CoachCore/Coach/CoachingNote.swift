import Foundation

/// Datenschutzmodus für KI-Aufrufe. Im kostenlosen Gemini-Kontingent darf Google Eingaben zur
/// Produktverbesserung nutzen (Gemini API Additional Terms, „Unpaid Services“). „Reduziert“ schickt daher
/// keine Rohwerte (Ruhepuls, HRV in ms, Schlafstunden), nur Einordnungen.
public enum PrivacyMode: String, Codable, Sendable, CaseIterable {
  case reduced = "reduziert"
  case full = "voll"
}

/// Baut die Eingabe der Worker-Aufgabe `daily_note` und die Notiz ohne KI.
public enum CoachingNote {
  public static func input(
    recommendation: Recommendation,
    metrics: DailyMetrics?,
    plan: PlanState,
    config: SeasonConfig,
    week: WeeklyVolume,
    privacy: PrivacyMode
  ) -> [String: JSONValue] {
    let decisionReasons = privacy == .full ? recommendation.reasons : neutralReasons(recommendation, metrics)
    return [
      "weekday": .string(plan.weekday),
      "phase": .string(plan.phase.rawValue),
      "phaseFocus": .string(plan.phase.focus),
      "phaseDetail": .string(plan.plan.promptText),
      "raceName": .string(config.mainRaceDescription),
      "raceDate": .string(GermanFormat.date(config.mainRaceDate)),
      "raceGoal": .string(config.raceGoal),
      "daysToRace": .number(Double(plan.daysToRace)),
      "testValues": .string(SeasonPlan.testValuesText(config)),
      "todayItems": .array(plan.todayFixed.map { .string($0.text) }),
      "openItems": .array(plan.weekOpen.map { .string($0) }),
      "daysLeftInWeek": .number(Double(plan.daysLeftInWeek)),
      "volumes": .object([
        "swimKm": .number(rounded(week.kilometers[.swim] ?? 0)),
        "bikeKm": .number(rounded(week.kilometers[.bike] ?? 0)),
        "runKm": .number(rounded(week.kilometers[.run] ?? 0)),
      ]),
      "vitals": .array(vitals(metrics, privacy: privacy).map { .string($0) }),
      "decision": .object([
        "label": .string(recommendation.label),
        "advice": .string(recommendation.advice),
        "reasons": .array(decisionReasons.map { .string($0) }),
      ]),
    ]
  }

  /// Erholungsblock: im Modus „reduziert“ ohne Rohwerte (wie `vitals_block` im Altbestand).
  public static func vitals(_ metrics: DailyMetrics?, privacy: PrivacyMode) -> [String] {
    guard let metrics else { return ["keine Erholungsdaten für heute"] }
    let status = metrics.hrvStatus.map { RecoveryEvaluator.hrvStatusGerman[$0] ?? $0 } ?? "keine Daten"
    switch privacy {
    case .full:
      return [
        "Ruhepuls: \(number(metrics.restingHeartRate, " bpm"))",
        "HRV letzte Nacht: \(number(metrics.hrvLastNightAverage, " ms")), 7-Tage-Schnitt "
          + "\(number(metrics.hrvWeeklyAverage, " ms")) (Status \(status))",
        "Body Battery: \(number(metrics.bodyBatteryHigh, ""))",
        "Schlaf: \(metrics.sleepHours.map { GermanFormat.decimal($0) + " h" } ?? "keine Daten"), Score "
          + number(metrics.sleepScore, ""),
      ]
    case .reduced:
      return [
        "HRV-Status (7-Tage-Schnitt vs. Baseline): \(status)",
        "Schlaf: \(band(metrics.sleepHours, [(6, "kurz"), (7.5, "normal")], otherwise: "gut"))",
        "Body Battery: \(band(metrics.bodyBatteryHigh, [(30, "niedrig"), (60, "mittel")], otherwise: "hoch"))",
      ]
    }
  }

  /// Begründungen ohne Zahlen für den Modus „reduziert“.
  static func neutralReasons(_ recommendation: Recommendation, _ metrics: DailyMetrics?) -> [String] {
    recommendation.reasons.map { reason in
      if reason.hasPrefix("Ruhepuls") { return "Ruhepuls deutlich über deinem 7-Tage-Schnitt" }
      if reason.hasPrefix("nur") && reason.hasSuffix("Schlaf") { return "sehr kurzer Schlaf" }
      if reason.hasPrefix("kurzer Schlaf") { return "kurzer Schlaf" }
      if reason.hasPrefix("Readiness") { return "Garmin-Readiness niedrig" }
      return reason
    }
  }

  /// Notiz ohne KI – wird angezeigt, solange die KI nicht erreichbar oder nicht eingerichtet ist.
  public static func fallback(_ recommendation: Recommendation, plan: PlanState) -> [String] {
    var lines = [
      "\(recommendation.label): \(recommendation.advice)",
      "Grund: " + recommendation.reasons.joined(separator: "; ") + ".",
    ]
    let today = plan.todayFixed.map(\.text)
    if !today.isEmpty { lines.append("Heute laut Wochenrahmen: " + today.joined(separator: ", ") + ".") }
    if !plan.weekOpen.isEmpty {
      if plan.daysLeftInWeek == 0 {
        let rest =
          recommendation.level == .normal ? "nur noch heute möglich" : "entfällt bei dieser Tagesampel diese Woche"
        lines.append("Offen, heute letzter Tag der Woche (\(rest)): " + plan.weekOpen.joined(separator: ", ") + ".")
      } else {
        lines.append("Diese Woche noch offen: " + plan.weekOpen.joined(separator: ", ") + ".")
      }
    }
    return lines
  }

  /// Liest `{"punkte": ["…", …]}` aus der KI-Antwort.
  public static func points(from output: JSONValue) -> [String] {
    let values = output["punkte"]?.arrayValue ?? output.arrayValue ?? []
    return values.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  private static func number(_ value: Double?, _ unit: String) -> String {
    value.map { GermanFormat.decimal($0) + unit } ?? "keine Daten"
  }

  private static func band(_ value: Double?, _ limits: [(Double, String)], otherwise: String) -> String {
    guard let value else { return "keine Daten" }
    return limits.first { value < $0.0 }?.1 ?? otherwise
  }

  private static func rounded(_ value: Double) -> Double {
    (value * 10).rounded() / 10
  }
}
