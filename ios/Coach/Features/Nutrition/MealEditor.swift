import CoachCore
import SwiftUI

/// Prüfen und Anpassen einer Mahlzeit vor dem Speichern. Mengen aus Fotos sind Schätzungen – hier korrigieren.
struct MealEditor: View {
  @State var draft: NutritionViewModel.Draft
  let viewModel: NutritionViewModel
  let foods: [FoodRecord]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Titel", text: $draft.title)
          Picker("Mahlzeit", selection: $draft.category) {
            ForEach(MealCategory.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          // Nachtragen: Zeitpunkt wählen, die Mahlzeit folgt der Uhrzeit.
          DatePicker(
            "Zeitpunkt",
            selection: Binding(
              get: { draft.date ?? viewModel.timestamp() },
              set: { date in
                draft.date = date
                draft.category = NutritionViewModel.category(at: date)
              }),
            in: ...Date.now.addingTimeInterval(3_600))
          if !draft.hint.isEmpty {
            Label(draft.hint, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
          }
        }

        ForEach($draft.items) { $item in
          Section {
            ItemEditor(item: $item)
          } header: {
            HStack {
              Text(item.source.rawValue + (item.confidence.map { " · Sicherheit \($0)" } ?? ""))
              Spacer()
              Button("Entfernen", role: .destructive) {
                draft.items.removeAll { $0.id == item.id }
              }
              .font(.caption)
            }
          }
        }

        Section {
          Button("Position hinzufügen", systemImage: "plus") {
            draft.items.append(MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues()))
          }
          if !foods.isEmpty {
            Menu("Aus eigenen Lebensmitteln", systemImage: "star") {
              ForEach(foods.prefix(20)) { food in
                Button(food.name) {
                  if var item = food.item {
                    item.id = UUID()
                    draft.items.append(item)
                  }
                }
              }
            }
          }
        }

        Section("Summe") {
          let totals = NutritionSummary.totals(draft.items)
          LabeledContent("Kalorien", value: "\(Int((totals[.kcal] ?? 0).rounded())) kcal")
          LabeledContent("Protein", value: "\(Int((totals[.protein] ?? 0).rounded())) g")
          LabeledContent("Kohlenhydrate", value: "\(Int((totals[.carbs] ?? 0).rounded())) g")
          LabeledContent("Fett", value: "\(Int((totals[.fat] ?? 0).rounded())) g")
        }
      }
      .navigationTitle(draft.record == nil ? "Neue Mahlzeit" : "Mahlzeit bearbeiten")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Speichern") {
            viewModel.save(draft, context: context, foods: foods)
            if viewModel.draft == nil { dismiss() }
          }
        }
      }
    }
  }
}

private struct ItemEditor: View {
  @Binding var item: MealItem

  var body: some View {
    TextField("Lebensmittel", text: $item.name)
    HStack {
      Text("Menge")
      Spacer()
      TextField("g", value: $item.grams, format: .number.precision(.fractionLength(0...1)))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 90)
      Text(item.isDrink ? "ml" : "g").foregroundStyle(.secondary)
    }
    if let text = item.amountText, !text.isEmpty {
      Text(text).font(.caption).foregroundStyle(.secondary)
    }
    LabeledContent("Kalorien", value: "\(Int((item.amounts[.kcal] ?? 0).rounded())) kcal")
    DisclosureGroup("Nährwerte je 100 g") {
      ForEach([Nutrient.kcal, .protein, .carbs, .sugar, .fat, .saturatedFat, .fiber], id: \.self) { nutrient in
        HStack {
          Text(nutrient.label)
          Spacer()
          TextField(
            nutrient.unit,
            value: Binding(get: { item.per100g[nutrient] }, set: { item.per100g[nutrient] = $0 }),
            format: .number.precision(.fractionLength(0...1))
          )
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(maxWidth: 90)
          Text(nutrient.unit).foregroundStyle(.secondary)
        }
      }
    }
  }
}
