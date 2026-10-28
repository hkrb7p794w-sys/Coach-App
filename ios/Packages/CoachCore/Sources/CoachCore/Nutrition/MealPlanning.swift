import Foundation

/// „Was esse ich jetzt?“ – drei Vorschläge passend zu dem, was heute noch übrig ist. Die KI schlägt Gerichte vor,
/// die App prüft Ernährungsweise und Allergene und skaliert die Mengen auf das Ziel dieser Mahlzeit.
public enum MealNow {
  /// Größte sinnvolle Mahlzeit; mehr Rest wird auf weitere Mahlzeiten verteilt.
  public static let maximumKilocalories = 900.0
  public static let minimumKilocalories = 150.0
  static let scaleRange = 0.5...1.6

  /// Energieziel dieser Mahlzeit; `nil`, wenn heute kaum noch etwas übrig ist.
  public static func targetKilocalories(remaining: Double) -> Double? {
    guard remaining >= minimumKilocalories else { return nil }
    return min(remaining, maximumKilocalories)
  }

  public static func input(
    remaining: NutrientValues, category: MealCategory, diet: Diet, preferences: RecipePreferences, pantry: [String],
    favorites: [String]
  ) -> [String: JSONValue] {
    let kcal = targetKilocalories(remaining: remaining[.kcal] ?? 0) ?? minimumKilocalories
    let share = kcal / max(remaining[.kcal] ?? kcal, kcal)
    func grams(_ nutrient: Nutrient) -> JSONValue {
      .number(max(0, ((remaining[nutrient] ?? 0) * share).rounded()))
    }
    return [
      "mahlzeit": .string(category.rawValue),
      "kcal": .number(kcal.rounded()),
      "protein_g": grams(.protein),
      "carbs_g": grams(.carbs),
      "fat_g": grams(.fat),
      "diet": .string(diet.rawValue),
      "allergens": .array(preferences.allergens.sorted { $0.rawValue < $1.rawValue }.map { .string($0.label) }),
      "dislikes": .string(String(preferences.dislikes.prefix(200))),
      "maxMinutes": .number(Double(preferences.maxMinutes)),
      "pantry": .array(pantry.prefix(30).map { .string($0) }),
      "favorites": .array(favorites.prefix(15).map { .string($0) }),
    ]
  }

  /// Antwort `{"gerichte": [...]}` prüfen und auf das Ziel skalieren (auf 5 g gerundet).
  public static func suggestions(
    output: JSONValue, targetKilocalories: Double, diet: Diet, allergens: Set<Allergen>
  ) -> (recipes: [Recipe], notes: [String]) {
    var notes: [String] = []
    let recipes = (output["gerichte"]?.arrayValue ?? []).compactMap(RecipePlanner.recipe).compactMap {
      recipe -> Recipe? in
      let problems = RecipePlanner.violations(recipe, diet: diet, allergens: allergens)
      if !problems.isEmpty {
        notes.append("„\(recipe.title)“ verworfen: enthält \(problems.joined(separator: ", ")).")
        return nil
      }
      if let item = recipe.ingredients.first(where: RecipePlanner.implausible) {
        notes.append("„\(recipe.title)“ verworfen: unstimmige Nährwerte bei „\(item.name)“.")
        return nil
      }
      return scaled(recipe, to: targetKilocalories)
    }
    return (Array(recipes.prefix(3)), notes)
  }

  static func scaled(_ recipe: Recipe, to kcal: Double) -> Recipe {
    let total = recipe.totals[.kcal] ?? 0
    guard total > 0, kcal > 0 else { return recipe }
    let factor = min(max(kcal / total, scaleRange.lowerBound), scaleRange.upperBound)
    var copy = recipe
    copy.ingredients = recipe.ingredients.map { item in
      var item = item
      item.grams = max(5, (item.grams * factor / 5).rounded() * 5)
      return item
    }
    return copy
  }
}

/// Eigenes Rezept für Meal-Prep: Zutaten für den ganzen Topf, gekochtes Gewicht und Portionen. Eingetragen wird eine
/// Portion oder eine Menge in Gramm vom Topf; der Zähler zeigt, wie viele Portionen noch da sind.
public struct OwnRecipe: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  public var ingredients: [MealItem]
  /// Gewicht des fertigen Gerichts (gekocht); `nil` = Summe der Zutaten.
  public var cookedGrams: Double?
  public var portions: Int
  /// Noch übrige Portionen vom letzten Kochen; `nil` = kein Vorrat.
  public var remainingPortions: Double?

  public init(
    id: UUID = UUID(), name: String, ingredients: [MealItem], cookedGrams: Double? = nil, portions: Int = 1,
    remainingPortions: Double? = nil
  ) {
    self.id = id
    self.name = name
    self.ingredients = ingredients
    self.cookedGrams = cookedGrams
    self.portions = max(portions, 1)
    self.remainingPortions = remainingPortions
  }

  public var totalGrams: Double {
    cookedGrams.flatMap { $0 > 0 ? $0 : nil } ?? ingredients.reduce(0) { $0 + $1.grams }
  }

  public var totals: NutrientValues { NutritionSummary.totals(ingredients) }

  /// Nährwerte je 100 g des fertigen Gerichts.
  public var per100g: NutrientValues {
    guard totalGrams > 0 else { return NutrientValues() }
    return totals.scaled(toGrams: 100 * 100 / totalGrams)
  }

  /// Eine Position „Chili“ mit `grams` vom Topf (Standard: eine Portion).
  public func item(grams: Double? = nil) -> MealItem {
    let portionGrams = totalGrams / Double(portions)
    var item = MealItem(name: name, grams: grams ?? portionGrams, source: .manual, per100g: per100g)
    item.portion = Portion(name: "Portion", grams: (portionGrams * 10).rounded() / 10)
    return item
  }

  /// Rezept aus einer gespeicherten Mahlzeit (eine Portion).
  public static func from(meal title: String, items: [MealItem]) -> OwnRecipe {
    OwnRecipe(name: title, ingredients: items, portions: 1)
  }

  /// Nach dem Eintragen: Vorrat um die gegessene Menge verringern.
  public mutating func consume(grams: Double) {
    guard let remaining = remainingPortions, totalGrams > 0 else { return }
    let eaten = grams / (totalGrams / Double(portions))
    remainingPortions = max(0, ((remaining - eaten) * 10).rounded() / 10)
  }
}

