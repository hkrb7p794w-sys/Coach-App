import CoachCore
import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

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
