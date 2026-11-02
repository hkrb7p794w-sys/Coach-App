import CoachCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model
  @State private var invite: LeagueInvite?
  @State private var sharedMeal: SharedMealLink?

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
    TabView {
      Tab("Heute", systemImage: "sun.max") {
        TodayView()
      }
      // Der Plan liegt im Reiter Training (Entscheidung vom 02.11.2026: fünf Reiter ohne „Mehr“).
      Tab("Training", systemImage: "heart.text.square") {
        TrainingView()
      }
      Tab("Ernährung", systemImage: "fork.knife") {
        NutritionView()
      }
      if profile.trains(.strength) {
        Tab("Gym", systemImage: "dumbbell") {
          GymView()
        }
      }
      Tab("AI", systemImage: "sparkles") {
        AIView()
      }
      .badge(InsightInbox.unreadCount(model.settings.insights, now: .now))
    }
    .task { await model.syncIfDue() }
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
    .onOpenURL { url in
      if let link = SharedMealLink(url: url) {
        sharedMeal = link
      } else {
        invite = LeagueInvite(url: url)
      }
    }
    .sheet(item: $sharedMeal) { link in ReceivedMealSheet(code: link.code) }
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
