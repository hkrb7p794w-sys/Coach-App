import CoachCore
import SwiftUI

/// Farbe und Symbol je Einheit – einheitlich in Plan, Training und Gym. Systemfarben passen sich dem Dark Mode an.
extension PlannedUnit.Kind {
  var color: Color {
    switch self {
    case .bike, .bikeOptional: .orange
    case .swim: .blue
    case .quality, .easyRun, .longRun: .green
    case .gym: .purple
    }
  }

  var symbol: String {
    switch self {
    case .bike, .bikeOptional: "figure.outdoor.cycle"
    case .swim: "figure.pool.swim"
    case .quality: "speedometer"
    case .easyRun: "figure.run"
    case .longRun: "road.lanes"
    case .gym: "dumbbell.fill"
    }
  }
}

extension TrainingSport {
  var color: Color {
    switch self {
    case .run: .green
    case .strength: .purple
    case .bike: .orange
    case .swim: .blue
    case .other: .teal
    }
  }

  var shortLabel: String {
    switch self {
    case .run: "Laufen"
    case .strength: "Kraft"
    case .bike: "Rad"
    case .swim: "Schwimmen"
    case .other: "Anderes"
    }
  }
}

extension SessionSlot {
  /// Kurzbeschriftung für Chips: „Laufen · Locker“.
  var chipLabel: String {
    sport == .other ? sport.shortLabel : "\(sport.shortLabel) · \(intensity.label)"
  }
}

/// Symbol in einer farbigen, abgerundeten Fläche (wie in den Einstellungen von iOS).
struct SportIcon: View {
  let symbol: String
  let color: Color
  var size: CGFloat = 32

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
      .accessibilityHidden(true)
  }
}
