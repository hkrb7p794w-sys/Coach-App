import Foundation

/// Export für den „manuellen KI-Coach“: alle Daten eines Zeitraums als eine Markdown-Datei, die sich in ChatGPT,
/// Gemini oder Claude hochladen lässt. Oben steht die Anleitung für die KI samt Antwortformat (`CoachImport`),
/// damit ihre Vorschläge wieder in die App übernommen werden können.
public enum CoachExport {
  public struct Preset: Equatable, Sendable, Identifiable {
    public var label: String
    public var days: Int
    public var id: Int { days }
  }

  public static let presets = [
    Preset(label: "7 Tage", days: 7), Preset(label: "30 Tage", days: 30), Preset(label: "90 Tage", days: 90),
    Preset(label: "1 Jahr", days: 365),
  ]

  /// Eine Mahlzeit, wie sie exportiert wird (die App liest sie aus SwiftData).
  public struct Meal: Equatable, Sendable {
    public var day: CalendarDay
    public var category: String
    public var title: String
    public var items: [MealItem]

    public init(day: CalendarDay, category: String, title: String, items: [MealItem]) {
      self.day = day
      self.category = category
      self.title = title
      self.items = items
    }
  }

  public struct Input: Sendable {
    public var profile: UserProfile
    public var schedule: WeekSchedule
    public var routines: [Routine]
    public var custom: [ExerciseInfo]
    public var equipment: Set<Equipment>
    public var metrics: [DailyMetrics]
    public var activities: [GarminActivity]
    public var gym: [GymSession]
    public var meals: [Meal]
    public var weights: [WeightEntry]

    public init(
      profile: UserProfile, schedule: WeekSchedule, routines: [Routine], custom: [ExerciseInfo],
      equipment: Set<Equipment>, metrics: [DailyMetrics], activities: [GarminActivity], gym: [GymSession],
      meals: [Meal], weights: [WeightEntry]
    ) {
      self.profile = profile
      self.schedule = schedule
      self.routines = routines
      self.custom = custom
      self.equipment = equipment
      self.metrics = metrics
      self.activities = activities
      self.gym = gym
      self.meals = meals
      self.weights = weights
    }
  }

  public static func markdown(_ input: Input, from start: CalendarDay, to end: CalendarDay) -> String {
    let inRange = { (day: CalendarDay?) -> Bool in day.map { start <= $0 && $0 <= end } ?? false }
    var lines: [String] = []
    lines.append("# IronLudi – Trainingsdaten \(start.iso) bis \(end.iso)")
    lines.append("")
    lines += instructions(input)
    lines += profile(input)
    lines += metrics(input.metrics.filter { inRange($0.day) }.sorted { $0.day < $1.day })
    let activities = input.activities.filter { inRange($0.day) }
    lines += Self.activities(activities.sorted { ($0.startLocal ?? "") < ($1.startLocal ?? "") })
    lines += gym(input.gym.filter { inRange($0.day) }.sorted { $0.start < $1.start })
    lines += meals(input.meals.filter { inRange($0.day) })
    lines += weights(input.weights.filter { inRange($0.day) }.sorted { $0.day < $1.day })
    lines += exerciseList(input)
    return lines.joined(separator: "\n")
  }

  // MARK: - Abschnitte

