import CoachCore
import SwiftUI

/// Prüfen und Anpassen einer Mahlzeit vor dem Speichern. Oben steht, was danach vom Tag übrig ist; Positionen sind
/// kompakte Zeilen mit ± (Portion bzw. 10 g), Antippen öffnet Menge und Nährwerte. Unsichere Schätzungen sind gelb
/// markiert.
struct MealEditor: View {
  @State var draft: NutritionViewModel.Draft
  let viewModel: NutritionViewModel
  let foods: [FoodRecord]
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var editing: UUID?

  var body: some View {
    NavigationStack {
      List {
        Section {
          DraftSummary(items: draft.items, remainingBefore: remainingBefore)
        }
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

        Section {
          ForEach($draft.items) { $item in
            ItemRow(item: $item) { editing = item.id }
          }
          .onDelete { draft.items.remove(atOffsets: $0) }
          Button("Position hinzufügen", systemImage: "plus") {
            let item = MealItem(name: "", grams: 100, source: .manual, per100g: NutrientValues())
            draft.items.append(item)
            editing = item.id
          }
          if !foods.isEmpty {
            Menu("Aus eigenen Lebensmitteln", systemImage: "star") {
              ForEach(foods.prefix(30)) { food in
                Button(food.name) {
                  if var item = food.item {
                    item.id = UUID()
                    draft.items.append(item)
                  }
                }
              }
            }
          }
        } header: {
          Text("Positionen")
        } footer: {
          if draft.items.contains(where: Self.isUncertain) {
            Label("Gelb = unsichere Schätzung, bitte Menge prüfen.", systemImage: "circle.fill")
              .foregroundStyle(.yellow)
          }
        }

        if draft.items.count > 0 {
          Section {
            HStack(spacing: 8) {
              ForEach([0.5, 1.5, 2], id: \.self) { factor in
                Button("× \(PortionGuess.format(factor))") {
                  draft.items = draft.items.map { $0.scaled(by: factor) }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
              }
            }
          } header: {
            Text("Menge für alle")
          } footer: {
            Text("Halbe Portion gegessen oder doppelt? Alle Positionen auf einmal anpassen.")
          }
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
          .bold()
        }
      }
      .sheet(item: Binding(get: { editing.map { EditingID(id: $0) } }, set: { editing = $0?.id })) { target in
        if let index = draft.items.firstIndex(where: { $0.id == target.id }) {
          ItemDetailSheet(item: $draft.items[index])
        }
      }
    }
  }

  private struct EditingID: Identifiable {
    let id: UUID
  }

  /// Übrige kcal des Tages ohne diese Mahlzeit (beim Bearbeiten zählt die alte Fassung nicht doppelt).
  private var remainingBefore: Double? {
    guard let target = viewModel.targets?.values[.kcal] else { return nil }
    let old = draft.record.map { NutritionSummary.totals($0.items)[.kcal] ?? 0 } ?? 0
    return target - ((viewModel.totals[.kcal] ?? 0) - old)
  }

  static func isUncertain(_ item: MealItem) -> Bool {
    item.confidence == "niedrig" || item.confidence == "mittel"
  }
}

/// Summe groß oben: kcal, Makros und „danach … kcal übrig“; Lücken in den Nährwerten werden genannt.
private struct DraftSummary: View {
  let items: [MealItem]
  let remainingBefore: Double?

  var body: some View {
    let totals = NutritionSummary.totals(items)
    let kcal = totals[.kcal] ?? 0
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(Int(kcal.rounded())) kcal").font(.title.bold()).monospacedDigit()
        Spacer()
        if let remainingBefore {
          let after = remainingBefore - kcal
          Text(after >= 0 ? "danach \(Int(after.rounded())) übrig" : "danach \(Int(-after.rounded())) drüber")
            .font(.subheadline)
            .foregroundStyle(after >= 0 ? Color.secondary : Color.red)
        }
      }
      Text(
        "Protein \(Int((totals[.protein] ?? 0).rounded())) g · KH \(Int((totals[.carbs] ?? 0).rounded())) g · "
          + "Fett \(Int((totals[.fat] ?? 0).rounded())) g"
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)
      let missing = NutrientCheck.missing(.protein, in: items)
      if missing > 0, !items.isEmpty {
        Label(
          missing == 1 ? "Bei 1 Position fehlen Makros – Summe ohne sie." : "Bei \(missing) Positionen fehlen Makros.",
          systemImage: "exclamationmark.circle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }
    }
  }
}

/// Kompakte Zeile: Name, Menge, kcal und Protein; ± ändert um eine Portion bzw. 10 g.
private struct ItemRow: View {
  @Binding var item: MealItem
  let open: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      if MealEditor.isUncertain(item) {
        Circle().fill(.yellow).frame(width: 8, height: 8).accessibilityLabel("Unsichere Schätzung")
      }
      Button(action: open) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.name.isEmpty ? "Neue Position" : item.name).lineLimit(1)
          Text(
            "\(item.amountLabel) · \(Int((item.amounts[.kcal] ?? 0).rounded())) kcal · "
              + "\(Int((item.amounts[.protein] ?? 0).rounded())) g P"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      stepButton("minus", -1)
      stepButton("plus", 1)
    }
  }

  private func stepButton(_ symbol: String, _ direction: Double) -> some View {
    Button {
      if let count = item.portionCount {
        item.setPortions(max(0, count + direction * (count < 1 ? 0.5 : 1)))
      } else {
        item.grams = max(0, item.grams + direction * 10)
      }
    } label: {
      Image(systemName: symbol).font(.body.bold()).frame(width: 36, height: 36)
        .background(.fill.tertiary, in: Circle())
    }
    .buttonStyle(.borderless)
    .accessibilityLabel(direction > 0 ? "Mehr" : "Weniger")
  }
}

