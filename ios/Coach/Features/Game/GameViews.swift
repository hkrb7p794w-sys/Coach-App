import CoachCore
import SwiftData
import SwiftUI

/// „Heute“: Tages-Serie, Stufe und nächstes Abzeichen; meldet den Stand an die Freundes-Rangliste.
struct GameSection: View {
  let summary: MotivationSummary
  let activities: [GarminActivity]
  let trainingDays: Set<CalendarDay>
  let today: CalendarDay
  @Environment(AppModel.self) private var model
  @Query(sort: \MealRecord.dayKey, order: .reverse) private var meals: [MealRecord]
  @Query(sort: \GymSessionRecord.start, order: .reverse) private var gymRecords: [GymSessionRecord]
  @State private var showFriends = false

  private var mealDays: Set<CalendarDay> {
    Set(meals.prefix(2_000).compactMap { CalendarDay(iso: $0.dayKey) })
  }

  /// Trainingsminuten je Tag aus Aktivitäten und Krafteinheiten (für Challenges).
  private var minutesByDay: [CalendarDay: Int] {
    var result: [CalendarDay: Int] = [:]
    let since = today.adding(days: -14)
    for activity in activities {
      guard let day = activity.day, day >= since, let seconds = activity.movingSeconds ?? activity.durationSeconds
      else { continue }
      result[day, default: 0] += Int((seconds / 60).rounded())
    }
    for record in gymRecords.prefix(60) {
      guard let session = record.session, session.day >= since, let end = session.end else { continue }
      result[session.day, default: 0] += Int((end.timeIntervalSince(session.start) / 60).rounded())
    }
    return result
  }

  var body: some View {
    let meals = mealDays
    let streak = DailyStreak.compute(activeDays: trainingDays.union(meals), today: today)
    let level = GameLevel.progress(totalPoints: summary.totalPoints)
    var stats = GameStats()
    stats.workouts = activities.count + gymRecords.count
    stats.bestDayStreak = streak.best
    stats.planWeekStreak = summary.streak
    stats.mealDays = meals.count
    stats.friends = model.social.friends.friends.count
    stats.challengesWon = model.game.challengesWon
    stats.level = level.level
    let next = BadgeRules.next(stats)
    return Section {
      Button {
        showFriends = true
      } label: {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Label {
              Text(streak.current == 1 ? "1 Tag in Folge" : "\(streak.current) Tage in Folge").font(.headline)
            } icon: {
              Image(systemName: "flame.fill").foregroundStyle(streak.activeToday ? .orange : .secondary)
            }
            Spacer()
            Text("Stufe \(level.level)").font(.subheadline.bold())
          }
          ProgressView(value: Double(level.inLevel), total: Double(level.perLevel))
            .accessibilityLabel("Fortschritt zur nächsten Stufe: \(level.inLevel) von \(level.perLevel) Punkten")
          if !streak.activeToday, streak.current > 0 {
            Text("Erfasse heute ein Training oder eine Mahlzeit, damit die Serie weiterläuft.")
              .font(.caption).foregroundStyle(.secondary)
          }
          if let next {
            Label("Nächstes Abzeichen: \(next.title) (\(next.progress(stats))/\(next.target))", systemImage: next.symbol)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
    } header: {
      Text("Fortschritt")
    } footer: {
      if !streak.jokerDays.isEmpty {
        Text("Joker eingesetzt: Ein freier Tag pro Woche unterbricht die Serie nicht – Pausen gehören dazu.")
      }
    }
    .sheet(isPresented: $showFriends) { FriendsView(initialPage: .game) }
    .task(id: "\(summary.weekPoints)-\(summary.totalPoints)-\(streak.current)-\(meals.count)-\(trainingDays.count)") {
      model.game.snapshot = GameService.Snapshot(streak: streak, summary: summary, stats: stats)
      await model.game.report(
        summary: summary, streak: streak,
        inputs: GameService.Inputs(
          today: today, minutesByDay: minutesByDay, mealDays: meals, adherence: summary.week))
    }
  }
}

/// „Wettkampf“ in Freunde: Stufe und Serie, Rangliste der Woche, Challenges, Abzeichen.
struct GameView: View {
  @Environment(AppModel.self) private var model
  @State private var creating = false

