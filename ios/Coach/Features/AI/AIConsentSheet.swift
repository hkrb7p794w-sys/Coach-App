import CoachCore
import SwiftUI
import UIKit

/// Vor der ersten KI-Nutzung: Was geht an wen, und was passiert ohne Zustimmung.
struct AIConsentSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var includesHealthDetails = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Die KI läuft über deinen Worker bei externen Anbietern. Regeln, Ampel und Ziele bleiben auf dem iPhone "
              + "und funktionieren auch ohne KI.")
        }
        Section("An wen Daten gehen") {
          LabeledContent("Google Gemini, Mistral") {
            Text("In den kostenlosen Stufen dürfen die Anbieter Eingaben auswerten.")
          }
          LabeledContent("Cerebras, Groq, Workers AI") {
            Text("Laut Anbieter kein Training mit deinen Eingaben.")
          }
        }
        Section {
          Toggle("Auch Gesundheitsangaben", isOn: $includesHealthDetails)
        } header: {
          Text("Besonders sensible Angaben")
        } footer: {
          Text(
            "Dazu gehören Chat-Fragen, Mahlzeitenfotos, Beschwerden und Allergien. Ohne Haken gehen sie nur an "
              + "Anbieter ohne Training.")
        }
        Section {
          Button("Einverstanden") {
            model.settings.ai.consent = AIConsent(date: .now, includesHealthDetails: includesHealthDetails)
            dismiss()
          }
          Button("Nur Anbieter ohne Training") {
            model.settings.ai.provider = .privat
            dismiss()
          }
        } footer: {
          Text("Du kannst das jederzeit unter Einstellungen › KI ändern oder widerrufen.")
        }
      }
      .navigationTitle("KI und deine Daten")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

/// Kopiert Text nur auf dieses Gerät und löscht ihn nach fünf Minuten wieder aus der Zwischenablage.
enum PrivateClipboard {
  static func copy(_ text: String) {
    UIPasteboard.general.setItems(
      [["public.utf8-plain-text": text]], options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(300)])
  }
}
