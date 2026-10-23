import SwiftUI

/// Platzhalter für Bereiche, die in späteren Phasen gebaut werden.
struct PlaceholderView: View {
  let title: String
  let systemImage: String
  let message: String

  var body: some View {
    NavigationStack {
      ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
        .navigationTitle(title)
    }
  }
}
