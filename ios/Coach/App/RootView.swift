import CoachCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

  /// Erinnerungen neu planen, sobald sich Plan, Ausnahmen oder Uhrzeit ändern.
  private var reminderKey: Int {
    var hasher = Hasher()
    hasher.combine(model.settings.profile)
    hasher.combine(model.settings.planAdjustments)
    hasher.combine(model.settings.reminders)
    return hasher.finalize()
  }

  var body: some View {
    let profile = model.settings.profile
    TabView {
      Tab("Heute", systemImage: "sun.max") {
        TodayView()
      }
      Tab("Plan", systemImage: "calendar") {
        if profile.mode == .season { PlanView() } else { MyWeekView() }
      }
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
    }
    .task { await model.syncIfDue() }
    .task(id: reminderKey) {
      guard profile.onboardingDone else { return }
      await model.refreshReminders()
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