  static func instructions(_ input: Input) -> [String] {
    var lines = [
      "## Anleitung für die KI",
      "",
      "Du bist mein Trainings- und Ernährungscoach. Analysiere die Daten unten: Erholung (Ruhepuls, HRV, Schlaf), "
        + "Trainingsumfang und -verteilung, Fortschritt im Krafttraining, Ernährung und Gewicht. Nenne die "
        + "wichtigsten Erkenntnisse und konkrete Verbesserungen. Stütze dich auf anerkannte sportwissenschaftliche "
        + "Empfehlungen und nenne Zahlen nur, wenn sie aus den Daten folgen.",
      "",
      "Wenn du Änderungen an meinen Trainingsplänen vorschlägst, gib sie zusätzlich am Ende in genau einem "
        + "Codeblock mit der Sprache `ironludi` aus (JSON, nur die Teile, die du ändern willst). Die App prüft den "
        + "Block mit ihren Regeln, bevor sie ihn übernimmt:",
      "",
      "```ironludi",
      "{",
      "  \"routinen\": {",
      "    \"modus\": \"ergaenzen\",",
      "    \"liste\": [",
      "      {\"name\": \"Push A\", \"uebungen\": [",
      "        {\"id\": \"bankdruecken\", \"saetze\": 3, \"wdh_min\": 6, \"wdh_max\": 10, \"pause\": 120, "
        + "\"gewicht\": 55}",
      "      ]}",
      "    ]",
      "  },",
    ]
    if input.profile.mode == .personal {
      lines += [
        "  \"wochenplan\": {",
        "    \"gilt_fuer\": \"dauerhaft\",",
        "    \"tage\": {\"mo\": [{\"sport\": \"strength\", \"intensitaet\": \"hard\"}], \"di\": [], \"mi\": "
          + "[{\"sport\": \"run\", \"intensitaet\": \"easy\"}]}",
        "  },",
      ]
    }
    lines += [
      "  \"hinweise\": [\"Kurzer Hinweis, der in der App angezeigt wird\"]",
      "}",
      "```",
      "",
      "- `routinen.modus`: `ergaenzen` (zu meinen Routinen hinzufügen bzw. gleichnamige ersetzen) oder `ersetzen` "
        + "(alle Routinen ersetzen). Übungen nur mit einer `id` aus der Liste „Erlaubte Übungen“ am Ende. "
        + "`saetze` 1–5, `pause` in Sekunden, `gewicht` in kg (optional), bei Übungen mit Sekunden sind "
        + "`wdh_min`/`wdh_max` Sekunden.",
    ]
    if input.profile.mode == .personal {
      lines.append(
        "- `wochenplan.gilt_fuer`: `dauerhaft` oder `naechste_woche`. Tage `mo`–`so`; `sport`: run, bike, swim, "
          + "strength, other; `intensitaet`: easy, hard, long. Nicht genannte Tage bleiben unverändert, `[]` = frei.")
    } else {
      lines.append("- Mein Ausdauerplan ist ein fester Saisonplan; schlage dafür keine Wochenplan-Änderungen vor.")
    }
    lines.append(
      "- Ernährungsziele berechnet die App selbst (mit Schutzgrenzen); Vorschläge dazu bitte nur als Text.")
    lines.append("")
    return lines
  }

  static func profile(_ input: Input) -> [String] {
    let profile = input.profile
    var lines = ["## Profil", ""]
    let planKind =
      profile.mode == .season ? "fester Saisonplan (Triathlon, Krafttraining nach Routinen)" : "eigener Wochenplan"
    lines.append("- Planart: \(planKind)")
    lines.append("- Ziel: \(profile.goal.label)")
    let sports = profile.sports.map { "\($0.label) (\(profile.level(for: $0).label))" }
    lines.append("- Sportarten: " + sports.joined(separator: ", "))
    if let event = profile.event {
      lines.append("- Wettkampf: \(event.name) am \(event.date.iso)")
    }
    if !profile.health.isEmpty {
      lines.append("- Gesundheit: " + profile.health.map(\.label).joined(separator: "; "))
    }
    let equipment = Equipment.allCases.filter { input.equipment.contains($0) }.map(\.label)
    lines.append("- Ausstattung: " + equipment.joined(separator: ", "))
    if profile.mode == .personal {
      lines.append("")
      lines.append("### Wochenplan")
      for weekday in Weekday.allCases {
        let slots = input.schedule.slots(on: weekday)
        lines.append("- \(weekday.long): " + (slots.isEmpty ? "frei" : slots.map(\.title).joined(separator: ", ")))
      }
    }
    if !input.routines.isEmpty {
      lines.append("")
      lines.append("### Krafttraining-Routinen")
      for routine in input.routines {
        let items = routine.items.map { item in
          var text = "\(item.name) [\(item.exerciseID)] \(item.sets)×\(item.lowerReps)–\(item.upperReps)"
          if let weight = item.weightKg { text += " @ \(number(weight)) kg" }
          return text
        }
        lines.append("- \(routine.name): " + items.joined(separator: "; "))
      }
    }
    lines.append("")
    return lines
  }

  static func metrics(_ days: [DailyMetrics]) -> [String] {
    guard !days.isEmpty else { return [] }
    var lines = [
      "## Tageswerte", "",
      "| Datum | Ruhepuls | HRV (ms) | Schlaf (h) | Schlaf-Score | Body Battery max | Stress | Schritte | "
        + "aktive kcal | VO2max |",
      "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for day in days {
      let cells = [
        day.restingHeartRate, day.hrvLastNightAverage, day.sleepHours, day.sleepScore, day.bodyBatteryHigh,
        day.stressAverage, day.steps, day.activeKilocalories, day.vo2Max,
      ].map { $0.map(number) ?? "–" }
      lines.append("| \(day.day.iso) | " + cells.joined(separator: " | ") + " |")
    }
    lines.append("")
    return lines
  }

