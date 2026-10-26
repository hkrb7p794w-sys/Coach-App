import CoachCore
import PhotosUI
import SwiftUI

/// Begleiter und Rangliste unter „Heute“.
struct MotivationSections: View {
  let snapshot: TodayViewModel.Snapshot
  let activities: [GarminActivity]
  let gymDays: Set<CalendarDay>
  @Environment(AppModel.self) private var model

  private var trainingDays: Set<CalendarDay> {
    Set(activities.filter { ($0.durationSeconds ?? 0) >= 900 }.compactMap(\.day)).union(gymDays)
  }

  var body: some View {
    let settings = model.settings
    let today = snapshot.plan.today
    let days = trainingDays
    let summary = model.motivation(trainingDays: days, today: today)
    if settings.companion.isActive {
      CompanionSection(
        companion: settings.companion,
        message: CompanionVoice.message(
          CompanionVoice.Context(
            plannedToday: plannedToday(today), trainedToday: days.contains(today),
            recovery: snapshot.metrics == nil ? nil : snapshot.recommendation.level, week: summary.week,
            missedYesterday: summary.missedYesterday(today: today)),
          companion: settings.companion, day: today))
    }
    if settings.league.isJoined {
      LeagueSection(summary: summary)
        .task(id: "\(summary.weekPoints)-\(summary.totalPoints)-\(settings.league.code)") {
          await model.league.sync(summary: summary)
        }
    }
  }

  private func plannedToday(_ today: CalendarDay) -> [String] {
    if model.settings.profile.mode == .personal {
      return model.settings.schedule(inWeekOf: today).slots(on: Weekday(day: today)).map(\.title)
    }
    return snapshot.today?.items.filter { $0.sport != .rest && !$0.done }.map(\.title) ?? []
  }
}

private struct CompanionSection: View {
  let companion: CompanionSettings
  let message: CompanionMessage
  @State private var photo: UIImage?

  var body: some View {
    Section {
      HStack(alignment: .top, spacing: 14) {
        ZStack(alignment: .bottomTrailing) {
          CompanionAvatar(companion: companion, photo: photo, size: 64)
          Image(systemName: message.mood.symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Color.pink.gradient, in: Circle())
            .offset(x: 4, y: 4)
            .accessibilityHidden(true)
        }
        VStack(alignment: .leading, spacing: 4) {
          Text(companion.displayName).font(.headline)
          Text(message.text).font(.subheadline)
        }
      }
      .padding(.vertical, 4)
      .accessibilityElement(children: .combine)
    }
    .task { photo = CompanionPhoto.load() }
  }
}

struct CompanionAvatar: View {
  let companion: CompanionSettings
  let photo: UIImage?
  var size: CGFloat = 64

