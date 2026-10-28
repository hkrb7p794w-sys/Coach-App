import Charts
import CoachCore
import SwiftUI

/// „Was esse ich jetzt?“: drei Ideen zu den übrigen Makros, auf Wunsch mit dem Vorrat aus der Einkaufsliste.
struct MealNowSheet: View {
  let viewModel: NutritionViewModel
  let pantry: [String]
  let take: (Recipe) -> Void
  let generate: () async -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          if let targets = viewModel.targets {
            let rest = [Nutrient.kcal, .protein, .carbs, .fat].map { nutrient -> String in
              let value = max(0, (targets.values[nutrient] ?? 0) - (viewModel.totals[nutrient] ?? 0))
              return "\(Int(value.rounded())) \(nutrient.unit) \(nutrient == .kcal ? "" : nutrient.label)"
            }
            Text("Noch übrig: " + rest.joined(separator: " · ")).font(.subheadline)
          }
          Text(
            pantry.isEmpty
              ? "Tipp: In der Einkaufsliste „Habe ich da“ abhaken – dann kocht die KI mit deinem Vorrat."
              : "Vorrat: \(pantry.prefix(8).joined(separator: ", "))"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          Button(viewModel.nowSuggestions.isEmpty ? "Ideen holen" : "Neue Ideen", systemImage: "sparkles") {
            Task { await generate() }
          }
          .disabled(viewModel.isWorking)
          if viewModel.isWorking { ProgressView() }
        }
        ForEach(viewModel.nowSuggestions) { recipe in
          Section {
            VStack(alignment: .leading, spacing: 4) {
              Text(recipe.title).font(.headline)
              Text(
                "\(recipe.minutes) min · \(Int((recipe.totals[.kcal] ?? 0).rounded())) kcal · "
                  + "\(Int((recipe.totals[.protein] ?? 0).rounded())) g Protein"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              let list = recipe.ingredients.map { "\(GermanFormat.number($0.grams)) g \($0.name)" }
              Text(list.joined(separator: ", ")).font(.footnote)
            }
            Button("Übernehmen und prüfen", systemImage: "plus.circle.fill") { take(recipe) }
              .bold()
          }
        }
        if !viewModel.nowNotes.isEmpty {
          Section {
            ForEach(viewModel.nowNotes, id: \.self) { Label($0, systemImage: "checkmark.shield").font(.footnote) }
          } footer: {
            Text("Ernährungsweise und Allergene prüft die App selbst; Mengen sind auf dein Ziel skaliert.")
          }
        }
      }
      .navigationTitle("Was jetzt?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
      }
      .task {
        if viewModel.nowSuggestions.isEmpty { await generate() }
      }
    }
  }
}

/// Eigene Rezepte mit Portionen und Vorrat (Meal-Prep): einmal kochen, mehrere Tage eintragen.
struct OwnRecipesView: View {
  let log: (OwnRecipe, Double?) -> Void
  @Environment(AppModel.self) private var model
  @State private var editing: OwnRecipe?
  @State private var logging: OwnRecipe?

  var body: some View {
    let recipes = model.settings.ownRecipes
    List {
      if recipes.isEmpty {
        ContentUnavailableView(
          "Noch keine eigenen Rezepte", systemImage: "fork.knife",
          description: Text("Eine Mahlzeit gedrückt halten › „Als eigenes Rezept speichern“."))
      }
      ForEach(recipes) { recipe in
        Button {
          logging = recipe
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name).font(.headline)
            let portion = recipe.item()
            Text(
              "\(recipe.portions) Portionen à \(GermanFormat.number(portion.grams.rounded())) g · "
                + "\(Int((portion.amounts[.kcal] ?? 0).rounded())) kcal"
                + (recipe.remainingPortions.map { " · noch \(PortionGuess.format($0))" } ?? "")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.plain)
        .swipeActions {
          Button("Löschen", role: .destructive) {
            model.settings.ownRecipes.removeAll { $0.id == recipe.id }
          }
          Button("Bearbeiten") { editing = recipe }.tint(.blue)
        }
      }
    }
    .navigationTitle("Eigene Rezepte")
    .sheet(item: $editing) { recipe in
      OwnRecipeEditor(recipe: recipe) { updated in
        if let index = model.settings.ownRecipes.firstIndex(where: { $0.id == updated.id }) {
          model.settings.ownRecipes[index] = updated
        }
      }
    }
    .sheet(item: $logging) { recipe in
      LogOwnRecipeSheet(recipe: recipe) { grams in log(recipe, grams) }
    }
  }
}