  static func activities(_ activities: [GarminActivity]) -> [String] {
    guard !activities.isEmpty else { return [] }
    var lines = [
      "## Ausdauer und andere Aktivitäten", "",
      "| Start | Sport | Name | Dauer (min) | Distanz (km) | Ø HF | Max HF | Belastung | Aerober TE |",
      "|---|---|---|---|---|---|---|---|---|",
    ]
    for activity in activities {
      let cells = [
        activity.startLocal ?? "–", activity.typeKey ?? "–", activity.name ?? "–",
        activity.durationSeconds.map { number(($0 / 60).rounded()) } ?? "–",
        activity.distanceMeters.map { number(($0 / 10).rounded() / 100) } ?? "–",
        activity.averageHeartRate.map(number) ?? "–", activity.maxHeartRate.map(number) ?? "–",
        activity.trainingLoad.map(number) ?? "–", activity.aerobicTrainingEffect.map(number) ?? "–",
      ]
      lines.append("| " + cells.map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: " | ") + " |")
    }
    lines.append("")
    return lines
  }

  static func gym(_ sessions: [GymSession]) -> [String] {
    guard !sessions.isEmpty else { return [] }
    var lines = ["## Krafttraining (Gewicht × Wiederholungen je Satz)", ""]
    for session in sessions {
      let minutes = session.end.map { Int(($0.timeIntervalSince(session.start) / 60).rounded()) }
      lines.append("### \(session.day.iso) – \(session.title)" + (minutes.map { " (\($0) min)" } ?? ""))
      for exercise in session.exercises {
        let sets = exercise.doneSets.map { set in
          var text = set.weightKg > 0 ? "\(number(set.weightKg))×\(set.reps)" : "\(set.reps)"
          if let rir = set.rir { text += " (RIR \(rir))" }
          return text
        }
        guard !sets.isEmpty else { continue }
        lines.append("- \(exercise.name) [\(exercise.exerciseID)]: " + sets.joined(separator: ", "))
      }
      lines.append("")
    }
    return lines
  }

  static func meals(_ meals: [Meal]) -> [String] {
    guard !meals.isEmpty else { return [] }
    var lines = ["## Ernährung", ""]
    for (day, entries) in Dictionary(grouping: meals, by: \.day).sorted(by: { $0.key < $1.key }) {
      let total = entries.flatMap(\.items).reduce(into: [Nutrient: Double]()) { sum, item in
        for nutrient in [Nutrient.kcal, .protein, .carbs, .fat] {
          sum[nutrient, default: 0] += item.amounts[nutrient] ?? 0
        }
      }
      lines.append(
        "### \(day.iso): \(number((total[.kcal] ?? 0).rounded())) kcal, Protein "
          + "\(number((total[.protein] ?? 0).rounded())) g, Kohlenhydrate \(number((total[.carbs] ?? 0).rounded())) g, "
          + "Fett \(number((total[.fat] ?? 0).rounded())) g")
      for meal in entries {
        let items = meal.items.map { "\($0.name) \(number($0.grams.rounded())) g" }.joined(separator: ", ")
        lines.append("- \(meal.category): \(meal.title)" + (items.isEmpty ? "" : " – \(items)"))
      }
      lines.append("")
    }
    return lines
  }

  static func weights(_ entries: [WeightEntry]) -> [String] {
    let merged = WeightTrend.merged(entries)
    guard !merged.isEmpty else { return [] }
    return ["## Gewicht", ""] + merged.map { "- \($0.day.iso): \(number($0.kilograms)) kg" } + [""]
  }

  static func exerciseList(_ input: Input) -> [String] {
    let available = (ExerciseLibrary.all + input.custom).filter { $0.isAvailable(with: input.equipment) }
    return ["## Erlaubte Übungen (id – Name – Muskel)", ""]
      + available.map { "- \($0.id) – \($0.name) – \($0.group.rawValue)" + ($0.tracking == .time ? " (Sekunden)" : "") }
      + [""]
  }

  static func number(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
  }
}
