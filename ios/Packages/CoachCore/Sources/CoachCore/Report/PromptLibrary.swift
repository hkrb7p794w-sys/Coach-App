import Foundation

/// Ein Prompt für eine externe KI. Platzhalter: `{zeitraum}`, `{tage}`, `{ziel}`, `{sportarten}`.
public struct PromptTemplate: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var text: String
  /// Daten, die automatisch angehängt werden.
  public var categories: [ExportCategory]
  /// Standardzeitraum in Tagen.
  public var days: Int
  public var isCustom: Bool

  public init(
    id: String = UUID().uuidString, title: String, text: String, categories: [ExportCategory], days: Int,
    isCustom: Bool = true
  ) {
    self.id = id
    self.title = title
    self.text = text
    self.categories = categories
    self.days = min(max(days, 1), 365)
    self.isCustom = isCustom
  }
}

/// Bibliothek der Prompts für externe KI-Analysen. Die App setzt Zeitraum, Ziel und Daten ein und hängt
/// Arbeitsregeln an (nur aus den Daten, Lücken benennen, Unsicherheit kennzeichnen).
public enum PromptLibrary {
  public static let builtIn: [PromptTemplate] = [
    PromptTemplate(
      id: "training", title: "Trainingsanalyse",
      text: "Analysiere meine Trainingsdaten der letzten {tage} Tage ({zeitraum}). Bewerte Trainingsvolumen, "
        + "Intensität, Verteilung über die Woche, Progression und mögliche Stagnationen. Mein Ziel: {ziel}. "
        + "Sportarten: {sportarten}.",
      categories: [.gym, .endurance, .history, .recovery], days: 30, isCustom: false),
    PromptTemplate(
      id: "recovery", title: "Erholung",
      text: "Bewerte meine Regeneration im Zeitraum {zeitraum} anhand von Schlafdaten, HRV, Ruheherzfrequenz und "
        + "der bisherigen Trainingsbelastung. Zeige, an welchen Tagen Belastung und Erholung nicht zusammenpassten, "
        + "und was ich in der nächsten Woche anders machen sollte.",
      categories: [.recovery, .sleep, .endurance, .gym], days: 14, isCustom: false),
    PromptTemplate(
      id: "nutrition", title: "Ernährung",
      text: "Analysiere meine Ernährung im Zeitraum {zeitraum} hinsichtlich meines aktuellen Trainingsziels ({ziel}) "
        + "und identifiziere Verbesserungspotenziale bei Kalorien, Protein und Nährstoffverteilung – auch im Bezug "
        + "auf Trainings- und Ruhetage.",
      categories: [.nutrition, .weight, .endurance, .gym], days: 14, isCustom: false),
    PromptTemplate(
      id: "planning", title: "Trainingsplanung",
      text: "Optimiere meinen Trainingsplan unter Berücksichtigung meiner bisherigen Leistungen ({zeitraum}), meiner "
        + "Regeneration und der Zeit, die ich laut Wochenplan tatsächlich trainiere. Ziel: {ziel}. Schlage konkrete "
        + "Änderungen vor (Übungen, Sätze, Wiederholungen, Tage) und begründe jede kurz.",
      categories: [.gym, .endurance, .recovery, .history], days: 28, isCustom: false),
    PromptTemplate(
      id: "stagnation", title: "Stagnation im Krafttraining",
      text: "Prüfe meine Krafteinheiten der letzten {tage} Tage auf Stagnation: Bei welchen Übungen steigen Gewicht "
        + "oder Wiederholungen nicht mehr? Nenne mögliche Ursachen aus den Daten (Volumen, Häufigkeit, Erholung) und "
        + "konkrete Gegenmaßnahmen.",
      categories: [.gym, .history, .recovery], days: 90, isCustom: false),
    PromptTemplate(
      id: "progress", title: "Langfristiger Fortschritt",
      text: "Fasse meinen Fortschritt im Zeitraum {zeitraum} zusammen: Trainingsumfang, Kraftwerte, Ausdauer und "
        + "Gewicht. Was hat sich verbessert, was stagniert, und welche zwei Dinge bringen mich meinem Ziel ({ziel}) "
        + "am meisten näher?",
      categories: [.history, .gym, .endurance, .weight], days: 365, isCustom: false),
    PromptTemplate(
      id: "sleep", title: "Schlaf",
      text: "Analysiere meinen Schlaf im Zeitraum {zeitraum}: Dauer, Regelmäßigkeit, Schlafphasen und den Bezug zu "
        + "Trainingstagen und Stress. Gib mir drei konkrete, umsetzbare Empfehlungen.",
      categories: [.sleep, .recovery, .health], days: 30, isCustom: false),
    PromptTemplate(
      id: "body", title: "Gewicht und Körper",
      text: "Bewerte meinen Gewichtsverlauf im Zeitraum {zeitraum} im Verhältnis zu Ernährung und Training. Passt "
        + "das Tempo zu meinem Ziel ({ziel})? Trenne dabei echte Trends von normalen Schwankungen.",
      categories: [.weight, .nutrition, .history], days: 90, isCustom: false),
  ]

  /// Arbeitsregeln, die jedem Prompt angehängt werden.
  public static let rules = [
    "Arbeitsweise:",
    "- Stütze dich nur auf die Daten unten. Erfinde keine Werte; „–“ bzw. null heißt nicht gemessen.",
    "- Fehlen Daten für eine Aussage, sag das ausdrücklich, statt zu schätzen.",
    "- Kennzeichne unsichere Schlüsse als solche.",
    "- Keine Diagnosen; bei auffälligen Gesundheitswerten Rücksprache mit Ärztin oder Arzt empfehlen.",
    "- Antworte auf Deutsch in dieser Gliederung: 1. Kernaussagen (höchstens 5), 2. Details, "
      + "3. Empfehlungen nach Wichtigkeit, 4. Fehlende Daten und offene Fragen.",
  ].joined(separator: "\n")

  /// Setzt die Platzhalter ein.
  public static func filled(
    _ template: PromptTemplate, profile: UserProfile, from start: CalendarDay, to end: CalendarDay
  ) -> String {
    let days = start.days(until: end) + 1
    return template.text
      .replacingOccurrences(of: "{zeitraum}", with: "\(GermanFormat.date(start)) bis \(GermanFormat.date(end))")
      .replacingOccurrences(of: "{tage}", with: String(days))
      .replacingOccurrences(of: "{ziel}", with: profile.goal.label)
      .replacingOccurrences(of: "{sportarten}", with: profile.sports.map(\.label).joined(separator: ", "))
  }

  /// Prompt, Arbeitsregeln und Daten in einem Text – zum Einfügen in ChatGPT, Gemini, Claude oder ein lokales Modell.
  public static func compose(
    _ template: PromptTemplate, input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay,
    format: ExportFormat = .markdown
  ) -> String {
    let categories = Set(template.categories)
    let data: String
    switch format {
    case .json:
      data = "```json\n" + DataExport.json(input, from: start, to: end, categories: categories) + "\n```"
    case .markdown, .csv:
      data = DataExport.markdown(input, from: start, to: end, categories: categories)
    }
    return [
      filled(template, profile: input.profile, from: start, to: end), "", rules, "", "---", "", data,
    ].joined(separator: "\n")
  }
}
