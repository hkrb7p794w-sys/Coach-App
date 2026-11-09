import Charts
import CoachCore
import SwiftData
import SwiftUI

/// Daten für die Widgets: Tageswerte plus Ersatzquellen (Wägungen, Belastung aus den eigenen Aktivitäten).
struct HealthData {
  let days: [DailyMetrics]
  let extra: [HealthWidget: [DayValue]]
  let today: CalendarDay

  init(days: [DailyMetrics], weights: [WeightEntry], activities: [GarminActivity], today: CalendarDay) {
    self.days = days
    self.today = today
    let weight = WeightTrend.merged(weights).map { DayValue(day: $0.day, value: $0.kilograms) }
    // Ohne Garmin-Konto: Tagesbelastung aus den eigenen Aktivitäten (gleiche Grundlage wie „Fitness & Form“).
    let load = FitnessForm.series(activities: activities, today: today).filter { $0.load > 0 }
      .map { DayValue(day: $0.day, value: $0.load.rounded()) }
    extra = [.weight: weight, .trainingLoad: load]
  }

  var available: Set<HealthWidget> { HealthDashboard.available(days: days, extra: extra, today: today) }

  func series(_ kind: HealthWidget, window: Int) -> [DayValue] {
    HealthDashboard.series(kind, days: days, extra: extra, today: today, window: window)
  }

  /// Persönlicher Bereich der letzten 30 Tage ohne heute.
  func norm(_ kind: HealthWidget) -> PersonalNorm? {
    PersonalNorm.of(series(kind, window: PersonalNorm.windowDays + 1).filter { $0.day < today }.map(\.value))
  }

  func metrics(on day: CalendarDay) -> DailyMetrics? { days.first { $0.day == day } }
}

/// Gesundheitsbereich: Morning Report oben, darunter die konfigurierbaren Widgets.
struct HealthDashboardView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var records: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activityRecords: [ActivityRecord]
  @State private var editing = false

  var body: some View {
    let today = CalendarDay(date: .now)
    let activities = activityRecords.compactMap(\.activity)
    let data = HealthData(
      days: records.compactMap(\.metrics), weights: model.allWeights, activities: activities, today: today)
    let available = data.available
    let visible = model.settings.healthDashboard.visible(available: available)
    let report = MorningReportBuilder.make(model: model, days: data.days, activities: activities, focus: nil)
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        NavigationLink {
          MorningReportView()
        } label: {
          MorningReportSummary(report: report)
        }
        .buttonStyle(.plain)

        NavigationLink {
          MobilityView()
        } label: {
          MobilitySummaryCard()
        }
        .buttonStyle(.plain)

        if visible.isEmpty {
          ContentUnavailableView {
            Label(
              available.isEmpty ? "Noch keine Werte" : "Alle Widgets ausgeblendet", systemImage: "heart.text.square")
          } description: {
            Text(
              available.isEmpty
                ? "Melde dich mit dem Garmin-Konto an oder schalte Apple Health ein und ziehe nach unten zum Abrufen."
                : "Tippe auf „Anpassen“, um Widgets einzublenden oder hinzuzufügen.")
          }
        } else {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(visible) { entry in
              NavigationLink {
                HealthWidgetDestination(kind: entry.kind, data: data)
              } label: {
                HealthWidgetCard(entry: entry, data: data)
              }
              .buttonStyle(.plain)
            }
          }
        }
        let missing = model.settings.healthDashboard.entries.filter { !$0.hidden && !available.contains($0.kind) }
        if !missing.isEmpty {
          Text(
            "Ohne Daten in den letzten 30 Tagen (ausgeblendet): "
              + missing.map { "\($0.kind.title) (\($0.kind.sources))" }.joined(separator: ", ")
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .padding()
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle("Gesundheit")
    .toolbar {
      Button("Anpassen") { editing = true }
    }
    .refreshable { await model.syncNow() }
    .sheet(isPresented: $editing) {
      HealthDashboardEditor(available: available)
    }
  }
}

/// Kopfkarte mit der Morgen-Einschätzung.
struct MorningReportSummary: View {
  let report: MorningReport

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        MorningReportHeader(report: report)
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
      }
      if !report.findings.isEmpty {
        Text(report.findings.prefix(2).joined(separator: " ")).font(.footnote).foregroundStyle(.secondary)
      }
      Text(report.recommendation).font(.footnote.weight(.semibold))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

/// Ein Widget: aktueller Wert, Einordnung gegen den eigenen Bereich und je nach Darstellung ein kleiner Verlauf.
struct HealthWidgetCard: View {
  let entry: HealthDashboard.Entry
  let data: HealthData

