import CoachCore
import SwiftData
import SwiftUI
import UIKit

/// Prompt-Bibliothek für externe KI: fertige Vorlagen und eigene Prompts. Jeder Prompt wird mit Zeitraum, Ziel und
/// den passenden Daten ergänzt und lässt sich kopieren oder als Datei teilen.
struct PromptLibraryView: View {
  @Environment(AppModel.self) private var model
  @State private var editing: PromptTemplate?

  var body: some View {
    List {
      Section {
        ForEach(PromptLibrary.builtIn) { template in
          NavigationLink(template.title) { PromptDetailView(template: template) }
        }
      } header: {
        Text("Vorlagen")
      } footer: {
        Text("Jede Vorlage hängt die passenden Daten und Arbeitsregeln an: nur aus den Daten, Lücken benennen.")
      }
      Section {
        ForEach(model.settings.customPrompts) { template in
          NavigationLink(template.title) { PromptDetailView(template: template) }
        }
        .onDelete { offsets in model.settings.customPrompts.remove(atOffsets: offsets) }
        Button("Neuer Prompt", systemImage: "plus") {
          editing = PromptTemplate(title: "", text: "", categories: [.gym, .endurance], days: 30)
        }
      } header: {
        Text("Eigene Prompts")
      }
    }
    .navigationTitle("Prompt-Bibliothek")
    .sheet(item: $editing) { template in PromptEditor(template: template) }
  }
}

/// Ein Prompt mit Vorschau, Zeitraum, Datenauswahl und Format.
struct PromptDetailView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \DailyMetricsRecord.dayKey) private var days: [DailyMetricsRecord]
  @Query(sort: \ActivityRecord.startLocal) private var activities: [ActivityRecord]
  @Query(sort: \GymSessionRecord.start) private var gymSessions: [GymSessionRecord]
  @Query(sort: \MealRecord.createdAt) private var meals: [MealRecord]
  let template: PromptTemplate
  @State private var range = ExportRange()
  @State private var categories: Set<ExportCategory> = []
  @State private var format = ExportFormat.markdown
  @State private var copied = false
  @State private var file: URL?
  @State private var editing: PromptTemplate?

  private var current: PromptTemplate {
    model.settings.customPrompts.first { $0.id == template.id } ?? template
  }

  var body: some View {
    let input = ExportInput.make(
      model: model, days: days, activities: activities, gymSessions: gymSessions, meals: meals)
    let counts = DataExport.counts(input, from: range.start, to: range.end)
    let prompt = selected
    Form {
      Section("Prompt") {
        Text(PromptLibrary.filled(prompt, profile: input.profile, from: range.start, to: range.end))
          .textSelection(.enabled)
      }
      ExportRangeSection(range: $range)
      Section {
        ForEach(ExportCategory.allCases, id: \.self) { category in
          Toggle(
            "\(category.label) (\(counts[category] ?? 0))",
            isOn: Binding(
              get: { categories.contains(category) },
              set: { on in
                if on { categories.insert(category) } else { categories.remove(category) }
              }))
        }
        Picker("Format der Daten", selection: $format) {
          Text("Markdown").tag(ExportFormat.markdown)
          Text("JSON").tag(ExportFormat.json)
        }
      } header: {
        Text("Angehängte Daten")
      } footer: {
        let empty = prompt.categories.filter { (counts[$0] ?? 0) == 0 }.map(\.label)
        if !empty.isEmpty {
          Text("Ohne Daten im Zeitraum: \(empty.joined(separator: ", ")). Die KI soll das als fehlend behandeln.")
        }
      }
      Section {
        Button(copied ? "Kopiert" : "Prompt mit Daten kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") {
          PrivateClipboard.copy(composed(prompt, input: input))
          copied = true
        }
        Button("Als Datei vorbereiten", systemImage: "doc") {
          file =
            ExportInput.write([
              DataExport.File(
                name: "IronLudi-Prompt-\(prompt.id.prefix(12)).md", content: composed(prompt, input: input))
            ]).first
        }
        if let file {
          ShareLink(item: file) { Label("Datei teilen", systemImage: "square.and.arrow.up") }
        }
      } footer: {
        Text("In ChatGPT, Gemini, Claude oder ein lokales Modell einfügen. Enthält Gesundheitsdaten.")
      }
      Section {
        if current.isCustom {
          Button("Bearbeiten", systemImage: "pencil") { editing = current }
        } else {
          Button("Als eigenen Prompt speichern", systemImage: "square.and.pencil") {
            editing = PromptTemplate(
              title: "\(current.title) (eigen)", text: current.text, categories: prompt.categories, days: current.days)
          }
        }
      }
    }
    .navigationTitle(current.title)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if categories.isEmpty { categories = Set(current.categories) }
      let preset = CoachExport.presets.map(\.days).contains(current.days) ? current.days : nil
      if preset == nil {
        range.presetDays = nil
        range.from = Calendar.current.date(byAdding: .day, value: -(current.days - 1), to: .now) ?? .now
      } else {
        range.presetDays = preset
      }
    }
    .onChange(of: range) { reset() }
    .onChange(of: categories) { reset() }
    .onChange(of: format) { reset() }
    .sheet(item: $editing) { template in PromptEditor(template: template) }
  }

  /// Der Prompt mit den gewählten Daten.
  private var selected: PromptTemplate {
    var prompt = current
    prompt.categories = ExportCategory.allCases.filter(categories.contains)
    return prompt
  }

  private func reset() {
    copied = false
    file = nil
  }

  private func composed(_ prompt: PromptTemplate, input: CoachExport.Input) -> String {
    PromptLibrary.compose(prompt, input: input, from: range.start, to: range.end, format: format)
  }
}

/// Eigenen Prompt anlegen oder ändern.
struct PromptEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var template: PromptTemplate

  var body: some View {
    NavigationStack {
      Form {
        Section("Titel") {
          TextField("z. B. Laufanalyse vor dem Wettkampf", text: $template.title)
        }
        Section {
          TextEditor(text: $template.text).frame(minHeight: 160)
        } header: {
          Text("Prompt")
        } footer: {
          Text("Platzhalter: {zeitraum}, {tage}, {ziel}, {sportarten} – die App setzt sie ein.")
        }
        Section("Daten") {
          ForEach(ExportCategory.allCases, id: \.self) { category in
            Toggle(
              category.label,
              isOn: Binding(
                get: { template.categories.contains(category) },
                set: { on in
                  template.categories.removeAll { $0 == category }
                  if on { template.categories.append(category) }
                }))
          }
          Stepper("Zeitraum: \(template.days) Tage", value: $template.days, in: 7...365, step: 7)
        }
      }
      .navigationTitle(template.title.isEmpty ? "Neuer Prompt" : template.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") {
            save()
            dismiss()
          }
          .disabled(template.title.trimmingCharacters(in: .whitespaces).isEmpty || template.text.isEmpty)
        }
      }
    }
  }

  private func save() {
    var saved = template
    saved.isCustom = true
    saved.categories = ExportCategory.allCases.filter(template.categories.contains)
    if let index = model.settings.customPrompts.firstIndex(where: { $0.id == saved.id }) {
      model.settings.customPrompts[index] = saved
    } else {
      model.settings.customPrompts.append(saved)
    }
  }
}
