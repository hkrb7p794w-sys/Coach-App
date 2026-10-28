import Foundation

/// Eine gespeicherte Mahlzeit, unabhängig von SwiftData (für Vorschläge, Suche und Wochenansicht).
public struct MealEntry: Equatable, Sendable {
  public var day: CalendarDay
  public var date: Date
  public var category: MealCategory
  public var title: String
  public var items: [MealItem]

  public init(day: CalendarDay, date: Date, category: MealCategory, title: String, items: [MealItem]) {
    self.day = day
    self.date = date
    self.category = category
    self.title = title
    self.items = items
  }
}

/// Schnell eintragen: Was isst die Person um diese Zeit meistens, was gab es gestern?
/// Wiederkehrendes Essen soll ein Tipp sein statt Suchen, Menge prüfen, Speichern.
public enum MealSuggestions {
  public struct Suggestion: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var category: MealCategory
    public var items: [MealItem]
    public var count: Int
    public var lastDate: Date

    public var kilocalories: Double { NutritionSummary.totals(items)[.kcal] ?? 0 }
  }

  /// Gleiche Mahlzeit = gleiche Lebensmittel mit etwa gleicher Menge (auf 10 g gerundet).
  public static func signature(_ items: [MealItem]) -> String {
    items.map { "\(FoodSearch.normalized($0.name))@\(Int(($0.grams / 10).rounded()))" }.sorted()
      .joined(separator: "|")
  }

  /// Häufigste Mahlzeiten dieser Kategorie aus den letzten `lookbackDays` Tagen; was heute schon in derselben
  /// Kategorie eingetragen ist, wird nicht noch einmal vorgeschlagen.
  public static func frequent(
    _ entries: [MealEntry], category: MealCategory, today: CalendarDay, lookbackDays: Int = 60, limit: Int = 5
  ) -> [Suggestion] {
    let start = today.adding(days: -lookbackDays)
    let loggedToday = Set(
      entries.filter { $0.day == today && $0.category == category }.map { signature($0.items) })
    var groups: [String: Suggestion] = [:]
    for entry in entries where entry.category == category && start <= entry.day && entry.day < today {
      guard !entry.items.isEmpty else { continue }
      let key = signature(entry.items)
      guard !loggedToday.contains(key) else { continue }
      if var existing = groups[key] {
        existing.count += 1
        if entry.date > existing.lastDate {
          existing.lastDate = entry.date
          existing.title = entry.title
          existing.items = entry.items
        }
        groups[key] = existing
      } else {
        groups[key] = Suggestion(
          id: key, title: entry.title, category: category, items: entry.items, count: 1, lastDate: entry.date)
      }
    }
    return groups.values.sorted { ($0.count, $0.lastDate) > ($1.count, $1.lastDate) }.prefix(limit).map { $0 }
  }

  /// Mahlzeiten von gestern in dieser Kategorie („wie gestern“).
  public static func yesterday(_ entries: [MealEntry], category: MealCategory, today: CalendarDay) -> [MealEntry] {
    let day = today.adding(days: -1)
    return entries.filter { $0.day == day && $0.category == category }.sorted { $0.date < $1.date }
  }
}

/// Suche über eigene Lebensmittel und frühere Mahlzeiten: alle Wörter müssen vorkommen, Treffer am Wortanfang und
/// häufig Genutztes zuerst. Groß-/Kleinschreibung und Umlaute spielen keine Rolle („muesli“ findet „Müsli“).
public enum FoodSearch {
  public struct Candidate: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var useCount: Int
    public var lastUsed: Date

    public init(id: String, title: String, useCount: Int, lastUsed: Date) {
      self.id = id
      self.title = title
      self.useCount = useCount
      self.lastUsed = lastUsed
    }
  }

  public static func normalized(_ text: String) -> String {
    text.lowercased()
      .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
      .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func rank(_ candidates: [Candidate], query: String, limit: Int = 12) -> [Candidate] {
    let words = normalized(query).split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    let scored = candidates.compactMap { candidate -> (Candidate, Int)? in
      let title = normalized(candidate.title)
      guard words.allSatisfy({ title.contains($0) }) else { return nil }
      let titleWords = title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      let prefixHits = words.filter { word in titleWords.contains { $0.hasPrefix(word) } }.count
      let starts = title.hasPrefix(words[0]) ? 2 : 0
      return (candidate, starts + prefixHits)
    }
    return scored.sorted {
      ($0.1, $0.0.useCount, $0.0.lastUsed) > ($1.1, $1.0.useCount, $1.0.lastUsed)
    }
    .prefix(limit).map(\.0)
  }
}

/// Was heute noch übrig ist – die Frage beim Essen ist „wie viel Protein fehlt noch?“, nicht „wie viel Prozent“.
public enum NutritionBudget {
  public struct Line: Equatable, Sendable, Identifiable {
    public var nutrient: Nutrient
    public var actual: Double
    public var target: Double
    public var id: Nutrient { nutrient }

    /// Positiv = noch übrig, negativ = darüber.
    public var remaining: Double { target - actual }
    public var progress: Double { target > 0 ? min(actual / target, 1) : 0 }
    /// Bei Obergrenzen (Zucker, gesättigte Fette) ist „darüber“ ein Warnsignal, bei Energie ab 10 %.
    public var isOver: Bool {
      nutrient.isUpperLimit ? actual > target : actual > target * (nutrient == .kcal ? 1.1 : 1.25)
    }
  }

  public static let main: [Nutrient] = [.protein, .carbs, .fat]

  public static func line(_ nutrient: Nutrient, targets: NutrientValues, totals: NutrientValues) -> Line? {
    guard let target = targets[nutrient], target > 0 else { return nil }
    return Line(nutrient: nutrient, actual: totals[nutrient] ?? 0, target: target)
  }

  /// „noch 62 g“ bzw. „18 g drüber“.
  public static func remainingText(_ line: Line) -> String {
    let amount = Int(abs(line.remaining).rounded())
    return line.remaining >= 0 ? "noch \(amount) \(line.nutrient.unit)" : "\(amount) \(line.nutrient.unit) drüber"
  }
}

extension MealItem {
  /// Schnell-Eintrag ohne Lebensmittel (z. B. Restaurant): die Werte gelten für die ganze Portion.
  public static func quick(
    name: String = "Schnell-Eintrag", kilocalories: Double, protein: Double? = nil, carbs: Double? = nil,
    fat: Double? = nil
  ) -> MealItem {
    var values = NutrientValues([.kcal: max(kilocalories, 0)])
    values[.protein] = protein.map { max($0, 0) }
    values[.carbs] = carbs.map { max($0, 0) }
    values[.fat] = fat.map { max($0, 0) }
    // 100 g „Portion“: Nährwerte je 100 g = Werte der Portion.
    var item = MealItem(name: name, grams: 100, source: .manual, per100g: values)
    item.amountText = "Schätzung"
    item.confidence = "niedrig"
    return item
  }

  /// Wasser in ml (1 ml ≈ 1 g).
  public static func water(milliliters: Double) -> MealItem {
    var item = MealItem(name: "Wasser", grams: milliliters, source: .manual, per100g: NutrientValues([.water: 100]))
    item.isDrink = true
    return item
  }

  public var isQuickEstimate: Bool { source == .manual && amountText == "Schätzung" }
}
