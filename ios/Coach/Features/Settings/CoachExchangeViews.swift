import CoachCore
import SwiftData
import SwiftUI
import UIKit

/// KI-Export: Zeitraum, Daten und Format wählen; als Datei teilen oder kopieren. Mit „Antwortformat beilegen“ ist es
/// Teil 1 des manuellen KI-Coachs (die Antwort kommt über „KI-Antwort importieren“ zurück).
struct CoachExportView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start) private var gymSessions: [GymSessionRecord]
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  @State private var range = ExportRange()
  @State private var categories = Set(ExportCategory.allCases)
  @State private var format = ExportFormat.markdown
  @State private var withImportFormat = true
  @State private var files: [URL] = []
  @State private var copied = false

  var body: some View {
    let input = ExportInput.make(
      model: model, days: days, activities: activities, gymSessions: gymSessions, meals: meals)
    let counts = DataExport.counts(input, from: range.start, to: range.end)
    Form {
      ExportRangeSection(range: $range)
      Section {
        ForEach(ExportCategory.allCases, id: \.self) { category in
          Toggle(
            isOn: Binding(
              get: { categories.contains(category) },
              set: { on in
                if on { categories.insert(category) } else { categories.remove(category) }
              })
          ) {
            VStack(alignment: .leading, spacing: 2) {
              Text(category.label)
              Text("\(counts[category] ?? 0) Einträge · \(category.detail)").font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Daten")
      } footer: {
        Text("Profil und Ziel sind immer dabei. Ohne Einträge im Zeitraum bleibt ein Bereich leer.")
      }
      Section {
        Picker("Format", selection: $format) {
          ForEach(ExportFormat.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if format == .markdown {
          Toggle("Antwortformat für den Import beilegen", isOn: $withImportFormat)
        }
      } footer: {
        Text(formatNote)
      }
      Section {
        Button("Export erstellen", systemImage: "doc.badge.arrow.up") { makeFiles(input) }
          .disabled(categories.isEmpty)
        if !files.isEmpty {
          ShareLink(items: files) {
            Label(
              files.count == 1 ? "Datei teilen" : "\(files.count) Dateien teilen", systemImage: "square.and.arrow.up")
          }
          if format != .csv {
            Button(copied ? "Kopiert" : "Als Text kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") {
              UIPasteboard.general.string = files.first.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
              copied = true
            }
          }
        }
      } footer: {
        Text(
          "Die Dateien enthalten Gesundheitsdaten. Teile sie nur mit Diensten, denen du sie anvertrauen willst – oder "
            + "nutze ein lokales Modell.")
      }
    }
    .navigationTitle("Daten für KI exportieren")
    .onChange(of: range) { files = [] }
    .onChange(of: categories) { files = [] }
    .onChange(of: format) { files = [] }
    .onChange(of: withImportFormat) { files = [] }
  }

  private var formatNote: String {
    switch format {
    case .markdown:
      "Lesbar für Menschen und jede KI. Mit Antwortformat schlägt die KI Planänderungen so vor, dass die App sie "
        + "prüfen und übernehmen kann."
    case .json: "Strukturiert mit festen Feldnamen; fehlende Werte sind null. Gut für längere Analysen."
    case .csv: "Eine Tabelle je Bereich – gut für Tabellenkalkulationen und Datenanalyse-Werkzeuge."
    }
  }

  private func makeFiles(_ input: CoachExport.Input) {
    let stem = "IronLudi-\(range.start.iso)-bis-\(range.end.iso)"
    let output: [DataExport.File]
    switch format {
    case .markdown:
      output = [
        DataExport.File(
          name: "\(stem).md",
          content: DataExport.markdown(
            input, from: range.start, to: range.end, categories: categories, withImportFormat: withImportFormat))
      ]
    case .json:
      output = [
        DataExport.File(
          name: "\(stem).json",
          content: DataExport.json(input, from: range.start, to: range.end, categories: categories))
      ]
    case .csv:
      output = DataExport.csv(input, from: range.start, to: range.end, categories: categories)
    }
    files = ExportInput.write(output)
    copied = false
  }
}

/// Zeitraum eines Exports: Vorgabe (7, 30, 90, 365 Tage) oder eigene Daten.
struct ExportRange: Equatable {
  var presetDays: Int? = 30
  var from = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
  var to = Date.now

  var start: CalendarDay {
    if let presetDays { return CalendarDay(date: .now).adding(days: -(presetDays - 1)) }
    return CalendarDay(date: min(from, to))
  }

  var end: CalendarDay {
    presetDays == nil ? CalendarDay(date: max(from, to)) : CalendarDay(date: .now)
  }
}

struct ExportRangeSection: View {
  @Binding var range: ExportRange

  var body: some View {
    Section {
      Picker("Zeitraum", selection: $range.presetDays) {
        ForEach(CoachExport.presets) { Text($0.label).tag(Optional($0.days)) }
        Text("Eigener").tag(Int?.none)
      }
      if range.presetDays == nil {
        DatePicker("Von", selection: $range.from, in: ...Date.now, displayedComponents: .date)
        DatePicker("Bis", selection: $range.to, in: ...Date.now, displayedComponents: .date)
      }
    } footer: {
      Text("Zeitraum: \(range.start.iso) bis \(range.end.iso)")
    }
  }
}

/// Daten der App für Export und Prompts.
enum ExportInput {
  static func make(
    model: AppModel, days: [DailyMetricsRecord], activities: [ActivityRecord], gymSessions: [GymSessionRecord],
    meals: [MealRecord]
  ) -> CoachExport.Input {
    let settings = model.settings
    let today = CalendarDay(date: .now)
    return CoachExport.Input(
      profile: settings.coachingProfile, schedule: settings.schedule(inWeekOf: today), routines: settings.gym.routines,
      custom: settings.gym.customExercises, equipment: settings.gym.equipment, metrics: days.compactMap(\.metrics),
      activities: activities.compactMap(\.activity), gym: gymSessions.compactMap(\.session),
      meals: meals.compactMap { record in
        CalendarDay(iso: record.dayKey).map {
          CoachExport.Meal(day: $0, category: record.category.label, title: record.title, items: record.items)
        }
      }, weights: model.allWeights, userSources: settings.userSources)
  }

  /// Schreibt die Dateien in einen eigenen temporären Ordner (alte Exporte werden ersetzt).
  static func write(_ files: [DataExport.File]) -> [URL] {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ki-export", isDirectory: true)
    try? FileManager.default.removeItem(at: folder)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return files.compactMap { file in
      let url = folder.appendingPathComponent(file.name)
      return (try? file.content.write(to: url, atomically: true, encoding: .utf8)) == nil ? nil : url
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
        Toggle("Alle bisherigen Trainingspläne löschen", isOn: $selection.replaceAllRoutines)
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
                  ? "Ersetzt deinen Trainingsplan „\(routine.name)“."
                  : "Dein Trainingsplan „\(routine.name)“ bleibt erhalten."
              )
              .font(.caption2)
              .foregroundStyle(.orange)
            }
          }
        }
      } header: {
        Text("Trainingspläne")
      } footer: {
        Text(
          selection.replaceAllRoutines
            ? "Achtung: Deine bisherigen Trainingspläne werden gelöscht; übrig bleiben nur die übernommenen."
            : "Für jeden Trainingsplan einzeln: bestehende gleichnamige ersetzen, zusätzlich anlegen oder weglassen.")
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
          : "Trainingspläne und Wochenplan lassen sich danach wie gewohnt bearbeiten; die Hinweise stehen unter "
            + "„Heute“ › „Diese Woche, Ziele und Verlauf“.")
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
