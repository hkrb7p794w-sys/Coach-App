import Foundation

/// Fakten für den Chat mit dem Coach: alles, was die Regeln der App berechnet haben, als kurze Sätze. Die KI darf
/// nur daraus antworten (Worker-Aufgabe `coach_chat`). Im Datenschutzmodus „reduziert“ gehen keine
/// Roh-Gesundheitswerte hinaus, nur Einordnungen.
public enum ChatContext {
  public static let evidence = [
    "recovery.hrv", "recovery.rhr", "recovery.sleep", "sleep.regularity", "sleep.extension", "run.progression",
    "plan.deload", "taper", "nutrition.energy", "nutrition.protein", "weight.trend", "load.fitness-form",
    "gym.progression",
  ]

  public struct Facts: Sendable {
    public var profile: UserProfile
    public var privacy: PrivacyMode
    public var recommendation: String?
    public var reasons: [String] = []
    public var todaySessions: [String] = []
    public var sleep: SleepCoach.Report?
    public var targets: NutritionTargets?
    public var eatenKilocalories: Double?
    public var formZone: FitnessForm.Zone?
    public var weekHighlights: [String] = []
    public var weightTrend: WeightTrend.Result?
    public var runWeek: RunPlanner.Week?

    public init(profile: UserProfile, privacy: PrivacyMode) {
      self.profile = profile
      self.privacy = privacy
    }
  }

  public static func lines(_ facts: Facts) -> [String] {
    let full = facts.privacy == .full
    var lines: [String] = []
    let profile = facts.profile
    lines.append("Ziel: \(profile.goal.label); Sportarten: \(profile.sports.map(\.label).joined(separator: ", ")).")
    if let event = profile.event {
      lines.append(
        "Wettkampf: \(event.name) (\(event.kind.label)) am \(GermanFormat.date(event.date))"
          + (event.targetSeconds.map { ", Zielzeit \(InputCheck.time(Double($0)))" } ?? "") + ".")
    }
    if let recommendation = facts.recommendation {
      // Gründe enthalten Messwerte; im reduzierten Modus nur die Einordnung.
      let reasons = full && !facts.reasons.isEmpty ? " (\(facts.reasons.joined(separator: "; ")))" : ""
      lines.append("Tagesampel heute: \(recommendation)\(reasons).")
    }
    lines.append(
      facts.todaySessions.isEmpty
        ? "Heute ist keine Einheit geplant." : "Heute geplant: \(facts.todaySessions.joined(separator: "; ")).")
    if let week = facts.runWeek {
      lines.append(
        "Laufwoche: \(week.phase.label), \(week.totalMinutes) Minuten geplant, Schnitt der letzten vier Wochen "
          + "\(week.baselineMinutes) Minuten.")
    }
    if let sleep = facts.sleep {
      if full {
        lines.append(
          "Schlaf der letzten \(sleep.nights) Nächte: im Schnitt \(GermanFormat.decimal(sleep.averageHours)) Stunden; "
            + "empfohlene Schlafenszeit heute \(SleepCoach.clock(sleep.bedtimeMinutes)).")
      } else {
        let category = sleep.averageHours < 7 ? "im Schnitt unter 7 Stunden" : "im Schnitt mindestens 7 Stunden"
        lines.append(
          "Schlaf der letzten Nächte: \(category); "
            + "empfohlene Schlafenszeit heute \(SleepCoach.clock(sleep.bedtimeMinutes)).")
      }
      if let spread = sleep.bedtimeSpreadMinutes, spread > SleepCoach.irregularMinutes {
        lines.append("Die Einschlafzeit schwankt stark.")
      }
    }
    if let targets = facts.targets {
      let kcal = Int(targets.values[.kcal] ?? 0)
      let protein = Int(targets.values[.protein] ?? 0)
      var line = "Tagesziel Ernährung (\(targets.dayType.label)): \(kcal) kcal, \(protein) g Protein"
      if let eaten = facts.eatenKilocalories { line += "; bisher erfasst \(Int(eaten.rounded())) kcal" }
      lines.append(line + ".")
    }
    if let trend = facts.weightTrend {
      if full {
        lines.append(
          "Gewichtstrend: \(GermanFormat.number(trend.trendKilograms)) kg, "
            + "\(GermanFormat.number(trend.weeklyPercent)) % pro Woche.")
      } else {
        let direction =
          abs(trend.weeklyPercent) < 0.1 ? "stabil" : trend.weeklyPercent < 0 ? "leicht fallend" : "leicht steigend"
        lines.append("Gewichtstrend: \(direction).")
      }
    }
    if let zone = facts.formZone {
      lines.append("Form (Fitness gegen Ermüdung): \(zone.label).")
    }
    for highlight in facts.weekHighlights.prefix(3) {
      lines.append("Wochenbericht: \(highlight)")
    }
    return lines
  }

  public static func input(_ facts: Facts, question: String, history: [(role: String, text: String)])
    -> [String: JSONValue]
  {
    [
      "question": .string(String(question.prefix(600))),
      "history": .array(
        history.suffix(6).map { .object(["role": .string($0.role), "text": .string(String($0.text.prefix(600)))]) }),
      "facts": .array(lines(facts).map { .string($0) }),
      "evidence": CoachingNote.evidenceInput(evidence),
    ]
  }

  /// Antwort aus `{"antwort": "...", "quellen": [...]}`.
  public static func answer(from output: JSONValue) -> (text: String, sources: [String])? {
    guard let text = output["antwort"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
    else { return nil }
    let sources = output["quellen"]?.arrayValue?.compactMap(\.stringValue) ?? []
    return (text, sources)
  }
}
