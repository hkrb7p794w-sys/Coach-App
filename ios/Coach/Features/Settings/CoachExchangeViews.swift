import CoachCore
import SwiftData
import SwiftUI
import UIKit

/// Manueller KI-Coach, Teil 1: alle Daten eines Zeitraums als eine Datei für ChatGPT, Gemini oder Claude.
struct CoachExportView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start) private var gymSessions: [GymSessionRecord]
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @State private var presetDays: Int? = 30
  @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
  @State private var to = Date.now
  @State private var file: URL?
  @State private var copied = false

  private var range: (start: CalendarDay, end: CalendarDay) {
    let today = CalendarDay(date: .now)
    if let presetDays { return (today.adding(days: -(presetDays - 1)), today) }
    let start = CalendarDay(date: min(from, to))
    let end = CalendarDay(date: max(from, to))
    return (start, end)
  }

  var body: some View {
    Form {
      Section {
        Picker("Zeitraum", selection: $presetDays) {
          ForEach(CoachExport.presets) { Text($0.label).tag(Optional($0.days)) }
          Text("Eigener").tag(Int?.none)
        }
        if presetDays == nil {
          DatePicker("Von", selection: $from, in: ...Date.now, displayedComponents: .date)
          DatePicker("Bis", selection: $to, in: ...Date.now, displayedComponents: .date)
        }
      } footer: {
        Text("Zeitraum: \(range.start.iso) bis \(range.end.iso)")
      }
      Section {
        Button("Export erstellen", systemImage: "doc.badge.arrow.up") { makeFile() }
        if let file {
          ShareLink(item: file) {
            Label("Datei teilen (z. B. an ChatGPT, Gemini, Claude)", systemImage: "square.and.arrow.up")
          }
          Button(copied ? "Kopiert" : "Als Text kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") {
            UIPasteboard.general.string = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            copied = true
          }
        }
      } footer: {
        Text(
          "Eine Markdown-Datei mit Profil, Plan, Routinen, Tageswerten, Aktivitäten, Krafteinheiten mit allen "
            + "Sätzen, Ernährung und Gewicht. Oben steht eine Anleitung für die KI mit dem Antwortformat – ihre "
            + "Antwort fügst du unter „KI-Antwort importieren“ ein. Die Datei enthält Gesundheitsdaten; teile sie "
            + "nur mit Diensten, denen du sie anvertrauen willst.")
      }
    }
    .navigationTitle("Daten für KI exportieren")
    .onChange(of: presetDays) { file = nil }
    .onChange(of: from) { file = nil }
    .onChange(of: to) { file = nil }
  }

  private func makeFile() {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    let input = CoachExport.Input(
      profile: settings.profile, schedule: settings.schedule(inWeekOf: today), routines: settings.gym.routines,
      custom: settings.gym.customExercises, equipment: settings.gym.equipment, metrics: days.compactMap(\.metrics),
      activities: activities.compactMap(\.activity), gym: gymSessions.compactMap(\.session),
      meals: meals.compactMap { record in
        CalendarDay(iso: record.dayKey).map {
          CoachExport.Meal(day: $0, category: record.category.label, title: record.title, items: record.items)
        }
      }, weights: model.allWeights)
    let text = CoachExport.markdown(input, from: range.start, to: range.end)
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("IronLudi-Export-\(range.start.iso)-bis-\(range.end.iso).md")
    do {
      try text.write(to: url, atomically: true, encoding: .utf8)
      file = url
      copied = false
    } catch {
      file = nil
    }
  }
}

/// Manueller KI-Coach, Teil 2: die Antwort der KI einfügen, von den Regeln prüfen lassen und übernehmen.
struct CoachImportView: View {
  @Environment(AppModel.self) private var model
  @State private var text = ""
  @State private var preview: CoachImport.Preview?
  @State private var selection = CoachImport.Selection()
  @State private var error: String?
  @State private var applied = false

