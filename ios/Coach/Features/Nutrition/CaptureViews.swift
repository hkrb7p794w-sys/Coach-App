import CoachCore
import PhotosUI
import SwiftUI
import UIKit
import Vision
import VisionKit

/// Ein Bildschirm für alles: Foto (Kamera oder Mediathek) und Beschreibung zusammen – „Foto + ohne Soße“ ist ein
/// Vorgang. „Sprechen“ diktiert auf Deutsch in das Textfeld (zum Korrigieren vor dem Analysieren). Darunter die
/// anderen Wege.
struct CaptureSheet: View {
  enum Other { case barcode, quick, manual }

  let analyze: (String, Data?) async -> Void
  let other: (Other) -> Void
  @State private var text = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var photo: Data?
  @State private var showsCamera = false
  @State private var dictation = Dictation()
  /// Text vor der laufenden Aufnahme; das Diktat wird angehängt.
  @State private var textBeforeDictation = ""
  @FocusState private var focused: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 12) {
            if CameraPicker.isAvailable {
              Button {
                showsCamera = true
              } label: {
                Label("Kamera", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 52)
              }
              .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
              Label("Foto", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
          }
          .listRowBackground(Color.clear)
          if let photo, let image = UIImage(data: photo) {
            HStack {
              Image(uiImage: image).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(
                RoundedRectangle(cornerRadius: 10))
              Text("Foto ausgewählt").foregroundStyle(.secondary)
              Spacer()
              Button("Entfernen", role: .destructive) {
                self.photo = nil
                photoItem = nil
              }
              .buttonStyle(.borderless)
            }
          }
        }
        Section {
          TextField(
            "z. B. 200 g Hähnchen, 1 EL Öl, 150 g Reis – oder „halbe Portion, ohne Soße“", text: $text,
            axis: .vertical
          )
          .lineLimit(2...8)
          .focused($focused)
          if Dictation.isSupported {
            Button {
              if !dictation.isRecording {
                focused = false
                textBeforeDictation = text.trimmingCharacters(in: .whitespaces)
              }
              Task { await dictation.toggle() }
            } label: {
              Label(
                dictation.isRecording ? "Fertig gesprochen" : "Sprechen",
                systemImage: dictation.isRecording ? "stop.circle.fill" : "mic.fill"
              )
              .frame(maxWidth: .infinity, minHeight: 44)
              .symbolEffect(.pulse, isActive: dictation.isRecording)
            }
            .buttonStyle(.bordered)
            .tint(dictation.isRecording ? .red : .accentColor)
            .listRowBackground(Color.clear)
            .accessibilityHint("Mahlzeit auf Deutsch diktieren, der Text erscheint im Feld darüber")
          }
          if let error = dictation.error {
            Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
          }
        } footer: {
          Text(
            dictation.isRecording
              ? (dictation.isOnDevice
                ? "Hört zu … Die Erkennung läuft auf dem iPhone." : "Hört zu … Apple wandelt die Sprache in Text um.")
              : "Mengen nennen, wenn bekannt – auch mehrere Mahlzeiten auf einmal. Tippen auf „Sprechen“ diktiert, "
                + "praktisch beim Kochen.")
        }
        Section {
          Button("Barcode scannen", systemImage: "barcode.viewfinder") { choose(.barcode) }
          Button("Nur Kalorien (Schätzung)", systemImage: "bolt") { choose(.quick) }
          Button("Manuell eingeben", systemImage: "square.and.pencil") { choose(.manual) }
        }
      }
      .navigationTitle("Erfassen")
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: dictation.transcript) { _, spoken in
        guard !spoken.isEmpty else { return }
        text = textBeforeDictation.isEmpty ? spoken : "\(textBeforeDictation) \(spoken)"
      }
      .onDisappear { dictation.stop() }
      .onChange(of: photoItem) { _, item in
        Task { photo = try? await item?.loadTransferable(type: Data.self) }
      }
      .fullScreenCover(isPresented: $showsCamera) {
        CameraPicker { data in photo = data }.ignoresSafeArea()
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Analysieren") {
            dictation.stop()
            let text = text
            let photo = photo
            dismiss()
            Task { await analyze(text, photo) }
          }
          .bold()
          .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil)
        }
      }
    }
  }

  /// Erst schließen, dann den nächsten Bildschirm öffnen (zwei Sheets gleichzeitig zeigt iOS nicht).
  private func choose(_ choice: Other) {
    dismiss()
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      other(choice)
    }
  }
}

