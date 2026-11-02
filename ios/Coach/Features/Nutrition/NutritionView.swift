import CoachCore
import PhotosUI
import SwiftData
import SwiftUI

/// Ernährung des Tages: Ziele nach Training, Mahlzeiten, Erfassen per Foto, Text, Barcode oder manuell und die
/// gemeinsame KI-Auswertung von Ernährung und Training.
struct NutritionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.modelContext) private var context
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \FoodRecord.useCount, order: .reverse) private var foods: [FoodRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @State private var viewModel = NutritionViewModel()
  @State private var sheet: Sheet?
  @State private var query = ""
  @State private var showsNow = false
  @State private var showsDashboardEditor = false
  @State private var sharing: MealRecord?
  @State private var showsReceived = false
  @State private var savingRecipe: MealRecord?

  enum Sheet: String, Identifiable {
    case capture, barcode, quick
    var id: String { rawValue }
  }

  private var todaysMeals: [MealRecord] {
    meals.filter { $0.dayKey == viewModel.day.iso }
  }

  private var refreshKey: String {
    let settings = model.settings
    return "\(meals.count)-\(meals.last?.itemsPayload.count ?? 0)-\(activities.count)-"
      + "\(settings.season.hashValue)-\(settings.nutrition.goal.rawValue)-\(settings.nutrition.weightKilograms ?? 0)-"
      + "\(viewModel.day.iso)"
  }

  var body: some View {
    NavigationStack {
      List {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
          searchResults
        } else {
          Section {
            DayStrip(selected: viewModel.day, today: viewModel.today) { day in
              viewModel.selectedDay = day == viewModel.today ? nil : day
            }
          }
          if !viewModel.pending.isEmpty {
            pendingSection
          }
          // Karten in der gewählten Reihenfolge („Übersicht anpassen“).
          ForEach(model.settings.nutritionDashboard.visible) { card in
            dashboardCard(card)
          }
        }
        // Auswertung tagsüber nur in der Woche; abends (ab 18 Uhr) auch hier.
        if Calendar.current.component(.hour, from: .now) >= 18 || !viewModel.reviewPoints.isEmpty {
          reviewSection
        }
        Section {
          Button("Übersicht anpassen", systemImage: "slider.horizontal.3") { showsDashboardEditor = true }
          if model.ai.isConfigured {
            Button("Geteilte Mahlzeit öffnen", systemImage: "tray.and.arrow.down") { showsReceived = true }
          }
          NavigationLink {
            NutritionWeekView(summary: weekSummary, weights: model.allWeights, goal: model.settings.nutrition.goal) {
              reviewSection
            }
          } label: {
            Label("Woche und Auswertung", systemImage: "calendar")
          }
          NavigationLink {
            OwnRecipesView { recipe, grams in logOwnRecipe(recipe, grams: grams) }
          } label: {
            Label("Eigene Rezepte und Meal-Prep", systemImage: "fork.knife")
          }
          NavigationLink {
            WeightTrendView()
          } label: {
            Label("Gewichtsverlauf", systemImage: "scalemass")
          }
          NavigationLink {
            RecipesView()
          } label: {
            Label("Rezeptideen für die kommende Woche", systemImage: "frying.pan")
          }
        }
      }
      .navigationTitle(viewModel.day == viewModel.today ? "Ernährung" : Formatters.day(viewModel.day))
      .searchable(text: $query, prompt: "Lebensmittel oder Mahlzeit suchen")
      .safeAreaInset(edge: .bottom) { bottomBar }
      .overlay {
        if viewModel.isWorking {
          ProgressView("Wird ausgewertet …")
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
      }
      // Neue oder gelöschte Mahlzeit: Erinnerungen neu planen (keine Mitteilung für schon Erfasstes).
      .onChange(of: meals.count) { Task { await model.refreshReminders() } }
      .task(id: refreshKey) {
        refresh()
        await viewModel.retryPending(ai: model.ai, settings: model.settings, foods: foods)
      }
      // Schnellaktion / Kurzbefehl „Mahlzeit erfassen“.
      .onChange(of: AppRouter.shared.pending, initial: true) {
        let mealCategory = AppRouter.shared.pending?.mealCategory
        guard AppRouter.shared.take(.logMeal) else { return }
        viewModel.preferredCategory = mealCategory
        query = ""
        viewModel.selectedDay = nil
        sheet = .capture
      }
      .sheet(isPresented: $showsDashboardEditor) { NutritionDashboardEditor() }
      .sheet(item: $sharing) { meal in ShareMealSheet(title: meal.title, items: meal.items) }
      .sheet(isPresented: $showsReceived) { ReceivedMealSheet(code: nil) }
      .sheet(isPresented: $showsNow) {
        MealNowSheet(viewModel: viewModel, pantry: model.settings.pantry) { recipe in
          showsNow = false
          Task {
            try? await Task.sleep(for: .milliseconds(450))
            viewModel.draft(from: recipe)
          }
        } generate: {
          await viewModel.suggestNow(ai: model.ai, settings: model.settings, foods: foods)
        }
      }
      .alert(
        "Als eigenes Rezept speichern",
        isPresented: Binding(get: { savingRecipe != nil }, set: { if !$0 { savingRecipe = nil } })
      ) {
        Button("Speichern") {
          if let meal = savingRecipe {
            model.settings.ownRecipes.append(OwnRecipe.from(meal: meal.title, items: meal.items))
          }
        }
        Button("Abbrechen", role: .cancel) {}
      } message: {
        Text("Unter „Eigene Rezepte“ kannst du Portionen und gekochtes Gewicht für Meal-Prep festlegen.")
      }
      .sheet(item: $sheet) { sheet in
        switch sheet {
        case .capture:
          CaptureSheet(shortcuts: captureShortcuts) { text, photo in
            await viewModel.analyze(text: text, photo: photo, ai: model.ai, settings: model.settings, foods: foods)
          } other: { choice in
            switch choice {
            case .barcode: self.sheet = .barcode
            case .quick: self.sheet = .quick
            case .manual: viewModel.newManualDraft()
            }
          }
        case .barcode:
          BarcodeEntry { code in
            Task { await viewModel.lookup(barcode: code, foods: foods, context: context) }
          }
        case .quick:
          QuickEntrySheet { title, category, item in
            viewModel.log(title: title, category: category, items: [item], context: context, foods: foods)
          }
        }
      }
      .sheet(item: $viewModel.draft) { draft in
        MealEditor(draft: draft, viewModel: viewModel, foods: foods)
      }
      .sheet(
        isPresented: Binding(
          get: { viewModel.missingBarcode != nil }, set: { if !$0 { viewModel.missingBarcode = nil } })
      ) {
        if let barcode = viewModel.missingBarcode {
          MissingBarcodeSheet(barcode: barcode) {
            viewModel.draftForMissingBarcode(barcode)
          } photograph: { data in
            viewModel.missingBarcode = nil
            Task { await viewModel.readLabel(photo: data, barcode: barcode, ai: model.ai) }
          }
        }
      }
      .alert(
        "Hinweis",
        isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(viewModel.errorMessage ?? "")
      }
    }
  }

  private func refresh() {
    viewModel.update(
      meals: meals,
      activities: activities.compactMap(\.activity),
      settings: model.settings,
      profile: model.sync.profile,
      hasGarminData: !days.isEmpty
    )
  }

  // MARK: - Unten: Rückgängig und großes „+“ in Daumenreichweite

  private var bottomBar: some View {
    HStack(alignment: .bottom, spacing: 12) {
      undoBar
      Spacer(minLength: 0)
      Button {
        sheet = .capture
      } label: {
        Image(systemName: "plus")
          .font(.title.bold())
          .foregroundStyle(.white)
          .frame(width: 64, height: 64)
          .background(Color.accentColor, in: Circle())
          .shadow(radius: 4, y: 2)
      }
      .accessibilityLabel("Erfassen")
    }
    .padding(.horizontal)
    .padding(.bottom, 4)
  }

  private var pendingSection: some View {
    Section {
      ForEach(viewModel.pending) { item in
        HStack {
          Image(systemName: item.hasPhoto ? "photo" : "text.bubble")
          Text(item.text.isEmpty ? "Foto" : item.text).lineLimit(1)
          Spacer()
          Text(item.created, style: .time).font(.caption).foregroundStyle(.secondary)
        }
        .swipeActions {
          Button("Löschen", role: .destructive) { viewModel.removePending(item) }
        }
      }
      Button("Jetzt auswerten", systemImage: "arrow.clockwise") {
        Task { await viewModel.retryPending(ai: model.ai, settings: model.settings, foods: foods) }
      }
    } header: {
      Text("Wartet auf Netz")
    } footer: {
      Text("Ohne Netz gespeichert. Wird automatisch ausgewertet, sobald die App wieder online ist.")
    }
  }

  // MARK: - Eigene Rezepte und Woche

  /// Portion (oder Gramm) vom Topf eintragen und den Vorrat verringern.
  private func logOwnRecipe(_ recipe: OwnRecipe, grams: Double?) {
    let item = recipe.item(grams: grams)
    viewModel.log(
      title: recipe.name, category: NutritionViewModel.category(at: .now), items: [item], context: context,
      foods: foods)
    if let index = model.settings.ownRecipes.firstIndex(where: { $0.id == recipe.id }) {
      model.settings.ownRecipes[index].consume(grams: item.grams)
    }
  }

  private var weekSummary: NutritionWeek.Summary {
    let monday = viewModel.day.adding(days: -viewModel.day.weekdayIndex)
    let all = activities.compactMap(\.activity)
    var targets: [CalendarDay: NutrientValues] = [:]
    for offset in 0..<7 {
      let day = monday.adding(days: offset)
      targets[day] =
        NutritionViewModel.targets(
          for: day, activities: all, settings: model.settings, profile: model.sync.profile,
          hasGarminData: !days.isEmpty
        ).values
    }
    return NutritionWeek.summary(
      entries: NutritionViewModel.entries(meals), monday: monday, targets: targets,
      trainedDays: Set(all.compactMap(\.day)), today: viewModel.today)
  }

  /// Mahlzeiten nach Kategorie mit Summe je Kategorie; Wasser steht beim Wasser-Balken.
  @ViewBuilder private var mealsSection: some View {
    let shown = todaysMeals.filter { !$0.isWater }
    if shown.isEmpty {
      Section("Mahlzeiten") {
        Text("Noch nichts erfasst. Oben ein Vorschlag mit einem Tipp – oder über „+“ per Foto, Text oder Barcode.")
          .foregroundStyle(.secondary)
      }
    }
    ForEach(MealCategory.allCases, id: \.self) { category in
      let items = shown.filter { $0.category == category }
      if !items.isEmpty {
        Section {
          ForEach(items) { meal in
            Button {
              viewModel.edit(meal)
            } label: {
              MealRow(meal: meal)
            }
            .buttonStyle(.plain)
            .swipeActions {
              Button("Löschen", role: .destructive) { viewModel.delete(meal, context: context) }
            }
            .contextMenu {
              Button("Erneut eintragen", systemImage: "arrow.clockwise") {
                viewModel.repeatMeal(meal, context: context, foods: foods)
              }
              Menu("Verschieben nach", systemImage: "arrow.up.arrow.down") {
                ForEach(MealCategory.allCases.filter { $0 != meal.category }, id: \.self) { target in
                  Button(target.label) { viewModel.move(meal, to: target, context: context) }
                }
              }
              Button("Gegessene Menge anpassen", systemImage: "chart.pie") { viewModel.edit(meal) }
              favoriteButton(meal)
              if model.ai.isConfigured {
                Button("Teilen …", systemImage: "square.and.arrow.up") { sharing = meal }
              }
              Button("Als eigenes Rezept speichern", systemImage: "fork.knife") { savingRecipe = meal }
              Button("Löschen", systemImage: "trash", role: .destructive) { viewModel.delete(meal, context: context) }
            }
          }
        } header: {
          let kcal = NutritionSummary.totals(items.flatMap(\.items))[.kcal] ?? 0
          HStack {
            Text(category.label)
            Spacer()
            Text("\(Int(kcal.rounded())) kcal").monospacedDigit()
          }
        }
      }
    }
  }

  // MARK: - Karten

  @ViewBuilder private func dashboardCard(_ card: NutritionDashboard.Card) -> some View {
    switch card {
    case .budget:
      if let targets = viewModel.targets {
        BudgetSection(targets: targets, totals: viewModel.totals, water: waterCount, showsWater: false) { _ in }
      }
    case .summary:
      let shown = todaysMeals.filter { !$0.isWater }
      DaySummarySection(
        summary: NutritionDaySummary(
          eaten: viewModel.totals[.kcal] ?? 0, goal: viewModel.targets?.values[.kcal], meals: shown.count),
        totals: viewModel.totals, targets: viewModel.targets?.values)
    case .water:
      if let targets = viewModel.targets, targets.values[.water] != nil {
        BudgetSection(targets: targets, totals: viewModel.totals, water: waterCount, showsRing: false) { amount in
          logWater(amount)
        }
      }
    case .ideas:
      if viewModel.targets != nil, viewModel.day == viewModel.today {
        Section {
          Button("Was esse ich jetzt?", systemImage: "sparkles") { showsNow = true }
            .font(.headline)
        } footer: {
          Text("Drei Ideen passend zu dem, was heute noch übrig ist – gern mit deinem Vorrat.")
        }
      }
    case .quick:
      QuickSection(
        entries: NutritionViewModel.entries(meals), day: viewModel.day,
        category: NutritionViewModel.category(at: .now), ownRecipes: model.settings.ownRecipes
      ) { title, category, items, label in
        viewModel.log(title: title, category: category, items: items, context: context, foods: foods, label: label)
      } logRecipe: { recipe in
        logOwnRecipe(recipe, grams: nil)
      }
    case .meals:
      mealsSection
    case .nutrients:
      if let targets = viewModel.targets {
        TargetsSection(targets: targets, totals: viewModel.totals)
      }
    }
  }

  // MARK: - Schnell erfassen und Favoriten

  private var captureShortcuts: CaptureShortcuts {
    let entries = NutritionViewModel.entries(meals)
    let category = NutritionViewModel.category(at: .now)
    return CaptureShortcuts(
      recent: MealShortcuts.recent(entries), frequent: MealShortcuts.frequent(entries, today: viewModel.day),
      recipes: model.settings.ownRecipes, favorites: model.settings.favoriteMeals,
      log: { title, items in
        viewModel.log(
          title: title, category: category, items: items.map(MealPortion.restored), context: context, foods: foods)
      },
      open: { title, items in
        // Erst das Erfassen-Blatt schließen lassen (zwei Sheets gleichzeitig zeigt iOS nicht).
        Task {
          try? await Task.sleep(for: .milliseconds(450))
          viewModel.draft = NutritionViewModel.Draft(
            title: title, category: category, hint: "",
            items: items.map(MealPortion.restored).map { item in
              var copy = item
              copy.id = UUID()
              return copy
            })
        }
      },
      logRecipe: { recipe in logOwnRecipe(recipe, grams: nil) })
  }

  @ViewBuilder private func favoriteButton(_ meal: MealRecord) -> some View {
    if let favorite = MealShortcuts.favorite(for: meal.items, in: model.settings.favoriteMeals) {
      Button("Aus Favoriten entfernen", systemImage: "star.slash") {
        model.settings.favoriteMeals.removeAll { $0.id == favorite.id }
      }
    } else {
      Button("Als Favorit merken", systemImage: "star") {
        model.settings.favoriteMeals.append(FavoriteMeal(title: meal.title, items: meal.items, category: meal.category))
      }
    }
  }

  // MARK: - Suche

  /// Eigene Lebensmittel und frühere Mahlzeiten; Antippen öffnet den Entwurf, „+“ trägt sofort ein.
  @ViewBuilder private var searchResults: some View {
    let foodCandidates = foods.map {
      FoodSearch.Candidate(id: "food:\($0.key)", title: $0.name, useCount: $0.useCount, lastUsed: $0.lastUsed)
    }
    let entries = NutritionViewModel.entries(meals)
    let mealGroups = Dictionary(
      grouping: entries.filter { $0.items.count > 1 }, by: { FoodSearch.normalized($0.title) })
    let mealCandidates = mealGroups.compactMap { key, group -> FoodSearch.Candidate? in
      guard let last = group.max(by: { $0.date < $1.date }) else { return nil }
      return FoodSearch.Candidate(id: "meal:\(key)", title: last.title, useCount: group.count, lastUsed: last.date)
    }
    let foundFoods = FoodSearch.rank(foodCandidates, query: query)
    let foundMeals = FoodSearch.rank(mealCandidates, query: query, limit: 6)
    let foundBLS = query.count >= 3 ? BLS.search(query, limit: 8) : []
    if foundFoods.isEmpty && foundMeals.isEmpty && foundBLS.isEmpty {
      Section {
        Text("Nichts gefunden. Über „+“ beschreiben, fotografieren oder Barcode scannen.").foregroundStyle(.secondary)
      }
    }
    if !foundMeals.isEmpty {
      Section("Frühere Mahlzeiten") {
        ForEach(foundMeals) { candidate in
          if let meal = mealGroups[String(candidate.id.dropFirst(5))]?.max(by: { $0.date < $1.date }) {
            QuickRow(title: meal.title, detail: Self.summary(meal.items)) {
              let category = NutritionViewModel.category(at: .now)
              viewModel.log(title: meal.title, category: category, items: meal.items, context: context, foods: foods)
              query = ""
            }
          }
        }
      }
    }
    if !foundFoods.isEmpty {
      Section("Lebensmittel") {
        ForEach(foundFoods) { candidate in
          if let item = foods.first(where: { "food:\($0.key)" == candidate.id })?.item {
            QuickRow(title: item.name, detail: Self.summary([item])) {
              let category = NutritionViewModel.category(at: .now)
              viewModel.log(title: item.name, category: category, items: [item], context: context, foods: foods)
              query = ""
            } open: {
              viewModel.draft(with: item)
              query = ""
            }
          }
        }
      }
    }
    if !foundBLS.isEmpty {
      Section {
        ForEach(foundBLS) { food in
          QuickRow(title: food.name, detail: BLSRow.summary(food.per100g)) {
            viewModel.draft(with: food.item())
            query = ""
          }
        }
      } header: {
        Text("Bundeslebensmittelschlüssel")
      } footer: {
        Text("Öffnet den Entwurf mit 100 g. Quelle: \(BLS.attribution).")
      }
    }
  }

  static func summary(_ items: [MealItem]) -> String {
    let totals = NutritionSummary.totals(items)
    let grams = items.count == 1 ? "\(GermanFormat.number(items[0].grams)) \(items[0].isDrink ? "ml" : "g") · " : ""
    return "\(grams)\(Int((totals[.kcal] ?? 0).rounded())) kcal · \(Int((totals[.protein] ?? 0).rounded())) g Protein"
  }

  // MARK: - Wasser und Rückgängig

  /// Flüssigkeit des Tages: Getränke und Wasser aus Lebensmitteln (`Hydration`), nicht nur „Wasser“-Einträge.
  private var waterCount: Hydration.Total {
    Hydration.total(todaysMeals.flatMap(\.items))
  }

  private func logWater(_ milliliters: Double) {
    viewModel.log(
      title: "Wasser", category: NutritionViewModel.category(at: .now), items: [.water(milliliters: milliliters)],
      context: context, foods: [], label: "\(Int(milliliters)) ml Wasser")
  }

  @ViewBuilder private var undoBar: some View {
    if let last = viewModel.lastLogged {
      HStack {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text(last.label).font(.subheadline).lineLimit(1)
        Spacer()
        Button("Rückgängig") { viewModel.undoLastLog(context: context) }.bold()
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 48)
      .background(.regularMaterial, in: Capsule())
      .padding(.horizontal)
      .padding(.bottom, 4)
      .task(id: last.label) {
        try? await Task.sleep(for: .seconds(5))
        if !Task.isCancelled { viewModel.clearLastLogged() }
      }
    }
  }

  private var reviewSection: some View {
    Section {
      ForEach(viewModel.reviewPoints, id: \.self) { point in
        Text(point)
      }
      Button("Ernährung und Training auswerten", systemImage: "sparkles") {
        Task {
          await viewModel.review(
            meals: meals, activities: activities.compactMap(\.activity), ai: model.ai, settings: model.settings,
            recovery: recoveryText)
        }
      }
      .disabled(viewModel.isWorking || !model.ai.allows("nutrition_review"))
      if !viewModel.reviewPoints.isEmpty {
        EvidenceDisclosure(ruleIDs: viewModel.reviewSources + NutritionViewModel.reviewEvidence)
      }
    } header: {
      Text("KI-Auswertung")
    } footer: {
      if let model = viewModel.reviewModel {
        Text("KI · \(model). Schätzungen – Nährwerte aus Fotos können deutlich abweichen.")
      } else if !model.ai.isConfigured {
        Text("Dafür den KI-Worker in den Einstellungen einrichten.")
      }
    }
  }

  private var recoveryText: String {
    let records = days.compactMap(\.metrics)
    guard let today = records.first else { return "keine Daten" }
    let average = RecoveryEvaluator.average(
      \.restingHeartRate, in: records, daysBefore: 1...7, today: today.day)
    return RecoveryEvaluator.evaluate(today, restingHeartRate7DayAverage: average).label
  }
}

