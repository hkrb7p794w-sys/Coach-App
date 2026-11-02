import CoachCore
import SwiftUI

/// Was beim Erfassen sofort bereitsteht: zuletzt, häufig, Rezepte, Favoriten. „+“ trägt mit einem Tipp ein
/// (mit Rückgängig), Antippen öffnet den Entwurf zum Anpassen. Eintragen legt immer eine Kopie an – Rezepte und
/// Favoriten bleiben unverändert.
struct CaptureShortcuts {
  var recent: [MealEntry] = []
  var frequent: [MealSuggestions.Suggestion] = []
  var recipes: [OwnRecipe] = []
  var favorites: [FavoriteMeal] = []
  /// Sofort eintragen.
  var log: (String, [MealItem]) -> Void = { _, _ in }
  /// Im Entwurf öffnen.
  var open: (String, [MealItem]) -> Void = { _, _ in }
  var logRecipe: (OwnRecipe) -> Void = { _ in }

  var isEmpty: Bool { recent.isEmpty && frequent.isEmpty && recipes.isEmpty && favorites.isEmpty }
}

struct CaptureShortcutsSection: View {
  enum Tab: String, CaseIterable {
    case recent = "Zuletzt"
    case frequent = "Häufig"
    case recipes = "Rezepte"
    case favorites = "Favoriten"
  }

  let shortcuts: CaptureShortcuts
  let done: () -> Void
  @State private var tab: Tab?

  var body: some View {
    if !shortcuts.isEmpty {
      let current = tab ?? firstTab
      Section {
        Picker("Auswahl", selection: Binding(get: { current }, set: { tab = $0 })) {
          ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        switch current {
        case .recent:
          rows(shortcuts.recent.map { ($0.title, $0.items) }, empty: "Noch nichts erfasst.")
        case .frequent:
          rows(shortcuts.frequent.map { ($0.title, $0.items) }, empty: "Erscheint, sobald du etwas öfter isst.")
        case .recipes:
          if shortcuts.recipes.isEmpty {
            Text("Noch keine Rezepte. Eine Mahlzeit lange drücken › „Als eigenes Rezept speichern“.")
              .foregroundStyle(.secondary)
          }
          ForEach(shortcuts.recipes) { recipe in
            ShortcutRow(
              title: recipe.name, subtitle: "Rezept · 1 Portion · \(kcal([recipe.item()])) kcal",
              add: {
                shortcuts.logRecipe(recipe)
                done()
              },
              open: {
                shortcuts.open(recipe.name, [recipe.item()])
                done()
              })
          }
        case .favorites:
          if shortcuts.favorites.isEmpty {
            Text("Noch keine Favoriten. Eine Mahlzeit lange drücken › „Als Favorit merken“.")
              .foregroundStyle(.secondary)
          }
          rows(shortcuts.favorites.map { ($0.title, $0.items) }, empty: nil)
        }
      } header: {
        Text("Schnell wieder eintragen")
      } footer: {
        Text("„+“ trägt sofort ein, Antippen öffnet die Mahlzeit zum Anpassen.")
      }
    }
  }

  private var firstTab: Tab {
    if !shortcuts.recent.isEmpty { return .recent }
    if !shortcuts.favorites.isEmpty { return .favorites }
    if !shortcuts.recipes.isEmpty { return .recipes }
    return .frequent
  }

  @ViewBuilder private func rows(_ meals: [(String, [MealItem])], empty: String?) -> some View {
    if meals.isEmpty, let empty {
      Text(empty).foregroundStyle(.secondary)
    }
    ForEach(Array(meals.enumerated()), id: \.offset) { _, meal in
      ShortcutRow(
        title: meal.0,
        subtitle: "\(GermanFormat.number(meal.1.reduce(0) { $0 + $1.grams }.rounded())) g · "
          + "\(kcal(meal.1)) kcal",
        add: {
          shortcuts.log(meal.0, meal.1)
          done()
        },
        open: {
          shortcuts.open(meal.0, meal.1)
          done()
        })
    }
  }

  private func kcal(_ items: [MealItem]) -> Int {
    Int((NutritionSummary.totals(items)[.kcal] ?? 0).rounded())
  }
}

private struct ShortcutRow: View {
  let title: String
  let subtitle: String
  let add: () -> Void
  let open: () -> Void

