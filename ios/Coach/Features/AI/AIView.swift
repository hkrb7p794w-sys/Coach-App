import CoachCore
import SwiftData
import SwiftUI

/// Reiter „AI“: alle Empfehlungen aus Regeln und KI an einem Ort, nach Themen, mit Bearbeitungsstand; dazu die
/// KI-Analyse auf Anfrage und alle übrigen KI-Funktionen. Gezeigt werden Erkenntnis und Empfehlung – die Grundlage
/// bleibt intern (lange drücken › „Worauf beruht das?“).
struct AIView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymSessions: [GymSessionRecord]
  @State private var viewModel = AIViewModel()
  @State private var topic: InsightTopic?
  @State private var basis: Insight?
  @State private var showsChat = false
  @State private var showsClosed = false
  @State private var showsGymPlan = false

  var body: some View {
    let now = Date.now
    let goals = model.settings.profile.effectiveGoals(today: CalendarDay(date: now))
    let groups = InsightInbox.groups(
      model.settings.insights, topic: topic, focus: Personalization.insightTopics(goals), now: now)
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          Section {
            TopicChips(selection: $topic, insights: model.settings.insights, now: now)
              .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
          }
          if groups.new.isEmpty && groups.open.isEmpty {
            Section {
              Text(
                topic == nil
                  ? "Gerade keine offenen Empfehlungen. Die Regeln der App melden sich, sobald es etwas gibt."
                  : "Zu „\(topic?.label ?? "")“ gibt es gerade nichts Offenes."
              )
              .foregroundStyle(.secondary)
            }
          }
          if !groups.new.isEmpty {
            Section("Neu") { rows(groups.new) }
          }
          if !groups.open.isEmpty {
            Section("Aktuell") { rows(groups.open) }
          }
          analysisSection
          if !groups.expired.isEmpty {
            Section {
              rows(groups.expired)
            } header: {
              Text("Nicht mehr aktuell")
            } footer: {
              Text("Gilt nicht mehr, weil sich deine Daten geändert haben oder die Zeit abgelaufen ist.")
            }
          }
          if !groups.closed.isEmpty {
            Section(isExpanded: $showsClosed) {
              rows(groups.closed)
            } header: {
              Text("Umgesetzt und verworfen (\(groups.closed.count))")
            }
          }
          functionsSection
        }
        // Schnellaktion / Kurzbefehl „KI-Analyse starten“: zur Analyse springen und sie anstoßen, sofern erlaubt.
        .onChange(of: AppRouter.shared.pending, initial: true) {
          guard AppRouter.shared.take(.aiAnalysis) else { return }
          topic = nil
          Task {
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation { proxy.scrollTo(Self.analysisID, anchor: .top) }
            analyzeFromShortcut()
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("AI")
      .refreshable { refreshRules() }
      .task(id: refreshKey) { refreshRules() }
      .sheet(item: $basis) { insight in InsightBasisSheet(insight: insight) }
      .sheet(isPresented: $showsChat) { ChatView(snapshot: viewModel.snapshot) }
      .sheet(isPresented: $showsGymPlan) { GymPlanView(viewModel: GymViewModel.shared) }
    }
  }

  private var refreshKey: Int {
    var hasher = Hasher()
    hasher.combine(days.count)
    hasher.combine(activities.count)
    hasher.combine(meals.count)
    hasher.combine(gymSessions.count)
    hasher.combine(CalendarDay(date: .now).iso)
    return hasher.finalize()
  }

  private func refreshRules() {
    viewModel.refreshRules(
      model: model, metrics: days.compactMap(\.metrics), activities: activities.compactMap(\.activity),
      meals: meals, gym: gymSessions.compactMap(\.session))
  }

  @ViewBuilder private func rows(_ insights: [Insight]) -> some View {
    ForEach(insights) { insight in
      InsightRow(insight: insight)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.mark(.read, insight, model: model, onlyIfNew: true) }
        .swipeActions(edge: .trailing) {
          if insight.status != .dismissed {
            Button("Verwerfen", systemImage: "xmark") { viewModel.mark(.dismissed, insight, model: model) }
              .tint(.gray)
          }
        }
        .swipeActions(edge: .leading) {
          if insight.status != .done {
            Button("Umgesetzt", systemImage: "checkmark") { viewModel.mark(.done, insight, model: model) }
              .tint(.green)
          }
        }
        .contextMenu {
          if insight.status == .new {
            Button("Als gelesen markieren", systemImage: "envelope.open") {
              viewModel.mark(.read, insight, model: model)
            }
          }
          Button("Umgesetzt", systemImage: "checkmark") { viewModel.mark(.done, insight, model: model) }
          Button("Verwerfen", systemImage: "xmark") { viewModel.mark(.dismissed, insight, model: model) }
          if insight.status == .done || insight.status == .dismissed {
            Button("Wieder öffnen", systemImage: "arrow.uturn.backward") {
              viewModel.mark(.read, insight, model: model)
            }
          }
          Button("Worauf beruht das?", systemImage: "info.circle") { basis = insight }
        }
    }
  }

  private static let analysisID = "analysis"

  private func analyze() async {
    await viewModel.analyze(
      topic: topic, model: model, metrics: days.compactMap(\.metrics),
      activities: activities.compactMap(\.activity), meals: meals, gym: gymSessions.compactMap(\.session))
  }

  private func analyzeFromShortcut() {
    guard model.ai.allows("ai_insights"), !viewModel.isAnalyzing else { return }
    Task { await analyze() }
  }

  private var analysisSection: some View {
    Section {
      if model.ai.allows("ai_insights") {
        Button {
          Task { await analyze() }
        } label: {
          Label(
            topic.map { "„\($0.label)“ analysieren" } ?? "Alles analysieren",
            systemImage: viewModel.isAnalyzing ? "hourglass" : "sparkles")
        }
        .disabled(viewModel.isAnalyzing)
      } else {
        Text(analysisUnavailableText).foregroundStyle(.secondary)
      }
      if let error = viewModel.error {
        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
      }
      if let note = viewModel.note {
        Text(note).font(.footnote).foregroundStyle(.secondary)
      }
      if !viewModel.missing.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Es fehlen Daten – dazu gibt es keine Aussage:").font(.footnote.bold())
          ForEach(viewModel.missing, id: \.self) { Text("· \($0)").font(.footnote) }
        }
        .foregroundStyle(.secondary)
      }
    } header: {
      Text("KI-Analyse")
    } footer: {
      Text(
        "Die KI wertet nur deine Daten aus, die die App selbst berechnet hat, und widerspricht den Regeln nicht. "
          + "Unsichere Aussagen sind gekennzeichnet."
      )
    }
    .id(Self.analysisID)
  }

  private var analysisUnavailableText: String {
    if !model.ai.isConfigured { return "Für die KI-Analyse den KI-Worker in den Einstellungen einrichten." }
    return AIPolicy.blockedMessage(model.settings.ai.mode)
  }

  private var functionsSection: some View {
    Section {
      if model.ai.allows("coach_chat") {
        Button("Coach fragen", systemImage: "bubble.left.and.text.bubble.right") { showsChat = true }
      }
      if model.settings.profile.trains(.strength) {
        Button("Trainingsplan von der KI", systemImage: "dumbbell") { showsGymPlan = true }
      }
      NavigationLink {
        RecipesView()
      } label: {
        Label("Rezeptideen für die Woche", systemImage: "frying.pan")
      }
      NavigationLink {
        PromptLibraryView()
      } label: {
        Label("Prompt-Bibliothek für externe KI", systemImage: "text.bubble")
      }
      NavigationLink {
        CoachExportView()
      } label: {
        Label("Daten für eine externe KI exportieren", systemImage: "square.and.arrow.up")
      }
      NavigationLink {
        CoachImportView()
      } label: {
        Label("Antwort einer externen KI übernehmen", systemImage: "square.and.arrow.down")
      }
      NavigationLink {
        Form { AISettingsSection() }.navigationTitle("KI-Einstellungen")
      } label: {
        Label("KI-Einstellungen", systemImage: "gearshape")
      }
    } header: {
      Text("Weitere KI-Funktionen")
    } footer: {
      Text("Mahlzeiten per Foto oder Text erfasst du im Reiter Ernährung, die Tagesnotiz steht unter „Heute“.")
    }
  }
}