/// Wochenstreifen: Tag antippen zum Ansehen und Nachtragen.
private struct DayStrip: View {
  let selected: CalendarDay
  let today: CalendarDay
  let select: (CalendarDay) -> Void
  @State private var weekOffset = 0

  var body: some View {
    let monday = today.adding(days: -today.weekdayIndex + weekOffset * 7)
    HStack(spacing: 4) {
      Button {
        weekOffset -= 1
      } label: {
        Image(systemName: "chevron.left").frame(width: 32, height: 44)
      }
      .accessibilityLabel("Vorige Woche")
      ForEach(0..<7, id: \.self) { offset in
        let day = monday.adding(days: offset)
        Button {
          select(day)
        } label: {
          VStack(spacing: 2) {
            Text(Weekday(day: day).short).font(.caption2)
            Text("\(day.day)").font(.subheadline.bold()).monospacedDigit()
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(
            day == selected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 10)
          )
          .foregroundStyle(today < day ? .secondary : .primary)
        }
        .disabled(today < day)
        .accessibilityLabel(Formatters.day(day))
      }
      Button {
        weekOffset += 1
      } label: {
        Image(systemName: "chevron.right").frame(width: 32, height: 44)
      }
      .disabled(weekOffset >= 0)
      .accessibilityLabel("Nächste Woche")
    }
    .buttonStyle(.borderless)
  }
}

