import Foundation

/// Allergene und Unverträglichkeiten (Auswahl der 14 kennzeichnungspflichtigen Allergene der EU-LMIV).
public enum Allergen: String, Codable, CaseIterable, Sendable, Identifiable {
  case gluten, lactose, nuts, peanuts, egg, soy, fish, shellfish, sesame

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .gluten: "Gluten"
    case .lactose: "Laktose / Milch"
    case .nuts: "Schalenfrüchte (Nüsse)"
    case .peanuts: "Erdnüsse"
    case .egg: "Ei"
    case .soy: "Soja"
    case .fish: "Fisch"
    case .shellfish: "Krebstiere und Weichtiere"
    case .sesame: "Sesam"
    }
  }
}

/// Wünsche für die Rezeptideen.
public struct RecipePreferences: Codable, Equatable, Hashable, Sendable {
  public var allergens: Set<Allergen>
  /// Freitext, z. B. „keine Pilze, wenig Koriander“.
  public var dislikes: String
  /// Höchstens so viele Minuten Zubereitung pro Gericht.
  public var maxMinutes: Int
  /// Zusätzlich ein Snack pro Tag.
  public var snacks: Bool
  /// Für wie viele Personen eingekauft wird.
  public var servings: Int
  /// Abends für den nächsten Mittag mitkochen.
  public var mealPrep: Bool

  public init(
    allergens: Set<Allergen> = [], dislikes: String = "", maxMinutes: Int = 30, snacks: Bool = true,
    servings: Int = 1, mealPrep: Bool = false
  ) {
    self.allergens = allergens
    self.dislikes = dislikes
    self.maxMinutes = maxMinutes
    self.snacks = snacks
    self.servings = servings
    self.mealPrep = mealPrep
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    allergens = (try? container.decodeIfPresent(Set<Allergen>.self, forKey: .allergens)) ?? []
    dislikes = (try? container.decodeIfPresent(String.self, forKey: .dislikes)) ?? ""
    maxMinutes = (try? container.decodeIfPresent(Int.self, forKey: .maxMinutes)) ?? 30
    snacks = (try? container.decodeIfPresent(Bool.self, forKey: .snacks)) ?? true
    servings = max((try? container.decodeIfPresent(Int.self, forKey: .servings)) ?? 1, 1)
    mealPrep = (try? container.decodeIfPresent(Bool.self, forKey: .mealPrep)) ?? false
  }
}

/// Ziele eines Tages der kommenden Woche, aus Wochenplan und Ernährungszielen (regelbasiert).
public struct RecipeDayTarget: Equatable, Sendable, Identifiable {
  public var day: CalendarDay
  public var sessions: [String]
  public var dayType: DayType
  public var kcal: Double
  public var protein: Double
  public var carbs: Double
  public var fat: Double
  public var id: CalendarDay { day }

  public init(
    day: CalendarDay, sessions: [String], dayType: DayType, kcal: Double, protein: Double, carbs: Double, fat: Double
  ) {
    self.day = day
    self.sessions = sessions
    self.dayType = dayType
    self.kcal = kcal
    self.protein = protein
    self.carbs = carbs
    self.fat = fat
  }

  public init(day: CalendarDay, sessions: [String], targets: NutritionTargets) {
    self.init(
      day: day, sessions: sessions, dayType: targets.dayType, kcal: targets.values[.kcal] ?? 0,
      protein: targets.values[.protein] ?? 0, carbs: targets.values[.carbs] ?? 0, fat: targets.values[.fat] ?? 0)
  }
}

/// Ein Rezept: Zutaten mit Menge und Nährwerten je 100 g (KI-Schätzung wie bei der Mahlzeiten-Analyse).
public struct Recipe: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var meal: MealCategory
  public var title: String
  public var minutes: Int
  public var ingredients: [MealItem]
  public var steps: [String]

  public init(
    id: UUID = UUID(), meal: MealCategory, title: String, minutes: Int, ingredients: [MealItem], steps: [String]
  ) {
    self.id = id
    self.meal = meal
    self.title = title
    self.minutes = minutes
    self.ingredients = ingredients
    self.steps = steps
  }

  /// Nährwerte aus den Zutaten berechnet.
  public var totals: NutrientValues { NutritionSummary.totals(ingredients) }
}

public struct RecipeDay: Codable, Equatable, Sendable, Identifiable {
  public var day: CalendarDay
  public var recipes: [Recipe]
  /// Faktor, mit dem die Mengen ans Tagesziel angepasst wurden.
  public var scale: Double
  public var id: CalendarDay { day }