  var body: some View {
    Group {
      if let photo {
        Image(uiImage: photo).resizable().scaledToFill()
      } else {
        Image(systemName: companion.kind.symbol)
          .font(.system(size: size * 0.45))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.orange.gradient)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}

private struct LeagueSection: View {
  let summary: MotivationSummary
  @Environment(AppModel.self) private var model

  var body: some View {
    let league = model.league
    let me = model.settings.league.memberID
    Section {
      if league.members.isEmpty {
        HStack {
          Text("Deine Woche: \(summary.weekPoints) Punkte")
          Spacer()
          if league.isLoading { ProgressView() }
        }
      }
      ForEach(Array(league.members.enumerated()), id: \.element.id) { index, member in
        HStack(spacing: 12) {
          Text(index == 0 && member.weekPoints > 0 ? "🏆" : "\(index + 1).")
            .font(.headline)
            .frame(width: 32)
          Image(systemName: member.avatar)
            .foregroundStyle(Color.accentColor)
            .frame(width: 24)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(member.id == me ? "\(member.name) (du)" : member.name)
              .font(.subheadline.weight(member.id == me ? .bold : .regular))
            Text("\(member.done) von \(member.planned) Einheiten · Serie \(member.streak) Wo.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(member.weekPoints)").font(.headline).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
      }
      if let error = league.lastError {
        Text(error).font(.footnote).foregroundStyle(.orange)
      }
    } header: {
      Text("Rangliste diese Woche")
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        Text(
          "Punkte gibt es für Einheiten aus deinem Plan (\(ScoreRules.pointsPerSession) je Einheit, "
            + "+\(ScoreRules.completeWeekBonus) für die ganze Woche). Mehr Training zählt nicht extra – "
            + "Ruhetage gehören dazu. Stufe \(summary.level).")
        EvidenceDisclosure(ruleIDs: ["motivation.gamification"])
      }
    }
  }
}

/// Einstellungen für Begleiter und Rangliste.
struct MotivationSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var pickedPhoto: PhotosPickerItem?
  @State private var photo: UIImage?
  @State private var joinCode = ""
  @State private var confirmLeave = false

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section {
        Toggle("Begleiter anzeigen", isOn: $settings.companion.enabled)
        if settings.companion.enabled {
          HStack(spacing: 14) {
            CompanionAvatar(companion: settings.companion, photo: photo, size: 56)
            TextField("Name, z. B. Daisy", text: $settings.companion.name)
          }
          Picker("Art", selection: $settings.companion.kind) {
            ForEach(CompanionSettings.Kind.allCases) { kind in
              Label(kind.label, systemImage: kind.symbol).tag(kind)
            }
          }
          PhotosPicker(selection: $pickedPhoto, matching: .images) {
            Label(photo == nil ? "Foto auswählen" : "Anderes Foto", systemImage: "photo")
          }
          if photo != nil {
            Button("Foto entfernen", role: .destructive) {
              CompanionPhoto.remove()
              photo = nil
            }
          }
        }
      } header: {
        Text("Begleiter")
      } footer: {
        Text(
          "Der Begleiter kommentiert deinen Tag freundlich und erinnert dich an Einheiten. Er richtet sich nach "
            + "denselben Regeln wie die Empfehlung: Bei schlechter Erholung lobt er das Ausruhen. Das Foto bleibt "
            + "auf diesem iPhone.")
      }

      Section {
        TextField("Dein Name in der Rangliste", text: $settings.league.name)
        if settings.league.isJoined {
          LabeledContent("Code", value: settings.league.code)
          if let invite = model.league.inviteURL {
            ShareLink(
              item: invite, subject: Text("Coach-Rangliste"), message: Text("Mach mit in meiner Coach-Rangliste!")
            ) {
              Label("Einladungslink teilen", systemImage: "square.and.arrow.up")
            }
          }
          Button("Rangliste verlassen", role: .destructive) { confirmLeave = true }
        } else {
          Button("Neue Rangliste erstellen") { model.league.create() }
            .disabled(!model.league.canUse)
          HStack {
            TextField("Code eingeben", text: $joinCode)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            Button("Beitreten") { model.league.join(code: joinCode) }
              .disabled(!LeagueCode.isValid(joinCode.lowercased()) || !model.league.canUse)
          }
        }
      } header: {
        Text("Rangliste")
      } footer: {
        if !model.league.canUse {
          Text("Für die Rangliste muss der KI-Worker eingerichtet sein (Einstellungen › KI-Worker).")
        } else {
          Text(
            "Geteilt werden nur Name, Symbol und Punkte – keine Gesundheitsdaten. Der Einladungslink enthält "
              + "auch das App-Token deines Workers; schicke ihn nur an Personen, denen du vertraust. Jede Person "
              + "richtet in ihrer App eigenes Profil und Garmin-Konto ein.")
        }
      }
    }
    .navigationTitle("Begleiter & Rangliste")
    .task { photo = CompanionPhoto.load() }
    .onChange(of: pickedPhoto) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          try? CompanionPhoto.save(data)
          photo = CompanionPhoto.load()
        }
      }
    }
    .confirmationDialog("Rangliste verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
      Button("Verlassen", role: .destructive) { Task { await model.league.leave() } }
    }
  }
}

/// Aus einem Einladungslink geöffnet.
struct JoinLeagueSheet: View {
  let invite: LeagueInvite
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var error: String?

  var body: some View {
    @Bindable var settings = model.settings
    NavigationStack {
      Form {
        Section {
          Text("Du wurdest in eine Coach-Rangliste eingeladen.")
          TextField("Dein Name in der Rangliste", text: $settings.league.name)
        } footer: {
          Text(
            "Die App nutzt dafür den KI-Worker aus der Einladung. Dein Profil, Garmin-Konto und alle Daten bleiben "
              + "auf deinem iPhone; geteilt werden nur Name und Punkte.")
        }
        if let error {
          Section { Text(error).foregroundStyle(.red) }
        }
      }
      .navigationTitle("Rangliste beitreten")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Beitreten") {
            do {
              try model.league.accept(invite)
              dismiss()
            } catch {
              self.error = error.localizedDescription
            }
          }
          .disabled(settings.league.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }
}
