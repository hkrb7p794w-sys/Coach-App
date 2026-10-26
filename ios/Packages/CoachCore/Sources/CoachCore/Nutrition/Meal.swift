import Foundation

public enum MealCategory: String, CaseIterable, Codable, Sendable {
  case breakfast = "fruehstueck"
  case lunch = "mittagessen"
  case dinner = "abendessen"
  case snack
  case other = "sonstiges"

  public var label: String {
    switch self {
    case .breakfast: "Frühstück"
    case .lunch: "Mittagessen"
    case .dinner: "Abendessen"
    case .snack: "Snack"
    case .other: "Sonstiges"
    }
  }

  /// Kategorie nach Uhrzeit (wie `guess_category` im Altbestand).
  public static func guess(hour: Int, minute: Int) -> MealCategory {
    let time = Double(hour) + Double(minute) / 60
    if 4 <= time && time < 10.5 { return .breakfast }
    if 10.5 <= time && time < 14.5 { return .lunch }
    if 17.5 <= time && time < 21.5 { return .dinner }
    return .snack
  }
}

/// Eine Position einer Mahlzeit.
public struct MealItem: Codable, Equatable, Sendable, Identifiable {
  public enum Source: String, Codable, Sendable {
    case ai = "KI"
    case openFoodFacts = "Open Food Facts"
    case manual = "Eigene Angabe"
  }

  public var id = UUID()
  public var name: String
  public var grams: Double
  public var amountText: String?
  public var isDrink = false
  /// `hoch`, `mittel`, `niedrig` (Einschätzung der KI).
  public var confidence: String?
  public var group: String?
  public var barcode: String?
  public var source: Source
  public var per100g: NutrientValues

  public init(name: String, grams: Double, source: Source, per100g: NutrientValues) {
    self.name = name
    self.grams = grams
    self.source = source
    self.per100g = per100g
  }

  public var amounts: NutrientValues {
    per100g.scaled(toGrams: grams)
  }
}

/// Ergebnis der KI-Analyse einer Mahlzeit (Foto oder Text).
public struct MealAnalysis: Equatable, Sendable {
  public var title: String
  public var category: MealCategory?
  public var hint: String
  public var items: [MealItem]

  /// Liest die Antwort der Worker-Aufgabe `meal_analyze` (Schema aus `analyze.py` im Altbestand).
  public init?(output: JSONValue) {
    guard let rawItems = output["items"]?.arrayValue else { return nil }
    title = String((output["titel"]?.stringValue ?? "").prefix(60))
    category = output["kategorie"]?.stringValue.flatMap(MealCategory.init(rawValue:))
    hint = output["hinweis"]?.stringValue ?? ""
    items = rawItems.compactMap(Self.item)
    if items.isEmpty { return nil }
  }

  static func item(_ value: JSONValue) -> MealItem? {
    guard let name = value["name"]?.stringValue, !name.isEmpty,
      let grams = value["menge_g"]?.doubleValue, grams > 0
    else { return nil }
    var per100g = NutrientValues()
    if let nutrients = value["naehrwerte_100g"]?.objectValue {
      for nutrient in Nutrient.allCases {
        let key = nutrient == .water ? "water_g" : nutrient.rawValue
        if let amount = nutrients[key]?.doubleValue, amount >= 0 { per100g[nutrient] = amount }
      }
    }
    var item = MealItem(name: name, grams: grams, source: .ai, per100g: per100g)
    item.amountText = value["menge_text"]?.stringValue
    item.isDrink = value["getraenk"] == .bool(true)
    item.confidence = value["sicherheit"]?.stringValue
    item.group = value["gruppe"]?.stringValue
    item.barcode = value["barcode"]?.stringValue.flatMap { OpenFoodFacts.isValidBarcode($0) ? $0 : nil }
    return item
  }
}

/// Summe einer Liste von Positionen und Fortschritt gegenüber den Tageszielen.
public enum NutritionSummary {
  public static func totals(_ items: [MealItem]) -> NutrientValues {
    items.reduce(NutrientValues()) { $0 + $1.amounts }
  }

  /// Anteil des Ziels in Prozent (bei Obergrenzen: Anteil der Grenze).
  public static func percent(_ value: Double?, of target: Double?) -> Int? {
    guard let target, target > 0 else { return nil }
    return Int(((value ?? 0) / target * 100).rounded())
  }
}