/// Portionen, gekochtes Gewicht und „Neu gekocht“ (Vorrat auffüllen).
private struct OwnRecipeEditor: View {
  @State var recipe: OwnRecipe
  let save: (OwnRecipe) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $recipe.name)
          Stepper("\(recipe.portions) Portionen", value: $recipe.portions, in: 1...20)
          HStack {
            Text("Gekocht gewogen")
            Spacer()
            TextField("optional", value: $recipe.cookedGrams, format: .number.precision(.fractionLength(0)))
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
              .frame(maxWidth: 100)
            Text("g").foregroundStyle(.secondary)
          }
        } footer: {
          let raw = GermanFormat.number(recipe.ingredients.reduce(0) { $0 + $1.grams }.rounded())
          Text(
            "Ohne gekochtes Gewicht zählt die Summe der Zutaten (\(raw) g). Gewogen ist genauer: Beim Kochen "
              + "verdunstet Wasser.")
        }
        Section {
          Button("Neu gekocht – \(recipe.portions) Portionen im Vorrat", systemImage: "frying.pan") {
            recipe.remainingPortions = Double(recipe.portions)
          }
          if let remaining = recipe.remainingPortions {
            LabeledContent("Vorrat", value: "\(PortionGuess.format(remaining)) Portionen")
            Button("Vorrat leeren", role: .destructive) { recipe.remainingPortions = nil }
          }
        }
        Section("Zutaten (ganzer Topf)") {
          ForEach(recipe.ingredients) { item in
            LabeledContent(item.name, value: item.amountLabel)
          }
          .onDelete { recipe.ingredients.remove(atOffsets: $0) }
        }
      }
      .navigationTitle("Rezept")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") {
            save(recipe)
            dismiss()
          }
          .disabled(recipe.name.trimmingCharacters(in: .whitespaces).isEmpty || recipe.ingredients.isEmpty)
        }
      }
    }
  }
}

/// Eine Portion oder eine gewogene Menge vom Topf eintragen.
private struct LogOwnRecipeSheet: View {
  let recipe: OwnRecipe
  let log: (Double?) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var grams: Double?

  var body: some View {
    let portion = recipe.item()
    NavigationStack {
      Form {
        Section {
          HStack {
            ForEach(PortionGuess.quickCounts, id: \.self) { count in
              Button(PortionGuess.format(count)) {
                log(portion.grams * count)
                dismiss()
              }
              .buttonStyle(.bordered)
              .frame(maxWidth: .infinity)
            }
          }
        } header: {
          Text("Portionen à \(GermanFormat.number(portion.grams.rounded())) g")
        }
        Section {
          HStack {
            TextField("Gramm vom Topf", value: $grams, format: .number.precision(.fractionLength(0)))
              .keyboardType(.numberPad)
            Text("g").foregroundStyle(.secondary)
            Button("Eintragen") {
              log(grams)
              dismiss()
            }
            .disabled((grams ?? 0) <= 0)
          }
        } header: {
          Text("Oder gewogen")
        }
      }
      .navigationTitle(recipe.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
    }
    .presentationDetents([.medium])
  }
}

/// Woche: Energie je Tag gegen das Ziel, Protein im Schnitt, Trainingstage, Gewichtstrend – und die KI-Auswertung.
struct NutritionWeekView<Review: View>: View {
  let summary: NutritionWeek.Summary
  let weights: [WeightEntry]
  let goal: NutritionGoal
  @ViewBuilder let review: () -> Review

  var body: some View {
    List {
      Section {
        Chart {
          ForEach(summary.days) { day in
            BarMark(x: .value("Tag", Weekday(day: day.day).short), y: .value("kcal", day.kilocalories))
              .foregroundStyle(day.trained ? Color.orange : Color.accentColor)
            if let target = day.targetKilocalories {
              PointMark(x: .value("Tag", Weekday(day: day.day).short), y: .value("Ziel", target))
                .symbol(.diamond)
                .foregroundStyle(.secondary)
            }
          }
        }
        .frame(height: 180)
        .accessibilityLabel("Kalorien je Tag, Raute = Ziel, orange = Trainingstag")
        if let average = summary.averageKilocalories {
          let target = summary.averageTargetKilocalories.map { " / \(Int($0))" } ?? ""
          LabeledContent("Schnitt", value: "\(Int(average)) kcal\(target)")
        }
        if let protein = summary.averageProtein {
          LabeledContent("Protein im Schnitt", value: "\(Int(protein)) g")
        }
      } header: {
        Text("Diese Woche")
      } footer: {
        Text("Nur Tage mit Einträgen zählen für den Schnitt. Orange = Trainingstag, Raute = Tagesziel.")
      }
      if let trend = WeightTrend.trend(weights, today: CalendarDay(date: .now)) {
        Section("Gewicht") {
          LabeledContent("Trend", value: "\(GermanFormat.decimal(trend.weeklyPercent)) % pro Woche")
          if let note = paceNote(trend.weeklyPercent) {
            Label(note, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
          }
        }
      }
      review()
    }
    .navigationTitle("Woche")
  }

  /// Ampel aus den Schutzgrenzen: zu schnell abnehmen ist nicht nachhaltig.
  private func paceNote(_ percent: Double) -> String? {
    if goal == .lose, percent < -GoalRules.maxLossPercentPerWeek {
      return "Du nimmst schneller ab als 1 % pro Woche – etwas mehr essen, damit es nachhaltig bleibt."
    }
    if goal == .lose, percent > 0 {
      return "Das Gewicht steigt trotz Ziel Abnehmen – Einträge und Portionen prüfen."
    }
    if goal == .gain, percent > GoalRules.maxGainPercentPerWeek {
      return "Du nimmst schneller zu als geplant – Überschuss etwas verringern."
    }
    return nil
  }
}
