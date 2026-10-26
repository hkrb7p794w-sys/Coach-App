import Foundation

/// Optionaler Begleiter (z. B. der eigene Hund), der den Tag in freundlichen Worten kommentiert. Er sagt nichts,
/// was nicht auch die Regeln sagen: Die Stimmung folgt aus Plan, Erholung und Erledigtem. Kein Druck, keine
/// Schuldgefühle – bei schlechter Erholung lobt er das Ausruhen.
public struct CompanionSettings: Codable, Equatable, Hashable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable, Identifiable {
    case dog, cat, coach
    /// Gezeichnete, animierte Daisy (`DaisyGeometry`).
    case daisy

    public var id: String { rawValue }

    public var label: String {
      switch self {
      case .daisy: "Daisy (animiert)"
      case .dog: "Hund"
      case .cat: "Katze"
      case .coach: "Trainer:in"
      }
    }

    public var symbol: String {
      switch self {
      case .dog, .daisy: "dog.fill"
      case .cat: "cat.fill"
      case .coach: "figure.strengthtraining.functional"
      }
    }
  }

  public var enabled: Bool
  public var name: String
  public var kind: Kind

  public init(enabled: Bool = false, name: String = "", kind: Kind = .dog) {
    self.enabled = enabled
    self.name = name
    self.kind = kind
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
    name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    kind = (try? container.decodeIfPresent(Kind.self, forKey: .kind)) ?? .dog
  }

  /// Anzeigename; ohne Eingabe ein Standardname.
  public var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { return trimmed }
    switch kind {
    case .dog, .daisy: return "Daisy"
    case .cat: return "Mimi"
    case .coach: return "Coach"
    }
  }

  public var isActive: Bool { enabled }

  /// Hund-Sätze gelten auch für Daisy.
  var voice: Kind { kind == .daisy ? .dog : kind }
}

public enum CompanionMood: String, Equatable, Sendable {
  /// Heute trainiert.
  case happy
  /// Woche komplett.
  case proud
  /// Einheit steht heute an.
  case excited
  /// Ruhetag.
  case resting
  /// Erholung niedrig: lieber kuscheln und ausruhen.
  case cozy
  /// Gestern etwas verpasst – heute ist ein neuer Tag.
  case hopeful

  /// Symbol für die Stimmung (neben dem Begleiter).
  public var symbol: String {
    switch self {
    case .happy: "heart.fill"
    case .proud: "star.fill"
    case .excited: "sparkles"
    case .resting: "moon.zzz.fill"
    case .cozy: "cup.and.saucer.fill"
    case .hopeful: "sun.max.fill"
    }
  }
}

public struct CompanionMessage: Equatable, Sendable {
  public var mood: CompanionMood
  public var text: String
}

public enum CompanionVoice {
  public struct Context: Equatable, Sendable {
    public var plannedToday: [String]
    public var trainedToday: Bool
    public var recovery: RecoveryLevel?
    public var week: WeekAdherence
    public var missedYesterday: Bool

    public init(
      plannedToday: [String], trainedToday: Bool, recovery: RecoveryLevel?, week: WeekAdherence,
      missedYesterday: Bool
    ) {
      self.plannedToday = plannedToday
      self.trainedToday = trainedToday
      self.recovery = recovery
      self.week = week
      self.missedYesterday = missedYesterday
    }
  }

  public static func mood(_ context: Context) -> CompanionMood {
    if context.trainedToday { return context.week.isComplete ? .proud : .happy }
    if context.recovery == .pause { return .cozy }
    if context.plannedToday.isEmpty { return context.week.isComplete ? .proud : .resting }
    if context.missedYesterday { return .hopeful }
    return .excited
  }

