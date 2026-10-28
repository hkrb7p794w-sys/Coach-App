import CoachCore
import SwiftUI

/// „Jetzt dran“: immer die erste Karte auf „Heute“, in beiden Modi gleich. Heutige Einheiten mit Soll, Ampel, eine
/// Zeile „warum“ und – wenn Regel und Plan sich widersprechen – beides mit der Entscheidung.
struct NowSection: View {
  let snapshot: TodayViewModel.Snapshot
  let focus: TodayFocus
  @Environment(AppModel.self) private var model

  private var color: Color {
    switch focus.level ?? .normal {
    case .normal: .green
    case .locker: .orange
    case .pause: .red
    }
  }

  private var symbol: String {
    if snapshot.advice?.mode == .done { return "checkmark.seal.fill" }
    if snapshot.advice?.mode == .restDay { return "leaf.fill" }
    switch focus.level ?? .normal {
    case .normal: return "checkmark.circle.fill"
    case .locker: return "tortoise.fill"
    case .pause: return "bed.double.fill"
    }
  }

  var body: some View {
    let plan = snapshot.plan
    let settings = model.settings
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
            Text(focus.headline).font(.title3.bold())
            Text(focus.level.map { "Erholung: \($0.label)" } ?? "Noch keine Erholungswerte für heute")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }
        if !focus.detail.isEmpty {
          Text(focus.detail).font(.subheadline)
        }
        if let why = focus.why {
          Label(why, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
        }
        if let conflict = focus.conflict {
          Label(conflict, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
        }
        if snapshot.isFromYesterday {
          Label("Noch keine Garmin-Werte für heute – Einordnung mit den Werten von gestern.", systemImage: "clock")
            .font(.footnote)
            .foregroundStyle(.orange)
        }
        if settings.profile.mode == .season {
          HStack(spacing: 8) {
            Chip(text: plan.phase.rawValue, color: .accentColor)
            if plan.daysToMarathon >= 0 { Chip(text: "Marathon \(countdown(plan.daysToMarathon))", color: .pink) }
            if plan.daysToRace >= 0 {
              Chip(text: "\(settings.season.mainRaceName) \(countdown(plan.daysToRace))", color: .teal)
            }
          }
        }
      }
      .padding(.vertical, 4)

      if focus.items.isEmpty {
        Text(settings.profile.mode == .season ? "Heute nichts Festes." : "Heute nichts geplant.")
          .foregroundStyle(.secondary)
      }
      ForEach(focus.items) { item in FocusItemRow(item: item) }
      if let note = snapshot.today?.focus, !note.isEmpty {
        Text(note).font(.footnote).foregroundStyle(.secondary)
      }
      if let advice = snapshot.advice {
        personalActions(advice)
      }
      if !focus.evidenceIDs.isEmpty {
        EvidenceDisclosure(ruleIDs: focus.evidenceIDs)
      }
    } header: {
      Text("Jetzt dran · \(plan.weekday), \(Formatters.shortDate(plan.today))")
    }
  }

  @ViewBuilder
  private func personalActions(_ advice: ScheduleAdvice) -> some View {
    let today = snapshot.plan.today
    let settings = model.settings
    let slots = settings.schedule(inWeekOf: today).slots(on: Weekday(day: today))
    let note = settings.planAdjustments.note(for: Weekday(day: today), inWeekOf: today)
    if let note {
      Label("Heute: \(note)", systemImage: "calendar.badge.clock").font(.footnote).foregroundStyle(.secondary)
    }
    if advice.mode != .done, !slots.isEmpty || note != nil {
      ScrollView(.horizontal, showsIndicators: false) {
        PlanDayActions(day: today, suggested: advice.move)
      }
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

/// Eine heutige Einheit: Sportart, Titel, Soll bzw. Soll/Ist, Status; Antippen zeigt den Ablauf.
private struct FocusItemRow: View {
  let item: TodayFocus.Item
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 12) {
        SportIcon(symbol: item.sport?.symbol ?? "leaf.fill", color: item.sport?.color ?? .mint)
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title).font(.headline)
          if !item.target.isEmpty {
            Text(item.target).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
          }
          if !item.chip.isEmpty {
            Chip(text: item.chip, color: item.chip == "nur locker bewegen" ? .red : .orange)
          }
        }
        Spacer(minLength: 0)
        if let status = item.status, status != .open, status != .planned {
          SessionStatusBadge(status: status)
        }
      }
      if expanded, !item.detail.isEmpty {
        Text(item.detail).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { if !item.detail.isEmpty { withAnimation { expanded.toggle() } } }
    .accessibilityElement(children: .combine)
    .accessibilityHint(item.detail.isEmpty ? "" : "Doppeltippen zeigt den Ablauf")
  }
}

