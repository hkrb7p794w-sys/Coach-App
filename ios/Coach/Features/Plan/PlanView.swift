import CoachCore
import SwiftData
import SwiftUI

/// Reiter „Plan“: alle Einheiten einer Woche mit Inhalt, Woche für Woche durch die Saison.
struct PlanView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymSessions: [GymSessionRecord]
  @State private var viewModel = PlanViewModel()
  @State private var showSeason = false

  private var refreshKey: String {
    let settings = model.settings
    return "\(activities.count)-\(gymSessions.count)-\(settings.season.hashValue)-"
      + "\(settings.competitionDecisions.count)-\(settings.competitionDecisions.values.map(\.rawValue).sorted())"
  }

  var body: some View {
    NavigationStack {
      List {
        if viewModel.schedule == nil {
          ContentUnavailableView(
            "Kein Plan", systemImage: "calendar.badge.exclamationmark",
            description: Text("Der Saisonplan konnte nicht geladen werden."))
        } else if let week = viewModel.week {
          WeekHeader(viewModel: viewModel, week: week)
          Section {
            ForEach(viewModel.units) { unit in
              NavigationLink {
                PlanUnitDetailView(unit: unit, week: week)
              } label: {
                PlanUnitRow(unit: unit)
              }
            }
          } header: {
            Text("Einheiten")
          } footer: {
            Text("Erledigt-Haken kommen aus Garmin und den Krafteinheiten der App. Testwerte unter Einstellungen.")
          }
          if let info = viewModel.phaseInfo {
            Section("Musterwoche · \(week.ph)") {
              Text(info.mw).font(.subheadline)
            }
            Section("Wenn die Zeit knapp ist") {
              Text(info.prio).font(.subheadline)
            }
          }
        }
      }
      .navigationTitle("Plan")
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if !viewModel.isCurrentWeek {
            Button("Heute") { withAnimation { viewModel.show(viewModel.currentWeekIndex) } }
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Saison", systemImage: "calendar") { showSeason = true }
        }
      }
      .sheet(isPresented: $showSeason) {
        SeasonOverviewView(viewModel: viewModel)
          .presentationDetents([.medium, .large])
      }
      .task(id: refreshKey) {
        viewModel.update(
          activities: activities.compactMap(\.activity),
          gymDays: gymSessions.compactMap { $0.session?.day },
          config: model.settings.season,
          decisions: model.settings.competitionDecisions)
      }
    }
  }
}

private struct WeekHeader: View {
  let viewModel: PlanViewModel
  let week: PlanWeek

  var body: some View {
    Section {
      HStack(spacing: 12) {
        Button {
          withAnimation { viewModel.step(-1) }
        } label: {
          Image(systemName: "chevron.left").frame(width: 44, height: 44)
        }
        .disabled(!viewModel.canGoBack)
        .accessibilityLabel("Vorherige Woche")

        VStack(spacing: 2) {
          Text(viewModel.weekTitle).font(.title2.bold())
          Text(viewModel.weekRange).font(.subheadline).foregroundStyle(.secondary)
          Text(week.ph)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15), in: Capsule())
        }
        .frame(maxWidth: .infinity)

        Button {
          withAnimation { viewModel.step(1) }
        } label: {
          Image(systemName: "chevron.right").frame(width: 44, height: 44)
        }
        .disabled(!viewModel.canGoForward)
        .accessibilityLabel("Nächste Woche")
      }
      .buttonStyle(.borderless)

      if viewModel.requiredCount > 0 {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Erledigt").font(.subheadline)
            Spacer()
            Text("\(viewModel.doneCount) von \(viewModel.requiredCount)")
              .font(.subheadline.monospacedDigit())
              .foregroundStyle(.secondary)
          }
          ProgressView(value: Double(viewModel.doneCount), total: Double(viewModel.requiredCount))
        }
      }
      if !week.f.isEmpty {
        Label(week.f, systemImage: "flag")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct PlanUnitRow: View {
  let unit: PlannedUnit

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      SportIcon(symbol: unit.kind.symbol, color: unit.kind.color)
      VStack(alignment: .leading, spacing: 2) {
        Text(unit.kind.label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(unit.kind.color)
        Text(unit.title).font(.headline)
        Text(unit.detail)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
      if unit.done {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityLabel("erledigt")
      } else if unit.decision == .open {
        Image(systemName: "questionmark.circle")
          .foregroundStyle(.orange)
          .accessibilityLabel("Entscheidung offen")
      }
    }
    .padding(.vertical, 2)
    .opacity(unit.kind == .bikeOptional ? 0.7 : 1)
  }
}

private struct SeasonOverviewView: View {
  let viewModel: PlanViewModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          if let schedule = viewModel.schedule {
            let phases = schedule.weeks.reduce(into: [String]()) { result, week in
              if result.last != week.ph { result.append(week.ph) }
            }
            ForEach(phases, id: \.self) { phase in
              Section(phase) {
                ForEach(Array(schedule.weeks.enumerated()).filter { $0.element.ph == phase }, id: \.element.w) {
                  index, week in
                  Button {
                    viewModel.show(index)
                    dismiss()
                  } label: {
                    SeasonWeekRow(week: week, isCurrent: index == viewModel.currentWeekIndex)
                  }
                  .tint(.primary)
                  .id(index)
                }
              }
            }
          }
        }
        .onAppear { proxy.scrollTo(viewModel.weekIndex, anchor: .center) }
      }
      .navigationTitle("Saison")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
    }
  }
}

private struct SeasonWeekRow: View {
  let week: PlanWeek
  let isCurrent: Bool

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(week.monday.map { "ab \(Formatters.shortDate($0))" } ?? week.w)
          .font(.subheadline.weight(isCurrent ? .bold : .regular))
        Text(
          [week.qc, week.lr > 0 ? "Longrun \(GermanFormat.decimal(week.lr)) km" : nil, week.f.isEmpty ? nil : week.f]
            .compactMap { $0 }.joined(separator: " · ")
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
      }
      Spacer()
      if isCurrent {
        Text("jetzt").font(.caption.bold()).foregroundStyle(.tint)
      }
    }
  }
}
