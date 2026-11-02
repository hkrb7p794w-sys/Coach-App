import CoachCore
import SwiftUI
import UIKit

/// Setzt die gewählte Darstellung auf allen Fenstern der App. Über `overrideUserInterfaceStyle` statt
/// `preferredColorScheme`, weil Letzteres beim Zurückschalten auf „Wie System“ in Sheets hängen bleiben kann.
enum AppearanceController {
  static func apply(_ appearance: AppAppearance) {
    let style: UIUserInterfaceStyle =
      switch appearance {
      case .system: .unspecified
      case .light: .light
      case .dark: .dark
      }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
    }
  }
}

/// Auswahl in den Einstellungen.
struct AppearanceSettingsSection: View {
  @AppStorage(AppAppearance.storageKey) private var stored = AppAppearance.system.rawValue

  var body: some View {
    Section {
      Picker("Darstellung", selection: $stored) {
        ForEach(AppAppearance.allCases) { appearance in
          Label(appearance.title, systemImage: appearance.symbol).tag(appearance.rawValue)
        }
      }
    } footer: {
      Text("„Wie System“ folgt dem Dunkelmodus des iPhones. Widgets richten sich immer nach dem System.")
    }
    .onChange(of: stored) { _, value in AppearanceController.apply(AppAppearance(stored: value)) }
  }
}
