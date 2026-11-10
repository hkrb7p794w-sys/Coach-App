import Foundation

/// Welche Daten der KI-Export enthält.
public enum ExportCategory: String, Codable, CaseIterable, Sendable {
  case gym
  case endurance = "ausdauer"
  case health = "gesundheit"
  case sleep = "schlaf"
  case nutrition = "ernaehrung"
  case weight = "gewicht"
  case recovery = "erholung"
  case history = "verlauf"

  public var label: String {
    switch self {
    case .gym: "Gym"
    case .endurance: "Ausdauertraining"
    case .health: "Gesundheit"
    case .sleep: "Schlaf"
    case .nutrition: "Ernährung"
    case .weight: "Gewicht und Körper"
    case .recovery: "Erholung"
    case .history: "Trainingsverlauf"
    }
  }

  public var detail: String {
    switch self {
    case .gym: "Einheiten mit allen Sätzen, Trainingspläne, Übungsliste"
    case .endurance: "Aktivitäten mit Dauer, Distanz, Herzfrequenz, Belastung"
    case .health: "Schritte, Stress, Kalorien, VO2max, SpO2"
    case .sleep: "Dauer, Score, Phasen, Einschlafzeit"
    case .nutrition: "Mahlzeiten mit Positionen und Tagessummen"
    case .weight: "Gewichtsverlauf"
    case .recovery: "Ruhepuls, HRV, Body Battery, Readiness"
    case .history: "Wochenübersicht: Einheiten, Minuten, Kilometer"
    }
  }
}

public enum ExportFormat: String, Codable, CaseIterable, Sendable {
  case markdown
  case json
  case csv

  public var label: String {
    switch self {
    case .markdown: "Markdown (lesbar)"
    case .json: "JSON (strukturiert)"
    case .csv: "CSV (Tabellen)"
    }
  }

  public var fileExtension: String {
    switch self {
    case .markdown: "md"
    case .json: "json"
    case .csv: "csv"
    }
  }
}

/// KI-Export mit Auswahl der Daten. Fehlende Werte stehen als „–“ bzw. `null` da – nie als 0, damit eine externe KI
/// nichts hineinliest, was nicht gemessen wurde.
public enum DataExport {
  public struct File: Equatable, Sendable {
    public var name: String
    public var content: String

    public init(name: String, content: String) {
      self.name = name
      self.content = content
    }
  }

  // MARK: - Markdown

