import CoachCore
import SwiftUI

/// Einstellungen nach Disziplin: alles zu einer Sportart an einem Ort.
struct DisciplineSettingsSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let profile = model.settings.profile
    // Im Saisonplan alle drei Ausdauer-Disziplinen, sonst nur die gewählten Sportarten.
    let endurance: [TrainingSport] = [.run, .bike, .swim].filter {
      profile.mode == .season || profile.sports.contains($0)
    }
    Section {
      if profile.mode == .season || profile.sports.contains(.strength) {
        NavigationLink { GymSettingsView() } label: { Label("Gym", systemImage: "dumbbell.fill") }
      }
      ForEach(endurance, id: \.self) { sport in
        NavigationLink { EnduranceSettingsView(sport: sport) } label: {
          Label(sport.shortLabel, systemImage: sport.symbol)
        }
      }
      NavigationLink { NutritionSettingsView() } label: { Label("Ernährung", systemImage: "fork.knife") }
      NavigationLink { SleepCoachView() } label: { Label("Schlaf", systemImage: "moon.stars.fill") }
    } header: {
      Text("Disziplinen")
    }
  }
}

/// Gym: Pausen, Aufwärmen, Abhaken, Übungen, Ausstattung, Sperrbildschirm, Garmin.
struct GymSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    Form {
      Section {
        restPicker("Grundübungen", $settings.gym.restCompound)
        restPicker("Isolationsübungen", $settings.gym.restIsolation)
        restPicker("Nach Aufwärmsätzen", $settings.gym.restWarmup)
        Toggle("Pause nach dem Satz sofort starten", isOn: $settings.gym.autoStartsRest)
        NavigationLink("Pausen und Notizen je Übung") { ExerciseSettingsList() }
      } header: {
        Text("Satzpausen")
      } footer: {
        Text(
          "Gilt, wenn weder die Routine noch die Übung eine eigene Pause hat. Eine Pause je Übung stellst du unter "
            + "„Pausen und Notizen je Übung“ oder während der Einheit im Menü der Übung ein. Ohne sofortigen Start "
            + "erscheint nach dem Satz „Pause starten“.")
      }
      Section {
        Picker("Satz abhaken", selection: $settings.gym.completeOnEdit) {
          ForEach(CompleteOnEdit.allCases) { Text($0.label).tag($0) }
        }
      } header: {
        Text("Nach dem Eintippen")
      } footer: {
        Text(
          "Wenn du Gewicht oder Wiederholungen über den Ziffernblock einträgst, hakt die App den Satz ab und startet "
            + "die Pause – ein Tipp weniger. Die ±-Knöpfe haken nie ab.")
      }
      Section {
        Toggle("Aufwärmsätze vorschlagen", isOn: $settings.gym.suggestsWarmUp)
      } footer: {
        Text(
          "Vor dem ersten Satz einer Grundübung: leere Stange, dann etwa 50, 70 und 85 % des Arbeitsgewichts "
            + "(Kurzhantel/Maschine 50 und 75 %). Optional – mit einem Tipp eingefügt, gezählt werden sie nicht.")
      }
      Section {
        NavigationLink("Ausstattung, Stange und Scheiben") { EquipmentSettingsView() }
      }
      Section {
        Toggle("Wiederholungen in Reserve abfragen", isOn: $settings.gym.tracksRIR)
      } footer: {
        Text(
          "In der Pause nach jedem Satz kurz antippen, wie viele Wiederholungen noch gegangen wären (RIR) – "
            + "freiwillig, das Abhaken bleibt ein Tipp. Bleiben in allen Sätzen 4 oder mehr übrig, schlägt die "
            + "App sofort mehr Gewicht vor.")
      }
      Section {
        Toggle("Bildschirm anlassen", isOn: $settings.gym.keepsScreenOn)
        Toggle("Pause auf dem Sperrbildschirm", isOn: $settings.gym.liveActivity)
      } footer: {
        Text(
          "Während einer Einheit sperrt sich das iPhone nicht – kein Entsperren mit verschwitzten Händen. Auf dem "
            + "Sperrbildschirm und in der Dynamic Island stehen Pause und nächster Satz, mit „Satz erledigt“ zum "
            + "Antippen (Live-Aktivität; in den iOS-Einstellungen unter IronLudi abschaltbar).")
      }
      Section {
        Toggle("Fokus während der Einheit", isOn: $settings.gym.focusShortcuts)
        if settings.gym.focusShortcuts {
          Button("Fokus jetzt testen", systemImage: "moon.fill") {
            if let url = WorkoutFocus.url(turningOn: true) { UIApplication.shared.open(url) }
          }
        }
      } header: {
        Text("Keine Störungen beim Training")
      } footer: {
        Text(
          "iOS lässt Apps den Fokus nicht selbst schalten – das übernehmen zwei Kurzbefehle. Einmal einrichten: "
            + "Kurzbefehle-App › + › Aktion „Fokus festlegen“ › Fokus (z. B. „Fitness“ oder „Nicht stören“) "
            + "einschalten, Name „\(WorkoutFocus.onShortcut)“. Einen zweiten mit „ausschalten“ und dem Namen "
            + "„\(WorkoutFocus.offShortcut)“. Nach dem ersten erledigten Satz (also in der Pause) und beim Beenden "
            + "wechselt IronLudi kurz in die Kurzbefehle-App und kommt sofort zurück. Welche Mitteilungen im Fokus "
            + "durchkommen, legst du in Einstellungen › Fokus fest.")
      }
      Section {
        Toggle("Nach Garmin Connect übertragen", isOn: $settings.gym.uploadsToGarmin)
      } footer: {
        Text(
          "Beendete Einheiten erscheinen in Garmin Connect als Krafttraining mit Übung, Wiederholungen und Gewicht "
            + "je Satz. Nur mit Garmin-Konto. Zeichnest du dieselbe Einheit auch mit der Uhr auf, gibt es sie doppelt.")
      }
    }
    .navigationTitle("Gym")
  }

  private func restPicker(_ title: String, _ value: Binding<Int>) -> some View {
    Picker(title, selection: value) {
      ForEach(RestText.options, id: \.self) { Text(RestText.format($0)).tag($0) }
    }
  }
}

