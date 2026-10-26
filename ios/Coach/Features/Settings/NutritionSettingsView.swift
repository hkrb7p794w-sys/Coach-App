import CoachCore
import SwiftUI

/// Ziel, Ernährungsweise und Körperwerte für die Tagesziele. Leere Körperwerte = Werte aus Garmin.
struct NutritionSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    let garmin = model.sync.profile
    Form {
      Section {
        if settings.profile.mode == .personal {
          // Ziel und Tempo kommen aus dem Profil (mit Schutzgrenzen), nicht von Hand.
          LabeledContent("Ziel", value: settings.nutrition.goal.label)
          if let rate = settings.nutrition.weeklyWeightChangePercent {
            LabeledContent("Tempo", value: "\(GermanFormat.decimal(rate)) % pro Woche")
          }
        } else {
          Picker("Ziel", selection: $settings.nutrition.goal) {
            ForEach(NutritionGoal.allCases, id: \.self) { Text($0.label).tag($0) }
          }
        }
        Picker("Ernährungsweise", selection: $settings.nutrition.diet) {
          ForEach(Diet.allCases, id: \.self) { Text($0.label).tag($0) }
        }
      } footer: {
        if settings.profile.mode == .personal {
          Text("Das Ziel änderst du im Profil (Einstellungen). Defizit und Überschuss gelten voll an Ruhe- und leichten Tagen, halb an moderaten, an harten Tagen nicht.")
        } else {
          Text("Abnehmen: −15 % an Ruhe- und leichten Tagen, halb so viel an moderaten, keins an harten Tagen.")
        }
      }

      Section {
        OptionalNumberField(
          title: "Gewicht", unit: "kg", value: $settings.nutrition.weightKilograms,
          placeholder: garmin?.weightKilograms)
        OptionalNumberField(
          title: "Größe", unit: "cm", value: $settings.nutrition.heightCentimeters,
          placeholder: garmin?.heightCentimeters)
        OptionalNumberField(
          title: "Körperfett", unit: "%", value: $settings.nutrition.bodyFatPercent, placeholder: nil)
        Stepper(
          "Aktivitätsfaktor ohne Sport \(GermanFormat.decimal(settings.nutrition.activityFactor))",
          value: $settings.nutrition.activityFactor, in: 1.2...2.0, step: 0.1)
      } header: {
        Text("Körperwerte")
      } footer: {
        Text("Leer lassen, um die Werte aus Garmin zu nutzen. Körperfett ohne Angabe: 15 % (Männer) bzw. 25 %.")
      }
    }
    .navigationTitle("Ernährung")
  }
}

private struct OptionalNumberField: View {
  let title: String
  let unit: String
  @Binding var value: Double?
  let placeholder: Double?

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      TextField(
        placeholder.map { GermanFormat.decimal($0) + " (Garmin)" } ?? "–", value: $value,
        format: .number.precision(.fractionLength(0...1))
      )
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.trailing)
      .frame(maxWidth: 140)
      Text(unit).foregroundStyle(.secondary)
    }
  }
}
