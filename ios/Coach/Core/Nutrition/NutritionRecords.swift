import CoachCore
import Foundation
import SwiftData

/// Eine gespeicherte Mahlzeit. Die Positionen liegen als JSON (`[MealItem]`) vor.
@Model
final class MealRecord {
  @Attribute(.unique) var id: UUID
  var dayKey: String
  var createdAt: Date
  var categoryRaw: String
  var title: String
  var hint: String
  var itemsPayload: Data

  init(
    day: CalendarDay, category: MealCategory, title: String, hint: String, items: [MealItem], at date: Date = .now
  ) {
    id = UUID()
    dayKey = day.iso
    createdAt = date
    categoryRaw = category.rawValue
    self.title = title
    self.hint = hint
    itemsPayload = (try? JSONEncoder().encode(items)) ?? Data()
  }

  var category: MealCategory {
    get { MealCategory(rawValue: categoryRaw) ?? .other }
    set { categoryRaw = newValue.rawValue }
  }

  var items: [MealItem] {
    get { (try? JSONDecoder().decode([MealItem].self, from: itemsPayload)) ?? [] }
    set { itemsPayload = (try? JSONEncoder().encode(newValue)) ?? itemsPayload }
  }

  /// Nur Wasser (Glas-Knopf) – erscheint nicht in der Mahlzeitenliste.
  var isWater: Bool {
    let items = self.items
    return !items.isEmpty && items.allSatisfy { $0.isDrink && $0.name == "Wasser" }
  }
}

/// Eigenes bzw. zuletzt genutztes Lebensmittel (auch Open-Food-Facts-Zwischenspeicher je Barcode).
/// Die Namen der häufigsten gehen als Hinweis an die KI-Analyse.
@Model
final class FoodRecord {
  @Attribute(.unique) var key: String
  var name: String
  var payload: Data
  var lastUsed: Date
  var useCount: Int

  init(item: MealItem) {
    key = Self.key(for: item)
    name = item.name
    payload = (try? JSONEncoder().encode(item)) ?? Data()
    lastUsed = .now
    useCount = 0
  }

  static func key(for item: MealItem) -> String {
    item.barcode.map { "barcode:\($0)" } ?? "name:\(item.name.lowercased())"
  }

  var item: MealItem? {
    try? JSONDecoder().decode(MealItem.self, from: payload)
  }
}