  var body: some View {
    Form {
      Section {
        TextEditor(text: $text)
          .frame(minHeight: 160)
          .font(.footnote.monospaced())
          .onChange(of: text) {
            preview = nil
            error = nil
            applied = false
          }
        Button("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard") {
          text = UIPasteboard.general.string ?? ""
        }
        Button("Prüfen", systemImage: "checkmark.shield") { check() }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if let error { Text(error).foregroundStyle(.red).font(.footnote) }
      } header: {
        Text("Antwort der KI")
      } footer: {
        Text("Die ganze Antwort einfügen – die App sucht den Block ```ironludi … ``` darin.")
      }
      if let preview {
        previewSections(preview)
      }
    }
    .navigationTitle("KI-Antwort importieren")
  }

  @ViewBuilder private func previewSections(_ preview: CoachImport.Preview) -> some View {
    let settings = model.settings
    if !preview.routines.isEmpty {
      Section {
        Toggle("Alle bisherigen Routinen löschen", isOn: $selection.replaceAllRoutines)
        ForEach(preview.routines) { routine in
          VStack(alignment: .leading, spacing: 6) {
            Text(routine.name).font(.headline)
            ForEach(routine.items) { item in
              Text(itemText(item)).font(.caption).foregroundStyle(.secondary)
            }
            let exists = settings.gym.routines.contains { $0.name == routine.name }
            Picker("Übernehmen", selection: routineBinding(routine)) {
              ForEach(CoachImport.RoutineChoice.allCases) { choice in
                if choice != .replace || exists || selection.replaceAllRoutines {
                  Text(choice.label).tag(choice)
                }
              }
            }
            .pickerStyle(.menu)
            if exists, !selection.replaceAllRoutines {
              Text(
                selection.choice(for: routine) == .replace
                  ? "Ersetzt deine Routine „\(routine.name)“."
                  : "Deine Routine „\(routine.name)“ bleibt erhalten."
              )
              .font(.caption2)
              .foregroundStyle(.orange)
            }
          }
        }
      } header: {
        Text("Routinen")
      } footer: {
        Text(
          selection.replaceAllRoutines
            ? "Achtung: Deine bisherigen Routinen werden gelöscht; übrig bleiben nur die übernommenen."
            : "Für jede Routine einzeln: bestehende gleichnamige ersetzen, zusätzlich anlegen oder weglassen.")
      }
    }
    if let schedule = preview.schedule {
      let current = currentSchedule
      Section {
        Toggle("Wochenplan übernehmen", isOn: $selection.schedule)
        if selection.schedule {
          Picker("Gilt für", selection: $selection.scheduleScope) {
            Text("Dauerhaft").tag(CoachImport.ScheduleScope.permanent)
            Text("Nur nächste Woche").tag(CoachImport.ScheduleScope.nextWeek)
          }
          ForEach(Weekday.allCases) { weekday in
            let new = schedule.slots(on: weekday)
            let old = current.slots(on: weekday)
            if new != old {
              Toggle(isOn: dayBinding(weekday)) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(weekday.long).font(.subheadline.weight(.semibold))
                  Text("bisher: \(slotText(old))").font(.caption).foregroundStyle(.secondary)
                  Text("neu: \(slotText(new))").font(.caption)
                }
              }
            }
          }
        }
      } header: {
        Text("Wochenplan")
      } footer: {
        Text("Nur die Tage mit Änderungen; abgewählte Tage bleiben wie bisher.")
      }
    }
    if !preview.notes.isEmpty {
      Section {
        ForEach(Array(preview.notes.enumerated()), id: \.offset) { index, note in
          Toggle(isOn: noteBinding(index)) { Text(note).font(.subheadline) }
        }
      } header: {
        Text("Hinweise der KI")
      } footer: {
        Text("Ausgewählte Hinweise ersetzen die Hinweise des letzten Imports.")
      }
    }
    if !preview.corrections.isEmpty || !preview.ruleNotes.isEmpty {
      Section("Geprüft von den Regeln") {
        ForEach(preview.corrections, id: \.self) { Label($0, systemImage: "xmark.circle").font(.footnote) }
        ForEach(preview.ruleNotes, id: \.self) { Label($0, systemImage: "info.circle").font(.footnote) }
      }
    }
    Section {
      if applied {
        Label("Übernommen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
      } else {
        Button("Auswahl übernehmen", systemImage: "square.and.arrow.down") { apply(preview) }
          .font(.headline)
          .disabled(!CoachImport.hasChanges(preview, selection: selection))
      }
    } footer: {
      Text(
        preview.isEmpty
          ? "Im Block war nichts, was die App übernehmen kann."
          : "Routinen und Wochenplan lassen sich danach wie gewohnt bearbeiten; die Hinweise stehen unter „Heute“ › "
            + "„Diese Woche, Ziele und Verlauf“.")
    }
  }

  /// Plan, mit dem der Vorschlag verglichen wird (dauerhaft bzw. nächste Woche).
  private var currentSchedule: WeekSchedule {
    let settings = model.settings
    switch selection.scheduleScope {
    case .permanent: return settings.profile.schedule
    case .nextWeek: return settings.schedule(inWeekOf: nextMonday)
    }
  }

  private var nextMonday: CalendarDay {
    PlanAdjustments.monday(of: CalendarDay(date: .now)).adding(days: 7)
  }

  private func slotText(_ slots: [SessionSlot]) -> String {
    slots.isEmpty ? "frei" : slots.map(\.title).joined(separator: ", ")
  }

  private func routineBinding(_ routine: Routine) -> Binding<CoachImport.RoutineChoice> {
    Binding(
      get: { selection.choice(for: routine) },
      set: { selection.routines[routine.id] = $0 })
  }

  private func dayBinding(_ weekday: Weekday) -> Binding<Bool> {
    Binding(
      get: { selection.scheduleDays.contains(weekday) },
      set: { isOn in
        if isOn { selection.scheduleDays.insert(weekday) } else { selection.scheduleDays.remove(weekday) }
      })
  }

  private func noteBinding(_ index: Int) -> Binding<Bool> {
    Binding(
      get: { selection.notes.contains(index) },
      set: { isOn in
        if isOn { selection.notes.insert(index) } else { selection.notes.remove(index) }
      })
  }

  private func itemText(_ item: RoutineItem) -> String {
    var text = "\(item.name): \(item.sets) × \(item.lowerReps)–\(item.upperReps), Pause \(item.restSeconds) s"
    if let weight = item.weightKg { text += ", \(GermanFormat.number(weight)) kg" }
    return text
  }

  private func check() {
    let settings = model.settings
    do {
      let checked = try CoachImport.preview(
        text, profile: settings.profile, equipment: settings.gym.equipment, custom: settings.gym.customExercises)
      selection = CoachImport.Selection.defaults(
        for: checked, existing: settings.gym.routines,
        currentSchedule: checked.scheduleScope == .nextWeek
          ? settings.schedule(inWeekOf: nextMonday) : settings.profile.schedule)
      preview = checked
      applied = false
      error = nil
    } catch {
      preview = nil
      self.error = error.localizedDescription
    }
  }

  private func apply(_ preview: CoachImport.Preview) {
    let settings = model.settings
    if !preview.routines.isEmpty {
      settings.gym.routines = CoachImport.routines(preview, selection: selection, existing: settings.gym.routines)
    }
    if let schedule = CoachImport.schedule(preview, selection: selection, current: currentSchedule) {
      switch selection.scheduleScope {
      case .permanent:
        settings.profile.schedule = schedule
      case .nextWeek:
        settings.planAdjustments.setWeekPlan(schedule, base: settings.profile.schedule, inWeekOf: nextMonday)
      }
    }
    let notes = CoachImport.notes(preview, selection: selection)
    if !notes.isEmpty {
      settings.importedNotes = ImportedNotes(day: CalendarDay(date: .now), texts: notes)
    }
    applied = true
  }
}
