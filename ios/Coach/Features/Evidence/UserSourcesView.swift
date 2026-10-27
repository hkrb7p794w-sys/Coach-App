import CoachCore
import SwiftUI

/// Eigene wissenschaftliche Quellen: Kurzbeleg, DOI/PMID/Link, Kernaussage und Themen. Die KI bekommt sie bei
/// passenden Aufgaben als zusätzliche belegte Regeln; die Entscheidungen der App ändern sie nicht.
struct UserSourcesView: View {
  @Environment(AppModel.self) private var model
  @State private var editing: UserSource?

  var body: some View {
    List {
      Section {
        if model.settings.userSources.isEmpty {
          Text("Noch keine eigenen Quellen.").foregroundStyle(.secondary)
        }
        ForEach(model.settings.userSources) { source in
          Button {
            editing = source
          } label: {
            UserSourceRow(source: source)
          }
          .buttonStyle(.plain)
        }
        .onDelete { model.settings.userSources.remove(atOffsets: $0) }
        Button("Quelle hinzufügen", systemImage: "plus") {
          editing = UserSource(citation: "", statement: "")
        }
      } footer: {
        Text(
          "Gemini Flash bekommt passende Quellen bei Coach-Notiz, Gym-Tipps, KI-Trainingsplan, Ernährungsauswertung, "
            + "Rezeptideen und im Chat zusätzlich zu den Regeln der App (höchstens \(UserSources.maxPerRequest) je "
            + "Anfrage) und darf sie zitieren. Tagesampel, Ziele, Gewichtssteigerung und Schutzgrenzen bleiben bei "
            + "den geprüften Regeln der App. Am besten Übersichtsarbeiten oder Meta-Analysen eintragen.")
      }
    }
    .navigationTitle("Eigene Quellen")
    .toolbar { EditButton() }
    .sheet(item: $editing) { source in
      UserSourceEditor(source: source) { saved in
        if let index = model.settings.userSources.firstIndex(where: { $0.id == saved.id }) {
          model.settings.userSources[index] = saved
        } else {
          model.settings.userSources.append(saved)
        }
        editing = nil
      }
    }
  }
}

struct UserSourceRow: View {
  let source: UserSource

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(source.citation).font(.subheadline.bold())
        Spacer()
        Text("Eigene Quelle").font(.caption2.weight(.semibold)).foregroundStyle(.purple)
      }
      Text(source.statement).font(.footnote)
      Text(source.topics.sorted { $0.rawValue < $1.rawValue }.map(\.label).joined(separator: " · "))
        .font(.caption2)
        .foregroundStyle(.secondary)
      if let url = source.url {
        Link(source.reference, destination: url).font(.caption)
      }
    }
  }
}

private struct UserSourceEditor: View {
  @State var source: UserSource
  let save: (UserSource) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Kurzbeleg, z. B. Schoenfeld et al. 2017", text: $source.citation)
          TextField("DOI, PMID oder Link", text: $source.reference)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Quelle")
        }
        Section {
          TextField("Was sagt die Studie?", text: $source.statement, axis: .vertical)
            .lineLimit(3...8)
        } header: {
          Text("Kernaussage")
        } footer: {
          Text(
            "In eigenen Worten und so konkret wie möglich, höchstens \(UserSources.maxStatementLength) Zeichen. "
              + "Diese Aussage bekommt die KI.")
        }
        Section("Themen") {
          ForEach(UserSource.Topic.allCases) { topic in
            Toggle(
              topic.label,
              isOn: Binding(
                get: { source.topics.contains(topic) },
                set: { isOn in
                  if isOn { source.topics.insert(topic) } else { source.topics.remove(topic) }
                }))
          }
        }
      }
      .navigationTitle("Eigene Quelle")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") {
            source.statement = String(source.statement.prefix(UserSources.maxStatementLength))
            save(source)
          }
          .disabled(!source.isValid || source.topics.isEmpty)
        }
      }
    }
  }
}