/// Gemeinsame Vorschlagsliste: jeder Vorschlag mit Diff, Regelprüfung und Übernehmen, Anpassen, Verwerfen.
/// Übernommene bleiben mit Rückgängig stehen, solange die Seite offen ist.
struct SuggestionsSection: View {
  let suggestions: [PlanSuggestion]
  var title = "Vorschläge"
  @Environment(AppModel.self) private var model
  @State private var applied: [Applied] = []
  @State private var editing: PlanSuggestion?

  var body: some View {
    let settings = model.settings
    let visible = suggestions.filter { suggestion in
      !settings.dismissedSuggestions.contains(suggestion.id) && !applied.contains { $0.id == suggestion.id }
    }
    if !visible.isEmpty || !applied.isEmpty {
      Section(title) {
        ForEach(applied) { entry in
          HStack {
            Label("Übernommen: \(entry.title)", systemImage: "checkmark").font(.subheadline)
            Spacer()
            Button("Rückgängig") {
              settings.planAdjustments = entry.previous
              applied.removeAll { $0.id == entry.id }
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
          }
        }
        ForEach(visible) { suggestion in
          SuggestionCard(
            suggestion: suggestion,
            apply: {
              applied.append(Applied(id: suggestion.id, title: suggestion.title, previous: settings.planAdjustments))
              settings.planAdjustments = suggestion.adjustments
            },
            adjust: { editing = suggestion },
            dismiss: {
              settings.dismissedSuggestions = Array((settings.dismissedSuggestions + [suggestion.id]).suffix(60))
            })
        }
      }
      .sheet(item: $editing) { suggestion in
        NextWeekPlanSheet(monday: suggestion.week, initial: suggestion.schedule)
      }
    }
  }
}

/// Übernommener Vorschlag mit dem Stand davor (für Rückgängig).
private struct Applied: Identifiable {
  let id: String
  let title: String
  let previous: PlanAdjustments
}

/// Ein Vorschlag als Karte: Quelle, Titel, Begründung, Diff je Tag, was bleibt, neue Regelkonflikte.
struct SuggestionCard: View {
  let suggestion: PlanSuggestion
  let apply: () -> Void
  let adjust: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(suggestion.source.label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
      Text(suggestion.title).font(.subheadline.weight(.semibold))
      if !suggestion.reason.isEmpty {
        Text(suggestion.reason).font(.footnote).foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        ForEach(suggestion.changes) { change in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(change.weekday.short).font(.caption.bold()).frame(width: 24, alignment: .leading)
            Text(PlanSuggestion.text(change.before)).strikethrough().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(PlanSuggestion.text(change.after))
          }
          .font(.caption)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            "\(change.weekday.long): \(PlanSuggestion.text(change.before)) wird \(PlanSuggestion.text(change.after))")
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
      if !suggestion.unchanged.isEmpty {
        Text(suggestion.unchanged.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
      }
      if suggestion.conflicts.isEmpty {
        Label("Planregeln geprüft: kein neuer Konflikt", systemImage: "checkmark.shield")
          .font(.caption)
          .foregroundStyle(.green)
      }
      ForEach(suggestion.conflicts) { hint in
        Label(hint.message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
      }
      HStack(spacing: 8) {
        Button("Übernehmen", systemImage: "checkmark", action: apply)
          .buttonStyle(.borderedProminent)
        Button("Anpassen", systemImage: "slider.horizontal.3", action: adjust)
          .buttonStyle(.bordered)
        Button("Verwerfen", role: .destructive, action: dismiss)
          .buttonStyle(.borderless)
      }
      .font(.subheadline)
      .controlSize(.small)
      .labelStyle(.titleOnly)
      if !suggestion.evidenceIDs.isEmpty {
        EvidenceDisclosure(ruleIDs: suggestion.evidenceIDs)
      }
    }
    .padding(.vertical, 4)
  }
}

/// Sonntags: Soll/Ist der Woche, Belastung, Höhepunkte und der Weg zur nächsten Woche.
struct WeeklyReviewSection: View {
  let review: WeeklyReview
  @State private var planning = false

