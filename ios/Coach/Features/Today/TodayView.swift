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
  @State private var showChat = false

  private var refreshKey: String {
    let settings = model.settings
    return "\(days.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(activities.count)-\(gymSessions.count)-"
      + "\(settings.season.hashValue)-\(settings.competitionDecisions.values.map(\.rawValue).sorted())-"
      + "\(settings.profile.hashValue)-\(settings.planAdjustments.hashValue)-\(settings.illnessDay?.iso ?? "")"
  }

  private var gymItems: [ActivityFeed.GymItem] {
    gymSessions.compactMap(\.session).map(ActivityFeed.GymItem.init)
  }

  /// Vorschläge für diese Woche (nur eigener Wochenplan): Tagesform und Wochenbelastung.
  private func suggestions(_ snapshot: TodayViewModel.Snapshot) -> [PlanSuggestion] {
    let settings = model.settings
    guard settings.profile.mode == .personal else { return [] }
    let today = snapshot.plan.today
    var list: [PlanSuggestion] = []
    if let advice = snapshot.advice,
      let suggestion = PlanSuggestion.recovery(
        advice: advice, profile: settings.profile, adjustments: settings.planAdjustments, today: today)
    {
      list.append(suggestion)
    }
    if let load = snapshot.load,
      let suggestion = PlanSuggestion.load(
        load, profile: settings.profile, adjustments: settings.planAdjustments, today: today)
    {
      list.append(suggestion)
    }
    return list
  }

  private func nextWeekSuggestions(_ snapshot: TodayViewModel.Snapshot) -> [PlanSuggestion] {
    let settings = model.settings
    guard settings.profile.mode == .personal, let load = snapshot.load else { return [] }
    return PlanSuggestion.nextWeek(
      load: load, profile: settings.profile, adjustments: settings.planAdjustments, today: snapshot.plan.today
    ).map { [$0] } ?? []
  }

  var body: some View {
    NavigationStack {
      List {
        SyncStatusSection()

        if !model.garmin.isConfigured && !model.health.isEnabled {
          Section {
            Text(
              "Melde dich in den Einstellungen mit deinem Garmin-Konto an oder schalte den Import aus Apple Health "
                + "(Apple Watch) ein."
            )
            .foregroundStyle(.secondary)
          }
        }

        // Feste Rangfolge: „Jetzt dran“, Entscheidungen (verpasst, Vorschläge, nach dem Training), Erledigtes, die
        // Woche als Balken. Schlaf und Warnungen nur als Chips, wenn sie heute zählen; alles Weitere eine Ebene tiefer.
        if let snapshot = viewModel.snapshot {
          let allActivities = activities.compactMap(\.activity)
          let gymDays = Set(gymSessions.compactMap { $0.session?.day })
          let today = snapshot.plan.today
          if let focus = snapshot.focus {
            NowSection(snapshot: snapshot, focus: focus)
          }
          CoachNoteSection(viewModel: viewModel)
          if let sessions = snapshot.sessions {
            MissedSessionSection(week: sessions)
          }
          SuggestionsSection(suggestions: suggestions(snapshot))
          PostWorkoutSection(records: activities.filter { $0.dayKey == today.iso }, sessions: snapshot.sessions)
          if let today = snapshot.today, model.settings.profile.mode == .season {
            SeasonOpenSections(today: today)
          }
          if WeeklyReview.isDue(today), let focus = snapshot.focus {
            WeeklyReviewSection(
              review: WeeklyReview.make(
                progress: focus.progress, week: snapshot.sessions, activities: allActivities, gym: gymItems,
                today: today))
            SuggestionsSection(suggestions: nextWeekSuggestions(snapshot), title: "Vorschlag für nächste Woche")
          }
          DoneTodaySection(records: activities, gymRecords: gymSessions, today: today)
          MotivationSections(snapshot: snapshot, activities: allActivities, gymDays: gymDays, showsLeague: false)
          TodayHintsSection(snapshot: snapshot, activities: allActivities, days: days.compactMap(\.metrics))

          Section {
            NavigationLink {
              WeekOverviewView(
                snapshot: snapshot, records: Array(activities.prefix(5)), activities: allActivities,
                gymDays: gymDays)
            } label: {
              VStack(alignment: .leading, spacing: 6) {
                if let progress = snapshot.focus?.progress {
                  Text(progress.text).font(.subheadline.weight(.semibold)).monospacedDigit()
                  ProgressView(value: progress.fraction).tint(progress.fraction >= 1 ? .green : .accentColor)
                }
                Label("Diese Woche, Ziele und Verlauf", systemImage: "calendar").font(.subheadline)
              }
            }
          } header: {
            Text("Woche")
          } footer: {
            if let lastSync = model.lastSync ?? model.health.lastImport {
              Text("Letzter Abruf \(lastSync.formatted(.relative(presentation: .named)))")
            }
          }
        }
      }
      .navigationTitle("Heute")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Coach fragen", systemImage: "bubble.left.and.text.bubble.right") { showChat = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Einstellungen", systemImage: "gearshape") { showSettings = true }
        }
      }
      .sheet(isPresented: $showSettings) { SettingsView() }
      .sheet(isPresented: $showChat) { ChatView(snapshot: viewModel.snapshot) }
      .refreshable {
        await model.syncNow()
        await viewModel.loadNote(ai: model.ai, settings: model.settings)
      }
      .task(id: refreshKey) {
        viewModel.update(
          days: days.compactMap(\.metrics),
          activities: activities.compactMap(\.activity),
          settings: model.settings,
          gymDays: gymSessions.compactMap { $0.session?.day },
          gym: gymItems
        )
        await viewModel.loadNote(ai: model.ai, settings: model.settings)
      }
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

