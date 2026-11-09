import CoachCore
import SwiftUI

/// Freunde: Feed mit Trainings, Mahlzeiten und Meilensteinen der Freunde sowie Freundesliste mit Suche.
struct FriendsView: View {
  enum Page: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case friends = "Freunde"
    var id: Self { self }
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var page: Page = .feed
  @State private var signIn: AccountAuthView.Mode?

  var body: some View {
    NavigationStack {
      Group {
        if model.social.isAvailable {
          VStack(spacing: 0) {
            Picker("Ansicht", selection: $page) {
              ForEach(Page.allCases) { item in
                if item == .friends, model.social.incomingCount > 0 {
                  Text("Freunde (\(model.social.incomingCount))").tag(item)
                } else {
                  Text(item.rawValue).tag(item)
                }
              }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            switch page {
            case .feed: FeedList()
            case .friends: FriendList()
            }
          }
        } else {
          ContentUnavailableView {
            Label("Freunde brauchen ein Konto", systemImage: "person.2")
          } description: {
            Text(
              "Mit einem eigenen Konto findest du Freunde über den Benutzernamen, siehst ihre Trainings und teilst "
                + "Mahlzeiten. Nur du kennst dein Passwort.")
          } actions: {
            Button("Anmelden") { signIn = .login }.buttonStyle(.borderedProminent)
            Button("Konto erstellen") { signIn = .register }
          }
        }
      }
      .navigationTitle("Freunde")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
      }
      .sheet(item: $signIn) { mode in AccountAuthView(initialMode: mode, invite: nil) }
      .task { await model.social.refresh() }
    }
  }
}

// MARK: - Feed

private struct FeedList: View {
  @Environment(AppModel.self) private var model
  @State private var importing: SharedMeal?

  var body: some View {
    let social = model.social
    List {
      if let error = social.lastError {
        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.footnote)
      }
      if social.feed.isEmpty, !social.isLoading {
        ContentUnavailableView(
          "Noch nichts geteilt", systemImage: "figure.run.circle",
          description: Text(
            "Teile ein Training (Abschluss im Gym oder Aktivität › Teilen) oder eine Mahlzeit (Ernährung › Teilen). "
              + "Hier erscheint, was deine Freunde teilen."))
      }
      ForEach(social.feed) { post in
        PostCard(post: post, importMeal: { importing = $0 })
          .onAppear {
            if post.id == social.feed.last?.id { Task { await social.loadMore() } }
          }
      }
      if social.isLoading { ProgressView().frame(maxWidth: .infinity) }
    }
    .listStyle(.plain)
    .refreshable { await social.refresh() }
    .sheet(item: Binding(get: { importing.map(ImportedMeal.init) }, set: { importing = $0?.meal })) { item in
      ReceivedMealSheet(code: nil, preloaded: item.meal)
    }
  }
}

private struct ImportedMeal: Identifiable {
  let meal: SharedMeal
  var id: String { meal.title + "\(meal.items.count)" }
}

/// Ein Beitrag: Person, Zeit, Inhalt, Reaktionen und Kommentare.
struct PostCard: View {
  let post: SocialPost
  var importMeal: (SharedMeal) -> Void = { _ in }
  @Environment(AppModel.self) private var model
  @State private var showComments = false
  @State private var confirmDelete = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Avatar(person: post.author)
        VStack(alignment: .leading, spacing: 1) {
          Text(post.mine ? "Du" : post.author.displayName).font(.subheadline.bold())
          if let date = post.date {
            Text(SocialFormat.relative(date)).font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        if post.mine {
          Menu {
            Button("Beitrag löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
          } label: {
            Image(systemName: "ellipsis").padding(8)
          }
          .accessibilityLabel("Optionen")
        }
      }
      Label(post.headline, systemImage: post.symbol).font(.headline)
      if !post.facts.isEmpty {
        Text(post.facts).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
      }
      if let exercises = post.payload.exercises, !exercises.isEmpty {
        Text(exercises.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
      }
      ForEach(post.payload.records ?? [], id: \.self) { record in
        Label(record, systemImage: "trophy.fill").font(.footnote).foregroundStyle(.orange)
      }
      if let note = post.payload.note, !note.isEmpty {
        Text(note).font(.body)
      }
      if post.kind == .meal, let meal = post.payload.meal, !post.mine {
        Button("In mein Tagebuch übernehmen", systemImage: "square.and.arrow.down") { importMeal(meal) }
          .font(.subheadline)
          .buttonStyle(.bordered)
      }
      ReactionBar(post: post) { showComments = true }
    }
    .padding(.vertical, 6)
    .sheet(isPresented: $showComments) { CommentsView(post: post) }
    .confirmationDialog("Beitrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Löschen", role: .destructive) { Task { try? await model.social.delete(post) } }
    }
  }
}

