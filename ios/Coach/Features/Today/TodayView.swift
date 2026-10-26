import CoachCore
import SwiftData
import SwiftUI

/// Tagesempfehlung, Wochen-Soll/Ist, Rennvorbereitung und die Garmin-Werte der letzten Tage.
struct TodayView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymSessions: [GymSessionRecord]
  @State private var viewModel = TodayViewModel()
  @State private var showSettings = false

  private var refreshKey: String {
    let settings = model.settings
    return "\(days.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(activities.count)-\(gymSessions.count)-"
      + "\(settings.season.hashValue)-\(settings.competitionDecisions.values.map(\.rawValue).sorted())-"
      + "\(settings.profile.hashValue)"
  }

  var body: some View {
    NavigationStack {
      List {
        SyncStatusSection()

        if !model.garmin.isConfigured {
          Section {
            Text("Melde dich in den Einstellungen mit deinem Garmin-Konto an (oder hinterlege den Personal API Key).")
              .foregroundStyle(.secondary)
          }
        }

        if let snapshot = viewModel.snapshot {
          if model.settings.profile.mode == .season {
            RecommendationSection(snapshot: snapshot)
            if let today = snapshot.today {
              TodayUnitsSection(today: today)
            }
            CoachNoteSection(viewModel: viewModel)
            if let today = snapshot.today, !today.rest.isEmpty {
              RestOfWeekSection(items: today.rest)
            }
            WeekSection(plan: snapshot.plan)
          } else {
            PersonalTodaySections(
              snapshot: snapshot, activities: activities.compactMap(\.activity),
              gymDays: Set(gymSessions.compactMap { $0.session?.day }))
          }
        }

        if !activities.isEmpty {
          Section("Letzte Aktivitäten") {
            ForEach(activities.prefix(5)) { record in
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
        if model.settings.profile.mode == .season {
          await viewModel.loadNote(ai: model.ai, settings: model.settings)
        }
      }
      .task(id: refreshKey) {
        viewModel.update(
          days: days.compactMap(\.metrics),
          activities: activities.compactMap(\.activity),
          settings: model.settings,
          gymDays: gymSessions.compactMap { $0.session?.day }
        )
        if model.settings.profile.mode == .season {
          await viewModel.loadNote(ai: model.ai, settings: model.settings)
        }
      }
    }
  }
}

/// Tagesampel als Kopf der Seite: Stufe, Ratschlag, Gründe, Phase und Countdown.
private struct RecommendationSection: View {
  let snapshot: TodayViewModel.Snapshot
  @Environment(AppModel.self) private var model

  private var color: Color {
    switch snapshot.recommendation.level {
    case .normal: .green
    case .locker: .orange
    case .pause: .red
    }
  }

  private var symbol: String {
    switch snapshot.recommendation.level {
    case .normal: "checkmark.circle.fill"
    case .locker: "tortoise.fill"
    case .pause: "bed.double.fill"
    }
  }

  var body: some View {
    let plan = snapshot.plan
    let season = model.settings.season
    Section {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: symbol)
            .font(.title)
            .foregroundStyle(.white)
            .frame(width: 52, height: 52)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.recommendation.label).font(.title3.bold())
            Text(snapshot.today?.advice ?? snapshot.recommendation.advice).font(.subheadline)
          }
        }
        if !snapshot.recommendation.reasons.isEmpty {
          Text(snapshot.recommendation.reasons.joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        if snapshot.isFromYesterday {
          Label("Noch keine Garmin-Werte für heute – Einordnung mit den Werten von gestern.", systemImage: "clock")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
        HStack(spacing: 8) {
          Chip(text: plan.phase.rawValue, color: .accentColor)
          if plan.daysToMarathon >= 0 { Chip(text: "Marathon \(countdown(plan.daysToMarathon))", color: .pink) }
          if plan.daysToRace >= 0 { Chip(text: "\(season.mainRaceName) \(countdown(plan.daysToRace))", color: .teal) }
        }
      }
      .padding(.vertical, 4)
    } header: {
      Text("\(plan.weekday), \(Formatters.shortDate(plan.today))")
    }
  }

  private func countdown(_ days: Int) -> String {
    switch days {
    case 0: "heute"
    case 1: "morgen"
    default: "in \(days) T."
    }
  }
}

/// Kleine farbige Kapsel für Phase, Countdown und Hinweise.
struct Chip: View {
  let text: String
  let color: Color

  var body: some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(color.opacity(0.15), in: Capsule())
      .foregroundStyle(color)
  }
}

/// Heutige Einheiten, offene Läufe ohne festen Tag und Ausfälle am letzten Wochentag.
private struct TodayUnitsSection: View {
  let today: TodayPlan

  var body: some View {
    Section {
      if today.items.isEmpty {
        Text("Heute nichts Festes.").foregroundStyle(.secondary)
      }
      ForEach(today.items) { item in TodayItemRow(item: item) }
    } header: {
      Text("Heute")
    } footer: {
      if !today.focus.isEmpty { Text(today.focus) }
    }
    if !today.open.isEmpty {
      Section {
        ForEach(today.open) { item in TodayItemRow(item: item) }
      } header: {
        Text("Noch offen · ohne festen Tag")
      } footer: {
        if !today.hint.isEmpty { Text(today.hint) }
      }
    }
    if !today.skipped.isEmpty {
      Section("Fällt diese Woche aus") {
        ForEach(today.skipped) { item in TodayItemRow(item: item) }
      }
    }
  }
}

private struct TodayItemRow: View {
  let item: TodayPlan.Item
  @State private var expanded = false

  private var kind: PlannedUnit.Kind {
    switch item.sport {
    case .swim: .swim
    case .bike: .bike
    case .run: item.title.hasPrefix("Longrun") ? .longRun : (item.hardness >= 2 ? .quality : .easyRun)
    case .strength, .rest: .gym
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 12) {
        if item.sport == .rest {
          SportIcon(symbol: "leaf.fill", color: .mint)
        } else {
          SportIcon(symbol: kind.symbol, color: kind.color)
        }
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            if let day = item.day { Text(day).font(.caption.bold()).foregroundStyle(.secondary) }
            Text(item.title).font(.headline)
          }
          if !item.caption.isEmpty {
            Text(item.caption).font(.subheadline).foregroundStyle(.secondary)
          }
          if !item.chip.isEmpty {
            Chip(text: item.chip, color: item.chip == "nur locker bewegen" ? .red : .orange)
          }
        }
        Spacer(minLength: 0)
        if item.done {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("erledigt")
        }
      }
      if expanded, !item.detail.isEmpty {
        Text(item.detail).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { if !item.detail.isEmpty { withAnimation { expanded.toggle() } } }
    .accessibilityHint(item.detail.isEmpty ? "" : "Doppeltippen zeigt den Ablauf")
  }
}

/// Coach-Notiz der KI (oder regelbasiert) mit Grundlage.
private struct CoachNoteSection: View {
  let viewModel: TodayViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    Section {
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
      EvidenceDisclosure(ruleIDs: viewModel.noteEvidence)
    } header: {
      Text("Coach-Notiz")
    }
  }
}

private struct RestOfWeekSection: View {
  let items: [TodayPlan.Item]

  var body: some View {
    Section("Rest der Woche") {
      ForEach(items) { item in TodayItemRow(item: item) }
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