/// Saisonplan: offene Läufe ohne festen Tag und Ausfälle am letzten Wochentag (die heutigen Einheiten stehen in
/// „Jetzt dran“).
private struct SeasonOpenSections: View {
  let today: TodayPlan

  var body: some View {
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

/// Heute erledigt, aus dem gemeinsamen Verlauf: Garmin, Apple Health, Nachgetragenes und Gym (Doppelte einmal).
private struct DoneTodaySection: View {
  let records: [ActivityRecord]
  let gymRecords: [GymSessionRecord]
  let today: CalendarDay

  var body: some View {
    let todays = records.filter { $0.dayKey == today.iso }
    let gym = gymRecords.filter { $0.session?.day == today }
    let entries = ActivityFeed.entries(
      activities: todays.compactMap(\.activity), gym: gym.compactMap(\.session).map(ActivityFeed.GymItem.init))
    if !entries.isEmpty {
      Section("Heute erledigt") {
        ForEach(entries) { entry in
          FeedEntryLink(
            entry: entry, record: todays.first { $0.garminID == entry.activity?.id },
            gymRecord: gym.first { $0.id == entry.gym?.id })
        }
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
      Text(model.settings.profile.mode == .season ? "Coach-Notiz" : "Warum?")
    }
  }
}

/// Alles, was nicht nur heute zählt: Rest der Woche, Wochenziele, Ziele, Rangliste und die letzten Aktivitäten.
private struct WeekOverviewView: View {
  let snapshot: TodayViewModel.Snapshot
  let records: [ActivityRecord]
  let activities: [GarminActivity]
  let gymDays: Set<CalendarDay>
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      if model.settings.profile.mode == .season {
        if let today = snapshot.today, !today.rest.isEmpty {
          RestOfWeekSection(items: today.rest)
        }
        WeekSection(plan: snapshot.plan)
      } else {
        PersonalWeekSections(snapshot: snapshot, activities: activities, gymDays: gymDays)
      }
      MotivationSections(snapshot: snapshot, activities: activities, gymDays: gymDays, showsCompanion: false)
      if let imported = model.settings.importedNotes {
        Section {
          ForEach(imported.texts, id: \.self) { Label($0, systemImage: "sparkles").font(.subheadline) }
          Button("Hinweise entfernen", role: .destructive) { model.settings.importedNotes = nil }
        } header: {
          Text("Vom KI-Coach (Import vom \(Formatters.shortDate(imported.day)))")
        }
      }
      if !records.isEmpty {
        Section("Letzte Aktivitäten") {
          ForEach(records) { record in
            if let activity = record.activity {
              NavigationLink {
                ActivityDetailView(record: record)
              } label: {
                ActivitySummaryRow(activity: activity)
              }
            }
          }
          NavigationLink("Alle Aktivitäten") { ActivityListView() }
        }
      }
    }
    .navigationTitle("Diese Woche")
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
          Text("Daten werden abgerufen …")
        }
      }
      if let error = model.lastError {
        Label(error, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.orange)
          .font(.footnote)
      }
      // Vom Health-Import nur Probleme zeigen; die Zusammenfassung steht in den Einstellungen.
      if let result = model.health.lastResult, result.hasPrefix("Keine") || result.contains("nicht lesbar") {
        Text(result).font(.footnote).foregroundStyle(.secondary)
      }
      if let report = model.lastReport, !report.errors.isEmpty {
        Text("\(report.errors.count) Endpunkte ohne Daten – Details unter Einstellungen › Garmin-Diagnose.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
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