/// Barcode ohne Treffer: selbst anlegen (Etikett abtippen) oder die Nährwerttabelle fotografieren.
struct MissingBarcodeSheet: View {
  let barcode: String
  let create: () -> Void
  let photograph: (Data) -> Void
  @State private var showsCamera = false
  @State private var photoItem: PhotosPickerItem?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(
            "Barcode \(barcode) ist bei Open Food Facts nicht bekannt. Einmal anlegen – beim nächsten Scan kennt "
              + "die App das Produkt.")
        }
        Section {
          if CameraPicker.isAvailable {
            Button("Nährwerttabelle fotografieren", systemImage: "camera") { showsCamera = true }
          }
          PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Foto der Tabelle wählen", systemImage: "photo")
          }
          Button("Werte selbst eintragen", systemImage: "square.and.pencil") {
            dismiss()
            Task {
              try? await Task.sleep(for: .milliseconds(450))
              create()
            }
          }
        } footer: {
          Text("Die KI liest die Werte je 100 g nur ab; du prüfst sie vor dem Speichern.")
        }
      }
      .navigationTitle("Produkt unbekannt")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
      }
      .fullScreenCover(isPresented: $showsCamera) {
        CameraPicker { data in finish(data) }.ignoresSafeArea()
      }
      .onChange(of: photoItem) { _, item in
        Task {
          if let data = try? await item?.loadTransferable(type: Data.self) { finish(data) }
        }
      }
    }
    .presentationDetents([.medium])
  }

  private func finish(_ data: Data) {
    dismiss()
    photograph(data)
  }
}

/// Kamera für Mahlzeit-Fotos (UIImagePickerController).
struct CameraPicker: UIViewControllerRepresentable {
  let onImage: (Data) -> Void
  @Environment(\.dismiss) private var dismiss

  static var isAvailable: Bool {
    UIImagePickerController.isSourceTypeAvailable(.camera)
  }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraPicker

    init(parent: CameraPicker) {
      self.parent = parent
    }

    func imagePickerController(
      _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      if let image = info[.originalImage] as? UIImage, let data = MealPhoto.jpeg(from: image) {
        parent.onImage(data)
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}

/// Barcode per Kamera (VisionKit) oder von Hand eingeben.
struct BarcodeEntry: View {
  let onCode: (String) -> Void
  @State private var manualCode = ""
  @Environment(\.dismiss) private var dismiss

  private var scannerAvailable: Bool {
    DataScannerViewController.isSupported && DataScannerViewController.isAvailable
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if scannerAvailable {
          BarcodeScanner { code in
            finish(code)
          }
          .frame(maxHeight: .infinity)
        } else {
          ContentUnavailableView(
            "Kamera-Scan nicht verfügbar", systemImage: "barcode.viewfinder",
            description: Text("Barcode unten eingeben."))
        }
        HStack {
          TextField("Barcode eingeben", text: $manualCode)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
          Button("Suchen") { finish(manualCode) }
            .disabled(!OpenFoodFacts.isValidBarcode(manualCode))
        }
        .padding()
      }
      .navigationTitle("Barcode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { dismiss() }
        }
      }
    }
  }

  private func finish(_ code: String) {
    let digits = code.filter(\.isNumber)
    guard OpenFoodFacts.isValidBarcode(digits) else { return }
    dismiss()
    onCode(digits)
  }
}

/// VisionKit-Scanner für EAN/UPC-Barcodes. Meldet den ersten gültigen Code.
private struct BarcodeScanner: UIViewControllerRepresentable {
  let onCode: (String) -> Void

  func makeUIViewController(context: Context) -> DataScannerViewController {
    let scanner = DataScannerViewController(
      recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
      qualityLevel: .balanced,
      recognizesMultipleItems: false,
      isHighFrameRateTrackingEnabled: false,
      isHighlightingEnabled: true
    )
    scanner.delegate = context.coordinator
    return scanner
  }

  func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
    if !scanner.isScanning { try? scanner.startScanning() }
  }

  static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
    scanner.stopScanning()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onCode: onCode)
  }

  final class Coordinator: NSObject, DataScannerViewControllerDelegate {
    let onCode: (String) -> Void
    private var reported = false

    init(onCode: @escaping (String) -> Void) {
      self.onCode = onCode
    }

    func dataScanner(
      _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]
    ) {
      for item in addedItems {
        guard !reported, case .barcode(let barcode) = item, let code = barcode.payloadStringValue,
          OpenFoodFacts.isValidBarcode(code)
        else { continue }
        reported = true
        onCode(code)
      }
    }
  }
}