/// Auf einen Blick: übrige kcal im Ring, Protein/KH/Fett als „noch … g“, Wasser mit Glas-Knopf.
private struct BudgetSection: View {
  let targets: NutritionTargets
  let totals: NutrientValues
  let water: Hydration.Total
  var showsRing = true
  var showsWater = true
  let addWater: (Double) -> Void

  var body: some View {
    Section {
      if showsRing { ring }
      if showsWater, let target = targets.values[.water] { waterRow(target) }
    } header: {
      if showsRing { Text("\(targets.dayType.label) · \(targets.source.rawValue)") }
    }
  }

  private var ring: some View {
    HStack(spacing: 20) {
      if let kcal = NutritionBudget.line(.kcal, targets: targets.values, totals: totals) {
        CalorieRing(line: kcal)
      }
      VStack(alignment: .leading, spacing: 10) {
        ForEach(NutritionBudget.main, id: \.self) { nutrient in
          if let line = NutritionBudget.line(nutrient, targets: targets.values, totals: totals) {
            MacroBar(line: line)
          }
        }
      }
    }
    .padding(.vertical, 6)
  }

  private func waterRow(_ target: Double) -> some View {
    HStack {
      Image(systemName: "drop.fill").foregroundStyle(.cyan)
      VStack(alignment: .leading, spacing: 2) {
        Text("Wasser \(GermanFormat.decimal(water.total / 1000)) / \(GermanFormat.decimal(target / 1000)) l")
          .monospacedDigit()
        if water.food >= 50 {
          Text("davon \(GermanFormat.decimal(water.food / 1000)) l aus Essen")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Menu {
        ForEach([150.0, 330, 500, 750], id: \.self) { amount in
          Button("\(Int(amount)) ml") { addWater(amount) }
        }
      } label: {
        Label("+250 ml", systemImage: "plus")
          .font(.subheadline.bold())
          .padding(.horizontal, 12)
          .frame(minHeight: 40)
          .background(.cyan.opacity(0.15), in: Capsule())
      } primaryAction: {
        addWater(250)
      }
      .accessibilityHint("Gedrückt halten für andere Mengen")
    }
  }
}

/// Tagesübersicht als Kacheln: gegessen, Ziel, übrig, Fortschritt, Mahlzeiten und Makros.
private struct DaySummarySection: View {
  let summary: NutritionDaySummary
  let totals: NutrientValues
  let targets: NutrientValues?

  var body: some View {
    Section("Tagesübersicht") {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
        Tile(title: "Gegessen", value: "\(Int(summary.eaten.rounded()))", unit: "kcal")
        Tile(title: "Ziel", value: summary.goal.map { "\(Int($0.rounded()))" } ?? "–", unit: "kcal")
        Tile(
          title: (summary.remaining ?? 0) >= 0 ? "Übrig" : "Drüber",
          value: summary.remaining.map { "\(Int(abs($0).rounded()))" } ?? "–", unit: "kcal")
        Tile(title: "Fortschritt", value: summary.percent.map { "\($0)" } ?? "–", unit: "%")
        Tile(title: "Mahlzeiten", value: "\(summary.meals)", unit: "erfasst")
        ForEach([Nutrient.protein, .carbs, .fat], id: \.self) { nutrient in
          Tile(
            title: nutrient.label, value: "\(Int((totals[nutrient] ?? 0).rounded()))",
            unit: targets?[nutrient].map { "von \(Int($0.rounded())) g" } ?? "g")
        }
      }
      .padding(.vertical, 4)
    }
  }

  private struct Tile: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.title3.bold()).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        Text(unit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(10)
      .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .combine)
    }
  }
}

