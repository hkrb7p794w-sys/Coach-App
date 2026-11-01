import CoachCore
import SwiftUI

/// Lebensmittel im Bundeslebensmittelschlüssel suchen und übernehmen (offline, rund 7.000 Einträge).
struct BLSPicker: View {
  let initialQuery: String
  let select: (BLSFood) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    let results = BLS.search(query, limit: 40)
    List {
      Section {
        if results.isEmpty {
          Text(query.count < 2 ? "Suchbegriff eingeben, z. B. „Haferflocken“." : "Nichts gefunden.")
            .foregroundStyle(.secondary)
        }
        ForEach(results) { food in
          Button {
            select(food)
            dismiss()
          } label: {
            BLSRow(food: food)
          }
          .buttonStyle(.plain)
        }
      } footer: {
        Text("Quelle: \(BLS.attribution). Nährwerte je 100 g, so wie im Namen beschrieben (roh, gekocht …).")
      }
    }
    .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Lebensmittel im BLS")
    .navigationTitle("BLS-Lebensmittel")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if query.isEmpty { query = initialQuery }
    }
  }
}

/// Name und Kernwerte je 100 g.
struct BLSRow: View {
  let food: BLSFood

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(food.name).lineLimit(2)
      Text(Self.summary(food.per100g)).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  static func summary(_ values: NutrientValues) -> String {
    let parts: [(Nutrient, String)] = [(.kcal, "kcal"), (.protein, "g P"), (.carbs, "g KH"), (.fat, "g F")]
    let text = parts.compactMap { nutrient, unit in
      values[nutrient].map { "\(Int($0.rounded())) \(unit)" }
    }
    return "je 100 g: " + text.joined(separator: " · ")
  }
}

extension MealItem {
  /// Herkunft der Nährwerte für Fußnoten: BLS mit Eintrag, KI als Schätzung.
  var sourceText: String {
    switch source {
    case .bls:
      let name = blsCode.flatMap { BLS.food(code: $0)?.name }.map { " – \($0)" } ?? ""
      return "\(BLS.sourceLabel)\(name)"
    case .ai: return "KI, geschätzt"
    case .openFoodFacts, .manual: return source.rawValue
    }
  }
}