  public var totals: NutrientValues {
    recipes.reduce(NutrientValues()) { $0 + $1.totals }
  }
}

public struct WeeklyRecipePlan: Codable, Equatable, Sendable {
  public var created: Date
  public var days: [RecipeDay]
  public var source: String
  /// Hinweise der Prüfung (verworfene Rezepte, Abweichungen vom Tagesziel).
  public var notes: [String]

  public init(created: Date, days: [RecipeDay], source: String, notes: [String]) {
    self.created = created
    self.days = days
    self.source = source
    self.notes = notes
  }

  public func day(_ day: CalendarDay) -> RecipeDay? {
    days.first { $0.day == day }
  }
}

/// Rezeptideen für die kommende Woche. Die Regeln legen die Tagesziele fest (Energie, Protein, Kohlenhydrate nach
/// Trainingstag) und prüfen jede Antwort der KI: Ernährungsweise und Allergene, Mengen passend zum Tagesziel.
public enum RecipePlanner {
  public static let evidence = ["nutrition.energy", "nutrition.carbs", "nutrition.protein", "nutrition.reds"]
  /// Mengen werden höchstens um diesen Faktor angepasst; darüber passt das Rezept nicht zum Tag.
  static let scaleRange = 0.75...1.33
  static let tolerance = 0.15

  // MARK: Eingabe für die KI

  public static func input(
    days: [RecipeDayTarget], preferences: RecipePreferences, diet: Diet, goal: String, gaps: [String],
    favorites: [String]
  ) -> [String: JSONValue] {
    let dayLines = days.map { target -> JSONValue in
      let sessions = target.sessions.isEmpty ? "frei" : target.sessions.joined(separator: " + ")
      return .object([
        "datum": .string(target.day.iso),
        "wochentag": .string(Weekday(day: target.day).long),
        "training": .string(sessions),
        "tagestyp": .string(target.dayType.label),
        "kcal": .number(target.kcal.rounded()),
        "protein_g": .number(target.protein.rounded()),
        "kohlenhydrate_g": .number(target.carbs.rounded()),
        "fett_g": .number(target.fat.rounded()),
      ])
    }
    return [
      "days": .array(dayLines),
      "diet": .string(diet.rawValue),
      "dietLabel": .string(diet.label),
      "goal": .string(goal),
      "allergens": .array(preferences.allergens.sorted { $0.rawValue < $1.rawValue }.map { .string($0.label) }),
      "dislikes": .string(String(preferences.dislikes.prefix(200))),
      "maxMinutes": .number(Double(preferences.maxMinutes)),
      "snacks": .bool(preferences.snacks),
      "mealPrep": .bool(preferences.mealPrep),
      "gaps": .array(gaps.map { .string($0) }),
      "favorites": .array(favorites.prefix(15).map { .string($0) }),
      "evidence": CoachingNote.evidenceInput(evidence),
    ]
  }

  // MARK: Antwort prüfen

  /// Liest die Antwort der Worker-Aufgabe `weekly_recipes`, verwirft unpassende Rezepte und passt die Mengen an
  /// das Tagesziel an.
  public static func plan(
    output: JSONValue, targets: [RecipeDayTarget], diet: Diet, allergens: Set<Allergen>, source: String,
    created: Date
  ) -> WeeklyRecipePlan? {
    guard let rawDays = output["tage"]?.arrayValue else { return nil }
    var notes: [String] = []
    var days: [RecipeDay] = []
    for target in targets {
      let raw = rawDays.first { $0["datum"]?.stringValue == target.day.iso }
      var recipes = (raw?["gerichte"]?.arrayValue ?? []).compactMap(recipe)
      let before = recipes.count
      recipes = recipes.filter { recipe in
        let problems = violations(recipe, diet: diet, allergens: allergens)
        if !problems.isEmpty {
          notes.append("„\(recipe.title)“ verworfen: enthält \(problems.joined(separator: ", ")).")
        }
        return problems.isEmpty
      }
      guard !recipes.isEmpty else {
        if before == 0 { notes.append("\(Weekday(day: target.day).long): keine Rezepte erhalten.") }
        continue
      }
      days.append(fit(day: target, recipes: recipes, notes: &notes))
    }
    guard !days.isEmpty else { return nil }
    return WeeklyRecipePlan(created: created, days: days, source: source, notes: notes)
  }

