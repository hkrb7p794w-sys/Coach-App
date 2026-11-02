import CoachCore
import SwiftUI

/// Hauptziel (eins) und Nebenziele (bis zu zwei, optional).
struct GoalsPicker: View {
  @Binding var goals: PersonalGoals

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Hauptziel").font(.headline)
      ForEach(TrainingGoal.allCases) { goal in
        SelectionCard(
          title: goal.label, detail: goal == goals.primary ? goal.effect : nil, symbol: goal.symbol,
          color: .accentColor, isSelected: goals.primary == goal
        ) {
          goals = PersonalGoals(
            primary: goal, secondary: goals.secondary.filter { $0 != goal }, priorities: goals.priorities,
            since: goals.since)
        }
      }
      Text("Nebenziele (optional, bis zu \(PersonalGoals.maxSecondary))").font(.headline).padding(.top, 8)
      FlowChips(
        items: TrainingGoal.allCases.filter { $0 != goals.primary }, label: \.label,
        isSelected: { goals.secondary.contains($0) }
      ) { goal in
        var secondary = goals.secondary
        if let index = secondary.firstIndex(of: goal) {
          secondary.remove(at: index)
        } else if secondary.count < PersonalGoals.maxSecondary {
          secondary.append(goal)
        }
        goals = PersonalGoals(
          primary: goals.primary, secondary: secondary, priorities: goals.priorities, since: goals.since)
      }
    }
  }
}

/// Was besonders wichtig ist (bis zu drei, Reihenfolge = Wichtigkeit). Ohne Auswahl gelten die Standards zum Ziel.
struct PrioritiesPicker: View {
  @Binding var goals: PersonalGoals

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      FlowChips(
        items: FocusArea.allCases,
        label: { area in
          if let index = goals.priorities.firstIndex(of: area) { return "\(index + 1). \(area.label)" }
          return area.label
        }, isSelected: { goals.priorities.contains($0) }
      ) { area in
        var priorities = goals.priorities
        if let index = priorities.firstIndex(of: area) {
          priorities.remove(at: index)
        } else if priorities.count < PersonalGoals.maxPriorities {
          priorities.append(area)
        }
        goals = PersonalGoals(
          primary: goals.primary, secondary: goals.secondary, priorities: priorities, since: goals.since)
      }
      if goals.priorities.isEmpty {
        Text(
          "Ohne Auswahl: \(goals.effectivePriorities.map(\.label).joined(separator: ", ")) – passend zu den Zielen."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Das ändert sich dadurch:").font(.footnote.weight(.semibold))
        Text(
          "Reihenfolge der Empfehlungen im Reiter „AI“, Startauswahl der Gesundheits-Widgets, worauf die KI in "
            + "Analysen achtet, und wie vorsichtig die Wochenbelastung steigen darf (Recovery/Gesundheit: 20 % "
            + "statt 30 %)."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }
}

/// Fitness-Tracker: ja/nein und welche Anbieter. Ehrlich, was davon in der App wirklich geht.
struct TrackerPicker: View {
  @Binding var setup: TrackerSetup

  static let offered: [DataProvider] = [.garmin, .appleHealth, .whoop, .polar, .fitbit]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Fitness-Tracker", selection: $setup.usesTracker) {
        Text("Ja").tag(Bool?.some(true))
        Text("Nein").tag(Bool?.some(false))
      }
      .pickerStyle(.segmented)
      if setup.usesTracker == true {
        ForEach(Self.offered) { provider in
          SelectionCard(
            title: provider == .appleHealth ? "Apple Watch / Apple Health" : provider.label,
            detail: Self.note(provider), symbol: Self.symbol(provider), color: .accentColor,
            isSelected: setup.providers.contains(provider)
          ) {
            if let index = setup.providers.firstIndex(of: provider) {
              setup.providers.remove(at: index)
            } else {
              setup.providers.append(provider)
            }
          }
        }
      } else if setup.usesTracker == false {
        Text(
          "Kein Problem: Trainings trägst du in der App ein (Gym-Einheiten, „Nachtragen“). Schritte zählt das iPhone "
            + "über Apple Health, wenn du es später einschaltest."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
    }
  }

  static func note(_ provider: DataProvider) -> String {
    switch provider {
    case .garmin: "Direkt verbinden: Anmeldung mit dem Garmin-Konto."
    case .appleHealth: "Direkt verbinden: Import aus Apple Health einschalten."
    case .whoop: "Noch keine direkte Verbindung – Schlaf, Ruhepuls und Workouts kommen über Apple Health."
    case .polar: "Noch keine direkte Verbindung – Trainings kommen über Apple Health (Polar Flow)."
    case .fitbit: "Derzeit nicht möglich: Fitbit schreibt nicht in Apple Health, die Web-API ist abgeschaltet."
    }
  }

  static func symbol(_ provider: DataProvider) -> String {
    switch provider {
    case .garmin: "applewatch.side.right"
    case .appleHealth: "heart.text.square.fill"
    case .whoop: "bolt.heart"
    case .polar: "heart.circle"
    case .fitbit: "figure.walk.circle"
    }
  }
}

/// Mehrfachauswahl als Chips, die umbrechen.
struct FlowChips<Item: Hashable>: View {
  let items: [Item]
  let label: (Item) -> String
  let isSelected: (Item) -> Bool
  let toggle: (Item) -> Void

