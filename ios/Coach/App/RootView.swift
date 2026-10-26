import SwiftUI

struct RootView: View {
  var body: some View {
    TabView {
      Tab("Heute", systemImage: "sun.max") {
        PlaceholderView(
          title: "Heute",
          systemImage: "sun.max",
          message: "Tagesempfehlung, Erholung und Wochen-Soll/Ist kommen in Phase 3."
        )
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
      Tab("Diagnose", systemImage: "stethoscope") {
        DiagnosticsView()
      }
    }
  }
}

#Preview {
  RootView()
}
