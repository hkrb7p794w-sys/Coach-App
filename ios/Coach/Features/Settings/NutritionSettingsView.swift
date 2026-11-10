import CoachCore
import SwiftUI

/// Ziel, Ernährungsweise und Körperwerte für die Tagesziele. Leere Körperwerte = Werte aus Garmin.
struct NutritionSettingsView: View {
  @Environment(AppModel.self) private var model
  @State private var showsRecipePreferences = false
  @AppStorage(MealsActivityController.settingKey) private var mealsLiveActivity = false

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
          Text(
            "Das Ziel änderst du im Profil (Einstellungen). Defizit und Überschuss gelten voll "
              + "an Ruhe- und leichten Tagen, halb an moderaten, an harten Tagen nicht."
          )
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

      Section {
        ForEach(MealReminderSettings.categories, id: \.self) { category in
          MealReminderRow(category: category, slot: mealSlot(category, settings: settings))
        }
      } header: {
        Text("Erinnerungen an Mahlzeiten")
      } footer: {
        Text(
          "Zur gewohnten Zeit kommt eine Mitteilung – aber nur, wenn die Mahlzeit an dem Tag noch nicht erfasst ist. "
            + "Die Zeiten gelten in der aktuellen Zeitzone, auch auf Reisen.")
      }

      Section {
        Toggle("Abends um 20 Uhr „Tag auswerten“", isOn: $settings.reminders.nutritionReview)
        Button("Rezept-Vorlieben …") { showsRecipePreferences = true }
      } header: {
        Text("Erinnerung und Rezepte")
      }

      Section {
        Toggle("Mahlzeiten auf dem Sperrbildschirm", isOn: $mealsLiveActivity)
          .onChange(of: mealsLiveActivity) { WidgetPublisher.publish(model: model) }
      } footer: {
        Text(
          "Farbig und in voller Breite: Serie und je Mahlzeit ein Ring mit „+“ zum Eintragen (Live-Aktivität). "
            + "iOS blendet sie nach einigen Stunden aus; beim nächsten Öffnen der App ist sie wieder da. Die kleinen "
            + "Sperrbildschirm-Widgets zeichnet iOS immer einfarbig und höchstens halb so breit.")
      }

      Section {
        LabeledContent("Lebensmittel", value: "BLS 4.0")
        LabeledContent("Markenprodukte (Barcode)", value: "Open Food Facts")
      } header: {
        Text("Nährwertquellen")
      } footer: {
        Text(
          "\(BLS.attribution). Die KI zerlegt Mahlzeiten nur in Lebensmittel; die Nährwerte kommen aus dem BLS. "
            + "Ohne passenden Eintrag bleibt die KI-Schätzung (in der Mahlzeit als „geschätzt“ markiert)."
        )
      }
    }
    .navigationTitle("Ernährung")
    .sheet(isPresented: $showsRecipePreferences) { RecipePreferencesView() }
  }
}

extension NutritionSettingsView {
  func mealSlot(_ category: MealCategory, settings: CoachSettings) -> Binding<MealReminderSettings.Slot> {
    Binding(
      get: { settings.reminders.meals[category] ?? .init(hour: 12, minute: 0) },
      set: { settings.reminders.meals[category] = $0 })
  }
}

/// Schalter und Uhrzeit einer Mahlzeit.
private struct MealReminderRow: View {
  let category: MealCategory
  @Binding var slot: MealReminderSettings.Slot

  var body: some View {
    Toggle(category.label, isOn: $slot.enabled)
    if slot.enabled {
      DatePicker(
        "Uhrzeit",
        selection: Binding(
          get: {
            Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: .now) ?? .now
          },
          set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            slot = .init(enabled: true, hour: parts.hour ?? slot.hour, minute: parts.minute ?? slot.minute)
          }),
        displayedComponents: .hourAndMinute)
    }
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