  var body: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text(review.progress.text).font(.headline).monospacedDigit()
        ProgressView(value: review.progress.fraction).tint(review.progress.fraction >= 1 ? .green : .accentColor)
      }
      if !review.missed.isEmpty {
        Label("Verpasst: \(review.missed.joined(separator: ", "))", systemImage: "xmark.circle")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Label(loadText, systemImage: "gauge.with.dots.needle.50percent").font(.subheadline)
      ForEach(review.highlights, id: \.self) { line in
        Label(line, systemImage: "star.fill").font(.subheadline).labelStyle(TintedIconLabelStyle(color: .yellow))
      }
      Button("Nächste Woche planen", systemImage: "calendar.badge.plus") { planning = true }
    } header: {
      Text("Wochenrückblick")
    } footer: {
      Text(
        "Belastung: Wert der Uhr, sonst aus Dauer × Intensität geschätzt; Vergleich mit dem Schnitt der "
          + "drei Wochen davor."
      )
    }
    .sheet(isPresented: $planning) { NextWeekPlanSheet() }
  }

  private var loadText: String {
    let load = review.load
    guard let increase = load.increase else { return "Belastung der letzten 7 Tage: \(Int(load.last))" }
    let percent = Int((increase * 100).rounded())
    return "Belastung \(Int(load.last)) (\(percent >= 0 ? "+" : "")\(percent) % zum Schnitt)"
  }
}

private struct TintedIconLabelStyle: LabelStyle {
  let color: Color

  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      configuration.icon.foregroundStyle(color).font(.caption)
      configuration.title
    }
  }
}

/// Hinweise, die heute zählen, als kleine Chips; Antippen öffnet die Einzelheiten.
struct TodayHintsSection: View {
  let snapshot: TodayViewModel.Snapshot
  let activities: [GarminActivity]
  let days: [DailyMetrics]
  @Environment(AppModel.self) private var model

  var body: some View {
    let settings = model.settings
    let today = snapshot.plan.today
    let run = LoadCheck.running(activities: activities, today: today)
    let sleep =
      Calendar.current.component(.hour, from: .now) >= 17
      ? SleepCoach.report(days: days, settings: settings.sleep, goal: settings.profile.goal, today: today) : nil
    let loadWarning = snapshot.load?.warning
    if run.warning != nil || loadWarning != nil || sleep != nil {
      Section {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            if let sleep {
              NavigationLink {
                SleepCoachView()
              } label: {
                HintChip(
                  text: "Ins Bett um \(SleepCoach.clock(sleep.bedtimeMinutes))", symbol: "moon.stars.fill",
                  color: .indigo)
              }
            }
            if let warning = run.warning {
              NavigationLink {
                HintPage(title: "Laufumfang", text: warning, ruleIDs: ["run.progression"])
              } label: {
                HintChip(
                  text: "Laufumfang +\(Int(((run.increase ?? 0) * 100).rounded())) %",
                  symbol: "exclamationmark.triangle.fill", color: .orange)
              }
            }
            if let loadWarning, let load = snapshot.load {
              NavigationLink {
                HintPage(title: "Wochenbelastung", text: loadWarning, ruleIDs: load.evidenceIDs, bySport: load.bySport)
              } label: {
                HintChip(
                  text: "Belastung +\(Int(((load.increase ?? 0) * 100).rounded())) %",
                  symbol: "gauge.with.dots.needle.67percent", color: .orange)
              }
            }
          }
          .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
      } header: {
        Text("Hinweise")
      }
    }
  }
}

private struct HintChip: View {
  let text: String
  let symbol: String
  let color: Color

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.subheadline.weight(.medium))
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(color.opacity(0.15), in: Capsule())
      .foregroundStyle(color)
  }
}

/// Einzelheiten eines Hinweises mit Grundlage.
private struct HintPage: View {
  let title: String
  let text: String
  let ruleIDs: [String]
  var bySport: [TrainingSport: Double] = [:]

  var body: some View {
    List {
      Section {
        Text(text)
      }
      if !bySport.isEmpty {
        Section("Letzte 7 Tage je Sportart") {
          ForEach(bySport.sorted { $0.value > $1.value }, id: \.key) { entry in
            LabeledContent(entry.key.label, value: "\(Int(entry.value))")
          }
        }
      }
      Section {
        EvidenceDisclosure(ruleIDs: ruleIDs)
      }
    }
    .navigationTitle(title)
  }
}
