import CoachCore
import SwiftData
import SwiftUI

/// Rezeptideen für die kommende Woche, passend zu Trainingstagen, Zielen und Ernährungsweise.
struct RecipesView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \FoodRecord.useCount, order: .reverse) private var foods: [FoodRecord]
  @State private var viewModel = RecipeViewModel()
  @State private var showPreferences = false

  private var refreshKey: String {
    let settings = model.settings
    return "\(meals.count)-\(settings.profile.hashValue)-\(settings.planAdjustments.hashValue)-"
      + "\(settings.nutrition.goal.rawValue)-\(settings.nutrition.diet.rawValue)"
  }

  var body: some View {
    let plan = viewModel.plan
    List {
      Section {
        if let first = viewModel.targets.first, let last = viewModel.targets.last {
          Text("Woche \(Formatters.shortDate(first.day)) – \(Formatters.shortDate(last.day))").font(.headline)
        }
        Text(
          "Die App berechnet für jeden Tag Energie, Protein und Kohlenhydrate aus deinem Wochenplan und deinem Ziel. "
            + "Die KI schlägt Gerichte vor; die App prüft Ernährungsweise und Allergene und passt die Mengen an."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        Button(plan == nil ? "Rezeptideen erstellen" : "Neu erstellen", systemImage: "sparkles") {
          Task {
            await viewModel.generate(ai: model.ai, settings: model.settings, favorites: foods.prefix(15).map(\.name))
          }
        }
        .disabled(viewModel.isWorking)
        Button("Wünsche und Allergene", systemImage: "slider.horizontal.3") { showPreferences = true }
        if let error = viewModel.errorMessage {
          Text(error).font(.footnote).foregroundStyle(.red)
        }
      }

      if !viewModel.gaps.isEmpty {
        Section {
          ForEach(viewModel.gaps, id: \.self) { Text($0).font(.subheadline) }
        } header: {
          Text("Wird gezielt ausgeglichen")
        } footer: {
          Text("Aus deinen erfassten Mahlzeiten der letzten 14 Tage (unter 80 % des Ziels).")
        }
      }

      if let plan {
        if !plan.notes.isEmpty {
          Section("Prüfung") {
            ForEach(plan.notes, id: \.self) { Label($0, systemImage: "checkmark.shield").font(.footnote) }
          }
        }
        ForEach(viewModel.targets) { target in
          RecipeDaySection(target: target, day: plan.day(target.day)) { recipe in
            viewModel.log(recipe, context: context)
          }
        }
        Section {
          NavigationLink {
            ShoppingListView(viewModel: viewModel, servings: model.settings.recipes.servings)
          } label: {
            Label("Einkaufsliste", systemImage: "cart")
          }
        } footer: {
          Text("Quelle: \(plan.source). Nährwerte der Zutaten sind KI-Schätzungen wie bei der Mahlzeiten-Analyse.")
        }
      } else {
        ForEach(viewModel.targets) { target in
          Section(Formatters.day(target.day)) { TargetRow(target: target) }
        }
      }
      Section {
        EvidenceDisclosure(ruleIDs: RecipePlanner.evidence)
      }
    }
    .navigationTitle("Rezeptideen")
    .overlay {
      if viewModel.isWorking {
        ProgressView("Rezepte werden erstellt …")
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
      }
    }
    .task(id: refreshKey) {
      viewModel.update(settings: model.settings, garminProfile: model.sync.profile, meals: meals)
    }
    .sheet(isPresented: $showPreferences) { RecipePreferencesView() }
  }
}