  var body: some View {
    let kind = entry.kind
    let series = data.series(kind, window: entry.style.days)
    let latest = data.series(kind, window: 7).last
    let norm = data.norm(kind)
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: kind.symbol).foregroundStyle(kind.color)
        Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        Spacer(minLength: 0)
      }
      Text(valueText(latest))
        .font(.title2.weight(.semibold))
        .monospacedDigit()
        .minimumScaleFactor(0.6)
        .lineLimit(1)
      if let latest {
        Text(caption(latest, norm: norm))
          .font(.caption2)
          .foregroundStyle(color(latest, norm: norm))
          .lineLimit(2)
      } else {
        Text("Keine Werte in den letzten 7 Tagen").font(.caption2).foregroundStyle(.secondary)
      }
      if entry.style != .value, series.count >= 2 {
        Chart {
          if let norm {
            RectangleMark(yStart: .value("von", norm.low), yEnd: .value("bis", norm.high))
              .foregroundStyle(.gray.opacity(0.12))
          }
          ForEach(series) { point in
            LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(kind.title, point.value))
              .foregroundStyle(kind.color)
              .interpolationMethod(.monotone)
          }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: entry.style == .month ? 70 : 44)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func valueText(_ latest: DayValue?) -> String {
    guard let latest else { return "–" }
    if entry.kind == .heartRateRange, let low = data.metrics(on: latest.day)?.minHeartRate {
      return "\(Int(low))–\(Int(latest.value)) bpm"
    }
    if entry.kind == .recoveryTime, latest.value == 0 { return "erholt" }
    return Formatters.number(latest.value, unit: entry.kind.unit, digits: entry.kind.digits)
  }

  private func caption(_ latest: DayValue, norm: PersonalNorm?) -> String {
    let when = latest.day == data.today ? "" : "\(Formatters.shortDate(latest.day)) · "
    guard let norm else { return when + "Eigener Bereich ab 7 Tagen" }
    switch norm.position(latest.value) {
    case .below: return when + "unter deinem Bereich"
    case .within: return when + "im üblichen Bereich"
    case .above: return when + "über deinem Bereich"
    }
  }

  private func color(_ latest: DayValue, norm: PersonalNorm?) -> Color {
    guard let norm, let higher = entry.kind.higherIsBetter else { return .secondary }
    switch norm.position(latest.value) {
    case .within: return .secondary
    case .above: return higher ? .green : .orange
    case .below: return higher ? .orange : .green
    }
  }
}

/// Ziel beim Antippen: eigene Seiten für Body Battery und Schlaf, sonst der Verlauf.
struct HealthWidgetDestination: View {
  let kind: HealthWidget
  let data: HealthData

  var body: some View {
    switch kind {
    case .bodyBattery: BodyBatteryView()
    case .sleep: SleepCoachView()
    default: HealthMetricDetail(kind: kind, data: data)
    }
  }
}

/// Verlauf eines Werts über 30 oder 90 Tage mit eigenem Bereich.
struct HealthMetricDetail: View {
  let kind: HealthWidget
  let data: HealthData
  @State private var window = 30

  var body: some View {
    let series = data.series(kind, window: window)
    let norm = data.norm(kind)
    List {
      Section {
        Picker("Zeitraum", selection: $window) {
          Text("30 Tage").tag(30)
          Text("90 Tage").tag(90)
        }
        .pickerStyle(.segmented)
        if series.count >= 2 {
          Chart {
            if let norm {
              RectangleMark(yStart: .value("von", norm.low), yEnd: .value("bis", norm.high))
                .foregroundStyle(.gray.opacity(0.15))
            }
            ForEach(series) { point in
              LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(kind.title, point.value))
                .foregroundStyle(kind.color)
                .interpolationMethod(.monotone)
              PointMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(kind.title, point.value))
                .foregroundStyle(kind.color)
                .symbolSize(12)
            }
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .frame(height: 200)
        } else {
          Text("Zu wenige Werte für einen Verlauf.").foregroundStyle(.secondary)
        }
      } footer: {
        Text(
          norm.map {
            "Grau: dein üblicher Bereich (Ø \(Formatters.number($0.mean, unit: kind.unit, digits: kind.digits)), "
              + "\($0.count) Tage)."
          } ?? "Dein üblicher Bereich erscheint ab 7 Tagen mit Werten.")
      }
      Section("Werte") {
        LabeledContent("Tage mit Werten", value: "\(series.count) von \(window)")
        if let latest = series.last {
          LabeledContent(
            "Zuletzt (\(Formatters.shortDate(latest.day)))",
            value: Formatters.number(latest.value, unit: kind.unit, digits: kind.digits))
        }
        if !series.isEmpty {
          let average = series.map(\.value).reduce(0, +) / Double(series.count)
          LabeledContent("Schnitt", value: Formatters.number(average, unit: kind.unit, digits: kind.digits))
        }
        LabeledContent("Quelle", value: kind.sources)
      }
    }
    .navigationTitle(kind.title)
  }
}