private struct ReactionBar: View {
  let post: SocialPost
  let openComments: () -> Void
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 4) {
      ForEach(SocialReaction.allCases, id: \.self) { reaction in
        let selected = post.myReaction == reaction.rawValue
        Button {
          Task { await model.social.react(post, with: reaction) }
        } label: {
          Text(reaction.rawValue)
            .font(.title3)
            .frame(minWidth: 40, minHeight: 36)
            .background(selected ? Color.accentColor.opacity(0.2) : .clear, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reaction.label + (selected ? ", gewählt" : ""))
        .sensoryFeedback(.selection, trigger: selected)
      }
      Spacer()
      if post.reactions > 0 {
        Text("\(post.topReactions) \(post.reactions)").font(.caption).foregroundStyle(.secondary)
      }
      Button(action: openComments) {
        Label("\(post.comments)", systemImage: "bubble.right").font(.caption)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(post.comments) Kommentare")
    }
  }
}

struct Avatar: View {
  let person: SocialPerson
  var size: CGFloat = 36

  var body: some View {
    Text(person.initial)
      .font(.system(size: size * 0.45, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color, in: .circle)
      .accessibilityHidden(true)
  }

  /// Gleiche Farbe je Benutzername.
  private var color: Color {
    let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .mint]
    let sum = person.username.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count]
  }
}