private struct TargetRow: View {
  let target: RecipeDayTarget

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(target.sessions.isEmpty ? "Kein Training geplant" : target.sessions.joined(separator: " + "))
        .font(.subheadline)
      Text(
        "\(target.dayType.label) · Ziel \(Int(target.kcal)) kcal, \(Int(target.protein)) g Protein, "
          + "\(Int(target.carbs)) g KH"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

private struct RecipeDaySection: View {
  let target: RecipeDayTarget
  let day: RecipeDay?
  let log: (Recipe) -> Void

  var body: some View {
    Section {
      TargetRow(target: target)
      if let day {
        ForEach(day.recipes) { recipe in
          NavigationLink {
            RecipeDetailView(recipe: recipe, log: log)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(recipe.title).font(.headline)
              Text(
                "\(recipe.meal.label) · \(recipe.minutes) min · \(Int((recipe.totals[.kcal] ?? 0).rounded())) kcal · "
                  + "\(Int((recipe.totals[.protein] ?? 0).rounded())) g Protein"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }
        }
        let totals = day.totals
        Text(
          "Summe: \(Int((totals[.kcal] ?? 0).rounded())) kcal, \(Int((totals[.protein] ?? 0).rounded())) g Protein"
            + (day.scale == 1 ? "" : " · Mengen ×\(GermanFormat.number(day.scale))")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("Für diesen Tag gibt es keine passenden Rezepte.").font(.footnote).foregroundStyle(.secondary)
      }
    } header: {
      Text(Formatters.day(target.day))
    }
  }
}

struct RecipeDetailView: View {
  let recipe: Recipe
  let log: (Recipe) -> Void
  @Query(sort: \FoodRecord.useCount, order: .reverse) private var foods: [FoodRecord]
  @State private var nutrition = NutritionViewModel()
  @State private var logged = false

  var body: some View {
    let totals = recipe.totals
    List {
      Section {
        LabeledContent("Mahlzeit", value: recipe.meal.label)
        LabeledContent("Zubereitung", value: "\(recipe.minutes) min")
        LabeledContent("Energie", value: "\(Int((totals[.kcal] ?? 0).rounded())) kcal")
        LabeledContent(
          "Protein · KH · Fett",
          value: [Nutrient.protein, .carbs, .fat].map { "\(Int((totals[$0] ?? 0).rounded())) g" }
            .joined(separator: " · "))
        if let fiber = totals[.fiber] {
          LabeledContent("Ballaststoffe", value: "\(Int(fiber.rounded())) g")
        }
      }
      Section("Zutaten (1 Person)") {
        ForEach(recipe.ingredients) { item in
          LabeledContent(item.name, value: "\(GermanFormat.number(item.grams)) g")
        }
      }
      if !recipe.steps.isEmpty {
        Section("Zubereitung") {
          ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
            HStack(alignment: .top, spacing: 10) {
              Text("\(index + 1)").font(.caption.bold()).frame(width: 18, height: 18)
                .background(Color.accentColor.opacity(0.15), in: Circle())
              Text(step).font(.subheadline)
            }
          }
        }
      }
      Section {
        // Erst prüfen: Portion, Zutaten tauschen, Zeitpunkt – nichts landet ungefragt im Tagebuch.
        Button(logged ? "Eingetragen" : "Als Mahlzeit eintragen …", systemImage: logged ? "checkmark" : "plus") {
          nutrition.draft = NutritionViewModel.Draft(
            title: recipe.title, category: NutritionViewModel.category(at: .now),
            hint: "Aus Rezeptidee (Nährwerte KI-geschätzt)", items: recipe.ingredients)
        }
      } footer: {
        Text("Öffnet den Entwurf: Menge (½, 2 Portionen), Zutaten und Zeitpunkt anpassen, dann speichern.")
      }
    }
    .navigationTitle(recipe.title)
    .sheet(
      item: $nutrition.draft,
      onDismiss: {
        if nutrition.lastSaved != nil { logged = true }
      }
    ) { draft in
      MealEditor(draft: draft, viewModel: nutrition, foods: foods)
    }
  }
}

struct ShoppingListView: View {
  let viewModel: RecipeViewModel
  let servings: Int

  var body: some View {
    let items = viewModel.plan.map { RecipePlanner.shoppingList($0, servings: servings) } ?? []
    List {
      Section {
        ForEach(items) { item in
          Button {
            viewModel.toggle(item)
          } label: {
            HStack {
              Image(systemName: viewModel.checked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(viewModel.checked.contains(item.id) ? .green : .secondary)
              Text(item.name).strikethrough(viewModel.checked.contains(item.id))
              Spacer()
              Text(amount(item.grams)).foregroundStyle(.secondary).monospacedDigit()
            }
          }
          .foregroundStyle(.primary)
        }
      } footer: {
        Text("Mengen für \(servings) \(servings == 1 ? "Person" : "Personen"), roh bzw. wie eingekauft.")
      }
    }
    .navigationTitle("Einkaufsliste")
    .toolbar {
      ShareLink(
        item: items.map { "\($0.name): \(amount($0.grams))" }.joined(separator: "\n"),
        subject: Text("Einkaufsliste"))
    }
  }

  private func amount(_ grams: Double) -> String {
    grams >= 1000 ? "\(GermanFormat.number((grams / 100).rounded() / 10)) kg" : "\(Int(grams)) g"
  }
}

struct RecipePreferencesView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    @Bindable var settings = model.settings
    NavigationStack {
      Form {
        Section {
          Picker("Ernährungsweise", selection: $settings.nutrition.diet) {
            ForEach(Diet.allCases, id: \.self) { Text($0.label).tag($0) }
          }
        }
        Section("Allergene und Unverträglichkeiten") {
          ForEach(Allergen.allCases) { allergen in
            Toggle(
              allergen.label,
              isOn: Binding(
                get: { settings.recipes.allergens.contains(allergen) },
                set: { on in
                  if on {
                    settings.recipes.allergens.insert(allergen)
                  } else {
                    settings.recipes.allergens.remove(allergen)
                  }
                }))
          }
        }
        Section {
          TextField("Mag ich nicht, z. B. Pilze, Koriander", text: $settings.recipes.dislikes, axis: .vertical)
          Stepper(
            "Höchstens \(settings.recipes.maxMinutes) min Zubereitung", value: $settings.recipes.maxMinutes,
            in: 10...90, step: 5)
          Toggle("Snack pro Tag", isOn: $settings.recipes.snacks)
          Toggle("Abends für den nächsten Mittag mitkochen", isOn: $settings.recipes.mealPrep)
          let people = settings.recipes.servings == 1 ? "Person" : "Personen"
          Stepper("Einkauf für \(settings.recipes.servings) \(people)", value: $settings.recipes.servings, in: 1...6)
        } header: {
          Text("Wünsche")
        } footer: {
          Text(
            "Allergene prüft die App bei jeder Zutat noch einmal selbst und verwirft unpassende Rezepte. Bei einer "
              + "ernsten Allergie trotzdem jede Zutat selbst kontrollieren.")
        }
      }
      .navigationTitle("Rezept-Wünsche")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
    }
  }
}
