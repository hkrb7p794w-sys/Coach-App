import CoachCore
import SwiftData
import SwiftUI

/// Ein Verlauf für alles Training: Garmin, Apple Health, Nachgetragenes und die Gym-Einheiten der App.
/// Doppelte Einheiten (Gym-App und Garmin-Kraft) erscheinen einmal, mit beiden Quellen.
struct ActivityListView: View {
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var records: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymRecords: [GymSessionRecord]
  @Environment(AppModel.self) private var model
  @State private var filter = ActivityFeed.Filter()

  /// So viele Wochen bekommen den Bezug zum Plan (ältere Wochen ohne, damit die Liste schnell bleibt).
  private static let plannedWeeks = 6

  var body: some View {
    let all = feed()
    let entries = filter.apply(all, today: CalendarDay(date: .now))
    let grouped = Dictionary(grouping: entries) { String($0.day.iso.prefix(7)) }
    let recordsByID = Dictionary(records.map { ($0.garminID, $0) }, uniquingKeysWith: { first, _ in first })
    let gymByID = Dictionary(gymRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    List {
      Section {
        Picker("Zeitraum", selection: $filter.period) {
          ForEach(ActivityFeed.Filter.Period.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
      } footer: {
        if filter.narrows || !filter.search.isEmpty {
          Text(
            "\(entries.count) von \(all.count) Einheiten · Filter oben rechts"
              + (filter.onlyPlanned ? " · Plan-Bezug der letzten \(Self.plannedWeeks) Wochen" : ""))
        }
      }
      if all.isEmpty {
        ContentUnavailableView(
          "Noch keine Aktivitäten", systemImage: "figure.run",
          description: Text("Ziehe unter „Heute“ nach unten, um Garmin abzurufen, oder trage ein Training nach."))
      } else if entries.isEmpty {
        ContentUnavailableView.search(text: filter.search)
      }
      ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
        Section(monthTitle(month)) {
          ForEach(grouped[month] ?? []) { entry in
            FeedEntryLink(
              entry: entry, record: entry.activity.flatMap { recordsByID[$0.id] },
              gymRecord: entry.gym.flatMap { gymByID[$0.id] })
          }
        }
      }
    }
    .navigationTitle("Aktivitäten")
    .searchable(text: $filter.search, prompt: "Name, Sportart, Wert")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Picker("Sportart", selection: $filter.sport) {
            Text("Alle Sportarten").tag(TrainingSport?.none)
            ForEach(TrainingSport.allCases) { sport in
              Label(sport.label, systemImage: sport.symbol).tag(TrainingSport?.some(sport))
            }
          }
          Toggle("Nur Plan-Einheiten", isOn: $filter.onlyPlanned)
          Toggle("Nur harte Einheiten", isOn: $filter.onlyHard)
          if filter.narrows {
            Button("Filter zurücksetzen", systemImage: "xmark.circle") {
              filter = ActivityFeed.Filter(period: filter.period, search: filter.search)
            }
          }
        } label: {
          Label(
            "Filter",
            systemImage: filter.narrows
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
      }
    }
  }

  private func feed() -> [ActivityFeed.Entry] {
    let activities = records.compactMap(\.activity)
    let sessions = gymRecords.compactMap(\.session)
    var results: [SessionResult] = []
    if model.settings.profile.mode == .personal {
      let today = CalendarDay(date: .now)
      let gymDays = sessions.map(\.day)
      for week in 0..<Self.plannedWeeks {
        results +=
          TodayViewModel.sessionWeek(
            settings: model.settings, activities: activities, gymDays: gymDays, today: today,
            weekOf: today.adding(days: -7 * week)
          ).results
      }
    }
    return ActivityFeed.entries(activities: activities, gym: sessions.map(ActivityFeed.GymItem.init), results: results)
  }

  private func monthTitle(_ key: String) -> String {
    guard let day = CalendarDay(iso: key + "-01") else { return key }
    return day.localDate.formatted(.dateTime.month(.wide).year())
  }
}

/// Zeile mit Link zur passenden Detailseite (Garmin/Health/Nachgetragen oder Gym-Einheit).
struct FeedEntryLink: View {
  let entry: ActivityFeed.Entry
  let record: ActivityRecord?
  let gymRecord: GymSessionRecord?

  var body: some View {
    if entry.activity != nil, let record {
      NavigationLink {
        ActivityDetailView(record: record)
      } label: {
        FeedRow(entry: entry)
      }
    } else if let gymRecord, let session = gymRecord.session {
      NavigationLink {
        SessionDetailView(record: gymRecord, session: session)
      } label: {
        FeedRow(entry: entry)
      }
    } else {
      FeedRow(entry: entry)
    }
  }
}

/// Zeile im Verlauf: Sportart, Titel, Kernwerte, Intensität, Quellen und Bezug zum Plan.
struct FeedRow: View {
  let entry: ActivityFeed.Entry

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      let sport = SessionMatcher.sport(entry.sport)
      SportIcon(symbol: sport.symbol, color: sport.color)
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline) {
          Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
          Spacer(minLength: 4)
          Text(Formatters.day(entry.day)).font(.caption).foregroundStyle(.secondary)
        }
        if !entry.values.isEmpty {
          Text(entry.values.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        HStack(spacing: 6) {
          FeedBadges(sources: entry.sources, intensity: entry.intensity)
          if let planned = entry.planned {
            SessionStatusBadge(status: planned.status)
          }
        }
        if let planned = entry.planned {
          Text("Plan: \(planned.planned.slot.title)" + (planned.intensityNote.map { " · \($0)" } ?? ""))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}