private struct CommentsView: View {
  let post: SocialPost
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var comments: [SocialComment] = []
  @State private var text = ""
  @State private var error: String?
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      List {
        ForEach(comments) { comment in
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(comment.author.displayName).font(.subheadline.bold())
              if let date = SocialFormat.date(comment.createdAt) {
                Text(SocialFormat.relative(date)).font(.caption).foregroundStyle(.secondary)
              }
            }
            Text(comment.text)
          }
          .swipeActions {
            if comment.canDelete {
              Button("Löschen", role: .destructive) {
                Task {
                  try? await model.social.deleteComment(comment, on: post)
                  await load()
                }
              }
            }
          }
        }
        if comments.isEmpty {
          Text("Noch keine Kommentare.").foregroundStyle(.secondary)
        }
        if let error { Text(error).foregroundStyle(.red).font(.footnote) }
      }
      .safeAreaInset(edge: .bottom) {
        HStack {
          TextField("Kommentar …", text: $text, axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
          Button("Senden", systemImage: "paperplane.fill") { Task { await send() } }
            .labelStyle(.iconOnly)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(.bar)
      }
      .navigationTitle(post.headline)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
      .task { await load() }
    }
  }

  private func load() async {
    do { comments = try await model.social.comments(post) } catch { self.error = error.localizedDescription }
  }

  private func send() async {
    let value = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
    do {
      try await model.social.comment(post, text: value)
      text = ""
      await load()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Freunde

private struct FriendList: View {
  @Environment(AppModel.self) private var model
  @State private var query = ""
  @State private var results: [SocialPerson] = []
  @State private var error: String?
  @State private var inviting = false

  var body: some View {
    let social = model.social
    List {
      if !query.isEmpty {
        Section("Suche") {
          if results.isEmpty {
            Text("Niemand gefunden. Benutzernamen beginnen mit dem, was du tippst.").foregroundStyle(.secondary)
          }
          ForEach(results) { person in
            PersonRow(person: person) { await search() }
          }
        }
      }
      if !social.friends.incoming.isEmpty {
        Section("Anfragen an dich") {
          ForEach(social.friends.incoming) { person in
            HStack {
              PersonLabel(person: person)
              Spacer()
              Button("Annehmen") { act { try await social.addFriend(person.username) } }
                .buttonStyle(.borderedProminent)
              Button("Ablehnen", systemImage: "xmark") { act { try await social.removeFriend(person.username) } }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
            }
          }
        }
      }
      Section {
        if social.friends.friends.isEmpty {
          Text("Noch keine Freunde. Suche oben nach einem Benutzernamen oder lade jemanden ein.")
            .foregroundStyle(.secondary)
        }
        ForEach(social.friends.friends) { person in
          NavigationLink {
            PersonView(username: person.username, displayName: person.displayName)
          } label: {
            PersonLabel(person: person)
          }
          .swipeActions {
            Button("Entfernen", role: .destructive) { act { try await social.removeFriend(person.username) } }
          }
        }
      } header: {
        Text("Freunde (\(social.friends.friends.count))")
      }
      if !social.friends.outgoing.isEmpty {
        Section("Gesendete Anfragen") {
          ForEach(social.friends.outgoing) { person in
            HStack {
              PersonLabel(person: person)
              Spacer()
              Button("Zurückziehen") { act { try await social.removeFriend(person.username) } }
                .font(.caption)
            }
          }
        }
      }
      Section {
        NavigationLink {
          AccountDetailView()
        } label: {
          Label("Jemanden ohne Konto einladen", systemImage: "person.badge.plus")
        }
      } footer: {
        Text("Freunde sehen nur, was du ausdrücklich teilst – nie Gewicht, Puls, Schlaf oder andere Körperwerte.")
      }
      if let error { Text(error).foregroundStyle(.red).font(.footnote) }
    }
    .searchable(text: $query, prompt: "Benutzername suchen")
    .textInputAutocapitalization(.never)
    .autocorrectionDisabled()
    .task(id: query) {
      try? await Task.sleep(for: .milliseconds(300))
      await search()
    }
    .refreshable { await social.refresh() }
  }

  private func search() async {
    do {
      results = try await model.social.search(query)
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func act(_ action: @escaping () async throws -> Void) {
    Task {
      do { try await action() } catch { self.error = error.localizedDescription }
    }
  }
}

private struct PersonLabel: View {
  let person: SocialPerson

  var body: some View {
    HStack(spacing: 10) {
      Avatar(person: person, size: 32)
      VStack(alignment: .leading) {
        Text(person.displayName)
        Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

/// Suchtreffer mit passender Aktion.
private struct PersonRow: View {
  let person: SocialPerson
  let changed: () async -> Void
  @Environment(AppModel.self) private var model
  @State private var error: String?

  var body: some View {
    HStack {
      PersonLabel(person: person)
      Spacer()
      switch person.relation ?? SocialRelation.none {
      case .friends: Text("Befreundet").font(.caption).foregroundStyle(.secondary)
      case .outgoing: Text("Angefragt").font(.caption).foregroundStyle(.secondary)
      case .incoming: Button("Annehmen") { run { try await model.social.addFriend(person.username) } }
      case .blocked: Button("Entsperren") { run { try await model.social.unblock(person.username) } }
      case .none, .me:
        Button("Hinzufügen", systemImage: "person.badge.plus") {
          run { try await model.social.addFriend(person.username) }
        }
        .buttonStyle(.borderedProminent)
      }
    }
    if let error { Text(error).font(.caption).foregroundStyle(.red) }
  }

  private func run(_ action: @escaping () async throws -> Void) {
    Task {
      do {
        try await action()
        await changed()
      } catch {
        self.error = error.localizedDescription
      }
    }
  }
}

/// Profil einer befreundeten Person mit ihren letzten Beiträgen.
private struct PersonView: View {
  let username: String
  let displayName: String
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var profile: SocialService.Profile?
  @State private var error: String?
  @State private var confirmBlock = false

  var body: some View {
    List {
      Section {
        HStack(spacing: 14) {
          Avatar(person: SocialPerson(username: username, displayName: displayName), size: 56)
          VStack(alignment: .leading) {
            Text(displayName).font(.title3.bold())
            Text("@\(username)").foregroundStyle(.secondary)
          }
        }
      }
      if let profile {
        Section("Letzte Beiträge") {
          if profile.posts.isEmpty { Text("Noch nichts geteilt.").foregroundStyle(.secondary) }
          ForEach(profile.posts) { post in
            VStack(alignment: .leading, spacing: 4) {
              Label(post.headline, systemImage: post.symbol).font(.headline)
              if !post.facts.isEmpty { Text(post.facts).font(.subheadline).foregroundStyle(.secondary) }
              if let date = post.date { Text(SocialFormat.relative(date)).font(.caption).foregroundStyle(.secondary) }
            }
          }
        }
      }
      Section {
        Button("Freundschaft beenden", role: .destructive) {
          Task {
            try? await model.social.removeFriend(username)
            dismiss()
          }
        }
        Button("Sperren", role: .destructive) { confirmBlock = true }
      } footer: {
        Text(
          "Wer gesperrt ist, sieht deine Beiträge nicht und kann dir keine Anfragen schicken. Es gibt keine Mitteilung."
        )
      }
      if let error { Text(error).foregroundStyle(.red).font(.footnote) }
    }
    .navigationTitle(displayName)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      do { profile = try await model.social.profile(username) } catch { self.error = error.localizedDescription }
    }
    .confirmationDialog("\(displayName) sperren?", isPresented: $confirmBlock, titleVisibility: .visible) {
      Button("Sperren", role: .destructive) {
        Task {
          try? await model.social.block(username)
          dismiss()
        }
      }
    }
  }
}

// MARK: - Teilen

/// „Mit Freunden teilen“: kurze Notiz, Vorschau dessen, was geteilt wird, dann senden.
struct ShareWithFriendsSheet: View {
  enum Content {
    case workout(WorkoutShare)
    case meal(SharedMeal)
  }

  let content: Content
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var note = ""
  @State private var isSending = false
  @State private var error: String?
  @State private var signIn: AccountAuthView.Mode?

  var body: some View {
    NavigationStack {
      Form {
        if !model.social.isAvailable {
          Section {
            Text("Zum Teilen mit Freunden brauchst du ein Konto.")
            Button("Anmelden") { signIn = .login }
            Button("Konto erstellen") { signIn = .register }
          }
        } else {
          Section {
            preview
          } header: {
            Text("Das sehen deine Freunde")
          } footer: {
            Text("Keine Körperwerte: Puls, Kalorienverbrauch, Gewicht und Schlaf bleiben auf deinem iPhone.")
          }
          Section("Notiz (optional)") {
            TextField("z. B. Endlich wieder unter 5 min/km!", text: $note, axis: .vertical)
              .lineLimit(1...4)
          }
          Section {
            Button {
              Task { await send() }
            } label: {
              HStack {
                Text("Teilen")
                Spacer()
                if isSending { ProgressView() }
              }
            }
            .disabled(isSending)
          } footer: {
            if let error { Text(error).foregroundStyle(.red) }
          }
        }
      }
      .navigationTitle("Mit Freunden teilen")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
      .sheet(item: $signIn) { mode in AccountAuthView(initialMode: mode, invite: nil) }
    }
  }

  @ViewBuilder private var preview: some View {
    switch content {
    case .workout(let workout):
      LabeledContent("Training", value: workout.title)
      if let minutes = workout.durationMin { LabeledContent("Dauer", value: "\(minutes) min") }
      if let km = workout.distanceKm { LabeledContent("Strecke", value: "\(GermanFormat.decimal(km)) km") }
      if let up = workout.elevationM { LabeledContent("Höhenmeter", value: "\(up) m") }
      if let sets = workout.sets { LabeledContent("Sätze", value: "\(sets)") }
      if let exercises = workout.exercises { Text(exercises.joined(separator: " · ")).font(.footnote) }
      ForEach(workout.records ?? [], id: \.self) { Label($0, systemImage: "trophy.fill").font(.footnote) }
    case .meal(let meal):
      LabeledContent(meal.title, value: "\(Int(meal.kilocalories.rounded())) kcal")
      Text("\(meal.items.count) Positionen mit Mengen und Nährwerten – deine Freunde können sie übernehmen.")
        .font(.footnote)
    }
  }

  private func send() async {
    isSending = true
    defer { isSending = false }
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      switch content {
      case .workout(var workout):
        workout.note = trimmed.isEmpty ? nil : String(trimmed.prefix(280))
        try await model.social.share(workout: workout)
      case .meal(let meal):
        try await model.social.share(
          meal: MealPostShare(meal: meal, note: trimmed.isEmpty ? nil : String(trimmed.prefix(280))))
      }
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