/// Karten ein- und ausblenden und sortieren.
struct NutritionDashboardEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.settings.nutritionDashboard.order) { card in
            Toggle(
              isOn: Binding(
                get: { !model.settings.nutritionDashboard.hidden.contains(card) },
                set: { model.settings.nutritionDashboard.set(card, visible: $0) })
            ) {
              Label(card.label, systemImage: card.symbol)
            }
          }
          .onMove { model.settings.nutritionDashboard.move(fromOffsets: $0, toOffset: $1) }
        } footer: {
          Text("Ziehen zum Sortieren. Ausgeblendete Karten bleiben hier und lassen sich jederzeit wieder einschalten.")
        }
        Section {
          Button("Standard wiederherstellen") { model.settings.nutritionDashboard = NutritionDashboard() }
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Übersicht anpassen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }
  }
}

private struct CalorieRing: View {
  let line: NutritionBudget.Line

  var body: some View {
    ZStack {
      Circle().stroke(.fill.tertiary, lineWidth: 12)
      Circle()
        .trim(from: 0, to: line.progress)
        .stroke(line.isOver ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
        .rotationEffect(.degrees(-90))
      VStack(spacing: 0) {
        Text("\(Int(abs(line.remaining).rounded()))")
          .font(.title2.bold())
          .monospacedDigit()
          .minimumScaleFactor(0.6)
        Text(line.remaining >= 0 ? "kcal übrig" : "kcal drüber").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .frame(width: 112, height: 112)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(Int(abs(line.remaining).rounded())) Kilokalorien \(line.remaining >= 0 ? "übrig" : "über dem Ziel")")
  }
}

private struct MacroBar: View {
  let line: NutritionBudget.Line

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(line.nutrient.label).font(.subheadline)
        Spacer()
        Text(NutritionBudget.remainingText(line))
          .font(.subheadline.bold())
          .monospacedDigit()
          .foregroundStyle(line.isOver ? .red : .primary)
      }
      ProgressView(value: line.progress).tint(line.isOver ? .red : .accentColor)
    }
  }
}