  /// `withImportFormat`: Anleitung samt Antwortformat (`CoachImport`) für den manuellen KI-Coach voranstellen.
  public static func markdown(
    _ input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay, categories: Set<ExportCategory>,
    withImportFormat: Bool = false
  ) -> String {
    let data = Slice(input, from: start, to: end)
    var lines = ["# AIronLudi – Daten \(start.iso) bis \(end.iso)", ""]
    let included = ExportCategory.allCases.filter(categories.contains).map(\.label)
    lines.append("Enthalten: " + included.joined(separator: ", "))
    lines.append("Fehlende Werte stehen als „–“ da und bedeuten: nicht gemessen.")
    lines.append("")
    if withImportFormat { lines += CoachExport.instructions(input) }
    lines += CoachExport.profile(input)
    if categories.contains(.recovery) {
      lines += table(
        "Erholung", ["Datum", "Ruhepuls", "HRV (ms)", "HRV-Status", "Body Battery max", "Readiness"], data.metrics
      ) { day in
        [
          day.day.iso, num(day.restingHeartRate), num(day.hrvLastNightAverage), day.hrvStatus ?? "–",
          num(day.bodyBatteryHigh), num(day.trainingReadiness),
        ]
      }
    }
    if categories.contains(.sleep) {
      lines += table(
        "Schlaf", ["Datum", "Schlaf (h)", "Score", "Tief (h)", "REM (h)", "Wach (min)"],
        data.metrics.filter { $0.sleepSeconds != nil }
      ) { day in
        [
          day.day.iso, num(day.sleepHours), num(day.sleepScore), hours(day.deepSleepSeconds),
          hours(day.remSleepSeconds),
          num(day.awakeSleepSeconds.map { $0 / 60 }),
        ]
      }
    }
    if categories.contains(.health) {
      lines += table(
        "Gesundheit", ["Datum", "Schritte", "Stress", "aktive kcal", "VO2max", "SpO2"], data.metrics
      ) { day in
        [
          day.day.iso, num(day.steps), num(day.stressAverage), num(day.activeKilocalories), num(day.vo2Max),
          num(day.spo2Average),
        ]
      }
    }
    if categories.contains(.endurance) { lines += CoachExport.activities(data.endurance) }
    if categories.contains(.gym) { lines += CoachExport.gym(data.gym) }
    if categories.contains(.nutrition) { lines += CoachExport.meals(data.meals) }
    if categories.contains(.weight) { lines += CoachExport.weights(data.weights) }
    if categories.contains(.history) {
      lines += table(
        "Trainingsverlauf je Woche",
        ["Woche ab", "Ausdauer-Einheiten", "Ausdauer (min)", "Kilometer", "Krafteinheiten", "Sätze"],
        weeks(data, from: start, to: end)
      ) { week in
        [
          week.monday.iso, String(week.endurance), String(week.minutes), num(week.kilometers), String(week.gym),
          String(week.sets),
        ]
      }
    }
    lines += CoachExport.sources(input.userSources)
    if categories.contains(.gym) || withImportFormat { lines += CoachExport.exerciseList(input) }
    return lines.joined(separator: "\n")
  }

  // MARK: - JSON

