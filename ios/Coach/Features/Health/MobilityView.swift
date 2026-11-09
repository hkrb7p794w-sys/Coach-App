import CoachCore
import SwiftData
import SwiftUI

/// Mobility: Einheit nach Belastung der letzten Tage und eigenen Selbsttests, dazu die Tests mit Verlauf.
/// Die Auswahl trifft `MobilityPlanner` (Regeln), keine KI.
struct MobilityView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymRecords: [GymSessionRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activityRecords: [ActivityRecord]
  @State private var context: MobilityContext = .restDay
  @State private var testing: MobilityTest?

  var body: some View {
    let today = CalendarDay(date: .now)
    let settings = model.settings.mobility
    let routine = MobilityPlanner.routine(
      context: context, minutes: settings.minutes,
      recentSets: MobilityPlanner.recentSets(
        sessions: gymRecords.prefix(30).compactMap(\.session), now: .now,
        custom: model.settings.gym.customExercises),
      enduranceMinutes: MobilityPlanner.enduranceMinutes(
        activities: activityRecords.suffix(60).compactMap(\.activity), today: today),
      results: settings.results)
    let doneToday = settings.log.contains { $0.day == today }
    let latest = MobilityTestResult.latest(settings.results)

    List {
      Section {
        Picker("Wann", selection: $context) {
          ForEach(MobilityContext.allCases) { Text($0.label).tag($0) }
        }
        Picker("Dauer", selection: minutesBinding) {
          ForEach(MobilityPlanner.durations, id: \.self) { Text("\($0) min").tag($0) }
        }
        .pickerStyle(.segmented)
      } footer: {
        Text(
          context == .preTraining
            ? "Vor dem Training nur Übungen in Bewegung – langes Halten direkt davor kann die Leistung kurz mindern."
            : "Nach dem Training und am Ruhetag zuerst Halteübungen, je etwa 45 Sekunden."
        )
      }

      Section("Schwerpunkte heute") {
        ForEach(routine.reasons, id: \.self) { reason in
          Text(reason).font(.subheadline)
        }
      }

      Section {
        ForEach(routine.blocks) { block in
          DisclosureGroup {
            ForEach(Array(block.drill.steps.enumerated()), id: \.offset) { index, step in
              Text("\(index + 1). \(step)").font(.footnote)
            }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(block.drill.name).font(.subheadline.weight(.semibold))
              Text(Self.detail(block)).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Ablauf · etwa \(Self.minutes(routine.totalSeconds)) min")
      }

      Section {
        Button {
          model.settings.mobility.log = Self.appending(
            MobilityLogEntry(day: today, minutes: Self.minutes(routine.totalSeconds), areas: routine.focus),
            to: model.settings.mobility.log, today: today)
        } label: {
          Label(
            doneToday ? "Heute erledigt" : "Als erledigt eintragen",
            systemImage: doneToday ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .disabled(doneToday)
      } footer: {
        Text("Diese Woche: \(settings.sessions(inWeekEnding: today)) Mobility-Einheiten")
      }

      Section {
        ForEach(MobilityTest.all) { test in
          Button {
            testing = test
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(test.name).font(.subheadline).foregroundStyle(.primary)
                Text(test.areas.map(\.label).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              if let result = latest[test.id] {
                Text(test.rating(result.value).label)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(Self.color(test.rating(result.value)))
              } else {
                Text("noch nicht getestet").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
      } header: {
        Text("Selbsttests")
      } footer: {
        Text(
          "Etwa alle vier Wochen wiederholen. Eingeschränkte Bereiche bekommen in der Einheit Vorrang. "
            + "Die Grenzen sind Orientierungswerte, keine Diagnose – bei Schmerzen ärztlich abklären lassen."
        )
      }

      Section {
        EvidenceDisclosure(ruleIDs: ["mobility.stretching", "mobility.focus"])
      }
    }
    .navigationTitle("Mobility")
    .sheet(item: $testing) { test in
      NavigationStack {
        MobilityTestSheet(test: test)
      }
    }
  }

  private var minutesBinding: Binding<Int> {
    Binding(
      get: { model.settings.mobility.minutes },
      set: { model.settings.mobility.minutes = $0 })
  }

  static func minutes(_ seconds: Int) -> Int { max(1, Int((Double(seconds) / 60).rounded())) }

  static func detail(_ block: MobilityRoutine.Block) -> String {
    let drill = block.drill
    let time = "\(drill.seconds) s" + (drill.perSide ? " je Seite" : "")
    let style = drill.style == .hold ? "halten" : "in Bewegung"
    return "\(time) · \(style) · \(block.area.label)"
  }

  static func color(_ rating: MobilityTest.Rating) -> Color {
    switch rating {
    case .limited: .orange
    case .moderate: .yellow
    case .good: .green
    }
  }

  /// Neuer Eintrag, Verlauf höchstens ein Jahr.
  static func appending(_ entry: MobilityLogEntry, to log: [MobilityLogEntry], today: CalendarDay)
    -> [MobilityLogEntry]
  {
    let cutoff = today.adding(days: -365)
    return log.filter { $0.day >= cutoff } + [entry]
  }
}

/// Ein Selbsttest: Anleitung, Eingabe, bisherige Ergebnisse.
struct MobilityTestSheet: View {
  let test: MobilityTest
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var value: Double = 0

  var body: some View {
    let history = model.settings.mobility.results.filter { $0.testID == test.id }.sorted { $0.day > $1.day }
    Form {
      Section("So geht’s") {
        ForEach(Array(test.steps.enumerated()), id: \.offset) { index, step in
          Text("\(index + 1). \(step)").font(.subheadline)
        }
      }
      Section {
        switch test.input {
        case .centimeters(let range, _, _):
          Stepper(value: $value, in: range, step: 1) {
            Text("\(Int(value)) cm")
              .monospacedDigit()
          }
        case .levels(let labels):
          Picker("Ergebnis", selection: $value) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
              Text(label).tag(Double(index))
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        }
        Text("Einstufung: \(test.rating(value).label)")
          .font(.footnote)
          .foregroundStyle(MobilityView.color(test.rating(value)))
      } header: {
        Text("Ergebnis")
      }
      if !history.isEmpty {
        Section("Bisher") {
          ForEach(history.prefix(6)) { result in
            HStack {
              Text(GermanFormat.date(result.day))
              Spacer()
              Text(Self.text(result.value, test: test)).monospacedDigit()
              Text(test.rating(result.value).label)
                .font(.caption)
                .foregroundStyle(MobilityView.color(test.rating(result.value)))
            }
          }
        }
      }
    }
    .navigationTitle(test.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button("Abbrechen") { dismiss() }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("Speichern") {
          model.settings.mobility.results.append(
            MobilityTestResult(testID: test.id, day: CalendarDay(date: .now), value: value))
          dismiss()
        }
      }
    }
    .onAppear {
      if let last = history.first {
        value = last.value
      } else if case .centimeters(let range, _, _) = test.input {
        value = max(range.lowerBound, min(range.upperBound, 0))
      }
    }
  }

  static func text(_ value: Double, test: MobilityTest) -> String {
    switch test.input {
    case .centimeters: "\(Int(value)) cm"
    case .levels(let labels): "Stufe \(Int(value) + 1) von \(labels.count)"
    }
  }
}

/// Karte im Gesundheitsbereich.
struct MobilitySummaryCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let today = CalendarDay(date: .now)
    let settings = model.settings.mobility
    let count = settings.sessions(inWeekEnding: today)
    let tested = !settings.results.isEmpty
    HStack(spacing: 12) {
      Image(systemName: "figure.flexibility")
        .font(.title2)
        .foregroundStyle(.teal)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Mobility").font(.headline)
        Text(
          (count == 0 ? "Diese Woche noch keine Einheit" : "Diese Woche \(count) Einheiten")
            + (tested ? "" : " · Selbsttests noch offen")
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Image(systemName: "chevron.right").foregroundStyle(.tertiary)
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
