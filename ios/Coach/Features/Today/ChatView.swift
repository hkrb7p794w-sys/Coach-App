import CoachCore
import SwiftData
import SwiftUI

/// Chat mit dem Coach. Die App schickt nur Fakten aus ihren Regeln (im Modus „reduziert“ ohne Rohwerte); die KI
/// antwortet daraus. Antworten mit Zahlen, die nicht in den Fakten stehen, verwirft der Worker. Der Verlauf bleibt
/// nur im Speicher, solange der Chat offen ist.
struct ChatView: View {
  let snapshot: TodayViewModel.Snapshot?
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymSessions: [GymSessionRecord]

  struct Message: Identifiable, Equatable {
    let id = UUID()
    let fromCoach: Bool
    let text: String
    var sources: [String] = []
  }

  @State private var messages: [Message] = []
  @State private var draft = ""
  @State private var isSending = false
  @FocusState private var focused: Bool

  private let suggestions = [
    "Soll ich heute hart trainieren?", "Wie war mein Schlaf diese Woche?", "Wie viel sollte ich heute essen?",
    "Wie läuft meine Vorbereitung?",
  ]

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          if messages.isEmpty {
            Section {
              Text(
                "Frag mich zu Training, Erholung, Schlaf oder Ernährung. Ich antworte nur aus deinen Daten und den "
                  + "Regeln der App."
              )
              .font(.subheadline)
              .foregroundStyle(.secondary)
              ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { send(suggestion) }
              }
            }
          }
          ForEach(messages) { message in
            bubble(message).id(message.id).listRowSeparator(.hidden)
          }
          if isSending {
            HStack(spacing: 8) {
              ProgressView()
              Text("Coach denkt nach …").font(.subheadline).foregroundStyle(.secondary)
            }
            .listRowSeparator(.hidden)
          }
        }
        .listStyle(.plain)
        .onChange(of: messages) { _, messages in
          if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
      }
      .safeAreaInset(edge: .bottom) { inputBar }
      .navigationTitle("Coach fragen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
      }
    }
  }

  private var inputBar: some View {
    HStack(spacing: 8) {
      TextField("Frage stellen", text: $draft, axis: .vertical)
        .lineLimit(1...4)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .submitLabel(.send)
        .onSubmit { send(draft) }
      Button {
        send(draft)
      } label: {
        Image(systemName: "arrow.up.circle.fill").font(.title)
      }
      .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
      .accessibilityLabel("Senden")
    }
    .padding()
    .background(.bar)
  }

  @ViewBuilder
  private func bubble(_ message: Message) -> some View {
    VStack(alignment: message.fromCoach ? .leading : .trailing, spacing: 6) {
      Text(message.text)
        .padding(10)
        .background(
          message.fromCoach ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.2),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .textSelection(.enabled)
      if !message.sources.isEmpty {
        EvidenceDisclosure(ruleIDs: message.sources, title: "Belege")
          .font(.caption)
      }
    }
    .frame(maxWidth: .infinity, alignment: message.fromCoach ? .leading : .trailing)
  }

  private func send(_ text: String) {
    let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty, !isSending else { return }
    let history = messages.map { (role: $0.fromCoach ? "coach" : "user", text: $0.text) }
    messages.append(Message(fromCoach: false, text: question))
    draft = ""
    guard model.ai.isConfigured else {
      messages.append(
        Message(fromCoach: true, text: "Für den Chat brauche ich den KI-Worker – richte ihn in den Einstellungen ein."))
      return
    }
    isSending = true
    let input = ChatContext.input(facts(), question: question, history: history)
    Task {
      defer { isSending = false }
      do {
        let response = try await model.ai.run(task: "coach_chat", input: input)
        if let answer = ChatContext.answer(from: response.output) {
          messages.append(Message(fromCoach: true, text: answer.text, sources: answer.sources))
        } else {
          messages.append(Message(fromCoach: true, text: "Dazu habe ich gerade keine belegte Antwort."))
        }
      } catch {
        messages.append(
          Message(
            fromCoach: true,
            text:
              "Dazu konnte ich keine Antwort geben, die sich auf deine Daten stützt. Schau unter „Heute“, „Plan“ "
              + "oder „Training“ nach."))
      }
    }
  }

  /// Fakten aus den Regeln der App für die Frage.
  private func facts() -> ChatContext.Facts {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    var facts = ChatContext.Facts(profile: settings.profile, privacy: settings.privacy)
    let metrics = days.compactMap(\.metrics)
    let allActivities = activities.compactMap(\.activity)
    if let snapshot {
      facts.recommendation = snapshot.recommendation.label
      facts.reasons = snapshot.recommendation.reasons
      if let advice = snapshot.advice {
        facts.todaySessions = [advice.headline]
      } else if let plan = snapshot.today {
        facts.todaySessions = plan.items.map(\.title)
      }
    }
    if settings.profile.mode == .personal {
      let schedule = settings.schedule(inWeekOf: today)
      facts.runWeek = RunPlanner.week(
        profile: settings.profile, schedule: schedule, monday: PlanAdjustments.monday(of: today),
        activities: allActivities)
      if facts.todaySessions.isEmpty {
        facts.todaySessions = schedule.slots(on: Weekday(day: today)).map(\.title)
      }
    }
    facts.sleep = SleepCoach.report(days: metrics, settings: settings.sleep, goal: settings.profile.goal, today: today)
    facts.targets = NutritionPlanner.compute(
      activities: allActivities.filter { $0.day == today }, planItems: [], settings: settings.nutrition,
      garminProfile: model.sync.profile, day: today, hasGarminData: !metrics.isEmpty)
    let eaten = meals.filter { $0.dayKey == today.iso }.flatMap(\.items)
    if !eaten.isEmpty { facts.eatenKilocalories = NutritionSummary.totals(eaten)[.kcal] }
    facts.weightTrend = WeightTrend.trend(WeightTrend.merged(settings.weights + model.sync.weights), today: today)
    let form = FitnessForm.series(activities: allActivities, today: today)
    if FitnessForm.isReliable(form), let percent = form.last?.formPercent {
      facts.formZone = FitnessForm.Zone.of(percent)
    }
    facts.weekHighlights =
      WeeklyReport.lastWeek(
        activities: allActivities, days: metrics, gymDays: gymSessions.compactMap { $0.session?.day }, today: today
      ).highlights
    return facts
  }
}
