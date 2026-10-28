import CoachCore
import SwiftData
import SwiftUI

extension SessionStatus {
  var symbol: String {
    switch self {
    case .done: "checkmark.circle.fill"
    case .partial: "circle.lefthalf.filled"
    case .substituted: "arrow.triangle.swap"
    case .missed: "xmark.circle"
    case .open: "circle.dotted"
    case .planned: "circle"
    }
  }

  var color: Color {
    switch self {
    case .done: .green
    case .partial, .substituted: .orange
    case .missed: .red
    case .open: .accentColor
    case .planned: .secondary
    }
  }
}

/// „erledigt“, „teilweise“ … als kleines Etikett neben der Einheit.
struct SessionStatusBadge: View {
  let status: SessionStatus

  var body: some View {
    Label(status.label, systemImage: status.symbol)
      .font(.caption.weight(.semibold))
      .foregroundStyle(status.color)
      .labelStyle(.titleAndIcon)
  }
}

/// Verpasste Einheit von gestern (oder früher in der Woche): nachholen, streichen oder „war krank“.
struct MissedSessionSection: View {
  let week: SessionMatcher.Week
  @Environment(AppModel.self) private var model
  @State private var addingManual = false

  var body: some View {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    if let missed = MissedSessions.open(week, handled: Set(settings.handledMissed)).first {
      let session = missed.planned
      let makeUp = MissedSessions.makeUpDay(
        for: session, schedule: settings.schedule(inWeekOf: today), profile: settings.profile, today: today,
        makeUpsThisWeek: makeUps(today: today))
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Label {
            Text("\(Weekday(day: session.day).long): \(session.slot.title) nicht gemacht").font(.headline)
          } icon: {
            Image(systemName: "xmark.circle").foregroundStyle(.red)
          }
          Text(
            makeUp.map { "Nachholen geht am \($0.long) – ohne zwei harte Tage hintereinander." }
              ?? "Diese Woche passt kein Nachholtag mehr. Einfach streichen: Eine verpasste Einheit kostet nichts."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        if let makeUp {
          Button("Am \(makeUp.long) nachholen", systemImage: "arrow.turn.down.right") {
            model.reminders.move(session.day, to: makeUp)
            handle([missed.id])
          }
        }
        Button("Doch gemacht – nachtragen", systemImage: "plus.circle") { addingManual = true }
        Button("Streichen", systemImage: "forward.end") { handle([missed.id]) }
        Button("War krank", systemImage: "cross.case") {
          settings.illnessDay = today
          handle(MissedSessions.open(week, handled: []).map(\.id))
        }
      } header: {
        Text("Verpasst")
      } footer: {
        Text(
          "„War krank“: Die nächsten \(MissedSessions.illnessEasyDays) Tage empfiehlt die App höchstens locker. "
            + "Höchstens \(MissedSessions.maxMakeUpsPerWeek)× pro Woche nachholen, sonst staut sich die Belastung.")
      }
      .sheet(isPresented: $addingManual) {
        ManualActivitySheet(sport: session.slot.sport, day: session.day, minutes: session.targetMinutes) {
          handle([missed.id])
        }
      }
    }
  }

  /// Schon nachgeholte Einheiten dieser Woche: von einem vergangenen Tag auf einen späteren verschoben.
  private func makeUps(today: CalendarDay) -> Int {
    model.settings.planAdjustments.changes(inWeekOf: today).filter {
      $0.from.rawValue < today.weekdayIndex && ($0.to?.rawValue ?? -1) > $0.from.rawValue
    }.count
  }

  /// Merken, worüber entschieden ist; Einträge älter als zwei Wochen fallen heraus.
  private func handle(_ ids: [String]) {
    let cutoff = CalendarDay(date: .now).adding(days: -14)
    let kept = model.settings.handledMissed.filter { id in
      CalendarDay(iso: String(id.prefix(10))).map { $0 >= cutoff } ?? false
    }
    model.settings.handledMissed = Array(Set(kept + ids)).sorted()
  }
}

/// Training ohne Uhr nachtragen: Sportart, Zeitpunkt, Dauer, Anstrengung 1–10 (daraus die Belastung).
struct ManualActivitySheet: View {
  @State var sport: TrainingSport
  @State private var start: Date
  @State private var minutes: Int
  @State private var effort = 5
  @State private var name = ""
  var saved: () -> Void = {}
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss

  init(sport: TrainingSport = .run, day: CalendarDay? = nil, minutes: Int = 45, saved: @escaping () -> Void = {}) {
    _sport = State(initialValue: sport)
    let base = day.flatMap { Calendar.current.date(from: DateComponents(year: $0.year, month: $0.month, day: $0.day)) }
    _start = State(initialValue: base.map { $0.addingTimeInterval(18 * 3600) } ?? .now.addingTimeInterval(-3600))
    _minutes = State(initialValue: minutes)
    self.saved = saved
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Sportart", selection: $sport) {
            ForEach(TrainingSport.allCases, id: \.self) { sport in
              Label(sport.label, systemImage: sport.symbol).tag(sport)
            }
          }
          DatePicker("Beginn", selection: $start, in: ...Date.now)
          Stepper("\(minutes) min", value: $minutes, in: 5...600, step: 5)
          TextField("Bezeichnung (optional)", text: $name)
        }
        Section {
          VStack(alignment: .leading) {
            HStack {
              Text("Anstrengung")
              Spacer()
              Text("\(effort) – \(effortLabel)").foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(
              value: Binding(get: { Double(effort) }, set: { effort = Int($0.rounded()) }), in: 1...10, step: 1)
          }
        } footer: {
          Text(
            "Belastung ≈ \(Int(ManualActivity.estimatedLoad(minutes: minutes, effort: effort).rounded())) "
              + "(Minuten × Anstrengung, „session RPE“). Ohne Uhr gibt es keine Herzfrequenz; die Einheit zählt "
              + "trotzdem für Wochenplan und Belastung.")
        }
      }
      .navigationTitle("Training nachtragen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") {
            let activity = ManualActivity.make(
              sport: sport, start: start, minutes: minutes, effort: effort,
              name: name.trimmingCharacters(in: .whitespaces))
            context.insert(ActivityRecord(activity: activity))
            try? context.save()
            saved()
            dismiss()
          }
        }
      }
    }
  }

  private var effortLabel: String {
    switch effort {
    case ...2: "sehr leicht"
    case 3...4: "leicht"
    case 5...6: "mittel"
    case 7...8: "hart"
    default: "maximal"
    }
  }
}