/// Häufigstes zur Tageszeit und „wie gestern“ – ein Tipp trägt ein.
private struct QuickSection: View {
  let entries: [MealEntry]
  let day: CalendarDay
  let category: MealCategory
  var ownRecipes: [OwnRecipe] = []
  let log: (String, MealCategory, [MealItem], String?) -> Void
  let logRecipe: (OwnRecipe) -> Void

  var body: some View {
    let suggestions = MealSuggestions.frequent(entries, category: category, today: day, limit: 4)
    let yesterday = MealSuggestions.yesterday(entries, category: category, today: day)
    let stock = ownRecipes.filter { ($0.remainingPortions ?? 0) >= 0.5 }
    if !suggestions.isEmpty || !yesterday.isEmpty || !stock.isEmpty {
      Section {
        ForEach(stock) { recipe in
          QuickRow(
            title: "\(recipe.name) · noch \(PortionGuess.format(recipe.remainingPortions ?? 0)) Portionen",
            detail: NutritionView.summary([recipe.item()])
          ) {
            logRecipe(recipe)
          }
        }
        if !yesterday.isEmpty {
          QuickRow(
            title: "Wie gestern: \(yesterday.map(\.title).joined(separator: ", "))",
            detail: NutritionView.summary(yesterday.flatMap(\.items))
          ) {
            log(
              yesterday.map(\.title).joined(separator: ", "), category, yesterday.flatMap(\.items),
              "\(category.label) wie gestern eingetragen")
          }
        }
        ForEach(suggestions) { suggestion in
          QuickRow(title: suggestion.title, detail: NutritionView.summary(suggestion.items)) {
            log(suggestion.title, category, suggestion.items, nil)
          }
        }
      } header: {
        Text("Schnell: \(category.label)")
      }
    }
  }
}

