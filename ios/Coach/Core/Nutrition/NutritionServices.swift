import CoachCore
import Foundation
import UIKit

/// Open Food Facts per Barcode. Gefundene Produkte merkt sich die App als `FoodRecord`, ein zweiter Scan
/// braucht dann keinen Netzzugriff.
final class OpenFoodFactsClient {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  enum LookupError: Error, LocalizedError {
    case invalidBarcode
    case notFound
    case network(String)

    var errorDescription: String? {
      switch self {
      case .invalidBarcode: "Ungültiger Barcode (Prüfziffer stimmt nicht)."
      case .notFound: "Produkt nicht bei Open Food Facts gefunden oder ohne Nährwerte."
      case .network(let detail): "Open Food Facts nicht erreichbar: \(detail)"
      }
    }
  }

  func product(barcode: String) async throws -> OpenFoodFacts.Product {
    guard OpenFoodFacts.isValidBarcode(barcode), let url = OpenFoodFacts.productURL(barcode: barcode) else {
      throw LookupError.invalidBarcode
    }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue(OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")
    let data: Data
    do {
      data = try await session.data(for: request).0
    } catch {
      throw LookupError.network(error.localizedDescription)
    }
    guard let json = try? JSONValue(data: data), let product = OpenFoodFacts.product(from: json, barcode: barcode)
    else { throw LookupError.notFound }
    return product
  }
}

/// Verkleinert Fotos vor dem Versand an die KI und kodiert sie neu – dabei fallen EXIF- und GPS-Daten weg.
enum MealPhoto {
  static let maxPixels: CGFloat = 1280

  static func jpeg(from data: Data) -> Data? {
    guard let image = UIImage(data: data) else { return nil }
    return jpeg(from: image)
  }

  static func jpeg(from image: UIImage) -> Data? {
    let longest = max(image.size.width, image.size.height)
    let scale = longest > maxPixels ? maxPixels / longest : 1
    let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: 0.7)
  }
}