  public static func json(
    _ input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay, categories: Set<ExportCategory>
  ) -> String {
    let data = Slice(input, from: start, to: end)
    var root: [String: JSONValue] = [
      "export": .object([
        "app": .string("AIronLudi"), "von": .string(start.iso), "bis": .string(end.iso),
        "kategorien": .array(ExportCategory.allCases.filter(categories.contains).map { .string($0.rawValue) }),
        "hinweis": .string("null = nicht gemessen. Gewicht in kg, Zeiten in Minuten, Distanz in km."),
      ]),
      "profil": .object([
        "ziel": .string(input.profile.goal.label),
        "planart": .string(input.profile.mode == .season ? "saisonplan" : "eigener_wochenplan"),
        "sportarten": .array(input.profile.sports.map { .string($0.label) }),
      ]),
    ]
    if categories.contains(.recovery) {
      root["erholung"] = .array(
        data.metrics.map { day in
          .object([
            "datum": .string(day.day.iso), "ruhepuls": value(day.restingHeartRate),
            "hrv_ms": value(day.hrvLastNightAverage), "hrv_status": day.hrvStatus.map(JSONValue.string) ?? .null,
            "body_battery_max": value(day.bodyBatteryHigh), "readiness": value(day.trainingReadiness),
          ])
        })
    }
    if categories.contains(.sleep) {
      root["schlaf"] = .array(
        data.metrics.filter { $0.sleepSeconds != nil }.map { day in
          .object([
            "datum": .string(day.day.iso), "stunden": value(day.sleepHours), "score": value(day.sleepScore),
            "tief_min": value(day.deepSleepSeconds.map { $0 / 60 }),
            "rem_min": value(day.remSleepSeconds.map { $0 / 60 }),
            "wach_min": value(day.awakeSleepSeconds.map { $0 / 60 }),
          ])
        })
    }
    if categories.contains(.health) {
      root["gesundheit"] = .array(
        data.metrics.map { day in
          .object([
            "datum": .string(day.day.iso), "schritte": value(day.steps), "stress": value(day.stressAverage),
            "aktive_kcal": value(day.activeKilocalories), "vo2max": value(day.vo2Max), "spo2": value(day.spo2Average),
          ])
        })
    }
    if categories.contains(.endurance) {
      root["ausdauer"] = .array(
        data.endurance.map { activity in
          .object([
            "start": activity.startLocal.map(JSONValue.string) ?? .null,
            "sport": activity.typeKey.map(JSONValue.string) ?? .null,
            "name": activity.name.map(JSONValue.string) ?? .null,
            "dauer_min": value(activity.durationSeconds.map { $0 / 60 }),
            "distanz_km": value(activity.distanceMeters.map { $0 / 1000 }),
            "hf_schnitt": value(activity.averageHeartRate), "hf_max": value(activity.maxHeartRate),
            "belastung": value(activity.trainingLoad), "aerober_te": value(activity.aerobicTrainingEffect),
          ])
        })
    }
    if categories.contains(.gym) {
      root["gym"] = .array(
        data.gym.map { session in
          .object([
            "datum": .string(session.day.iso), "titel": .string(session.title),
            "dauer_min": value(session.end.map { $0.timeIntervalSince(session.start) / 60 }),
            "uebungen": .array(
              session.exercises.filter { !$0.loggedSets.isEmpty }.map { exercise in
                .object([
                  "id": .string(exercise.exerciseID), "name": .string(exercise.name),
                  "saetze": .array(
                    exercise.loggedSets.map { set in
                      .object([
                        "kg": .number(set.weightKg), "wdh": .number(Double(set.reps)),
                        "rir": set.rir.map { .number(Double($0)) } ?? .null, "art": .string(set.kind.rawValue),
                      ])
                    }),
                ])
              }),
          ])
        })
      root["trainingsplaene"] = .array(
        input.routines.map { routine in
          .object([
            "name": .string(routine.name),
            "uebungen": .array(
              routine.items.map { item in
                .object([
                  "id": .string(item.exerciseID), "name": .string(item.name), "saetze": .number(Double(item.sets)),
                  "wdh_min": .number(Double(item.lowerReps)), "wdh_max": .number(Double(item.upperReps)),
                  "kg": value(item.weightKg),
                ])
              }),
          ])
        })
    }
    if categories.contains(.nutrition) {
      root["ernaehrung"] = .array(
        Dictionary(grouping: data.meals, by: \.day).sorted { $0.key < $1.key }.map { day, meals in
          let totals = NutritionSummary.totals(meals.flatMap(\.items))
          return .object([
            "datum": .string(day.iso), "kcal": value(totals[.kcal]), "protein_g": value(totals[.protein]),
            "kohlenhydrate_g": value(totals[.carbs]), "fett_g": value(totals[.fat]),
            "ballaststoffe_g": value(totals[.fiber]),
            "mahlzeiten": .array(
              meals.map { meal in
                .object([
                  "kategorie": .string(meal.category), "titel": .string(meal.title),
                  "positionen": .array(
                    meal.items.map { .object(["name": .string($0.name), "g": .number($0.grams.rounded())]) }),
                ])
              }),
          ])
        })
    }
    if categories.contains(.weight) {
      root["gewicht"] = .array(
        WeightTrend.merged(data.weights).map { .object(["datum": .string($0.day.iso), "kg": .number($0.kilograms)]) })
    }
    if categories.contains(.history) {
      root["verlauf_wochen"] = .array(
        weeks(data, from: start, to: end).map { week in
          .object([
            "woche_ab": .string(week.monday.iso), "ausdauer_einheiten": .number(Double(week.endurance)),
            "ausdauer_min": .number(Double(week.minutes)), "kilometer": .number(week.kilometers),
            "krafteinheiten": .number(Double(week.gym)), "saetze": .number(Double(week.sets)),
          ])
        })
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(JSONValue.object(root))).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }

  // MARK: - CSV