/// Zeile mit großem „+“ (sofort eintragen); optional öffnet Antippen den Entwurf.
private struct QuickRow: View {
  let title: String
  let detail: String
  let add: () -> Void
  var open: (() -> Void)?

  var body: some View {
    HStack {
      Button {
        (open ?? add)()
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).lineLimit(2)
          Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Alle Nährstoffe mit Ziel – unter „Mehr“, damit oben nur das Wichtige steht.
private struct TargetsSection: View {
  static let primary: [Nutrient] = [.kcal, .protein, .carbs, .fat, .fiber, .water]
  let targets: NutritionTargets
  let totals: NutrientValues

  var body: some View {
    Section {
      DisclosureGroup("Alle Nährstoffe") {
        ForEach(Self.primary + Nutrient.allCases.filter { !Self.primary.contains($0) }, id: \.self) { nutrient in
          NutrientRow(nutrient: nutrient, actual: totals[nutrient], target: targets.values[nutrient])
        }
      }
    } footer: {
      Text(
        "Grundumsatz \(Int(targets.basalMetabolicRate)) kcal, Training \(Int(targets.exerciseKilocalories)) kcal, "
          + "Protein \(GermanFormat.decimal(targets.proteinPerKilogram)) g/kg."
          + (targets.energyAvailabilityFloorApplied ? " Energie auf Mindestverfügbarkeit angehoben." : ""))
    }
  }
}

private struct NutrientRow: View {
  let nutrient: Nutrient
  let actual: Double?
  let target: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(nutrient.label)
        Spacer()
        let wholeNumbers = (target ?? 0) >= 10
        let actualText = wholeNumbers ? String(Int((actual ?? 0).rounded())) : Self.format(actual ?? 0)
        Text("\(actualText) / \(target.map(Self.format) ?? "–") \(nutrient.unit)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      if let percent = NutritionSummary.percent(actual, of: target) {
        ProgressView(value: Double(min(percent, 100)), total: 100)
          .tint(nutrient.isUpperLimit ? (percent > 100 ? .red : .orange) : (percent >= 100 ? .green : .accentColor))
      }
    }
  }

  static func format(_ value: Double) -> String {
    value >= 10 ? String(Int(value.rounded())) : GermanFormat.decimal(value)
  }
}

private struct MealRow: View {
  let meal: MealRecord