  /// Fester Satz je Stimmung und Begleiter. `day` wählt zwischen Varianten, damit es nicht jeden Tag gleich klingt.
  public static func message(_ context: Context, companion: CompanionSettings, day: CalendarDay) -> CompanionMessage {
    let mood = mood(context)
    let name = companion.displayName
    let session = context.plannedToday.first ?? "Training"
    let variants: [String]
    switch (companion.voice, mood) {
    case (.dog, .happy):
      variants = [
        "Wuff! Du warst heute fleißig – \(name) wedelt ganz doll mit dem Schwanz.",
        "\(name) ist stolz auf dich! Jetzt gibt's Kuscheln und was Leckeres.",
      ]
    case (.dog, .proud):
      variants = [
        "Alles geschafft diese Woche! \(name) dreht vor Freude Kreise.",
        "Wochenziel erreicht – \(name) bringt dir zur Feier das Lieblingsspielzeug.",
      ]
    case (.dog, .excited):
      variants = [
        "Heute steht „\(session)“ an. \(name) sitzt schon an der Tür und wartet auf dich!",
        "\(name) stupst dich an: Heute ist „\(session)“ dran. Du schaffst das!",
      ]
    case (.dog, .resting):
      variants = [
        "Ruhetag! \(name) liegt im Körbchen – mach es genauso und erhol dich.",
        "Heute ist frei. \(name) findet: Spaziergang und Sofa sind auch Training für die Seele.",
      ]
    case (.dog, .cozy):
      variants = [
        "Du wirkst heute müde. \(name) kuschelt sich an dich – Ausruhen ist heute das Beste.",
        "\(name) meint: Heute lieber langsam. Erholung macht dich stärker.",
      ]
    case (.dog, .hopeful):
      variants = [
        "Gestern hat's nicht geklappt? Egal! \(name) freut sich einfach auf heute: „\(session)“.",
        "Neuer Tag, neues Glück – \(name) wedelt und wartet auf „\(session)“.",
      ]
    case (.cat, .happy): variants = ["\(name) schnurrt zufrieden: gut gemacht heute!"]
    case (.cat, .proud): variants = ["Wochenziel erreicht. \(name) ist (ausnahmsweise) beeindruckt."]
    case (.cat, .excited): variants = ["\(name) streckt sich: Heute ist „\(session)“ dran. Du auch?"]
    case (.cat, .resting): variants = ["Ruhetag. \(name) zeigt dir, wie Entspannen geht."]
    case (.cat, .cozy): variants = ["\(name) rollt sich neben dir ein: Heute ist Erholung angesagt."]
    case (.cat, .hopeful): variants = ["Gestern verpasst? \(name) ist nicht nachtragend. Heute: „\(session)“."]
    case (.coach, .happy): variants = ["Stark! Einheit erledigt. Jetzt essen, trinken, erholen."]
    case (.coach, .proud): variants = ["Wochenziel erreicht. Genau so geht Fortschritt: Woche für Woche."]
    case (.coach, .excited): variants = ["Heute: „\(session)“. Ruhig starten, sauber durchziehen."]
    case (.coach, .resting): variants = ["Ruhetag. Erholung gehört zum Training."]
    case (.coach, .cozy): variants = ["Deine Erholung ist niedrig. Heute lieber locker oder frei – das zahlt sich aus."]
    case (.coach, .hopeful): variants = ["Gestern ist vorbei. Heute zählt: „\(session)“."]
    case (.daisy, _): variants = ["\(name) ist bei dir."]  // nicht erreicht: `voice` bildet Daisy auf .dog ab
    }
    let index = abs(day.day + day.month * 31) % variants.count
    return CompanionMessage(mood: mood, text: variants[index])
  }

  /// Kurzer Zusatz für die Erinnerung, z. B. „Daisy wartet schon“.
  public static func reminderLead(_ companion: CompanionSettings) -> String? {
    guard companion.isActive else { return nil }
    switch companion.kind {
    case .dog, .daisy: return "\(companion.displayName) wartet schon an der Tür."
    case .cat: return "\(companion.displayName) schaut erwartungsvoll."
    case .coach: return nil
    }
  }
}
