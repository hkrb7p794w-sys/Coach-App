import CoachCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var invite: LeagueInvite?
  @State private var sharedMeal: SharedMealLink?
  @State private var cookLink: CookLink?
  @State private var router = AppRouter.shared

  /// Erinnerungen neu planen, sobald sich Plan, Ausnahmen oder Uhrzeit ändern.
  private var reminderKey: Int {
    var hasher = Hasher()
    hasher.combine(model.settings.profile)
    hasher.combine(model.settings.planAdjustments)
    hasher.combine(model.settings.reminders)
    hasher.combine(model.settings.companion)
    return hasher.finalize()
  }

  var body: some View {
    let profile = model.settings.profile
    TabView(selection: $router.tab) {
      Tab("Heute", systemImage: "sun.max", value: AppTab.today) {
        TodayView()
      }
      // Der Plan liegt im Reiter Training (Entscheidung vom 02.11.2026: fünf Reiter ohne „Mehr“).
      Tab("Training", systemImage: "heart.text.square", value: AppTab.training) {
        TrainingView()
      }
      Tab("Ernährung", systemImage: "fork.knife", value: AppTab.nutrition) {
        NutritionView()
      }
      if profile.trains(.strength) {
        Tab("Gym", systemImage: "dumbbell", value: AppTab.gym) {
          GymView()
        }
      }
      Tab("AI", systemImage: "sparkles", value: AppTab.ai) {
        AIView()
      }
      .badge(InsightInbox.unreadCount(model.settings.insights, now: .now))
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if CoachSchema.isTemporary && !model.isDemo { StorageWarningBanner() }
    }
    .task { await model.syncIfDue() }
    // Schnellaktion, Kurzbefehl oder Link: Reiter wählen; die Aktion übernimmt die Zielansicht.
    .onChange(of: router.pending, initial: true) {
      router.resolve(trainsStrength: profile.trains(.strength), ready: profile.onboardingDone)
    }
    // Gym-Reiter entfällt (kein Krafttraining mehr): nicht auf einem leeren Reiter stehen bleiben.
    .onChange(of: profile.trains(.strength)) { _, strength in
      if !strength && router.tab == .gym { router.tab = .today }
    }
    .task(id: reminderKey) {
      guard profile.onboardingDone else { return }
      await model.refreshReminders()
    }
    // Andere Zeitzone (Reise): Essens- und Trainingszeiten gelten in der neuen Ortszeit.
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      Task { await model.refreshReminders() }
    }
    // Einladungslink coach://join?… (Rangliste).
    // Geteilte Mahlzeit coach://meal/<code>.
    // Ziel in der App coach://open/<route> (Widgets, Kurzbefehle).
    .onOpenURL { url in
      if let link = CookLink(url: url) {
        cookLink = link
      } else if let route = AppRoute(url: url) {
        router.open(route, mealCategory: AppRoute.mealCategory(from: url))
      } else if let link = SharedMealLink(url: url) {
        sharedMeal = link
      } else {
        invite = LeagueInvite(url: url)
      }
    }
    .sheet(item: $sharedMeal) { link in ReceivedMealSheet(code: link.code) }
    .sheet(item: $cookLink) { link in
      NavigationStack {
        switch link {
        case .partner(let code): CookPartnersView(initialCode: code)
        case .release: CookPartnersView(initialCode: nil)
        }
      }
    }
    .sheet(isPresented: Binding(get: { invite != nil }, set: { if !$0 { invite = nil } })) {
      if let invite { JoinLeagueSheet(invite: invite) }
    }
    // Aus einer Mitteilung „Verschieben …“ gewählt.
    .sheet(
      isPresented: Binding(
        get: { model.reminders.pendingDay != nil }, set: { if !$0 { model.reminders.pendingDay = nil } })
    ) {
      if let day = model.reminders.pendingDay {
        AdjustDaySheet(day: day)
      }
    }
    // Aus der Sonntags-Mitteilung „Nächste Woche planen“.
    .sheet(
      isPresented: Binding(
        get: { model.reminders.showsWeekPlanning }, set: { model.reminders.showsWeekPlanning = $0 })
    ) {
      NextWeekPlanSheet()
    }
    // Erster Start: Einrichtungsassistent, bis das Profil fertig ist.
    .fullScreenCover(isPresented: Binding(get: { !profile.onboardingDone }, set: { _ in })) {
      OnboardingView()
    }
  }
}

#Preview {
  RootView()
    .environment(AppModel(inMemory: true, secrets: InMemorySecretStore(), defaults: UserDefaults()))
}

/// Warnung, wenn der Datenspeicher nicht geöffnet werden konnte (`CoachSchema.isTemporary`).
private struct StorageWarningBanner: View {
  var body: some View {
    Label {
      Text(
        "Gespeicherte Daten konnten nicht geöffnet werden. Neue Einträge gehen beim Schließen verloren – "
          + "bitte nichts erfassen und auf ein Update warten. Deine bisherigen Daten bleiben erhalten.")
    } icon: {
      Image(systemName: "exclamationmark.triangle.fill")
    }
    .font(.footnote)
    .foregroundStyle(.primary)
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.orange.opacity(0.25))
    .accessibilityElement(children: .combine)
  }
}
