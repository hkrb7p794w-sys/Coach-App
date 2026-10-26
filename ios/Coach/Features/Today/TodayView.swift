import CoachCore
import SwiftData
import SwiftUI

/// Tagesempfehlung, Wochen-Soll/Ist, Rennvorbereitung und die Garmin-Werte der letzten Tage.
struct TodayView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @State private var viewModel = TodayViewModel()
  @State private var showSettings = false

  private var refreshKey: String {
    "\(days.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(activities.count)-\(model.settings.season.hashValue)"
  }

  var body: some View {
    NavigationStack {
      List {
        SyncStatusSection()

        if !model.garmin.hasKey {
          Section {
            Text("Hinterlege in den Einstellungen deinen Garmin Personal API Key, um Daten abzurufen.")
              .foregroundStyle(.secondary)
          }
        }

        if let snapshot = viewModel.snapshot {
          RecommendationSection(snapshot: snapshot, viewModel: viewModel)
          WeekSection(plan: snapshot.plan)
          RaceSection(plan: snapshot.plan, config: model.settings.season)
        }

        if !days.isEmpty {
          Section("Erholung") {
            ForEach(days.prefix(14)) { record in
              if let metrics = record.metrics {
                DayRow(metrics: metrics)
              }
            }
          }
        }

        if !activities.isEmpty {
          Section("Aktivitäten") {
            ForEach(activities.prefix(10)) { record in
              if let activity = record.activity {
                ActivityRow(activity: activity)
              }
            }
          }
        }
      }
      .navigationTitle("Heute")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .refreshable {
        await model.syncNow()
        await viewModel.loadNote(ai: model.ai, settings: model.settings)
      }
      .task(id: refreshKey) {
        viewModel.update(
          days: days.compactMap(\.metrics),
          activities: activities.compactMap(\.activity),
          settings: model.settings
        )
        await viewModel.loadNote(ai: model.ai, settings: model.settings)
      }
    }
  }
}

private struct RecommendationSection: View {
  let snapshot: TodayViewModel.Snapshot
  let viewModel: TodayViewModel
  @Environment(AppModel.self) private var model

  private var color: Color {
    switch snapshot.recommendation.level {
    case .normal: .green
    case .locker: .orange
    case .pause: .red
    }
  }

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Label(snapshot.recommendation.label, systemImage: "circle.fill")
          .font(.title3.bold())
          .foregroundStyle(color)
        Text(snapshot.recommendation.advice)
        Text(snapshot.recommendation.reasons.joined(separator: " · "))
          .font(.footnote)
          .foregroundStyle(.secondary)
        if snapshot.isFromYesterday {
          Text("Für heute liegen noch keine Garmin-Werte vor – Einordnung mit den Werten von gestern.")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        ForEach(viewModel.notePoints, id: \.self) { point in
          Label(point, systemImage: "chevron.right")
            .labelStyle(BulletLabelStyle())
        }
        HStack {
          Text(viewModel.noteSource).font(.caption).foregroundStyle(.secondary)
          Spacer()
          if viewModel.isLoadingNote {
            ProgressView()
          } else if model.ai.isConfigured {
            Button("Neu formulieren") {
              Task { await viewModel.loadNote(ai: model.ai, settings: model.settings, force: true) }
            }
            .font(.caption)
          }
        }
        if let error = viewModel.noteError {
          Text(error).font(.caption).foregroundStyle(.orange)
        }
      }
      EvidenceDisclosure(ruleIDs: viewModel.noteEvidence)
    } header: {
      Text("Tagesempfehlung")
    }
  }
}

private struct BulletLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      configuration.icon.font(.caption2).foregroundStyle(.secondary)
      configuration.title
    }
  }
}

private struct WeekSection: View {
  let plan: PlanState

  var body: some View {
    Section {
      ForEach(plan.targets, id: \.target.label) { item in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(item.target.label)
            Spacer()
            Text(soll(item)).foregroundStyle(.secondary).monospacedDigit()
          }
          ProgressView(value: Double(item.percent), total: 100)
            .tint(item.done >= item.target.minimum ? .green : .accentColor)
          if !item.target.detail.isEmpty {
            Text(item.target.detail).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      if !plan.todayFixed.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Heute laut Wochenrahmen").font(.subheadline.bold())
          ForEach(plan.todayFixed, id: \.text) { item in
            Label(item.text, systemImage: item.done ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(item.done ? .secondary : .primary)
          }
        }
      }
    } header: {
      Text("Woche (\(plan.weekday), noch \(plan.daysLeftInWeek) Tage)")
    } footer: {
      if !plan.weekOpen.isEmpty {
        Text("Noch offen: " + plan.weekOpen.joined(separator: ", "))
      }
    }
  }

  private func soll(_ item: TargetProgress) -> String {
    let target = item.target
    let range = target.minimum == target.maximum ? "\(target.minimum)" : "\(target.minimum)–\(target.maximum)"
    return "\(item.done) / \(range)"
  }
}