  var body: some View {
    let game = model.game
    List {
      if let snapshot = game.snapshot {
        Section {
          let level = GameLevel.progress(totalPoints: snapshot.summary.totalPoints)
          HStack(spacing: 16) {
            statTile("\(snapshot.streak.current)", "Tage in Folge", "flame.fill", .orange)
            statTile("\(level.level)", "Stufe", "star.fill", .yellow)
            statTile("\(snapshot.summary.weekPoints)", "Punkte diese Woche", "chart.bar.fill", .blue)
          }
          .padding(.vertical, 4)
        } footer: {
          Text(
            "Punkte gibt es für dein eigenes Plan-Ziel, nicht für mehr Training: Wer wenig plant, kann genauso gewinnen. "
              + "Beste Serie: \(snapshot.streak.best) Tage.")
        }
      }

      if !game.invitations.isEmpty {
        Section("Einladungen") {
          ForEach(game.invitations) { challenge in
            VStack(alignment: .leading, spacing: 6) {
              Text(challenge.title).font(.headline)
              Text("\(challenge.metricTitle) · Woche ab \(weekLabel(challenge))").font(.caption)
                .foregroundStyle(.secondary)
              HStack {
                Button("Mitmachen") { Task { await game.join(challenge) } }.buttonStyle(.borderedProminent)
                Button("Ablehnen") { Task { await game.leave(challenge) } }.buttonStyle(.bordered)
              }
            }
          }
        }
      }

      Section {
        if game.leaderboard.count <= 1 {
          Text("Füge Freunde hinzu, um euch in der Rangliste zu vergleichen.").foregroundStyle(.secondary)
        }
        ForEach(game.leaderboard) { entry in
          HStack {
            Text(entry.rank <= 3 ? ["🥇", "🥈", "🥉"][entry.rank - 1] : "\(entry.rank).")
              .frame(width: 32)
            Avatar(person: SocialPerson(username: entry.username, displayName: entry.displayName), size: 30)
            VStack(alignment: .leading) {
              Text(entry.me ? "Du" : entry.displayName).font(.subheadline.bold())
              Text("Stufe \(max(entry.level, 1)) · 🔥 \(entry.dayStreak)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.reported ? "\(entry.weekPoints)" : "–").font(.headline).monospacedDigit()
          }
          .listRowBackground(entry.me ? Color.accentColor.opacity(0.08) : nil)
        }
      } header: {
        Text("Rangliste diese Woche")
      } footer: {
        Text("Wochenpunkte: 100 = alles Geplante erledigt.")
      }

      Section {
        Button("Neue Challenge", systemImage: "flag.checkered") { creating = true }
          .disabled(model.social.friends.friends.isEmpty)
        ForEach(game.challenges.filter { $0.status == "joined" }) { challenge in
          ChallengeRow(challenge: challenge)
        }
      } header: {
        Text("Challenges")
      } footer: {
        if model.social.friends.friends.isEmpty {
          Text("Challenges gibt es mit Freunden – füge zuerst jemanden hinzu.")
        } else {
          Text("Eine Challenge läuft immer eine Kalenderwoche. Der Stand aktualisiert sich beim Öffnen von „Heute“.")
        }
      }

      if let snapshot = game.snapshot {
        BadgeGrid(stats: snapshot.stats)
      }
      if let error = game.lastError {
        Text(error).font(.footnote).foregroundStyle(.orange)
      }
    }
    .refreshable { await game.refresh() }
    .task { await game.refresh() }
    .sheet(isPresented: $creating) { NewChallengeSheet() }
  }

  private func statTile(_ value: String, _ label: String, _ symbol: String, _ color: Color) -> some View {
    VStack(spacing: 4) {
      Image(systemName: symbol).foregroundStyle(color)
      Text(value).font(.title2.bold()).monospacedDigit()
      Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }

  private func weekLabel(_ challenge: Challenge) -> String {
    challenge.monday.map { Formatters.shortDate($0) } ?? challenge.week
  }
}

private struct ChallengeRow: View {
  let challenge: Challenge
  @Environment(AppModel.self) private var model
  @State private var confirmLeave = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(challenge.title).font(.headline)
        Spacer()
        if challenge.finished {
          Text(challenge.iWon ? "🏆 Gewonnen" : "Beendet").font(.caption.bold())
            .foregroundStyle(challenge.iWon ? .orange : .secondary)
        }
      }
      Text(challenge.kind?.rule ?? challenge.metricTitle).font(.caption).foregroundStyle(.secondary)
      ForEach(challenge.joined) { member in
        HStack {
          Text((member.winner ? "🏆 " : "") + (member.me ? "Du" : member.displayName))
            .font(.subheadline)
            .frame(width: 110, alignment: .leading)
            .lineLimit(1)
          ProgressView(value: min(member.progress, Double(max(challenge.max, 1))), total: Double(max(challenge.max, 1)))
            .tint(member.me ? .accentColor : .secondary)
          Text("\(Int(member.progress)) \(challenge.kind?.unit ?? "")")
            .font(.caption).monospacedDigit()
            .frame(width: 64, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
      }
      let pending = challenge.members.filter { $0.status == "invited" }.count
      if pending > 0 {
        Text("\(pending) eingeladen, noch nicht dabei").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
    .swipeActions {
      Button(challenge.mineCreated ? "Löschen" : "Verlassen", role: .destructive) { confirmLeave = true }
    }
    .confirmationDialog(
      challenge.mineCreated ? "Challenge für alle löschen?" : "Challenge verlassen?", isPresented: $confirmLeave,
      titleVisibility: .visible
    ) {
      Button(challenge.mineCreated ? "Löschen" : "Verlassen", role: .destructive) {
        Task { await model.game.leave(challenge) }
      }
    }
  }
}

private struct BadgeGrid: View {
  let stats: GameStats

  var body: some View {
    let earned = BadgeRules.earned(stats).count
    Section {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
        ForEach(BadgeRules.all) { badge in
          let done = badge.isEarned(stats)
          VStack(spacing: 4) {
            Image(systemName: badge.symbol)
              .font(.title2)
              .foregroundStyle(done ? Color.orange : Color.secondary.opacity(0.5))
              .frame(width: 48, height: 48)
              .background(done ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.08), in: .circle)
            Text(badge.title).font(.caption.bold()).multilineTextAlignment(.center).lineLimit(2)
            Text(done ? badge.detail : "\(badge.progress(stats))/\(badge.target)")
              .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(badge.title), \(done ? "erreicht" : "\(badge.progress(stats)) von \(badge.target)")")
        }
      }
      .padding(.vertical, 6)
    } header: {
      Text("Abzeichen (\(earned)/\(BadgeRules.all.count))")
    } footer: {
      Text("Abzeichen gibt es für Beständigkeit – nie für mehr Training als geplant oder für weniger Essen.")
    }
  }
}

private struct NewChallengeSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var metric: ChallengeMetric = .plan
  @State private var nextWeek = false
  @State private var title = ""
  @State private var invited: Set<String> = []
  @State private var error: String?
  @State private var isSending = false

  var body: some View {
    let today = CalendarDay(date: .now)
    let monday = PlanAdjustments.monday(of: today)
    NavigationStack {
      Form {
        Section {
          Picker("Worum geht’s?", selection: $metric) {
            ForEach(ChallengeMetric.allCases) { Text($0.title).tag($0) }
          }
        } footer: {
          Text(metric.rule)
        }
        Section {
          Picker("Woche", selection: $nextWeek) {
            Text("Diese Woche").tag(false)
            Text("Nächste Woche").tag(true)
          }
          .pickerStyle(.segmented)
          TextField("Name (optional), z. B. Novemberduell", text: $title)
        }
        Section("Freunde einladen") {
          ForEach(model.social.friends.friends) { friend in
            Button {
              if invited.contains(friend.username) {
                invited.remove(friend.username)
              } else {
                invited.insert(friend.username)
              }
            } label: {
              HStack {
                Text(friend.displayName)
                Spacer()
                if invited.contains(friend.username) { Image(systemName: "checkmark").foregroundStyle(.tint) }
              }
            }
            .foregroundStyle(.primary)
          }
        }
        Section {
          Button("Challenge starten") {
            Task {
              isSending = true
              defer { isSending = false }
              do {
                try await model.game.create(
                  metric: metric, week: nextWeek ? monday.adding(days: 7) : monday,
                  title: title.trimmingCharacters(in: .whitespacesAndNewlines), invite: Array(invited))
                dismiss()
              } catch {
                self.error = error.localizedDescription
              }
            }
          }
          .disabled(invited.isEmpty || isSending)
        } footer: {
          if let error { Text(error).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Neue Challenge")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
    }
  }
}
