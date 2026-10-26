import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    TabView {
      Tab("Heute", systemImage: "sun.max") {
        TodayView()
      }
      Tab("Plan", systemImage: "calendar") {
        PlanView()
      }
      Tab("Training", systemImage: "heart.text.square") {
        TrainingView()
      }
      Tab("Ernährung", systemImage: "fork.knife") {
        NutritionView()
      }
      Tab("Gym", systemImage: "dumbbell") {
        GymView()
      }
    }
    .task { await model.syncIfDue() }
  }
}

#Preview {
  RootView()
    .environment(AppModel(inMemory: true, secrets: InMemorySecretStore(), defaults: UserDefaults()))
}
