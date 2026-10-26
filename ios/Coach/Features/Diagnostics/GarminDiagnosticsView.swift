import CoachCore
import SwiftData
import SwiftUI

/// Zeigt, was Garmin tatsächlich liefert: Fehler des letzten Abrufs, befüllte Tageswerte und die
/// Feldnamen jeder Rohantwort. Damit lässt sich die Zuordnung an echte Daten anpassen.
struct GarminDiagnosticsView: View {
  @Environment(AppModel.self) private var model
  @Query(sort: \RawResponseRecord.endpoint) private var responses: [RawResponseRecord]
  @Query(sort: \DailyMetricsRecord.dayKey, order: .reverse) private var days: [DailyMetricsRecord]

  var body: some View {
    List {
      if let report = model.lastReport {
        Section("Letzter Abruf") {
          Text(report.summary)
          ForEach(report.errors, id: \.self) { error in
            Text(error).font(.footnote).foregroundStyle(.orange)
          }
        }
      }

      if let latest = days.first?.metrics {
        Section("Befüllte Werte (\(latest.day.iso))") {
          let present = latest.presentFields
          Text(present.isEmpty ? "keine" : present.joined(separator: ", "))
        }
      }

      Section("Rohantworten") {
        if responses.isEmpty {
          Text("Noch kein Abruf.").foregroundStyle(.secondary)
        }
        ForEach(responses) { response in
          NavigationLink {
            RawResponseDetail(record: response)
          } label: {
            VStack(alignment: .leading) {
              Text(response.endpoint).font(.footnote.monospaced())
              Text("\(response.body.count) Bytes · \(response.fetchedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
    .navigationTitle("Garmin-Diagnose")
  }
}

private struct RawResponseDetail: View {
  let record: RawResponseRecord

  private var keyPaths: [String] {
    (try? JSONValue(data: record.body))?.keyPaths(limit: 300) ?? []
  }

  var body: some View {
    List {
      Section("Felder (ohne Werte)") {
        if keyPaths.isEmpty {
          Text("Leere oder keine JSON-Antwort").foregroundStyle(.secondary)
        }
        ForEach(keyPaths, id: \.self) { path in
          Text(path).font(.footnote.monospaced())
        }
      }
    }
    .navigationTitle(record.endpoint)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ShareLink(item: keyPaths.joined(separator: "\n")) {
        Label("Feldliste teilen", systemImage: "square.and.arrow.up")
      }
    }
  }
}
