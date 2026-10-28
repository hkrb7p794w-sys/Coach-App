import CoachCore
import SwiftUI

/// Renntermine und Saisonphasen. Phasen, Wochen-Soll und Plantexte rechnen sich daraus.
struct SeasonSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section("Hauptrennen") {
        TextField("Name", text: $settings.season.mainRaceName)
        TextField("Beschreibung", text: $settings.season.mainRaceDescription, axis: .vertical)
        DatePicker("Datum", selection: dayBinding($settings.season.mainRaceDate), displayedComponents: .date)
        TextField("Ziel", text: $settings.season.raceGoal)
      }

      Section {
        DatePicker("Marathon", selection: dayBinding($settings.season.marathonDate), displayedComponents: .date)
        DatePicker("Grundlage ab", selection: dayBinding($settings.season.baseStart), displayedComponents: .date)
        DatePicker(
          "Marathonblock ab", selection: dayBinding($settings.season.marathonBlockStart), displayedComponents: .date)
      } header: {
        Text("Saison")
      } footer: {
        Text(
          "Daraus ergeben sich die Phasen: Marathon-Taper 3 Wochen, danach 2 Wochen Regeneration; Peak 3 Wochen und "
            + "Taper ab dem Montag der vorletzten Rennwoche.")
      }

      Section {
        Text("FTP, CSS, Paces und Herzfrequenz stehen unter Einstellungen › Disziplinen (Laufen, Rad, Schwimmen).")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      Section {
        Button("Auf Standardwerte zurücksetzen", role: .destructive) {
          settings.season = .standard
        }
      }
    }
    .navigationTitle("Saison & Rennen")
  }

  private func dayBinding(_ binding: Binding<CalendarDay>) -> Binding<Date> {
    Binding(
      get: { binding.wrappedValue.localDate },
      set: { binding.wrappedValue = CalendarDay(date: $0) }
    )
  }
}
