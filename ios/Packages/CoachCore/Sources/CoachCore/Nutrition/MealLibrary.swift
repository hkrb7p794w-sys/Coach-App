import Foundation

/// Eine als Favorit gespeicherte Mahlzeit – eine Vorlage, getrennt von Rezepten (`OwnRecipe`) und vom Tagebuch:
/// Eintragen legt immer eine Kopie an, Änderungen am Tagebuch-Eintrag ändern den Favoriten nicht.
public struct FavoriteMeal: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var title: String
  public var items: [MealItem]
  public var category: MealCategory?
  public var created: Date

  public init(
    id: UUID = UUID(), title: String, items: [MealItem], category: MealCategory? = nil, created: Date = .now
  ) {
    self.id = id
    self.title = title
    // Vorlage ohne Portionsanpassung: Menge = was ursprünglich geplant war.
    self.items = items.map(MealPortion.restored)
    self.category = category
    self.created = created
  }

  public var kilocalories: Double { NutritionSummary.totals(items)[.kcal] ?? 0 }
  public var signature: String { MealSuggestions.signature(items) }
}

/// Was beim Erfassen sofort zur Auswahl steht.
public enum MealShortcuts {
  /// Zuletzt erfasste Mahlzeiten, neueste zuerst, jede Zusammenstellung nur einmal.
  public static func recent(_ entries: [MealEntry], limit: Int = 8) -> [MealEntry] {
    var seen = Set<String>()
    var result: [MealEntry] = []
    for entry in entries.sorted(by: { $0.date > $1.date }) where !entry.items.isEmpty {
      let key = MealSuggestions.signature(entry.items.map(MealPortion.restored))
      guard seen.insert(key).inserted else { continue }
      result.append(entry)
      if result.count == limit { break }
    }
    return result
  }

  /// Häufigste Mahlzeiten über alle Kategorien (letzte 60 Tage), mindestens zweimal gegessen.
  public static func frequent(_ entries: [MealEntry], today: CalendarDay, limit: Int = 8)
    -> [MealSuggestions.Suggestion]
  {
    let all = MealCategory.allCases.flatMap { category in
      MealSuggestions.frequent(entries, category: category, today: today.adding(days: 1), limit: limit)
    }
    var merged: [String: MealSuggestions.Suggestion] = [:]
    for suggestion in all {
      if var existing = merged[suggestion.id] {
        existing.count += suggestion.count
        merged[suggestion.id] = existing
      } else {
        merged[suggestion.id] = suggestion
      }
    }
    return merged.values.filter { $0.count >= 2 }
      .sorted { ($0.count, $0.lastDate) > ($1.count, $1.lastDate) }
      .prefix(limit).map { $0 }
  }

  /// Ist diese Zusammenstellung schon ein Favorit?
  public static func favorite(for items: [MealItem], in favorites: [FavoriteMeal]) -> FavoriteMeal? {
    let key = MealSuggestions.signature(items.map(MealPortion.restored))
    return favorites.first { $0.signature == key }
  }
}

/// Nachträglich weniger (oder mehr) gegessen: Mengen anteilig ändern, die ursprüngliche Menge bleibt je Position
/// gespeichert (`plannedGrams`). Nährwerte je 100 g bleiben gleich, daher stimmen alle Summen proportional.
/// Gilt nur für den Tagebuch-Eintrag – Rezepte und Favoriten sind eigene Kopien.
public enum MealPortion {
  public static let presets: [Double] = [0.25, 0.5, 0.75, 1]

  /// Anteil gegessen bezogen auf die ursprüngliche Menge (1 = alles).
  public static func eatenFraction(_ items: [MealItem]) -> Double {
    let planned = items.reduce(0) { $0 + ($1.plannedGrams ?? $1.grams) }
    guard planned > 0 else { return 1 }
    return items.reduce(0) { $0 + $1.grams } / planned
  }

  /// Ursprüngliche Gesamtmenge.
  public static func plannedGrams(_ items: [MealItem]) -> Double {
    items.reduce(0) { $0 + ($1.plannedGrams ?? $1.grams) }
  }

  /// Alle Positionen auf `fraction` der ursprünglichen Menge setzen. Mehrfaches Anpassen rechnet immer von der
  /// ursprünglichen Menge aus (75 %, dann 50 % = 50 %, nicht 37,5 %); 100 % stellt den Ausgangszustand her.
  public static func adjusted(_ items: [MealItem], to fraction: Double) -> [MealItem] {
    let fraction = min(max(fraction, 0.05), 3)
    return items.map { item in
      var copy = item
      let base = item.plannedGrams ?? item.grams
      copy.grams = (base * fraction * 10).rounded() / 10
      copy.plannedGrams = abs(fraction - 1) < 0.001 ? nil : base
      return copy
    }
  }

  /// Position mit ursprünglicher Menge (für Vorlagen und Vergleiche).
  public static func restored(_ item: MealItem) -> MealItem {
    var copy = item
    if let planned = item.plannedGrams { copy.grams = planned }
    copy.plannedGrams = nil
    return copy
  }

  /// „75 % von 500 g“.
  public static func label(_ items: [MealItem]) -> String {
    "\(Int((eatenFraction(items) * 100).rounded())) % von \(GermanFormat.number(plannedGrams(items).rounded())) g"
  }
}
