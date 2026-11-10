import CoachCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Datensicherung: automatisch in einen Ordner, als Datei teilen, Sicherung einspielen.
struct BackupView: View {
  @Environment(\.modelContext) private var context
  @State private var pickerMode: PickerMode?
  @State private var sharedFile: URL?
  @State private var pending: AppBackup?
  @State private var message: String?
  @State private var restored: BackupService.RestoreResult?
  @State private var refresh = 0

  enum PickerMode {
    case folder, file
  }

  var body: some View {
    let defaults = UserDefaults.standard
    let folder = BackupService.folder()
    let last = defaults.object(forKey: BackupService.lastAutoKey) as? Date
    let error = defaults.string(forKey: BackupService.lastErrorKey)
    Form {
      Section {
        if let folder {
          LabeledContent("Ordner", value: folder.lastPathComponent)
          LabeledContent("Letzte Sicherung", value: last.map(Self.format) ?? "noch keine")
          if let error {
            Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
          }
          Button("Jetzt sichern", systemImage: "arrow.clockwise") {
            let ok = BackupService.backupToFolder(context: context, force: true)
            message = ok ? "Gesichert in „\(folder.lastPathComponent)“." : "Sichern hat nicht geklappt."
            refresh += 1
          }
          Button("Anderen Ordner wählen", systemImage: "folder") { pickerMode = .folder }
          Button("Automatische Sicherung beenden", role: .destructive) {
            BackupService.clearFolder()
            refresh += 1
          }
        } else {
          Button("Ordner wählen", systemImage: "folder.badge.plus") { pickerMode = .folder }
        }
      } header: {
        Text("Automatisch")
      } footer: {
        Text(
          "Einmal am Tag, wenn du die App verlässt, sichert AIronLudi in den Ordner – am besten in iCloud Drive "
            + "oder einen anderen Cloud-Ordner. Die Datei liegt außerhalb der App und bleibt auch erhalten, wenn "
            + "AIronLudi gelöscht wird. Die vorherige Sicherung bleibt als „…-vorher.json“ liegen."
        )
      }

      Section {
        if let sharedFile {
          ShareLink(item: sharedFile) {
            Label("Sicherung teilen oder in „Dateien“ sichern", systemImage: "square.and.arrow.up")
          }
        } else {
          Button("Sicherung erstellen", systemImage: "doc.badge.plus") {
            do {
              sharedFile = try BackupService.temporaryFile(context: context)
            } catch {
              message = "Sicherung konnte nicht erstellt werden: \(error.localizedDescription)"
            }
          }
        }
      } header: {
        Text("Von Hand")
      }

      Section {
        Button("Sicherung einspielen", systemImage: "square.and.arrow.down") { pickerMode = .file }
      } header: {
        Text("Einspielen")
      } footer: {
        Text(
          "Führt zusammen: Vorhandene Krafteinheiten und Mahlzeiten bleiben, fehlende kommen dazu. Die "
            + "Einstellungen werden durch die der Sicherung ersetzt. Nicht enthalten sind Zugangsdaten (Garmin, "
            + "App-Token) – die gibst du nach einer Neuinstallation neu ein. Garmin- und Health-Werte kommen beim "
            + "nächsten Abruf von selbst wieder."
        )
      }
    }
    .id(refresh)
    .navigationTitle("Datensicherung")
    .fileImporter(
      isPresented: Binding(get: { pickerMode != nil }, set: { if !$0 { pickerMode = nil } }),
      allowedContentTypes: pickerMode == .folder ? [.folder] : [.json]
    ) { result in
      let mode = pickerMode
      pickerMode = nil
      handle(result, mode: mode)
    }
    .confirmationDialog(
      "Sicherung einspielen?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
      titleVisibility: .visible
    ) {
      Button("Einspielen") {
        guard let backup = pending else { return }
        pending = nil
        do {
          restored = try BackupService.restore(backup, context: context)
        } catch {
          message = "Einspielen hat nicht geklappt: \(error.localizedDescription)"
        }
      }
      Button("Abbrechen", role: .cancel) { pending = nil }
    } message: {
      if let pending {
        Text("Sicherung vom \(Self.format(pending.createdAt)): \(pending.summary).")
      }
    }
    .alert(
      "Sicherung eingespielt", isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })
    ) {
      Button("App schließen") { exit(0) }
    } message: {
      Text(
        (restored?.text ?? "")
          + " Damit die Einstellungen gelten, schließt sich AIronLudi jetzt. Öffne die App danach einfach neu."
      )
    }
    .alert(
      "Datensicherung", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    ) {
      Button("OK") { message = nil }
    } message: {
      Text(message ?? "")
    }
  }

  private func handle(_ result: Result<URL, any Error>, mode: PickerMode?) {
    switch result {
    case .failure(let error):
      message = error.localizedDescription
    case .success(let url):
      switch mode {
      case .folder:
        do {
          try BackupService.setFolder(url)
          let ok = BackupService.backupToFolder(context: context, force: true)
          message =
            ok
            ? "Ordner „\(url.lastPathComponent)“ gewählt und erste Sicherung angelegt."
            : "Ordner gewählt, die erste Sicherung hat aber nicht geklappt."
        } catch {
          message = "Ordner konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
        refresh += 1
      case .file:
        do {
          pending = try BackupService.read(url)
        } catch {
          message = error.localizedDescription
        }
      case nil:
        break
      }
    }
  }

  static func format(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
  }
}