/// Themen als Filter; die Zahl zeigt neue Empfehlungen.
private struct TopicChips: View {
  @Binding var selection: InsightTopic?
  let insights: [Insight]
  let now: Date

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip(nil, label: "Alle", count: InsightInbox.unreadCount(insights, now: now))
        ForEach(InsightTopic.allCases, id: \.self) { topic in
          let topicInsights = insights.filter { $0.topic == topic }
          if !topicInsights.isEmpty {
            chip(topic, label: topic.label, count: InsightInbox.unreadCount(topicInsights, now: now))
          }
        }
      }
      .padding(.horizontal, 16)
    }
  }

  private func chip(_ topic: InsightTopic?, label: String, count: Int) -> some View {
    Button {
      selection = topic
    } label: {
      HStack(spacing: 4) {
        if let topic { Image(systemName: topic.symbol) }
        Text(label)
        if count > 0 {
          Text("\(count)").font(.caption.bold()).padding(.horizontal, 6).background(.red, in: Capsule())
            .foregroundStyle(.white)
        }
      }
      .padding(.horizontal, 12).padding(.vertical, 8)
      .background(
        selection == topic ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12), in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selection == topic ? .isSelected : [])
  }
}

/// Erkenntnis und Empfehlung – ohne Datenquellen.
private struct InsightRow: View {
  let insight: Insight

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: insight.topic.symbol)
        .foregroundStyle(insight.status == .new ? Color.accentColor : .secondary)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(insight.title).font(.headline)
          if insight.status == .new {
            Circle().fill(Color.accentColor).frame(width: 8, height: 8).accessibilityLabel("neu")
          }
        }
        Text(insight.text).font(.subheadline)
        HStack(spacing: 8) {
          Text(insight.topic.label)
          if insight.uncertain { Text("· unsicher, wenige Daten") }
          if insight.status == .done { Text("· umgesetzt") }
          if insight.status == .dismissed { Text("· verworfen") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}

/// Interne Nachvollziehbarkeit: worauf eine Empfehlung beruht, woher sie kommt und wie lange sie gilt.
private struct InsightBasisSheet: View {
  let insight: Insight
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section("Grundlage") {
          ForEach(insight.basis, id: \.self) { Text($0) }
        }
        Section("Herkunft") {
          LabeledContent("Erstellt von", value: insight.origin == .rules ? "Regeln der App" : "KI")
          if let model = insight.model { LabeledContent("Modell", value: model) }
          LabeledContent("Erstellt", value: insight.created.formatted(date: .abbreviated, time: .shortened))
          LabeledContent("Gilt bis", value: insight.validUntil.formatted(date: .abbreviated, time: .shortened))
          LabeledContent("Betreff", value: insight.subject)
        }
      }
      .navigationTitle("Worauf beruht das?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
    }
    .presentationDetents([.medium, .large])
  }
}