  var body: some View {
    let totals = NutritionSummary.totals(meal.items)
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(meal.title).font(.headline).lineLimit(1)
        Spacer()
        Text("\(Int((totals[.kcal] ?? 0).rounded())) kcal").monospacedDigit()
      }
      Text(
        "\(meal.category.label) · Protein \(Int((totals[.protein] ?? 0).rounded())) g · "
          + "KH \(Int((totals[.carbs] ?? 0).rounded())) g · Fett \(Int((totals[.fat] ?? 0).rounded())) g"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }
}

/// „Nur Kalorien“: Restaurant, Kantine, unterwegs – Schätzung ohne Lebensmittel.
private struct QuickEntrySheet: View {
  let save: (String, MealCategory, MealItem) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var category = NutritionViewModel.category(at: .now)
  @State private var kcal: Double?
  @State private var protein: Double?
  @State private var carbs: Double?
  @State private var fat: Double?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          number("Kalorien", "kcal", $kcal)
          number("Protein", "g", $protein)
          number("Kohlenhydrate", "g", $carbs)
          number("Fett", "g", $fat)
        } footer: {
          Text("Nur Kalorien reichen; Makros helfen bei der Tagesbilanz. Wird als Schätzung markiert.")
        }
        Section {
          TextField("Was war es? (optional)", text: $name)
          Picker("Mahlzeit", selection: $category) {
            ForEach(MealCategory.allCases, id: \.self) { Text($0.label).tag($0) }
          }
        }
      }
      .navigationTitle("Nur Kalorien")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Eintragen") {
            let title = name.trimmingCharacters(in: .whitespaces)
            let item = MealItem.quick(
              name: title.isEmpty ? "Schnell-Eintrag" : title, kilocalories: kcal ?? 0, protein: protein,
              carbs: carbs, fat: fat)
            save(title.isEmpty ? "Schnell-Eintrag" : title, category, item)
            dismiss()
          }
          .disabled((kcal ?? 0) <= 0)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func number(_ label: String, _ unit: String, _ value: Binding<Double?>) -> some View {
    HStack {
      Text(label)
      Spacer()
      TextField("0", value: value, format: .number.precision(.fractionLength(0)))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: 100)
      Text(unit).foregroundStyle(.secondary)
    }
  }
}