extension HealthWidget {
  var symbol: String {
    switch self {
    case .bodyBattery: "bolt.batteryblock.fill"
    case .hrv: "waveform.path.ecg"
    case .restingHeartRate: "heart.fill"
    case .sleep: "bed.double.fill"
    case .stress: "brain.head.profile"
    case .vo2Max: "lungs.fill"
    case .trainingLoad: "chart.bar.fill"
    case .recoveryTime: "hourglass"
    case .readiness: "gauge.with.dots.needle.67percent"
    case .steps: "figure.walk"
    case .activeCalories: "flame.fill"
    case .restingCalories: "flame"
    case .weight: "scalemass.fill"
    case .heartRateRange: "heart.text.square"
    case .respiration: "wind"
    case .spo2: "drop.fill"
    }
  }

  var color: Color {
    switch category {
    case .health: .red
    case .sleep: .indigo
    case .recovery: .teal
    case .load: .orange
    case .performance: .purple
    }
  }
}

/// Widgets hinzufügen, entfernen, ein-/ausblenden, sortieren und die Darstellung wählen.
struct HealthDashboardEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  let available: Set<HealthWidget>

  var body: some View {
    @Bindable var settings = model.settings
    NavigationStack {
      List {
        Section {
          ForEach(settings.healthDashboard.entries) { entry in
            HealthEditorRow(entry: entry, hasData: available.contains(entry.kind))
          }
          .onMove { settings.healthDashboard.move(fromOffsets: $0, toOffset: $1) }
          .onDelete { offsets in
            for kind in offsets.map({ settings.healthDashboard.entries[$0].kind }) {
              settings.healthDashboard.remove(kind)
            }
          }
        } header: {
          Text("Im Gesundheitsbereich")
        } footer: {
          Text("Ziehen zum Sortieren, Auge zum Ein- und Ausblenden, nach links wischen zum Entfernen.")
        }
        let addable = HealthWidget.allCases.filter { !settings.healthDashboard.contains($0) }
        ForEach(HealthCategory.allCases, id: \.self) { category in
          let kinds = addable.filter { $0.category == category }
          if !kinds.isEmpty {
            Section("Hinzufügen · \(category.label)") {
              ForEach(kinds) { kind in
                Button {
                  settings.healthDashboard.add(kind)
                } label: {
                  HStack {
                    Label(kind.title, systemImage: kind.symbol)
                    Spacer()
                    if available.contains(kind) {
                      Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                    } else {
                      Text("keine Daten").font(.caption).foregroundStyle(.secondary)
                    }
                  }
                }
                .disabled(!available.contains(kind))
              }
            }
          }
        }
        Section {
          Button("Standard wiederherstellen") { settings.healthDashboard = HealthDashboard() }
        }
      }
      .environment(\.editMode, .constant(.active))
      .navigationTitle("Übersicht anpassen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
    }
  }
}

private struct HealthEditorRow: View {
  @Environment(AppModel.self) private var model
  let entry: HealthDashboard.Entry
  let hasData: Bool

  var body: some View {
    HStack {
      Button {
        model.settings.healthDashboard.setHidden(entry.kind, !entry.hidden)
      } label: {
        Image(systemName: entry.hidden ? "eye.slash" : "eye")
          .foregroundStyle(entry.hidden ? Color.secondary : Color.accentColor)
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(entry.hidden ? "Einblenden" : "Ausblenden")
      VStack(alignment: .leading, spacing: 2) {
        Label(entry.kind.title, systemImage: entry.kind.symbol)
          .foregroundStyle(entry.hidden ? .secondary : .primary)
        if !hasData {
          Text("keine Daten (\(entry.kind.sources))").font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer()
      Menu {
        Picker(
          "Darstellung",
          selection: Binding(
            get: { entry.style }, set: { model.settings.healthDashboard.setStyle(entry.kind, $0) })
        ) {
          ForEach(HealthWidgetStyle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
      } label: {
        Text(entry.style.label).font(.caption)
      }
    }
  }
}