  static func recipe(_ value: JSONValue) -> Recipe? {
    guard let title = value["titel"]?.stringValue, !title.isEmpty,
      let rawItems = value["zutaten"]?.arrayValue
    else { return nil }
    let items = rawItems.compactMap(MealAnalysis.item)
    guard !items.isEmpty, items.contains(where: { ($0.per100g[.kcal] ?? 0) > 0 }) else { return nil }
    let meal = value["mahlzeit"]?.stringValue.flatMap(MealCategory.init(rawValue:)) ?? .other
    let minutes = Int(value["minuten"]?.doubleValue ?? 0)
    let steps = (value["zubereitung"]?.arrayValue ?? []).compactMap(\.stringValue).prefix(8)
    return Recipe(
      meal: meal, title: String(title.prefix(60)), minutes: max(minutes, 0), ingredients: items, steps: Array(steps))
  }

  /// Mengen so skalieren, dass die Tagesenergie zum Ziel passt (in Grenzen), auf 5 g gerundet.
  static func fit(day target: RecipeDayTarget, recipes: [Recipe], notes: inout [String]) -> RecipeDay {
    let total = recipes.reduce(0) { $0 + ($1.totals[.kcal] ?? 0) }
    guard total > 0, target.kcal > 0 else { return RecipeDay(day: target.day, recipes: recipes, scale: 1) }
    let wanted = target.kcal / total
    let scale = min(max(wanted, scaleRange.lowerBound), scaleRange.upperBound)
    let scaled = recipes.map { recipe -> Recipe in
      var recipe = recipe
      recipe.ingredients = recipe.ingredients.map { item in
        var item = item
        item.grams = max(5, (item.grams * scale / 5).rounded() * 5)
        return item
      }
      return recipe
    }
    let result = RecipeDay(day: target.day, recipes: scaled, scale: (scale * 100).rounded() / 100)
    let kcal = result.totals[.kcal] ?? 0
    if abs(kcal - target.kcal) / target.kcal > tolerance {
      notes.append(
        "\(Weekday(day: target.day).long): Rezepte ergeben ca. \(Int(kcal.rounded())) statt "
          + "\(Int(target.kcal.rounded())) kcal – Portionen anpassen.")
    }
    return result
  }

  // MARK: Ernährungsweise und Allergene

  static let meat = [
    "fleisch", "hähnchen", "hühnchen", "huhn", "pute", "truthahn", "rind", "schwein", "speck", "schinken", "salami",
    "wurst", "würstchen", "hack", "lamm", "kalb", "ente", "chorizo", "bacon", "gyros", "leber",
  ]
  static let fish = [
    "fisch", "lachs", "thunfisch", "forelle", "kabeljau", "seelachs", "hering", "makrele", "sardine", "sardelle",
    "dorsch", "zander", "pangasius", "scholle", "rotbarsch",
  ]
  static let shellfish = [
    "garnele", "shrimp", "krabbe", "muschel", "hummer", "scampi", "languste", "krebs", "tintenfisch", "calamari",
  ]
  static let dairy = [
    "milch", "joghurt", "quark", "käse", "sahne", "butter", "skyr", "mozzarella", "parmesan", "feta", "schmand",
    "ricotta", "molke", "kefir", "ghee", "mascarpone", "halloumi", "whey",
  ]
  static let plantPrefixes = [
    "hafer", "soja", "mandel", "kokos", "reis", "erbsen", "cashew", "erdnuss", "nuss", "dinkel", "pflanz", "vegan",
  ]
  static let gluten = [
    "weizen", "dinkel", "roggen", "gerste", "hafer", "nudel", "pasta", "spaghetti", "penne", "brot", "brötchen",
    "couscous", "bulgur", "seitan", "mehl", "grieß", "toast", "tortilla", "wrap", "semmel", "lasagne", "gnocchi",
  ]
  static let glutenFree = [
    "glutenfrei", "buchweizen", "reismehl", "maismehl", "reisnudel", "glasnudel", "polenta", "kichererbsenmehl",
    "mandelmehl", "kokosmehl",
  ]
  static let nuts = [
    "mandel", "walnuss", "haselnuss", "cashew", "pistazie", "pekannuss", "macadamia", "paranuss", "nüsse", "nuss",
  ]
  static let soy = ["soja", "tofu", "edamame", "tempeh", "miso"]
  static let sesame = ["sesam", "tahin"]

