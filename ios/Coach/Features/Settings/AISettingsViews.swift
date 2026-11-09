import CoachCore
import SwiftUI

/// KI-Stufe und bevorzugter Anbieter; darunter Anbieter im Worker und das Nutzungsprotokoll.
struct AISettingsSection: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var settings = model.settings
    Section {
      Picker("KI nutzen", selection: $settings.ai.mode) {
        ForEach(AIMode.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      Text(settings.ai.mode.detail).font(.footnote).foregroundStyle(.secondary)
      if settings.ai.mode != .off {
        Picker("Anbieter", selection: $settings.ai.provider) {
          ForEach(AIProviderChoice.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Text(settings.ai.provider.detail).font(.footnote).foregroundStyle(.secondary)
      }
      NavigationLink("Anbieter und Nutzung") { AIUsageView() }
    } header: {
      Text("KI")
    } footer: {
      Text(
        "Empfehlungen, Ampel und Ziele kommen immer aus den Regeln der App; die KI formuliert und fasst nur "
          + "zusammen. Fällt sie aus oder ist sie aus, bleibt alles nutzbar – auch Importe und der Export."
      )
    }
  }
}

/// Eingerichtete Anbieter im Worker und internes Protokoll: Anfragen, Tokens, Listenpreis, Fehler.
struct AIUsageView: View {
  @Environment(AppModel.self) private var model
  @State private var days = 30
  @State private var providers: [ProviderStatus] = []
  @State private var providerError: String?

  struct ProviderStatus: Decodable, Identifiable {
    let id: String
    let label: String
    let enabled: Bool
    let model: String?
    let usesInputsForTraining: Bool
  }

  private struct Health: Decodable {
    let providerList: [ProviderStatus]?
  }

  var body: some View {
    let since = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    let summary = AIUsageLog.summary(model.settings.aiUsage, since: since)
    List {
      Section {
        if providers.isEmpty {
          Text(providerError ?? "Wird geladen …").foregroundStyle(.secondary)
        }
        ForEach(providers) { provider in
          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(provider.label)
              Spacer()
              Image(systemName: provider.enabled ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(provider.enabled ? .green : .secondary)
                .accessibilityLabel(provider.enabled ? "eingerichtet" : "nicht eingerichtet")
            }
            if let name = provider.model, provider.enabled {
              Text(name + (provider.usesInputsForTraining ? " · kostenloses Kontingent wertet Eingaben aus" : ""))
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Im Worker eingerichtet")
      } footer: {
        Text(
          "Anbieter und Modelle stellst du im Worker ein (docs/ki-modelle.md). Fällt einer aus, nimmt der Worker "
            + "den nächsten.")
      }

      Section {
        Picker("Zeitraum", selection: $days) {
          Text("7 Tage").tag(7)
          Text("30 Tage").tag(30)
          Text("180 Tage").tag(180)
        }
        .pickerStyle(.segmented)
        LabeledContent("Anfragen", value: "\(summary.requests)")
        LabeledContent("davon automatisch", value: "\(summary.automatic)")
        LabeledContent("fehlgeschlagen", value: "\(summary.failures)")
        LabeledContent("Listenpreis", value: Self.dollars(summary.listPriceUsd))
      } header: {
        Text("Nutzung")
      } footer: {
        Text(
          "Listenpreis = was die Anfragen bei bezahlter Nutzung kosten würden. In den kostenlosen Kontingenten "
            + "(Gemini, Cerebras, Groq, Mistral, Workers AI bis 10.000 Neurons am Tag) und auf dem eigenen Server "
            + "zahlst du nichts je "
            + "Anfrage. Protokolliert werden nur Aufgabe, Anbieter, Modell, Tokens und Dauer – keine Inhalte."
        )
      }

      if !summary.lines.isEmpty {
        Section("Je Anbieter und Modell") {
          ForEach(summary.lines) { line in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(AIUsageLog.providerLabel(line.provider)) · \(line.model)").lineLimit(2)
              Text(
                "\(line.requests) Anfragen · \(line.failures) Fehler · "
                  + "\(line.inputTokens + line.outputTokens) Tokens · "
                  + "Ø \(GermanFormat.decimal(line.averageSeconds)) s · \(Self.dollars(line.listPriceUsd))"
              )
              .font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Section("Je Aufgabe") {
          ForEach(summary.byTask, id: \.task) { item in
            LabeledContent(Self.taskLabel(item.task), value: "\(item.count)")
          }
        }
      }

      let failures = model.settings.aiUsage.filter { !$0.ok && $0.date >= since }.prefix(5)
      if !failures.isEmpty {
        Section("Letzte Fehler") {
          ForEach(Array(failures.enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 2) {
              Text("\(Self.taskLabel(entry.task)) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
              Text(entry.error ?? "unbekannt").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("KI-Anbieter und Nutzung")
    .task { await loadProviders() }
  }

  private func loadProviders() async {
    do {
      let data = try await model.ai.send(path: "v1/health", method: "GET")
      providers = try JSONDecoder().decode(Health.self, from: data).providerList ?? []
      if providers.isEmpty { providerError = "Der Worker meldet keine Anbieterliste (ältere Version)." }
    } catch {
      providerError = error.localizedDescription
    }
  }

  static func dollars(_ value: Double) -> String {
    value < 0.01 && value > 0 ? "< 0,01 $" : "\(GermanFormat.number(value)) $"
  }

  static func taskLabel(_ task: String) -> String {
    switch task {
    case "daily_note", "personal_note": "Tagesnotiz"
    case "meal_analyze": "Mahlzeit auswerten"
    case "nutrition_label": "Etikett lesen"
    case "nutrition_review": "Ernährung auswerten"
    case "gym_hints": "Gym-Tipps"
    case "gym_plan": "Trainingsplan"
    case "coach_chat": "Chat"
    case "meal_now": "Was jetzt?"
    case "weekly_recipes": "Rezeptideen"
    case "cook_plan": "Gemeinsam kochen"
    case "ai_insights": "KI-Analyse"
    case "ping": "Verbindungstest"
    default: task
    }
  }
}