/// Menge (Portionen oder Gramm), eigene Portion und Nährwerte je 100 g einer Position.
private struct ItemDetailSheet: View {
  @Binding var item: MealItem
  @Environment(\.dismiss) private var dismiss
  @State private var inPortions = true
  @State private var portionName = ""
  @State private var portionGrams: Double?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Lebensmittel", text: $item.name)
        }
        Section {
          if item.portion != nil {
            Picker("Eingabe", selection: $inPortions) {
              Text("Portionen").tag(true)
              Text(item.isDrink ? "ml" : "Gramm").tag(false)
            }
            .pickerStyle(.segmented)
          }
          if let portion = item.portion, inPortions {
            HStack {
              ForEach(PortionGuess.quickCounts, id: \.self) { count in
                Button(PortionGuess.format(count)) { item.setPortions(count) }
                  .buttonStyle(.bordered)
                  .tint(abs((item.portionCount ?? 0) - count) < 0.01 ? .accentColor : .secondary)
                  .frame(maxWidth: .infinity)
              }
            }
            Stepper(
              "\(PortionGuess.format(item.portionCount ?? 0)) × \(portion.name)",
              value: Binding(get: { item.portionCount ?? 0 }, set: { item.setPortions($0) }), in: 0...50, step: 0.5)
          } else {
            HStack {
              Button("−10") { item.grams = max(0, item.grams - 10) }.buttonStyle(.bordered)
              TextField("Menge", value: $item.grams, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.title3.bold())
              Text(item.isDrink ? "ml" : "g").foregroundStyle(.secondary)
              Button("+10") { item.grams += 10 }.buttonStyle(.bordered)
            }
          }
          if let text = item.amountText, !text.isEmpty {
            Text("Schätzung: \(text)").font(.caption).foregroundStyle(.secondary)
          }
        } header: {
          Text("Menge · \(Int((item.amounts[.kcal] ?? 0).rounded())) kcal")
        }
        Section {
          TextField("Name, z. B. Scheibe", text: $portionName)
          HStack {
            TextField("Gramm je Portion", value: $portionGrams, format: .number.precision(.fractionLength(0...1)))
              .keyboardType(.decimalPad)
            Text("g").foregroundStyle(.secondary)
          }
          Button(item.portion == nil ? "Portion festlegen" : "Portion ändern") {
            guard let grams = portionGrams, grams > 0 else { return }
            let name = portionName.trimmingCharacters(in: .whitespaces)
            item.portion = Portion(name: name.isEmpty ? "Portion" : name, grams: grams)
            inPortions = true
          }
          .disabled((portionGrams ?? 0) <= 0)
        } header: {
          Text("Eigene Portion")
        } footer: {
          Text("Die App merkt sich Portion und Menge je Lebensmittel für das nächste Mal.")
        }
        Section {
          ForEach([Nutrient.kcal, .protein, .carbs, .sugar, .fat, .saturatedFat, .fiber], id: \.self) { nutrient in
            HStack {
              Text(nutrient.label)
              Spacer()
              TextField(
                "–", value: Binding(get: { item.per100g[nutrient] }, set: { item.per100g[nutrient] = $0 }),
                format: .number.precision(.fractionLength(0...1))
              )
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .frame(maxWidth: 90)
              Text(nutrient.unit).foregroundStyle(.secondary)
            }
          }
          if let warning = NutrientCheck.energyMismatch(item.per100g) {
            Label(warning, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
          }
        } header: {
          Text("Nährwerte je 100 \(item.isDrink ? "ml" : "g")")
        } footer: {
          Text("„–“ = unbekannt; zählt in der Summe nicht mit. Quelle: \(item.source.rawValue).")
        }
      }
      .navigationTitle(item.name.isEmpty ? "Position" : item.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
      .onAppear {
        portionName = item.portion?.name ?? ""
        portionGrams = item.portion?.grams
      }
    }
    .presentationDetents([.large])
  }
}
