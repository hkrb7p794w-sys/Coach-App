import Foundation

/// Eine geteilte Mahlzeit: nur Titel und Positionen (Menge, Nährwerte je 100 g, Herkunft der Werte) – kein Name, kein
/// Datum, keine Gesundheitsdaten. Beim Empfänger wird daraus immer ein neuer Tagebuch-Eintrag oder Favorit.
public struct SharedMeal: Codable, Equatable, Sendable {
  public struct Item: Codable, Equatable, Sendable {
    public var name: String
    public var grams: Double
    public var isDrink: Bool
    public var source: String
    public var per100g: [String: Double]
    public var amountText: String?
  }

  public var title: String
  public var items: [Item]
  public var expiresAt: String?

  /// Zum Teilen: ursprüngliche Mengen (vor einer Portionsanpassung), Nährwerte wie gespeichert.
  public init(title: String, items: [MealItem]) {
    self.title = title
    self.items = items.map(MealPortion.restored).map { item in
      Item(
        name: item.name, grams: item.grams, isDrink: item.isDrink, source: item.source.rawValue,
        per100g: Dictionary(uniqueKeysWithValues: item.per100g.values.map { ($0.key.rawValue, $0.value) }),
        amountText: item.amountText)
    }
  }

  /// Positionen für das eigene Tagebuch (neue IDs).
  public var mealItems: [MealItem] {
    items.map { shared in
      var values: [Nutrient: Double] = [:]
      for (key, value) in shared.per100g {
        if let nutrient = Nutrient(rawValue: key) { values[nutrient] = value }
      }
      var item = MealItem(
        name: shared.name, grams: shared.grams, source: MealItem.Source(rawValue: shared.source) ?? .manual,
        per100g: NutrientValues(values))
      item.isDrink = shared.isDrink
      item.amountText = shared.amountText
      return item
    }
  }

  public var kilocalories: Double { NutritionSummary.totals(mealItems)[.kcal] ?? 0 }
}

public enum MealShare {
  /// Code aus `coach://meal/<code>`, `https://…/m/<code>` oder einem eingetippten Code.
  public static func code(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if isValid(trimmed) { return trimmed }
    guard let url = URL(string: trimmed) else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    if url.scheme == "coach", url.host() == "meal", let last = parts.last, isValid(last) { return last }
    if parts.count == 2, parts[0] == "m", isValid(parts[1]) { return parts[1] }
    return nil
  }

  public static func isValid(_ code: String) -> Bool {
    code.count == 10 && code.allSatisfy { $0.isLetter || $0.isNumber } && code == code.lowercased()
      && code.allSatisfy(\.isASCII)
  }

  /// Text für Nachrichten-Apps: Link (öffnet die App) und Code zum Eintippen.
  public static func message(title: String, kilocalories: Double, link: URL?, code: String) -> String {
    var lines = ["Mahlzeit „\(title)“ (\(Int(kilocalories.rounded())) kcal) für IronLudi:"]
    if let link { lines.append(link.absoluteString) }
    lines.append("Oder in der App unter Ernährung › „Geteilte Mahlzeit öffnen“ den Code \(code) eingeben.")
    lines.append("Der Code gilt 7 Tage.")
    return lines.joined(separator: "\n")
  }
}
