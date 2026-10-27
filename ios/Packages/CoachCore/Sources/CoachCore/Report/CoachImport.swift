import Foundation

/// Import der Antwort einer externen KI (ChatGPT, Gemini, Claude) aus dem Format, das `CoachExport` vorgibt: ein
/// Codeblock ```ironludi … ``` mit JSON. Die KI schlägt vor, die Regeln prüfen: nur bekannte Übungen der eigenen
/// Ausstattung, Grenzen für Sätze, Wiederholungen, Pausen und Gewicht, Wochenvolumen; Wochenplan nur im eigenen
/// Plan. Nichts wird übernommen, bevor die Vorschau bestätigt ist.
public enum CoachImport {
  public enum RoutineMode: String, Sendable {
    case add = "ergaenzen"
    case replace = "ersetzen"
  }

  public enum ScheduleScope: String, Sendable {
    case permanent = "dauerhaft"
    case nextWeek = "naechste_woche"
  }

  public struct Preview: Equatable, Sendable {
    public var routines: [Routine] = []
    public var routineMode: RoutineMode = .add
    public var schedule: WeekSchedule?
    public var scheduleScope: ScheduleScope = .permanent
    public var notes: [String] = []
    /// Was die Regeln geändert oder verworfen haben.
    public var corrections: [String] = []
    /// Hinweise der Regeln zum Ergebnis (z. B. Wochenvolumen, Plan-Prüfung).
    public var ruleNotes: [String] = []

    public var isEmpty: Bool { routines.isEmpty && schedule == nil && notes.isEmpty }
  }

  public enum ImportError: Error, Equatable, LocalizedError {
    case noBlock
    case invalidJSON

    public var errorDescription: String? {
      switch self {
      case .noBlock:
        "Kein Block ```ironludi … ``` gefunden. Bitte die ganze Antwort der KI einfügen; das Format steht oben in "
          + "der Export-Datei."
      case .invalidJSON: "Der ironludi-Block ist kein gültiges JSON."
      }
    }
  }

  /// JSON aus dem ersten ```ironludi-Block, sonst aus einem ```json- oder unbenannten Block mit passenden Schlüsseln.
  public static func block(in text: String) throws -> JSONValue {
    var blocks: [(tag: String, body: String)] = []
    var rest = Substring(text.replacingOccurrences(of: "\r\n", with: "\n"))
    while let open = rest.range(of: "```") {
      let afterFence = rest[open.upperBound...]
      guard let lineEnd = afterFence.firstIndex(of: "\n") else { break }
      let body = afterFence[afterFence.index(after: lineEnd)...]
      guard let close = body.range(of: "```") else { break }
      let tag = afterFence[..<lineEnd].trimmingCharacters(in: .whitespaces).lowercased()
      blocks.append((tag, String(body[..<close.lowerBound])))
      rest = body[close.upperBound...]
    }
    if let block = blocks.first(where: { $0.tag == "ironludi" }) {
      guard let json = try? JSONValue(data: Data(block.body.utf8)) else { throw ImportError.invalidJSON }
      return json
    }
    for block in blocks where block.tag == "json" || block.tag.isEmpty {
      if let json = try? JSONValue(data: Data(block.body.utf8)),
        json["routinen"] != nil || json["wochenplan"] != nil || json["hinweise"] != nil
      {
        return json
      }
    }
    throw ImportError.noBlock
  }

  public static func preview(
    _ text: String, profile: UserProfile, equipment: Set<Equipment>, custom: [ExerciseInfo]
  ) throws -> Preview {
    let json = try block(in: text)
    var preview = Preview()

    if let routines = json["routinen"] {
      preview.routineMode = RoutineMode(rawValue: routines["modus"]?.stringValue ?? "") ?? .add
      let list = routines["liste"]?.arrayValue ?? routines.arrayValue ?? []
      var weights: [String: Double] = [:]
      let normalized = list.map { raw -> JSONValue in
        guard case .object(var routine) = raw else { return raw }
        let items = (raw["uebungen"]?.arrayValue ?? []).map { entry -> JSONValue in
          guard case .object(var item) = entry else { return entry }
          let id = resolve(item["id"]?.stringValue ?? item["name"]?.stringValue ?? "", custom: custom)
          item["id"] = .string(id)
          if let weight = item["gewicht"]?.doubleValue, (0...500).contains(weight) { weights[id] = weight }
          return .object(item)
        }
        routine["uebungen"] = .array(items)
        return .object(routine)
      }
      var request = GymCoach.PlanRequest()
      request.daysPerWeek = 10
      request.minutesPerSession = 120
      let checked = GymCoach.validatePlan(
        .object(["routinen": .array(normalized)]), request: request, equipment: equipment, custom: custom,
        lastWeights: weights)
      preview.routines = checked.routines
      preview.corrections += checked.corrections
      preview.ruleNotes += checked.notes
    }

    if let plan = json["wochenplan"] {
      if profile.mode == .season {
        preview.corrections.append("Wochenplan ignoriert: Im Saisonplan stehen die Tage fest.")
      } else {
        preview.scheduleScope = ScheduleScope(rawValue: plan["gilt_fuer"]?.stringValue ?? "") ?? .permanent
        var schedule = profile.schedule
        for (index, key) in ["mo", "di", "mi", "do", "fr", "sa", "so"].enumerated() {
          guard let entries = plan["tage"]?[key]?.arrayValue, let weekday = Weekday(rawValue: index) else { continue }
          var slots: [SessionSlot] = []
          for entry in entries.prefix(3) {
            guard let sport = sport(entry["sport"]?.stringValue) else {
              preview.corrections.append("\(weekday.long): Sportart „\(entry["sport"]?.stringValue ?? "?")“ unbekannt.")
              continue
            }
            slots.append(SessionSlot(sport, intensity(entry["intensitaet"]?.stringValue)))
          }
          schedule.set(slots, on: weekday)
        }
        preview.schedule = schedule
        let missing = Set(TrainingSport.allCases.filter { sport in
          Weekday.allCases.contains { schedule.slots(on: $0).contains { $0.sport == sport } }
        }).subtracting(profile.sports)
        for sport in missing.sorted(by: { $0.rawValue < $1.rawValue }) {
          preview.ruleNotes.append("\(sport.label) steht im Plan, ist aber nicht in deinem Profil gewählt.")
        }
        preview.ruleNotes += ScheduleCheck.hints(schedule: schedule, profile: profile).map(\.message)
      }
    }

    preview.notes = (json["hinweise"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(10)
      .map { String($0.prefix(400)) }
    return preview
  }

  /// ID aus der Bibliothek; sonst Übung gleichen Namens (Groß-/Kleinschreibung egal).
  static func resolve(_ text: String, custom: [ExerciseInfo]) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    if ExerciseLibrary.info(trimmed, custom: custom) != nil { return trimmed }
    let lower = trimmed.lowercased()
    return (ExerciseLibrary.all + custom).first { $0.name.lowercased() == lower }?.id ?? trimmed
  }

  static func sport(_ text: String?) -> TrainingSport? {
    switch text?.lowercased() ?? "" {
    case "run", "laufen", "lauf": .run
    case "bike", "rad", "radfahren": .bike
    case "swim", "schwimmen": .swim
    case "strength", "kraft", "krafttraining", "gym": .strength
    case "other", "anderes", "yoga", "mobilität": .other
    default: nil
    }
  }

  static func intensity(_ text: String?) -> SessionIntensity {
    switch text?.lowercased() ?? "" {
    case "hard", "intensiv", "hart": .hard
    case "long", "lang": .long
    default: .easy
    }
  }
}