/// Übungen aus den eigenen Routinen und alle mit eigener Pause oder Notiz – per Suche jede andere.
struct ExerciseSettingsList: View {
  @Environment(AppModel.self) private var model
  @State private var search = ""

  var body: some View {
    let gym = model.settings.gym
    let mine = Set(gym.routines.flatMap { $0.items.map(\.exerciseID) })
      .union(gym.restOverrides.keys).union(gym.notes.keys).union(gym.bars.keys)
    let found = search.isEmpty ? [] : ExerciseLibrary.search(search, custom: gym.customExercises, available: nil)
    let own = mine.compactMap { gym.exercise($0) }.sorted { $0.name < $1.name }
    List {
      if !own.isEmpty {
        Section("Meine Übungen") {
          ForEach(own) { row($0) }
        }
      }
      if !found.isEmpty {
        Section("Suche") {
          ForEach(found.filter { !mine.contains($0.id) }) { row($0) }
        }
      }
    }
    .searchable(text: $search, prompt: "Übung suchen")
    .navigationTitle("Je Übung")
  }

  private func row(_ exercise: ExerciseInfo) -> some View {
    let gym = model.settings.gym
    return NavigationLink {
      ExerciseSettingsDetail(exercise: exercise)
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text(exercise.name)
        let rest = gym.rest(for: exercise.id, compound: exercise.compound)
        let custom = gym.restOverrides[exercise.id] != nil
        Text("Pause \(RestText.format(rest))\(custom ? "" : " (Standard)")" + (gym.notes[exercise.id].map { " · \($0)" } ?? ""))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
}

/// Pause, Notiz und Stange einer Übung.
private struct ExerciseSettingsDetail: View {
  let exercise: ExerciseInfo
  @Environment(AppModel.self) private var model

  var body: some View {
    let gym = model.settings.gym
    Form {
      Section {
        Picker("Pause", selection: restBinding) {
          Text("Standard (\(RestText.format(gym.rest(for: "", compound: exercise.compound))))").tag(0)
          ForEach(RestText.options, id: \.self) { Text(RestText.format($0)).tag($0) }
        }
      } footer: {
        Text("Gilt ab der nächsten Einheit, auch wenn die Routine eine andere Pause hat.")
      }
      Section {
        TextField("z. B. Sitz 4, Griff weit, Bank auf Stufe 3", text: noteBinding, axis: .vertical)
          .lineLimit(2...5)
      } header: {
        Text("Notiz")
      } footer: {
        Text("Steht bei jeder Einheit unter der Übung – für Sitzhöhe, Griff, Bankeinstellung oder Gerätenummer.")
      }
      if exercise.equipment.first == .barbell {
        Section("Stange") {
          Picker("Stange", selection: barBinding) {
            Text("Standard (\(GermanFormat.number(gym.barKg)) kg)").tag(0.0)
            ForEach([20.0, 15, 10, 25, 7.5], id: \.self) { Text("\(GermanFormat.number($0)) kg").tag($0) }
          }
        }
      }
    }
    .navigationTitle(exercise.name)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var restBinding: Binding<Int> {
    Binding(
      get: { model.settings.gym.restOverrides[exercise.id] ?? 0 },
      set: { model.settings.gym.restOverrides[exercise.id] = $0 == 0 ? nil : $0 })
  }

  private var noteBinding: Binding<String> {
    Binding(
      get: { model.settings.gym.notes[exercise.id] ?? "" },
      set: { text in
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.settings.gym.notes[exercise.id] = trimmed.isEmpty ? nil : text
      })
  }

  private var barBinding: Binding<Double> {
    Binding(
      get: { model.settings.gym.bars[exercise.id] ?? 0 },
      set: { model.settings.gym.bars[exercise.id] = $0 == 0 ? nil : $0 })
  }
}

/// Laufen, Rad, Schwimmen: Herzfrequenz für alle; Testwerte (FTP, CSS, Paces) nur im Saisonplan.
struct EnduranceSettingsView: View {
  let sport: TrainingSport
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    let season = settings.profile.mode == .season
    Form {
      if season {
        Section {
          switch sport {
          case .run:
            paceStepper("Schwellenpace", $settings.season.thresholdPaceSecondsPerKm)
            paceStepper("Marathonpace", $settings.season.marathonPaceSecondsPerKm)
            paceStepper("Renn-Laufpace", $settings.season.racePaceSecondsPerKm)
          case .bike:
            Stepper("FTP \(settings.season.ftpWatts) W", value: $settings.season.ftpWatts, in: 80...500)
          case .swim:
            Stepper(
              "CSS \(GermanFormat.minutesSeconds(settings.season.cssSecondsPer100m)) /100 m",
              value: $settings.season.cssSecondsPer100m, in: 60...240)
          default:
            EmptyView()
          }
        } header: {
          Text("Testwerte")
        } footer: {
          Text("Nach jedem Test aktualisieren – Watt- und Pace-Angaben im Plan und in der KI-Notiz rechnen sich daraus.")
        }
      }
      if sport == .run || sport == .bike {
        Section {
          HeartRateStepper(title: "HFmax", value: $settings.heartRate.maxHeartRate, range: 140...230)
          if sport == .run {
            HeartRateStepper(title: "Schwelle Laufen", value: $settings.heartRate.thresholdRun, range: 120...210)
          } else {
            HeartRateStepper(title: "Schwelle Rad", value: $settings.heartRate.thresholdBike, range: 120...210)
          }
        } header: {
          Text("Herzfrequenz")
        } footer: {
          Text(
            "Ohne eigene Werte nutzt die App die Laktatschwelle von Garmin und den höchsten bestätigten Puls aus "
              + "deinen Einheiten. Schwelle: 30 Minuten am Anschlag, Ø-HF der letzten 20 Minuten. HFmax gilt für "
              + "Laufen und Rad.")
        }
      }
      if sport == .swim {
        Section {
          if season {
            Toggle("Ausrüstung am Vorabend (18 Uhr)", isOn: $settings.reminders.equipment)
          }
        } header: {
          Text("Erinnerung")
        } footer: {
          Text(
            season
              ? "Am Abend vor dem Schwimmen: Badesachen, Brille, Schloss."
              : "Herzfrequenz am Handgelenk ist im Wasser ungenau – Schwimmen bewertet die App nach Dauer und Plan.")
        }
      }
    }
    .navigationTitle(sport.shortLabel)
  }

  private func paceStepper(_ title: String, _ value: Binding<Int>) -> some View {
    Stepper("\(title) \(GermanFormat.minutesSeconds(value.wrappedValue)) /km", value: value, in: 150...480)
  }
}

/// Eigener Pulswert; „automatisch“, solange keiner gesetzt ist.
struct HeartRateStepper: View {
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
