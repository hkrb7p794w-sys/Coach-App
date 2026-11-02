import AppIntents
import CoachCore
import SwiftUI
import WidgetKit

// Homescreen- und Sperrbildschirm-Widgets. Sie lesen nur den Stand, den die App in die App Group schreibt
// (`WidgetStore`); interaktiv ist allein „+250 ml Wasser“ (Warteschlange, die App übernimmt beim Öffnen).
// Diese Erweiterung läuft ohne MainActor-Voreinstellung (project.yml), damit `@Parameter` in den
// Konfigurations-Intents geht.

// MARK: - Zeitleiste

struct HomeEntry<Config: Sendable>: TimelineEntry {
  let date: Date
  /// `nil`: noch kein Stand (App nie geöffnet oder keine App Group).
  let display: WidgetSnapshot.Display?
  let config: Config
}

enum HomeTimeline {
  /// Jetzt und ab Mitternacht (neuer Tag ohne Mahlzeiten und Plan); danach liest das Widget neu.
  static func entries<Config: Sendable>(config: Config, now: Date = .now) -> Timeline<HomeEntry<Config>> {
    let snapshot = WidgetStore.loadSnapshot()
    let queue = WidgetStore.loadQueue()
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
    let midnight = tomorrow.addingTimeInterval(60)
    let entries = [now, midnight].map { date in
      HomeEntry(
        date: date, display: snapshot?.display(on: CalendarDay(date: date), queue: queue), config: config)
    }
    return Timeline(entries: entries, policy: .atEnd)
  }

  static func preview<Config: Sendable>(config: Config) -> HomeEntry<Config> {
    HomeEntry(date: .now, display: SampleSnapshot.value.display(on: SampleSnapshot.value.day), config: config)
  }
}

struct ConfiguredHomeProvider<Intent: WidgetConfigurationIntent>: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> HomeEntry<Intent> { HomeTimeline.preview(config: Intent()) }

  func snapshot(for configuration: Intent, in context: Context) async -> HomeEntry<Intent> {
    context.isPreview
      ? HomeTimeline.preview(config: configuration) : HomeTimeline.entries(config: configuration).entries[0]
  }

  func timeline(for configuration: Intent, in context: Context) async -> Timeline<HomeEntry<Intent>> {
    HomeTimeline.entries(config: configuration)
  }
}

// MARK: - Konfiguration

struct TodayWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Heute"

  @Parameter(title: "Kalorien zeigen", default: true) var showsNutrition: Bool
  @Parameter(title: "Body Battery zeigen", default: true) var showsBodyBattery: Bool

  init() {}
}

enum NutritionWidgetDisplay: String, AppEnum {
  case remaining, eaten, protein, lastMeal

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeige"
  static let caseDisplayRepresentations: [NutritionWidgetDisplay: DisplayRepresentation] = [
    .remaining: "Verbleibende Kalorien",
    .eaten: "Tageskalorien",
    .protein: "Protein",
    .lastMeal: "Letzte Mahlzeit",
  ]
}

struct NutritionWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Ernährung"

  @Parameter(title: "Anzeige", default: .remaining) var display: NutritionWidgetDisplay

  init() {}
}

enum HealthWidgetMetric: String, AppEnum {
  case bodyBattery, sleep, hrv, recovery, restingHeartRate, stress

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Wert"
  static let caseDisplayRepresentations: [HealthWidgetMetric: DisplayRepresentation] = [
    .bodyBattery: "Body Battery",
    .sleep: "Schlaf",
    .hrv: "HRV",
    .recovery: "Recovery",
    .restingHeartRate: "Ruhepuls",
    .stress: "Stress",
  ]

  var metric: HealthMetric { HealthMetric(rawValue: rawValue) ?? .bodyBattery }
}

struct HealthWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Health"

  @Parameter(title: "Wert", default: .bodyBattery) var metric: HealthWidgetMetric

  init() {}
}

