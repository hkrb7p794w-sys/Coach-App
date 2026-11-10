import CoachCore
import SwiftData
import SwiftUI

/// Reiter „Aktivitäten“: eigene Trainings und die Beiträge der Freunde in einer Liste, neueste oben.
/// „Meine“ ist der vollständige eigene Verlauf mit Suche und Filter, „Freunde“ nur deren Beiträge.
struct ActivitiesView: View {
  enum Scope: String, CaseIterable, Identifiable {
    case all = "Alle"
    case mine = "Meine"
    case friends = "Freunde"
    var id: Self { self }
  }

  /// So viele eigene Trainings stehen höchstens unter „Alle“; der ganze Verlauf steht unter „Meine“.
  private static let ownLimit = 300

  @Environment(AppModel.self) private var model
  @Query(sort: \ActivityRecord.startLocal, order: .reverse) private var records: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymRecords: [GymSessionRecord]
  @State private var scope = Scope.all
  @State private var showFriends = false
  @State private var importing: SharedMeal?
  @State private var commenting: SocialPost?
  @AppStorage(SocialAutoShare.enabledKey) private var autoShare = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Picker("Ansicht", selection: $scope) {
          ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 8)
        switch scope {
        case .all: timeline(friendsOnly: false)
        case .mine: ActivityListView()
        case .friends: timeline(friendsOnly: true)
        }
      }
      .navigationTitle("Aktivitäten")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(
            model.social.incomingCount > 0 ? "Freunde, \(model.social.incomingCount) neue Anfragen" : "Freunde",
            systemImage: model.social.incomingCount > 0 ? "person.2.fill" : "person.2"
          ) { showFriends = true }
        }
        if scope != .mine, model.social.isAvailable {
          ToolbarItem(placement: .topBarTrailing) {
            Menu {
              Toggle(
                "Trainings automatisch teilen",
                isOn: Binding(get: { autoShare }, set: { SocialAutoShare.setEnabled($0) }))
              Text("Ohne Körperwerte: Puls, Kalorien, Gewicht und Schlaf bleiben auf deinem iPhone.")
            } label: {
              Label("Teilen", systemImage: autoShare ? "dot.radiowaves.left.and.right" : "ellipsis.circle")
            }
          }
        }
      }
      .sheet(isPresented: $showFriends) { FriendsView(initialPage: .friends) }
      .sheet(item: $commenting) { post in CommentsView(post: post) }
      .sheet(item: Binding(get: { importing.map(ImportedMeal.init) }, set: { importing = $0?.meal })) { item in
        ReceivedMealSheet(code: nil, preloaded: item.meal)
      }
      .task {
        await model.social.refresh()
        await SocialAutoShare.run(model: model)
      }
      .onChange(of: autoShare) {
        Task { await SocialAutoShare.run(model: model) }
      }
    }
  }

  private func items(friendsOnly: Bool) -> [SocialTimeline.Item] {
    let social = model.social
    if friendsOnly {
      return SocialTimeline.merge(entries: [], posts: social.feed.filter { !$0.mine }, shared: [:])
    }
    let entries = ActivityFeed.entries(
      activities: records.prefix(Self.ownLimit).compactMap(\.activity),
      gym: gymRecords.prefix(Self.ownLimit).compactMap(\.session).map(ActivityFeed.GymItem.init))
    let oldest = social.isAvailable && social.hasMore ? social.feed.last?.date : nil
    return SocialTimeline.merge(
      entries: entries, posts: social.isAvailable ? social.feed : [], shared: SharedPostStore.load(), oldest: oldest)
  }

  private func timeline(friendsOnly: Bool) -> some View {
    let social = model.social
    let items = items(friendsOnly: friendsOnly)
    let recordsByID = Dictionary(records.map { ($0.garminID, $0) }, uniquingKeysWith: { first, _ in first })
    let gymByID = Dictionary(gymRecords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return List {
      if !social.isAvailable {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Label("Mit Freunden wird daraus ein Feed", systemImage: "person.2").font(.subheadline.weight(.semibold))
            Text("Mit einem Konto siehst du hier auch die Trainings deiner Freunde und kannst reagieren.")
              .font(.footnote)
              .foregroundStyle(.secondary)
            Button("Konto und Freunde") { showFriends = true }.buttonStyle(.bordered)
          }
          .padding(.vertical, 4)
        }
      } else if let error = social.lastError {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote)
      }
      if items.isEmpty, !social.isLoading {
        ContentUnavailableView(
          friendsOnly ? "Noch nichts von Freunden" : "Noch keine Aktivitäten",
          systemImage: friendsOnly ? "person.2" : "figure.run",
          description: Text(
            friendsOnly
              ? "Hier erscheint, was deine Freunde teilen. Freunde findest du oben links über den Benutzernamen."
              : "Deine Trainings von Uhr und Gym erscheinen hier, dazu alles, was deine Freunde teilen."))
      }
      ForEach(items) { item in
        Group {
          if let entry = item.entry {
            FeedEntryLink(
              entry: entry, record: entry.activity.flatMap { recordsByID[$0.id] },
              gymRecord: entry.gym.flatMap { gymByID[$0.id] }
            )
            .listRowSeparator(item.post == nil ? .automatic : .hidden, edges: .bottom)
            // Eigener geteilter Beitrag: Reaktionen und Kommentare der Freunde direkt darunter.
            if let post = item.post {
              ReactionBar(post: post) { commenting = post }
            }
          } else if let post = item.post {
            PostCard(post: post, importMeal: { importing = $0 })
          }
        }
        .onAppear {
          if item.id == items.last?.id { Task { await social.loadMore() } }
        }
      }
      if social.isLoading { ProgressView().frame(maxWidth: .infinity) }
    }
    .listStyle(.plain)
    .refreshable {
      await model.syncNow()
      await social.refresh()
      await SocialAutoShare.run(model: model)
    }
  }
}
