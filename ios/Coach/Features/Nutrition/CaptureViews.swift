import CoachCore
import PhotosUI
import SwiftUI
import UIKit
import Vision
import VisionKit

/// Mahlzeit beschreiben, optional mit Foto.
struct MealTextEntry: View {
  let analyze: (String, Data?) async -> Void
  @State private var text = ""
  @State private var photoItem: PhotosPickerItem?
  @State private var photo: Data?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("z. B. 2 Rühreier, 1 Scheibe Vollkornbrot, Kaffee mit Milch", text: $text, axis: .vertical)
            .lineLimit(3...8)
        } footer: {
          Text("Mengen nennen, wenn bekannt („200 g“, „1 Tasse“). Sonst schätzt die KI typische Portionen.")
        }
        Section {
          PhotosPicker(selection: $photoItem, matching: .images) {
            Label(photo == nil ? "Foto hinzufügen (optional)" : "Foto ausgewählt", systemImage: "photo")
          }
        }
      }
      .navigationTitle("Beschreiben")
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: photoItem) { _, item in
        Task { photo = try? await item?.loadTransferable(type: Data.self) }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Abbrechen") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Analysieren") {
            let text = text
            let photo = photo
            dismiss()
            Task { await analyze(text, photo) }
          }
          .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil)
        }
      }
    }
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