  var body: some View {
    HStack {
      Button(action: open) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).lineLimit(2)
          Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      Button(action: add) {
        Image(systemName: "plus.circle.fill").font(.title).frame(width: 48, height: 48)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("\(title) eintragen")
    }
  }
}

/// Gegessene Menge eines Eintrags anpassen: 25/50/75/100 % oder frei; rechnet immer von der ursprünglichen Menge.
struct EatenAmountSection: View {
  @Binding var items: [MealItem]

  var body: some View {
    let fraction = MealPortion.eatenFraction(items)
    Section {
      HStack(spacing: 8) {
        ForEach(MealPortion.presets, id: \.self) { preset in
          Button("\(Int(preset * 100)) %") { items = MealPortion.adjusted(items, to: preset) }
            .buttonStyle(.bordered)
            .tint(abs(fraction - preset) < 0.005 ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
        }
      }
      Slider(
        value: Binding(get: { fraction }, set: { items = MealPortion.adjusted(items, to: ($0 * 20).rounded() / 20) }),
        in: 0.05...1.5, step: 0.05
      ) {
        Text("Gegessen")
      }
    } header: {
      Text("Gegessen: \(MealPortion.label(items))")
    } footer: {
      Text(
        "Kalorien und Nährwerte passen sich anteilig an. Nur dieser Eintrag ändert sich – Rezepte und Favoriten "
          + "bleiben, wie sie sind.")
    }
  }
}

/// „Fehlt etwas?“ im Entwurf: per Text oder über Hinweise auf oft Übersehenes ergänzen. Die KI liefert nur neue
/// Positionen, die angehängt werden; bestehende bleiben, wie sie sind, und lassen sich weiter bearbeiten.
struct AmendSection: View {
  @Binding var draft: NutritionViewModel.Draft
  let viewModel: NutritionViewModel
  let foods: [FoodRecord]
  @Environment(AppModel.self) private var model
  @State private var text = ""
  @State private var isWorking = false
  @State private var note: String?

  var body: some View {
    Section {
      TextField("z. B. noch 150 g Hähnchenbrust und 1 EL Olivenöl", text: $text, axis: .vertical)
        .lineLimit(1...4)
      if !draft.possiblyMissing.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(draft.possiblyMissing, id: \.self) { hint in
              Button("+ \(hint)") { text = text.isEmpty ? hint : "\(text), \(hint)" }
                .buttonStyle(.bordered)
            }
          }
        }
      }
      Button {
        Task { await amend() }
      } label: {
        Label(isWorking ? "Wird ergänzt …" : "Per KI ergänzen", systemImage: "sparkles")
      }
      .disabled(isWorking || text.trimmingCharacters(in: .whitespaces).isEmpty)
      if let note {
        Text(note).font(.footnote).foregroundStyle(.secondary)
      }
    } header: {
      Text("Fehlt etwas?")
    } footer: {
      Text(
        "Ergänzungen kommen als neue Positionen dazu – nichts Bestehendes wird überschrieben. Mengen und Nährwerte "
          + "der KI sind Schätzungen; prüfe sie oder ändere sie durch Antippen.")
    }
  }

  private func amend() async {
    isWorking = true
    defer { isWorking = false }
    guard
      let result = await viewModel.amend(
        draft.items, with: text, photo: draft.photo, ai: model.ai, settings: model.settings, foods: foods)
    else {
      note = viewModel.errorMessage
      return
    }
    if result.items.isEmpty {
      note = result.hint.isEmpty ? "Nichts zu ergänzen erkannt – bitte genauer beschreiben." : result.hint
      return
    }
    draft.items.append(contentsOf: result.items)
    let kcal = Int((NutritionSummary.totals(result.items)[.kcal] ?? 0).rounded())
    note = "Ergänzt: \(result.items.map(\.name).joined(separator: ", ")) (\(kcal) kcal, geschätzt)."
      + (result.hint.isEmpty ? "" : " \(result.hint)")
    let added = Set(result.items.map { FoodSearch.normalized($0.name) })
    draft.possiblyMissing.removeAll { hint in added.contains { $0.contains(FoodSearch.normalized(hint)) } }
    text = ""
  }
}