  init(
    items: [Item], label: @escaping (Item) -> String, isSelected: @escaping (Item) -> Bool,
    toggle: @escaping (Item) -> Void
  ) {
    self.items = items
    self.label = label
    self.isSelected = isSelected
    self.toggle = toggle
  }

  init(
    items: [Item], label: KeyPath<Item, String>, isSelected: @escaping (Item) -> Bool,
    toggle: @escaping (Item) -> Void
  ) {
    self.init(items: items, label: { $0[keyPath: label] }, isSelected: isSelected, toggle: toggle)
  }

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
      ForEach(items, id: \.self) { item in
        let selected = isSelected(item)
        Button {
          toggle(item)
        } label: {
          Text(label(item))
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(
              selected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.fill.tertiary),
              in: Capsule()
            )
            .overlay { Capsule().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
      }
    }
  }
}

/// Einstellungen › Ziele & Prioritäten: jederzeit änderbar, gilt ab heute (frühere Zeiträume behalten ihre Ziele).
struct PersonalGoalsSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var goals: PersonalGoals?
  @State private var tracker = TrackerSetup()

  static let insets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)

  var body: some View {
    let today = CalendarDay(date: .now)
    Form {
      if let binding = Binding($goals) {
        Section("Ziele") { GoalsPicker(goals: binding).listRowInsets(Self.insets) }
        Section("Was dir besonders wichtig ist") { PrioritiesPicker(goals: binding).listRowInsets(Self.insets) }
      }
      Section {
        TrackerPicker(setup: $tracker).listRowInsets(Self.insets)
        NavigationLink("Datenquellen und Vorrang") { DataSourcesView() }
      } header: {
        Text("Fitness-Tracker")
      } footer: {
        Text("Garmin verbindest du unter Einstellungen › Garmin, Apple Health unter „Apple Health“.")
      }
      Section {
        EmptyView()
      } footer: {
        Text(
          "Änderungen gelten ab heute für Empfehlungen, Plan-Vorschläge und KI. Frühere Wochen behalten die Ziele, "
            + "die damals galten.")
      }
    }
    .navigationTitle("Ziele & Prioritäten")
    .onAppear {
      goals = model.settings.profile.effectiveGoals(today: today)
      tracker = model.settings.profile.tracker
    }
    .onDisappear { save(today: today) }
  }

  private func save(today: CalendarDay) {
    guard let goals else { return }
    PersonalizationApply.apply(goals: goals, tracker: tracker, to: model, today: today)
  }
}

/// Übernimmt Ziele und Tracker zentral: Profil (mit Verlauf), Ernährungsrichtung, Standard-Widgets, primäres Gerät.
enum PersonalizationApply {
  @MainActor
  static func apply(goals: PersonalGoals, tracker: TrackerSetup, to model: AppModel, today: CalendarDay) {
    let settings = model.settings
    var profile = settings.profile
    let before = profile.effectiveGoals(today: today)
    profile.updateGoals(goals, on: today)
    profile.tracker = tracker
    guard profile != settings.profile else { return }
    settings.profile = profile
    if profile.mode == .personal { settings.applyProfileToNutrition(garmin: model.sync.profile) }
    applyDefaults(goals: goals, before: before, tracker: tracker, to: model)
  }

  /// Standard-Widgets nach den Prioritäten (nur wenn noch nicht angepasst) und primäres Gerät.
  @MainActor
  static func applyDefaults(goals: PersonalGoals, before: PersonalGoals, tracker: TrackerSetup, to model: AppModel) {
    let settings = model.settings
    let untouched =
      settings.healthDashboard == HealthDashboard()
      || settings.healthDashboard.entries.map(\.kind) == Array(Personalization.healthWidgets(before).prefix(8))
    if untouched {
      settings.healthDashboard = HealthDashboard(
        entries: Personalization.healthWidgets(goals).prefix(8).map { HealthDashboard.Entry(kind: $0) })
    }
    // Primäres Gerät: erster gewählter Tracker mit eingebauter Anbindung (nur wenn noch keins gesetzt).
    if settings.sources.primary == nil,
      let first = tracker.providers.first(where: { $0.availability == .available })
    {
      settings.sources.primary = first
    }
  }
}
