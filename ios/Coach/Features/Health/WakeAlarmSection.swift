import CoachCore
import SwiftUI

/// Wecker zur Aufstehzeit stellen: Weckzeit aus dem Schlaf-Coach oder „jetzt ins Bett“ plus Schlafbedarf.
struct WakeAlarmSection: View {
  /// Weckzeit laut Schlaf-Coach.
  let wake: WakePlan.Time
  /// Schlafbedarf heute Nacht in Minuten (für „jetzt ins Bett“).
  let tonightMinutes: Int
  @Environment(AppModel.self) private var model
  @State private var alarms = WakeAlarmService()
  @State private var repeats = WakePlan.Repeat.once
  @State private var busy = false
  @State private var confirmation: String?

  private var sleepNow: WakePlan.Time {
    let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
    return WakePlan.wakeIfSleepingNow(
      nowMinutes: (now.hour ?? 0) * 60 + (now.minute ?? 0), sleepMinutes: tonightMinutes)
  }

  var body: some View {
    Section {
      if let stored = alarms.stored {
        let next = WakePlan.nextDate(stored.time, after: .now)
        LabeledContent("Wecker gestellt") {
          Text(
            stored.repeats == .once
              ? "\(next.map { WakePlan.dayLabel($0, now: .now) } ?? "") \(stored.time.text) Uhr"
              : "\(stored.time.text) Uhr · \(stored.repeats.label)")
        }
        Button("Wecker löschen", systemImage: "alarm.waves.left.and.right", role: .destructive) {
          alarms.cancel()
          confirmation = nil
        }
      }
      if alarms.isSupported {
        Picker("Wiederholen", selection: $repeats) {
          ForEach(WakePlan.Repeat.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Button {
          set(wake)
        } label: {
          Label("Wecker für \(wake.text) Uhr stellen", systemImage: "alarm.fill")
        }
        .disabled(busy)
        Button {
          set(sleepNow, repeats: .once)
        } label: {
          Label(
            "Jetzt ins Bett: Wecker \(sleepNow.text) Uhr (\(GermanFormat.decimal(Double(tonightMinutes) / 60)) h)",
            systemImage: "bed.double.fill")
        }
        .disabled(busy)
      } else {
        Text(
          "Einen Wecker kann die App erst ab iOS 26 stellen. Stelle ihn in der Uhr-App auf \(wake.text) Uhr – oder "
            + "nutze die Schlafenszeit-Erinnerung oben."
        )
        .foregroundStyle(.secondary)
      }
      if let confirmation {
        Label(confirmation, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      }
      if let error = alarms.lastError {
        Text(error).font(.footnote).foregroundStyle(.red)
      }
    } header: {
      Text("Wecker")
    } footer: {
      Text(
        alarms.state == .denied
          ? "Wecker sind für IronLudi nicht erlaubt (iOS-Einstellungen › IronLudi)."
          : "Ein echter iOS-Wecker (klingelt auch lautlos und im Fokus). iOS fragt beim ersten Mal nach Erlaubnis; "
            + "ein neuer Wecker ersetzt den alten.")
    }
    .onAppear { alarms.refreshState() }
    .onChange(of: alarms.stored, initial: true) { _, stored in syncSleepCoach(stored) }
  }

  /// Der gestellte Wecker bestimmt die empfohlene Schlafenszeit.
  private func syncSleepCoach(_ stored: WakeAlarmService.Stored?) {
    let alarm = stored.map { value in
      SleepAlarm(
        minutes: value.time.minutes,
        onlyDay: value.repeats == .once
          ? WakePlan.nextDate(value.time, after: .now).map { CalendarDay(date: $0) } : nil,
        weekdaysOnly: value.repeats == .weekdays)
    }
    if model.settings.sleep.alarm != alarm { model.settings.sleep.alarm = alarm }
  }

  private func set(_ time: WakePlan.Time, repeats override: WakePlan.Repeat? = nil) {
    busy = true
    confirmation = nil
    let mode = override ?? repeats
    Task {
      if await alarms.schedule(time, repeats: mode) {
        confirmation = "Wecker für \(time.text) Uhr gestellt."
      }
      busy = false
    }
  }
}