private struct RaceSection: View {
  let plan: PlanState
  let config: SeasonConfig

  var body: some View {
    Section {
      LabeledContent(config.mainRaceName) {
        Text(countdown(plan.daysToRace))
      }
      if plan.daysToMarathon >= 0 {
        LabeledContent("Marathon") {
          Text(countdown(plan.daysToMarathon))
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("Phase: \(plan.phase.rawValue) bis \(GermanFormat.date(plan.phaseEnd))").font(.subheadline.bold())
        Text(plan.phase.focus).font(.footnote).foregroundStyle(.secondary)
        if let next = plan.nextPhase {
          Text("Danach: \(next.rawValue)").font(.caption).foregroundStyle(.secondary)
        }
      }
      DisclosureGroup("Plan dieser Phase") {
        PlanLine(title: "Laufen", text: plan.plan.run)
        PlanLine(title: "Schwimmen", text: plan.plan.swim)
        PlanLine(title: "Rad", text: plan.plan.bike)
        PlanLine(title: "Kraft", text: plan.plan.strength)
      }
      DisclosureGroup("Saisonphasen") {
        ForEach(plan.phases, id: \.phase) { span in
          HStack {
            Text(span.phase.rawValue).fontWeight(span.phase == plan.phase ? .bold : .regular)
            Spacer()
            Text("\(GermanFormat.date(span.start)) – \(GermanFormat.date(span.end))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    } header: {
      Text("Rennvorbereitung")
    }
  }

  private func countdown(_ days: Int) -> String {
    switch days {
    case ..<0: "vorbei"
    case 0: "heute"
    case 1: "morgen"
    default: "noch \(days) Tage"
    }
  }
}

private struct PlanLine: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.caption.bold())
      Text(text).font(.footnote)
    }
  }
}

struct SyncStatusSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Section {
      if model.isSyncing {
        HStack {
          ProgressView()
          Text("Garmin-Daten werden abgerufen …")
        }
      } else if let lastSync = model.lastSync {
        LabeledContent("Letzter Abruf") {
          Text(lastSync, format: .relative(presentation: .named))
        }
      }
      if let error = model.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .font(.footnote)
      }
      if let report = model.lastReport, !report.errors.isEmpty {
        Text("\(report.errors.count) Endpunkte ohne Daten – Details unter Einstellungen › Garmin-Diagnose.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct DayRow: View {
  let metrics: DailyMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(Formatters.day(metrics.day)).font(.headline)
        Spacer()
        if let status = metrics.hrvStatus {
          Text(Formatters.hrvStatus(status))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Formatters.hrvColor(status).opacity(0.2), in: Capsule())
        }
      }
      HStack(spacing: 12) {
        Metric(symbol: "heart", value: Formatters.number(metrics.restingHeartRate, unit: "bpm"))
        Metric(symbol: "waveform.path.ecg", value: Formatters.number(metrics.hrvLastNightAverage, unit: "ms"))
        Metric(symbol: "bed.double", value: Formatters.number(metrics.sleepHours, unit: "h", digits: 1))
        Metric(symbol: "battery.75percent", value: Formatters.number(metrics.bodyBatteryHigh, unit: ""))
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }
}

private struct Metric: View {
  let symbol: String
  let value: String

  var body: some View {
    Label(value, systemImage: symbol)
      .labelStyle(.titleAndIcon)
      .lineLimit(1)
  }
}

private struct ActivityRow: View {
  let activity: GarminActivity

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(activity.name ?? activity.typeKey ?? "Aktivität").font(.headline)
      HStack(spacing: 12) {
        if let day = activity.day { Text(Formatters.day(day)) }
        if let seconds = activity.durationSeconds { Text(Formatters.duration(seconds)) }
        if let meters = activity.distanceMeters, meters > 0 {
          Text(Formatters.number(meters / 1000, unit: "km", digits: 1))
        }
        if let load = activity.trainingLoad { Text("Last \(Int(load.rounded()))") }
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
    }
  }
}

enum Formatters {
  static func number(_ value: Double?, unit: String, digits: Int = 0) -> String {
    guard let value else { return "–" }
    let text = value.formatted(.number.precision(.fractionLength(digits)))
    return unit.isEmpty ? text : "\(text) \(unit)"
  }

  static func day(_ day: CalendarDay) -> String {
    day.localDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
  }

  /// „26.10.“
  static func shortDate(_ day: CalendarDay) -> String {
    String(format: "%02d.%02d.", day.day, day.month)
  }

  static func duration(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
  }

  static func hrvStatus(_ status: String) -> String {
    RecoveryEvaluator.hrvStatusGerman[status] ?? "kein Status"
  }

  static func hrvColor(_ status: String) -> Color {
    switch status {
    case "BALANCED": .green
    case "UNBALANCED": .orange
    case "LOW", "POOR": .red
    default: .gray
    }
  }
}