enum GymWidgetFocus: String, AppEnum {
  case next, last, week

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Anzeige"
  static let caseDisplayRepresentations: [GymWidgetFocus: DisplayRepresentation] = [
    .next: "Nächstes Training",
    .last: "Letzte Einheit",
    .week: "Wochenfortschritt",
  ]
}

struct GymWidgetIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Gym"

  @Parameter(title: "Anzeige", default: .next) var focus: GymWidgetFocus

  init() {}
}

/// Einziger interaktiver Knopf: 250 ml Wasser vormerken. Läuft in der Erweiterung; die App übernimmt den Eintrag
/// beim nächsten Öffnen, das Widget zählt ihn sofort mit.
struct AddWaterIntent: AppIntent {
  static let title: LocalizedStringResource = "250 ml Wasser"
  static let isDiscoverable = false

  init() {}

  func perform() async throws -> some IntentResult {
    WidgetStore.updateQueue { $0.addWater(250, at: .now) }
    return .result()
  }
}

// MARK: - Widgets

struct TodayHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.today, intent: TodayWidgetIntent.self, provider: ConfiguredHomeProvider<TodayWidgetIntent>()
    ) { entry in
      TodayWidgetView(
        display: entry.display, showsNutrition: entry.config.showsNutrition,
        showsBodyBattery: entry.config.showsBodyBattery)
        .widgetURL(AppRoute.today.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Heute")
    .description("Tagesampel, nächste Einheit, Kalorien und Body Battery.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct NutritionHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.nutrition, intent: NutritionWidgetIntent.self,
      provider: ConfiguredHomeProvider<NutritionWidgetIntent>()
    ) { entry in
      NutritionWidgetView(display: entry.display, choice: entry.config.display)
        .widgetURL(AppRoute.nutrition.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Ernährung")
    .description("Kalorien, Protein oder letzte Mahlzeit – mittelgroß mit Wasser-Knopf.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct HealthHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.health, intent: HealthWidgetIntent.self,
      provider: ConfiguredHomeProvider<HealthWidgetIntent>()
    ) { entry in
      HealthWidgetView(display: entry.display, metric: entry.config.metric.metric)
        .widgetURL(AppRoute.health.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Health")
    .description("Body Battery, Schlaf, HRV, Recovery, Ruhepuls oder Stress der letzten Nacht.")
    .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct GymHomeWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: WidgetStore.Kind.gym, intent: GymWidgetIntent.self, provider: ConfiguredHomeProvider<GymWidgetIntent>()
    ) { entry in
      GymWidgetView(display: entry.display, focus: entry.config.focus)
        .widgetURL(AppRoute.gym.url)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Gym")
    .description("Nächstes Training, letzte Einheit oder Wochenfortschritt.")
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
  }
}

// MARK: - Ansichten

/// Ohne Stand: kurz erklären statt leerer Zahlen.
private struct NoDataView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: "arrow.up.forward.app").font(.title3)
      Text(WidgetStore.isAvailable ? "IronLudi einmal öffnen" : "Widget-Daten nicht verfügbar")
        .font(.caption.bold())
      if !WidgetStore.isAvailable {
        Text("Die App-Gruppe fehlt (Installation über SideStore prüfen).").font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private enum Style {
  static func color(_ level: RecoveryLevel?) -> Color {
    switch level {
    case .normal?: .green
    case .locker?: .orange
    case .pause?: .red
    case nil: .gray
    }
  }

  static func color(_ status: MorningReport.Status) -> Color {
    switch status {
    case .good: .green
    case .normal: .blue
    case .attention: .orange
    case .missing: .gray
    }
  }

  static func label(_ status: MorningReport.Status) -> String {
    switch status {
    case .good: "gut"
    case .normal: "üblich"
    case .attention: "auffällig"
    case .missing: "fehlt"
    }
  }

  static func kcal(_ value: Double) -> String { "\(Int(value.rounded()))" }
  static func grams(_ value: Double) -> String { "\(Int(value.rounded())) g" }
  static func liters(_ milliliters: Double) -> String { "\(GermanFormat.decimal(milliliters / 1_000)) l" }
}

struct TodayWidgetView: View {
  let display: WidgetSnapshot.Display?
  let showsNutrition: Bool
  let showsBodyBattery: Bool
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let snapshot = display?.snapshot {
      let today = snapshot.today
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 6) {
            Circle().fill(Style.color(today.level)).frame(width: 10, height: 10)
            Text("Heute").font(.caption.bold()).foregroundStyle(.secondary)
          }
          Text(today.headline).font(.subheadline.bold()).lineLimit(2).minimumScaleFactor(0.8)
          Spacer(minLength: 0)
          if let next = today.nextSession {
            Label(next.title, systemImage: next.symbol).font(.caption).lineLimit(1)
          } else if !today.sessions.isEmpty {
            Label("Alles erledigt", systemImage: "checkmark.circle").font(.caption)
          }
          if family == .systemSmall, showsNutrition, let remaining = snapshot.nutrition?.kcalRemaining {
            Text("\(Style.kcal(remaining)) kcal übrig").font(.caption2).foregroundStyle(.secondary)
          }
        }
        if family == .systemMedium {
          VStack(alignment: .leading, spacing: 6) {
            if showsNutrition, let nutrition = snapshot.nutrition, let remaining = nutrition.kcalRemaining {
              MetricLine(
                symbol: "fork.knife", text: "\(Style.kcal(remaining)) kcal übrig", fraction: nutrition.kcalFraction)
            }
            if showsBodyBattery, !(display?.healthIsOld ?? true), let battery = snapshot.health(.bodyBattery),
              let value = battery.value
            {
              MetricLine(
                symbol: "battery.75percent", text: "Body Battery \(value)", fraction: battery.gauge.map { $0 / 100 })
            }
            if let week = today.week {
              MetricLine(symbol: "calendar", text: week, fraction: today.weekFraction)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      NoDataView()
    }
  }
}

private struct MetricLine: View {
  let symbol: String
  let text: String
  let fraction: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Label(text, systemImage: symbol).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
      if let fraction { ProgressView(value: fraction).tint(.accentColor) }
    }
  }
}

struct NutritionWidgetView: View {
  let display: WidgetSnapshot.Display?
  let choice: NutritionWidgetDisplay
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let nutrition = display?.snapshot.nutrition {
      switch family {
      case .accessoryCircular: circular(nutrition)
      case .accessoryRectangular: rectangular(nutrition)
      case .accessoryInline: Text(headline(nutrition))
      case .systemMedium: medium(nutrition)
      default: small(nutrition)
      }
    } else {
      NoDataView()
    }
  }

  private func headline(_ nutrition: WidgetSnapshot.Nutrition) -> String {
    switch choice {
    case .remaining:
      nutrition.kcalRemaining.map { $0 >= 0 ? "\(Style.kcal($0)) kcal übrig" : "\(Style.kcal(-$0)) kcal drüber" }
        ?? "\(Style.kcal(nutrition.kcal)) kcal"
    case .eaten:
      nutrition.kcalTarget.map { "\(Style.kcal(nutrition.kcal)) / \(Style.kcal($0)) kcal" }
        ?? "\(Style.kcal(nutrition.kcal)) kcal"
    case .protein:
      nutrition.proteinTarget.map { "Protein \(Style.grams(nutrition.protein)) / \(Style.grams($0))" }
        ?? "Protein \(Style.grams(nutrition.protein))"
    case .lastMeal:
      nutrition.lastMeal.map { "\($0.title) · \($0.at.formatted(date: .omitted, time: .shortened))" }
        ?? "Noch keine Mahlzeit"
    }
  }

  private func fraction(_ nutrition: WidgetSnapshot.Nutrition) -> Double? {
    choice == .protein ? nutrition.proteinFraction : nutrition.kcalFraction
  }

  private func small(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Label("Ernährung", systemImage: "fork.knife").font(.caption.bold()).foregroundStyle(.secondary)
      Spacer(minLength: 0)
      if choice == .lastMeal, let meal = nutrition.lastMeal {
        Text(meal.title).font(.headline).lineLimit(2)
        Text("\(meal.at.formatted(date: .omitted, time: .shortened)) · \(Style.kcal(meal.kcal)) kcal")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text(headline(nutrition)).font(.headline).lineLimit(2).minimumScaleFactor(0.7)
        if let fraction = fraction(nutrition) { ProgressView(value: fraction) }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func medium(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    HStack(alignment: .top, spacing: 12) {
      small(nutrition)
      VStack(alignment: .leading, spacing: 6) {
        MetricLine(
          symbol: "bolt.fill",
          text: nutrition.proteinTarget.map { "Protein \(Style.grams(nutrition.protein))/\(Style.grams($0))" }
            ?? "Protein \(Style.grams(nutrition.protein))", fraction: nutrition.proteinFraction)
        MetricLine(
          symbol: "drop.fill",
          text: nutrition.waterTarget.map { "Wasser \(Style.liters(nutrition.waterMilliliters))/\(Style.liters($0))" }
            ?? "Wasser \(Style.liters(nutrition.waterMilliliters))", fraction: nutrition.waterFraction)
        HStack(spacing: 6) {
          if WidgetStore.isAvailable {
            Button(intent: AddWaterIntent()) { Label("250 ml", systemImage: "plus") }
              .font(.caption.bold())
          }
          Link(destination: AppRoute.logMeal.url) { Label("Erfassen", systemImage: "camera") }
            .font(.caption.bold())
        }
        .buttonStyle(.bordered)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func circular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    Gauge(value: fraction(nutrition) ?? 0) {
      Image(systemName: choice == .protein ? "bolt.fill" : "fork.knife")
    } currentValueLabel: {
      if choice == .protein {
        Text("\(Int(nutrition.protein.rounded()))")
      } else {
        Text(Style.kcal(nutrition.kcalRemaining ?? nutrition.kcal))
      }
    }
    .gaugeStyle(.accessoryCircularCapacity)
  }

  private func rectangular(_ nutrition: WidgetSnapshot.Nutrition) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(headline(nutrition)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
      if let fraction = fraction(nutrition) { ProgressView(value: fraction) }
      Text("Protein \(Style.grams(nutrition.protein))").font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct HealthWidgetView: View {
  let display: WidgetSnapshot.Display?
  let metric: HealthMetric
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let display {
      let health = display.snapshot.health(metric)
      let value = display.healthIsOld ? nil : health?.value
      switch family {
      case .accessoryCircular:
        if metric == .bodyBattery, let gauge = display.healthIsOld ? nil : health?.gauge {
          Gauge(value: gauge, in: 0...100) { Image(systemName: metric.symbol) } currentValueLabel: {
            Text("\(Int(gauge))")
          }
          .gaugeStyle(.accessoryCircular)
        } else {
          VStack(spacing: 0) {
            Image(systemName: metric.symbol).font(.caption)
            Text(value ?? "–").font(.headline).minimumScaleFactor(0.5)
          }
        }
      case .accessoryRectangular:
        VStack(alignment: .leading, spacing: 1) {
          Label(metric.title, systemImage: metric.symbol).font(.caption.bold())
          Text(value ?? "–").font(.headline)
          Text(health.map { Style.label($0.status) } ?? "fehlt").font(.caption2).foregroundStyle(.secondary)
        }
      case .accessoryInline:
        Text("\(metric.title) \(value ?? "–")")
      default:
        VStack(alignment: .leading, spacing: 4) {
          Label(metric.title, systemImage: metric.symbol).font(.caption.bold()).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          Text(value ?? "–").font(.title.bold()).minimumScaleFactor(0.6).lineLimit(1)
          if let health, value != nil {
            Text(Style.label(health.status)).font(.caption.bold()).foregroundStyle(Style.color(health.status))
            Text(health.note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
          } else {
            Text(display.healthIsOld ? "Kein Wert von letzter Nacht" : "Kein Wert").font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    } else {
      NoDataView()
    }
  }
}

struct GymWidgetView: View {
  let display: WidgetSnapshot.Display?
  let focus: GymWidgetFocus
  @Environment(\.widgetFamily) private var family

  var body: some View {
    if let gym = display?.snapshot.gym {
      switch family {
      case .accessoryRectangular:
        VStack(alignment: .leading, spacing: 1) {
          Label(gym.running ? "Läuft" : "Gym", systemImage: "dumbbell").font(.caption.bold())
          Text(gym.runningTitle ?? gym.next ?? "Kein Plan").font(.headline).lineLimit(1)
          Text(gym.weekText).font(.caption2).foregroundStyle(.secondary)
        }
      case .systemMedium:
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            section(.next, gym)
            Spacer(minLength: 0)
            Link(destination: AppRoute.startWorkout.url) {
              Label(gym.running ? "Fortsetzen" : "Starten", systemImage: "play.fill").font(.caption.bold())
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            section(.last, gym)
            section(.week, gym)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      default:
        VStack(alignment: .leading, spacing: 4) {
          Label("Gym", systemImage: "dumbbell").font(.caption.bold()).foregroundStyle(.secondary)
          Spacer(minLength: 0)
          section(gym.running ? .next : focus, gym)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    } else if display != nil {
      VStack(alignment: .leading, spacing: 4) {
        Image(systemName: "dumbbell")
        Text("Kein Krafttraining im Profil").font(.caption)
      }
    } else {
      NoDataView()
    }
  }

  @ViewBuilder private func section(_ focus: GymWidgetFocus, _ gym: WidgetSnapshot.Gym) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      switch focus {
      case .next:
        Text(gym.running ? "Läuft gerade" : "Nächstes Training").font(.caption2).foregroundStyle(.secondary)
        Text(gym.runningTitle ?? gym.next ?? "Kein Plan").font(.headline).lineLimit(2).minimumScaleFactor(0.7)
        if !gym.running, let detail = gym.nextDetail {
          Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
      case .last:
        Text("Letzte Einheit").font(.caption2).foregroundStyle(.secondary)
        if let last = gym.last {
          Text(last.title).font(.subheadline.bold()).lineLimit(1)
          Text("\(GermanFormat.date(last.day).prefix(6)) · \(last.sets) Sätze").font(.caption2)
            .foregroundStyle(.secondary)
        } else {
          Text("Noch keine").font(.subheadline)
        }
      case .week:
        Text("Woche").font(.caption2).foregroundStyle(.secondary)
        Text(gym.weekText).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
        if let planned = gym.weekPlanned, planned > 0 {
          ProgressView(value: min(Double(gym.weekDone) / Double(planned), 1))
        }
      }
    }
  }
}

// MARK: - Vorschau in der Widget-Galerie

enum SampleSnapshot {
  static let value = WidgetSnapshot(
    createdAt: .now, day: CalendarDay(date: .now),
    today: .init(
      level: .normal, headline: "Normal trainieren",
      sessions: [.init(title: "Push", target: "6 Übungen", done: false, symbol: "dumbbell")],
      week: "2/4 Einheiten · 95 min", weekFraction: 0.5),
    nutrition: .init(
      kcal: 1_450, kcalTarget: 2_400, protein: 95, proteinTarget: 150, waterMilliliters: 1_250, waterTarget: 2_500,
      lastMeal: .init(title: "Mittagessen", at: .now, kcal: 680)),
    gym: .init(
      next: "Push", nextDetail: "6 Übungen · ca. 55 min", running: false, runningTitle: nil,
      last: .init(title: "Pull", day: CalendarDay(date: .now).adding(days: -2), sets: 18, volumeKg: 7_400),
      weekDone: 1, weekPlanned: 3),
    health: [
      .init(metric: .bodyBattery, value: "72", gauge: 72, status: .normal, note: "Im üblichen Bereich"),
      .init(metric: .sleep, value: "7,4 h", gauge: nil, status: .good, note: "Über deinem Bedarf"),
      .init(metric: .hrv, value: "58 ms", gauge: nil, status: .normal, note: "Im Bereich der Baseline"),
    ])
}