  static func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter }.map(String.init)
  }

  static func contains(_ name: String, _ keywords: [String], except: [String] = []) -> Bool {
    words(name).contains { word in
      keywords.contains { word.contains($0) } && !except.contains { word.contains($0) }
    }
  }

  static func isEgg(_ name: String) -> Bool {
    words(name).contains { word in
      word == "ei" || word.hasPrefix("eier") || word.hasPrefix("eigelb") || word.hasPrefix("eiklar")
        || (word.hasSuffix("ei") && word.count > 3 && !word.hasSuffix("brei"))
    }
  }

  static func isDairy(_ name: String) -> Bool {
    words(name).contains { word in
      dairy.contains { word.contains($0) } && !plantPrefixes.contains { word.hasPrefix($0) }
    }
  }

  /// Was an einer Zutat nicht zu Ernährungsweise oder Allergenen passt.
  public static func violations(_ name: String, diet: Diet, allergens: Set<Allergen>) -> [String] {
    let lower = name.lowercased()
    var result: [String] = []
    let plantBased = lower.contains("vegan") || lower.contains("vegetarisch")
    if !plantBased {
      // Pflanzliche Ersatzprodukte wie „Sojahack“ oder „Erbsenwurst“ zählen nicht als Fleisch.
      if diet != .omnivore, contains(name, meat, except: ["soja", "erbsen", "tofu", "seitan"]) {
        result.append("Fleisch")
      }
      if diet == .vegetarian || diet == .vegan, contains(name, fish) || contains(name, shellfish) {
        result.append("Fisch")
      }
      if diet == .vegan {
        if isEgg(name) { result.append("Ei") }
        if isDairy(name) { result.append("Milchprodukte") }
        if contains(name, ["honig"]) { result.append("Honig") }
      }
    }
    for allergen in allergens.sorted(by: { $0.rawValue < $1.rawValue }) {
      let hit: Bool =
        switch allergen {
        case .gluten: contains(name, gluten) && !glutenFree.contains { lower.contains($0) }
        case .lactose: isDairy(name) && !lower.contains("laktosefrei")
        case .nuts: contains(name, nuts, except: ["erdnuss", "muskatnuss", "kokosnuss"])
        case .peanuts: lower.contains("erdnuss")
        case .egg: isEgg(name)
        case .soy: contains(name, soy)
        case .fish: contains(name, fish)
        case .shellfish: contains(name, shellfish)
        case .sesame: contains(name, sesame)
        }
      if hit { result.append(allergen.label) }
    }
    return result
  }

  public static func violations(_ recipe: Recipe, diet: Diet, allergens: Set<Allergen>) -> [String] {
    var seen = Set<String>()
    return recipe.ingredients.flatMap { violations($0.name, diet: diet, allergens: allergens) }
      .filter { seen.insert($0).inserted }
  }

  // MARK: Auswertung bisheriger Mahlzeiten und Einkaufsliste

  /// Nährstoffe, die in den letzten Tagen im Schnitt unter 80 % des Ziels lagen (nur Tage mit erfassten Mahlzeiten).
  public static func gaps(dailyTotals: [NutrientValues], targets: NutrientValues) -> [String] {
    guard dailyTotals.count >= 3 else { return [] }
    let watched: [Nutrient] = [.protein, .fiber, .omega3, .calcium, .iron, .iodine, .magnesium]
    return watched.compactMap { nutrient in
      guard let target = targets[nutrient], target > 0 else { return nil }
      let average = dailyTotals.reduce(0) { $0 + ($1[nutrient] ?? 0) } / Double(dailyTotals.count)
      guard average < 0.8 * target else { return nil }
      let percent = Int((average / target * 100).rounded())
      return "\(nutrient.label): im Schnitt \(Int(average.rounded())) von \(Int(target.rounded())) "
        + "\(nutrient.unit) (\(percent) %)"
    }
  }

  public struct ShoppingItem: Equatable, Sendable, Identifiable {
    public var name: String
    public var grams: Double
    public var id: String { name.lowercased() }
  }

  /// Einkaufsliste der Woche: gleiche Zutaten zusammengefasst, für `servings` Personen.
  public static func shoppingList(_ plan: WeeklyRecipePlan, servings: Int) -> [ShoppingItem] {
    var sums: [String: (name: String, grams: Double)] = [:]
    for item in plan.days.flatMap(\.recipes).flatMap(\.ingredients) {
      let key = item.name.lowercased().trimmingCharacters(in: .whitespaces)
      let current = sums[key] ?? (item.name, 0)
      sums[key] = (current.name, current.grams + item.grams * Double(max(servings, 1)))
    }
    return sums.values.map { ShoppingItem(name: $0.name, grams: ($0.grams / 5).rounded() * 5) }
      .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
  }
}