  /// Eine Tabelle je Kategorie (Komma als Trenner, Punkt als Dezimalzeichen, leere Zelle = nicht gemessen).
  public static func csv(
    _ input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay, categories: Set<ExportCategory>
  ) -> [File] {
    let data = Slice(input, from: start, to: end)
    var files: [File] = []
    func add(_ category: ExportCategory, _ header: [String], _ rows: [[String]]) {
      guard categories.contains(category) else { return }
      let lines = [header] + rows
      files.append(
        File(
          name: "IronLudi-\(category.rawValue)-\(start.iso)-bis-\(end.iso).csv",
          content: lines.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\n") + "\n"))
    }
    add(
      .recovery, ["datum", "ruhepuls", "hrv_ms", "hrv_status", "body_battery_max", "readiness"],
      data.metrics.map {
        [
          $0.day.iso, raw($0.restingHeartRate), raw($0.hrvLastNightAverage), $0.hrvStatus ?? "",
          raw($0.bodyBatteryHigh),
          raw($0.trainingReadiness),
        ]
      })
    add(
      .sleep, ["datum", "stunden", "score", "tief_min", "rem_min", "wach_min"],
      data.metrics.filter { $0.sleepSeconds != nil }.map {
        [
          $0.day.iso, raw($0.sleepHours), raw($0.sleepScore), raw($0.deepSleepSeconds.map { $0 / 60 }),
          raw($0.remSleepSeconds.map { $0 / 60 }), raw($0.awakeSleepSeconds.map { $0 / 60 }),
        ]
      })
    add(
      .health, ["datum", "schritte", "stress", "aktive_kcal", "vo2max", "spo2"],
      data.metrics.map {
        [
          $0.day.iso, raw($0.steps), raw($0.stressAverage), raw($0.activeKilocalories), raw($0.vo2Max),
          raw($0.spo2Average),
        ]
      })
    add(
      .endurance,
      ["start", "sport", "name", "dauer_min", "distanz_km", "hf_schnitt", "hf_max", "belastung", "aerober_te"],
      data.endurance.map {
        [
          $0.startLocal ?? "", $0.typeKey ?? "", $0.name ?? "", raw($0.durationSeconds.map { $0 / 60 }),
          raw($0.distanceMeters.map { $0 / 1000 }), raw($0.averageHeartRate), raw($0.maxHeartRate),
          raw($0.trainingLoad),
          raw($0.aerobicTrainingEffect),
        ]
      })
    add(
      .gym, ["datum", "einheit", "uebung_id", "uebung", "satz", "kg", "wdh", "rir", "art"],
      data.gym.flatMap { session in
        session.exercises.flatMap { exercise in
          exercise.loggedSets.enumerated().map { index, set in
            [
              session.day.iso, session.title, exercise.exerciseID, exercise.name, String(index + 1), raw(set.weightKg),
              String(set.reps), set.rir.map(String.init) ?? "", set.kind.rawValue,
            ]
          }
        }
      })
    add(
      .nutrition,
      ["datum", "kategorie", "mahlzeit", "position", "g", "kcal", "protein_g", "kohlenhydrate_g", "fett_g"],
      data.meals.sorted { $0.day < $1.day }.flatMap { meal in
        meal.items.map { item in
          [
            meal.day.iso, meal.category, meal.title, item.name, raw(item.grams.rounded()), raw(item.amounts[.kcal]),
            raw(item.amounts[.protein]), raw(item.amounts[.carbs]), raw(item.amounts[.fat]),
          ]
        }
      })
    add(.weight, ["datum", "kg"], WeightTrend.merged(data.weights).map { [$0.day.iso, raw($0.kilograms)] })
    add(
      .history, ["woche_ab", "ausdauer_einheiten", "ausdauer_min", "kilometer", "krafteinheiten", "saetze"],
      weeks(data, from: start, to: end).map {
        [$0.monday.iso, String($0.endurance), String($0.minutes), raw($0.kilometers), String($0.gym), String($0.sets)]
      })
    return files
  }

  /// Wie viele Einträge je Kategorie im Zeitraum vorhanden sind (für die Auswahl in der App).
  public static func counts(_ input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay)
    -> [ExportCategory: Int]
  {
    let data = Slice(input, from: start, to: end)
    return [
      .gym: data.gym.count, .endurance: data.endurance.count,
      .health: data.metrics.filter { $0.steps != nil || $0.stressAverage != nil }.count,
      .sleep: data.metrics.filter { $0.sleepSeconds != nil }.count,
      .nutrition: Set(data.meals.map(\.day)).count, .weight: WeightTrend.merged(data.weights).count,
      .recovery: data.metrics.filter { $0.restingHeartRate != nil || $0.hrvLastNightAverage != nil }.count,
      .history: data.gym.count + data.endurance.count,
    ]
  }

  // MARK: - Bausteine

  struct Slice {
    var metrics: [DailyMetrics]
    var endurance: [GarminActivity]
    var gym: [GymSession]
    var meals: [CoachExport.Meal]
    var weights: [WeightEntry]

    init(_ input: CoachExport.Input, from start: CalendarDay, to end: CalendarDay) {
      let inRange = { (day: CalendarDay?) -> Bool in day.map { start <= $0 && $0 <= end } ?? false }
      metrics = input.metrics.filter { inRange($0.day) }.sorted { $0.day < $1.day }
      // Krafttraining der Uhr steht schon unter Gym (mit Sätzen); doppelte Uploads fallen weg.
      let redundant = StrengthDuplicates.redundant(input.activities)
      endurance = input.activities.filter {
        inRange($0.day) && $0.typeKey != "strength_training" && !redundant.contains($0.id)
      }
      .sorted { ($0.startLocal ?? "") < ($1.startLocal ?? "") }
      gym = input.gym.filter { inRange($0.day) }.sorted { $0.start < $1.start }
      meals = input.meals.filter { inRange($0.day) }
      weights = input.weights.filter { inRange($0.day) }.sorted { $0.day < $1.day }
    }
  }

  struct Week {
    var monday: CalendarDay
    var endurance = 0
    var minutes = 0
    var kilometers = 0.0
    var gym = 0
    var sets = 0
  }

  static func weeks(_ data: Slice, from start: CalendarDay, to end: CalendarDay) -> [Week] {
    var weeks: [CalendarDay: Week] = [:]
    var monday = PlanAdjustments.monday(of: start)
    while monday <= end {
      weeks[monday] = Week(monday: monday)
      monday = monday.adding(days: 7)
    }
    for activity in data.endurance {
      guard let day = activity.day else { continue }
      let key = PlanAdjustments.monday(of: day)
      weeks[key, default: Week(monday: key)].endurance += 1
      weeks[key, default: Week(monday: key)].minutes += Int(((activity.durationSeconds ?? 0) / 60).rounded())
      weeks[key, default: Week(monday: key)].kilometers += ((activity.distanceMeters ?? 0) / 100).rounded() / 10
    }
    for session in data.gym {
      let key = PlanAdjustments.monday(of: session.day)
      weeks[key, default: Week(monday: key)].gym += 1
      weeks[key, default: Week(monday: key)].sets += session.exercises.reduce(0) { $0 + $1.doneSets.count }
    }
    return weeks.values.sorted { $0.monday < $1.monday }
  }

  static func table<Row>(_ title: String, _ header: [String], _ rows: [Row], cells: (Row) -> [String]) -> [String] {
    guard !rows.isEmpty else { return [] }
    var lines = ["## \(title)", "", "| " + header.joined(separator: " | ") + " |"]
    lines.append("|" + String(repeating: "---|", count: header.count))
    lines += rows.map { row in
      "| " + cells(row).map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: " | ") + " |"
    }
    lines.append("")
    return lines
  }

  static func num(_ value: Double?) -> String { value.map(CoachExport.number) ?? "–" }

  static func hours(_ seconds: Double?) -> String { num(seconds.map { ($0 / 360).rounded() / 10 }) }

  static func raw(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "" }
    let rounded = (value * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
  }

  static func value(_ number: Double?) -> JSONValue {
    guard let number, number.isFinite else { return .null }
    return .number((number * 100).rounded() / 100)
  }

  static func csvCell(_ text: String) -> String {
    guard text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}