/// Woche auf einen Blick: Energie je Tag gegen das Ziel, Protein im Schnitt, Trainingstage.
public enum NutritionWeek {
  public struct Day: Equatable, Sendable, Identifiable {
    public var day: CalendarDay
    public var kilocalories: Double
    public var protein: Double
    public var targetKilocalories: Double?
    public var targetProtein: Double?
    public var trained: Bool
    public var logged: Bool
    public var id: CalendarDay { day }
  }

  public struct Summary: Equatable, Sendable {
    public var days: [Day]
    /// Nur Tage mit Einträgen.
    public var averageKilocalories: Double?
    public var averageTargetKilocalories: Double?
    public var averageProtein: Double?
  }

  public static func summary(
    entries: [MealEntry], monday: CalendarDay, targets: [CalendarDay: NutrientValues], trainedDays: Set<CalendarDay>,
    today: CalendarDay
  ) -> Summary {
    let days = (0..<7).map { monday.adding(days: $0) }.filter { $0 <= today }.map { day -> Day in
      let items = entries.filter { $0.day == day }.flatMap(\.items)
      let totals = NutritionSummary.totals(items)
      return Day(
        day: day, kilocalories: totals[.kcal] ?? 0, protein: totals[.protein] ?? 0,
        targetKilocalories: targets[day]?[.kcal], targetProtein: targets[day]?[.protein],
        trained: trainedDays.contains(day), logged: !items.isEmpty)
    }
    let logged = days.filter(\.logged)
    func average(_ values: [Double]) -> Double? {
      values.isEmpty ? nil : (values.reduce(0, +) / Double(values.count)).rounded()
    }
    return Summary(
      days: days, averageKilocalories: average(logged.map(\.kilocalories)),
      averageTargetKilocalories: average(logged.compactMap(\.targetKilocalories)),
      averageProtein: average(logged.map(\.protein)))
  }
}

/// Einkaufsliste nach Supermarkt-Abteilung (aus der Lebensmittelgruppe der KI bzw. dem Namen).
public enum ShoppingAisle: String, CaseIterable, Sendable, Identifiable {
  case produce, cooled, meatFish, bakery, dry, spices, frozen, drinks, other

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .produce: "Obst und Gemüse"
    case .cooled: "Kühlregal"
    case .meatFish: "Fleisch und Fisch"
    case .bakery: "Brot und Backwaren"
    case .dry: "Nudeln, Reis, Hülsenfrüchte, Nüsse"
    case .spices: "Öl, Gewürze, Saucen"
    case .frozen: "Tiefkühl"
    case .drinks: "Getränke"
    case .other: "Sonstiges"
    }
  }

  public static func of(name: String, group: String?) -> ShoppingAisle {
    switch group {
    case "gemuese", "obst": return .produce
    case "milch", "ei": return .cooled
    case "fleisch", "fisch", "fisch_fett": return .meatFish
    case "vollkorn", "getreide", "kartoffel", "huelsenfruechte", "nuesse": return byName(name) ?? .dry
    case "fett": return .spices
    case "getraenk", "alkohol": return .drinks
    default: return byName(name) ?? .other
    }
  }

  static func byName(_ name: String) -> ShoppingAisle? {
    let lower = FoodSearch.normalized(name)
    if ["brot", "broetchen", "toast", "wrap", "tortilla"].contains(where: { lower.contains($0) }) { return .bakery }
    if ["tiefkuehl", "tk-", "gefroren"].contains(where: { lower.contains($0) }) { return .frozen }
    let spices = ["oel", "salz", "pfeffer", "gewuerz", "sauce", "sosse", "essig", "bruehe", "senf", "honig"]
    if spices.contains(where: { lower.contains($0) }) { return .spices }
    return nil
  }
}

extension ReminderPlanner {
  public static let nutritionReviewHour = 20

  /// Abends kurz Ernährung und Training auswerten (freiwillig, Standard aus).
  public static func nutritionReview(
    today: CalendarDay, minutesNow: Int, hour: Int = nutritionReviewHour, days: Int = 7
  ) -> [ScheduledNote] {
    (0..<max(days, 1)).compactMap { offset in
      if offset == 0, minutesNow >= hour * 60 { return nil }
      return ScheduledNote(
        kind: .nutritionReview, day: today.adding(days: offset), hour: hour, minute: 0, title: "Tag auswerten",
        body: "Kurz schauen: Hat das Essen heute zum Training gepasst? Fehlt noch Protein?")
    }
  }
}
