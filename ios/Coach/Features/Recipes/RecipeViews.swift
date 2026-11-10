import CoachCore
import SwiftData
import SwiftUI

/// Rezeptideen für einen frei gewählten Zeitraum, passend zu Zielen und Ernährungsweise; dazu die Einkaufsliste.
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
      + "\(settings.nutrition.goal.rawValue)-\(settings.nutrition.diet.rawValue)-"
      + "\(viewModel.start.iso)-\(viewModel.length)"
  }

  var body: some View {
    let plan = viewModel.plan
    List {
      Section {
        NavigationLink {
          CookPlanView(viewModel: viewModel, favorites: foods.prefix(10).map(\.name))
        } label: {
          Label("Kochen planen: für wen, wie viel", systemImage: "person.2")
        }
      } footer: {
        Text("Für dich, eine verbundene Person oder euch beide; auch zum Vorkochen für mehrere Tage.")
      }
      Section {
        DatePicker(
          "Ab",
          selection: Binding(
            get: { viewModel.start.localDate },
            set: { viewModel.setPeriod(start: CalendarDay(date: $0), days: viewModel.length) }),
          in: Date.now...Date.now.addingTimeInterval(60 * 24 * 3600), displayedComponents: .date)
        Stepper(
          "\(viewModel.length) \(viewModel.length == 1 ? "Tag" : "Tage")",
          value: Binding(
            get: { viewModel.length }, set: { viewModel.setPeriod(start: viewModel.start, days: $0) }),
          in: 1...RecipePlanner.maxPeriodDays)
        if let first = viewModel.targets.first, let last = viewModel.targets.last {
          Text(
            first.day == last.day
              ? Formatters.day(first.day) : "\(Formatters.shortDate(first.day)) – \(Formatters.shortDate(last.day))"
          )
          .font(.headline)
          Text(
            "Ziel je Tag: \(Int(first.kcal)) kcal, \(Int(first.protein)) g Protein, \(Int(first.carbs)) g KH – der "
              + "Durchschnitt deiner Woche, an jedem Tag gleich. Die KI schlägt Gerichte vor; die App prüft "
              + "Ernährungsweise und Allergene und passt die Mengen an."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
        Button(plan == nil ? "Rezeptideen erstellen" : "Neu erstellen", systemImage: "sparkles") {
          Task {
            await viewModel.generate(ai: model.ai, settings: model.settings, favorites: foods.prefix(15).map(\.name))
          }
        }
        .disabled(viewModel.isWorking)
        if plan != nil, !viewModel.missing.isEmpty {
          Button("Fehlende Tage erstellen (\(viewModel.missing.count))", systemImage: "plus.circle") {
            Task {
              await viewModel.generate(
                ai: model.ai, settings: model.settings, favorites: foods.prefix(15).map(\.name), missingOnly: true)
            }
          }
          .disabled(viewModel.isWorking)
        }
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
            Label("Einkaufsliste für den Zeitraum", systemImage: "cart")
          }
        } footer: {
          Text("Quelle: \(plan.source). Nährwerte der Zutaten sind KI-Schätzungen wie bei der Mahlzeiten-Analyse.")
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

private struct RecipeDaySection: View {
  let target: RecipeDayTarget
  let day: RecipeDay?
  let log: (Recipe) -> Void

  var body: some View {
    Section {
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
        Text("Für diesen Tag gibt es noch keine Rezepte – oben „Fehlende Tage erstellen“.")
          .font(.footnote)
          .foregroundStyle(.secondary)
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
  @Environment(AppModel.self) private var model
  /// Gewählter Ausschnitt; `nil` = erster bzw. letzter Tag mit Rezepten.
  @State private var from: CalendarDay?
  @State private var to: CalendarDay?

  var body: some View {
    let days = (viewModel.plan?.days ?? []).filter { !$0.recipes.isEmpty }.map(\.day)
    let today = CalendarDay(date: .now)
    let first = from ?? days.first ?? today
    let last = max(to ?? days.last ?? first, first)
    let items = viewModel.plan.map { RecipePlanner.shoppingList($0, servings: servings, from: first, to: last) } ?? []
    let groups = Dictionary(grouping: items, by: \.aisle)
    List {
      if days.count > 1 {
        Section {
          Picker("Von", selection: Binding(get: { first }, set: { from = $0 })) {
            ForEach(days, id: \.self) { Text(Formatters.day($0)).tag($0) }
          }
          Picker("Bis", selection: Binding(get: { last }, set: { to = $0 })) {
            ForEach(days.filter { $0 >= first }, id: \.self) { Text(Formatters.day($0)).tag($0) }
          }
        } header: {
          Text("Zeitraum")
        } footer: {
          let count = days.filter { $0 >= first && $0 <= last }.count
          Text("Alle Rezepte von \(count) \(count == 1 ? "Tag" : "Tagen") zusammengeführt.")
        }
      }
      // Nach Supermarkt-Abteilung, damit man den Laden einmal durchläuft statt hin und her.
      ForEach(ShoppingAisle.allCases.filter { groups[$0] != nil }) { aisle in
        Section(aisle.label) {
          ForEach(groups[aisle] ?? []) { item in
            let checked = viewModel.checked.contains(item.id)
            Button {
              viewModel.toggle(item)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                  .font(.title2)
                  .foregroundStyle(checked ? .green : .secondary)
                Text(item.name).strikethrough(checked)
                Spacer()
                Text(amount(item.grams)).foregroundStyle(.secondary).monospacedDigit()
              }
              .frame(minHeight: 44)
              .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
            .swipeActions(edge: .leading) {
              let inPantry = model.settings.pantry.contains(item.name)
              Button(inPantry ? "Nicht mehr da" : "Habe ich da", systemImage: "archivebox") {
                togglePantry(item.name)
              }
              .tint(.teal)
            }
          }
        }
      }
      Section {
        if model.settings.pantry.isEmpty {
          Text("Zutat nach rechts wischen › „Habe ich da“. „Was jetzt?“ kocht dann bevorzugt mit deinem Vorrat.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.settings.pantry, id: \.self) { name in
            Text(name)
          }
          .onDelete { model.settings.pantry.remove(atOffsets: $0) }
        }
      } header: {
        Text("Vorrat")
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

  private func togglePantry(_ name: String) {
    if model.settings.pantry.contains(name) {
      model.settings.pantry.removeAll { $0 == name }
    } else {
      model.settings.pantry.append(name)
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
