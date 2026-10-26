import CoachCore
import SwiftUI

/// Renntermine, Testwerte und KI-Datenschutz. Phasen, Wochen-Soll und Plantexte rechnen sich daraus.
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
        Stepper("FTP \(settings.season.ftpWatts) W", value: $settings.season.ftpWatts, in: 80...500)
        Stepper(
          "CSS \(GermanFormat.minutesSeconds(settings.season.cssSecondsPer100m)) /100 m",
          value: $settings.season.cssSecondsPer100m, in: 60...240)
        Stepper(
          "Schwellenpace \(GermanFormat.minutesSeconds(settings.season.thresholdPaceSecondsPerKm)) /km",
          value: $settings.season.thresholdPaceSecondsPerKm, in: 150...480)
        Stepper(
          "Marathonpace \(GermanFormat.minutesSeconds(settings.season.marathonPaceSecondsPerKm)) /km",
          value: $settings.season.marathonPaceSecondsPerKm, in: 150...480)
      } header: {
        Text("Testwerte")
      } footer: {
        Text(
          "Nach jedem Test hier aktualisieren – Watt- und Pace-Angaben im Plan und in der KI-Notiz rechnen sich "
            + "daraus.")
      }

      Section {
        HeartRateStepper(title: "HFmax", value: $settings.heartRate.maxHeartRate, range: 140...230)
        HeartRateStepper(title: "Schwelle Laufen", value: $settings.heartRate.thresholdRun, range: 120...210)
        HeartRateStepper(title: "Schwelle Rad", value: $settings.heartRate.thresholdBike, range: 120...210)
      } header: {
        Text("Herzfrequenz")
      } footer: {
        Text(
          "Ohne eigene Werte nutzt die App die Laktatschwelle von Garmin und den höchsten bestätigten Puls aus "
            + "deinen Einheiten. Schwelle: 30 Minuten am Anschlag, Ø-HF der letzten 20 Minuten.")
      }

      Section {
        Picker("KI-Datenschutz", selection: $settings.privacy) {
          Text("Reduziert (empfohlen)").tag(PrivacyMode.reduced)
          Text("Voll").tag(PrivacyMode.full)
        }
      } footer: {
        Text(
          "Reduziert: An die KI gehen nur Einordnungen (z. B. „HRV ausgeglichen“, „Schlaf kurz“), keine Rohwerte. "
            + "Im kostenlosen Gemini-Kontingent darf Google Eingaben zur Produktverbesserung nutzen.")
      }

      Section {
        Button("Auf Standardwerte zurücksetzen", role: .destructive) {
          settings.season = .standard
        }
      }
    }
    .navigationTitle("Saison & Ziele")
  }

  private func dayBinding(_ binding: Binding<CalendarDay>) -> Binding<Date> {
    Binding(
      get: { binding.wrappedValue.localDate },
      set: { binding.wrappedValue = CalendarDay(date: $0) }
    )
  }
}

/// Eigener Pulswert; „automatisch“, solange keiner gesetzt ist.
private struct HeartRateStepper: View {
  let title: String
  @Binding var value: Int?
  let range: ClosedRange<Int>

  var body: some View {
    if let current = value {
      HStack {
        Stepper(
          "\(title) \(current) bpm",
          value: Binding(get: { current }, set: { value = $0 }), in: range)
        Button("Auto") { value = nil }.buttonStyle(.borderless)
      }
    } else {
      LabeledContent(title) {
        Button("automatisch – eigenen Wert setzen") { value = (range.lowerBound + range.upperBound) / 2 + 10 }
          .buttonStyle(.borderless)
      }
    }
  }
}
