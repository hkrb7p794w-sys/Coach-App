import Foundation

/// Portion eines Lebensmittels: „Scheibe“ à 30 g, „Riegel“ à 45 g. Wer isst, denkt in Stück, nicht in Gramm.
public struct Portion: Codable, Equatable, Hashable, Sendable {
  public var name: String
  public var grams: Double

  public init(name: String, grams: Double) {
    self.name = name
    self.grams = grams
  }
}

extension MealItem {
  /// Menge in Portionen (z. B. 1,5 Scheiben); `nil` ohne bekannte Portion.
  public var portionCount: Double? {
    guard let portion, portion.grams > 0 else { return nil }
    return grams / portion.grams
  }

  public mutating func setPortions(_ count: Double) {
    guard let portion, portion.grams > 0 else { return }
    grams = max(0, (count * portion.grams * 10).rounded() / 10)
  }

  /// Menge mit Faktor (½ Rezept, doppelte Portion).
  public func scaled(by factor: Double) -> MealItem {
    var copy = self
    copy.grams = max(0, (grams * factor * 10).rounded() / 10)
    return copy
  }

  /// „2 × Scheibe (60 g)“ bzw. „150 g“.
  public var amountLabel: String {
    let unit = isDrink ? "ml" : "g"
    guard let portion, let count = portionCount else { return "\(GermanFormat.number(grams)) \(unit)" }
    return "\(PortionGuess.format(count)) × \(portion.name) (\(GermanFormat.number(grams.rounded())) \(unit))"
  }
}

public enum PortionGuess {
  /// Einheiten, die keine Portion sind.
  static let massUnits: Set<String> = ["g", "gramm", "kg", "ml", "l", "liter", "mg", "cl"]

  /// Plural → Singular für die häufigsten Portionen.
  static let singular: [String: String] = [
    "scheiben": "Scheibe", "stück": "Stück", "stücke": "Stück", "eier": "Ei", "gläser": "Glas", "tassen": "Tasse",
    "becher": "Becher", "portionen": "Portion", "riegel": "Riegel", "brötchen": "Brötchen", "packungen": "Packung",
    "dosen": "Dose", "flaschen": "Flasche", "bananen": "Banane", "äpfel": "Apfel", "esslöffel": "EL", "el": "EL",
    "teelöffel": "TL", "tl": "TL", "handvoll": "Handvoll", "schalen": "Schale", "schüsseln": "Schüssel",
    "teller": "Teller", "kugeln": "Kugel", "würfel": "Würfel", "beutel": "Beutel", "kapseln": "Kapsel",
  ]

  static let words: [String: Double] = [
    "ein": 1, "eine": 1, "einen": 1, "zwei": 2, "drei": 3, "vier": 4, "halbe": 0.5,
  ]

  /// Aus der KI-Angabe „2 Scheiben“ und 60 g → Scheibe à 30 g. Reine Gewichtsangaben („150 g“) ergeben nichts.
  public static func from(amountText: String?, grams: Double) -> Portion? {
    guard let text = amountText?.trimmingCharacters(in: .whitespaces), !text.isEmpty, grams > 0 else { return nil }
    let parts = text.replacingOccurrences(of: "(", with: " ").split(separator: " ").map(String.init)
    guard parts.count >= 2, let count = number(parts[0]), count > 0 else { return nil }
    let unit = parts[1].trimmingCharacters(in: .punctuationCharacters)
    guard !unit.isEmpty, !massUnits.contains(unit.lowercased()), unit.first?.isLetter == true else { return nil }
    let name = singular[unit.lowercased()] ?? unit
    return Portion(name: name, grams: (grams / count * 10).rounded() / 10)
  }

  /// Aus der Packungsangabe „1 Riegel (45 g)“ bzw. nur der Portionsmenge → „Portion“.
  public static func serving(text: String?, grams: Double?) -> Portion? {
    guard let grams, grams > 0 else { return nil }
    return from(amountText: text, grams: grams) ?? Portion(name: "Portion", grams: grams)
  }

  static func number(_ text: String?) -> Double? {
    guard let text else { return nil }
    let lower = text.lowercased()
    if let word = words[lower] { return word }
    if lower == "½" { return 0.5 }
    if lower.hasSuffix("½"), let whole = Double(lower.dropLast()) { return whole + 0.5 }
    return Double(lower.replacingOccurrences(of: ",", with: "."))
  }

  /// 0,5 → „½“, 1,5 → „1½“, 2 → „2“, 1,25 → „1,25“.
  public static func format(_ count: Double) -> String {
    let rounded = (count * 100).rounded() / 100
    let whole = rounded.rounded(.down)
    if abs(rounded - whole - 0.5) < 0.01 { return whole == 0 ? "½" : "\(Int(whole))½" }
    return GermanFormat.number(rounded)
  }

  /// Schnelltasten im Entwurf.
  public static let quickCounts: [Double] = [0.5, 1, 1.5, 2]
}

/// Lücken und Widersprüche in Nährwerten (Open Food Facts ist oft unvollständig).
public enum NutrientCheck {
  /// Wie viele Positionen keinen Wert für den Nährstoff haben – leere Werte zählen sonst still als 0.
  public static func missing(_ nutrient: Nutrient, in items: [MealItem]) -> Int {
    items.filter { $0.per100g[nutrient] == nil }.count
  }

  /// Energie aus den Makros (4 kcal/g Protein und KH, 9 kcal/g Fett, 2 kcal/g Ballaststoffe).
  public static func energyFromMacros(_ values: NutrientValues) -> Double? {
    guard let protein = values[.protein], let carbs = values[.carbs], let fat = values[.fat] else { return nil }
    return protein * 4 + carbs * 4 + fat * 9 + (values[.fiber] ?? 0) * 2
  }

  /// Hinweis, wenn kcal und Makros um mehr als 15 % auseinanderliegen (ab 20 kcal je 100 g).
  public static func energyMismatch(_ values: NutrientValues) -> String? {
    guard let kcal = values[.kcal], let computed = energyFromMacros(values), max(kcal, computed) >= 20 else {
      return nil
    }
    guard abs(kcal - computed) / max(kcal, computed) > 0.15 else { return nil }
    return "Laut Makros etwa \(Int(computed.rounded())) kcal je 100 g, eingetragen \(Int(kcal.rounded())). "
      + "Bitte Etikett prüfen."
  }
}

/// Antwort der Worker-Aufgabe `nutrition_label`: Nährwerttabelle vom Foto (Werte je 100 g wie auf dem Etikett).
public enum NutritionLabel {
  public static func item(from output: JSONValue) -> MealItem? {
    var per100g = NutrientValues()
    if let nutrients = output["naehrwerte_100g"]?.objectValue {
      for nutrient in Nutrient.allCases {
        let key = nutrient == .water ? "water_g" : nutrient.rawValue
        if let amount = nutrients[key]?.doubleValue, amount >= 0 { per100g[nutrient] = amount }
      }
    }
    guard per100g[.kcal] != nil else { return nil }
    let name = output["name"]?.stringValue.map { String($0.prefix(80)) } ?? ""
    let portionGrams = output["portion_g"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
    var item = MealItem(name: name, grams: portionGrams ?? 100, source: .manual, per100g: per100g)
    item.isDrink = output["getraenk"] == .bool(true)
    if let portionGrams {
      let portionName = output["portion_name"]?.stringValue.flatMap { $0.isEmpty ? nil : String($0.prefix(30)) }
      item.portion = Portion(name: portionName ?? "Portion", grams: portionGrams)
    }
    return item
  }
}
