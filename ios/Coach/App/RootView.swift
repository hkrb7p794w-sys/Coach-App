import SwiftUI

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    TabView {
      Tab("Heute", systemImage: "sun.max") {
        TodayView()
      }
      Tab("Ernährung", systemImage: "fork.knife") {
        PlaceholderView(
          title: "Ernährung",
          systemImage: "fork.knife",
          message: "Erfassung per Foto, Text und Barcode kommt in Phase 4."
        )
      }
      Tab("Gym", systemImage: "dumbbell") {
        PlaceholderView(
          title: "Gym",
          systemImage: "dumbbell",
          message: "Übungen, Sätze und Verlauf kommen in Phase 5."
        )
      }
      Tab("Einstellungen", systemImage: "gearshape") {
        SettingsView()
      }
    }
    .task { await model.syncIfDue() }
  }
}

#Preview {
  RootView()
    .environment(AppModel(inMemory: true, secrets: InMemorySecretStore(), defaults: UserDefaults()))
}
