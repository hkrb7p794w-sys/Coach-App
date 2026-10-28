import Foundation

/// Zoom und Ausschnitt für Verlaufsdiagramme: sichtbare Spanne in Tagen (per Knopf oder zwei Fingern) und die
/// Y-Achse passend zu den gerade sichtbaren Punkten, damit auch lange Verläufe lesbar bleiben.
public enum ChartZoom {
  public struct Preset: Equatable, Sendable, Identifiable {
    public var label: String
    /// `nil` = alles
    public var days: Double?
    public var id: String { label }
  }

  public static let presets = [
    Preset(label: "1 M", days: 30), Preset(label: "3 M", days: 91), Preset(label: "1 J", days: 365),
    Preset(label: "Alles", days: nil),
  ]

  public static let minimumDays = 14.0
  static let day = 86_400.0

  /// Gesamte Spanne der Daten in Tagen (mindestens `minimumDays`).
  public static func spanDays(_ dates: [Date]) -> Double {
    guard let first = dates.min(), let last = dates.max() else { return minimumDays }
    return max(last.timeIntervalSince(first) / day + 1, minimumDays)
  }

  /// Sichtbare Tage zwischen zwei Wochen und der ganzen Spanne.
  public static func clamp(_ days: Double, span: Double) -> Double {
    min(max(days, minimumDays), max(span, minimumDays))
  }

  /// Standard: drei Monate, bei kürzerem Verlauf alles.
  public static func initialDays(span: Double) -> Double {
    clamp(min(91, span), span: span)
  }

  /// Start des sichtbaren Ausschnitts, sodass er am letzten Punkt endet.
  public static func initialStart(_ dates: [Date], days: Double) -> Date {
    let last = dates.max() ?? Date(timeIntervalSince1970: 0)
    return last.addingTimeInterval(-days * day + day / 2)
  }

  /// Y-Bereich der sichtbaren Werte mit 10 % Luft (mindestens `minimumPadding`); ohne sichtbare Werte der ganze
  /// Bereich.
  public static func yDomain(
    _ points: [(date: Date, value: Double)], from start: Date, days: Double, includesZero: Bool = false,
    minimumPadding: Double = 1
  ) -> ClosedRange<Double> {
    let end = start.addingTimeInterval(days * day)
    let visible = points.filter { $0.date >= start && $0.date <= end }.map(\.value)
    let values = visible.isEmpty ? points.map(\.value) : visible
    guard var low = values.min(), var high = values.max() else { return 0...1 }
    if includesZero { low = min(low, 0) }
    let padding = max((high - low) * 0.1, max(abs(high) * 0.05, minimumPadding))
    high += padding
    low = includesZero ? low : low - padding
    return low...high
  }

  /// Punkte nur zeigen, solange sie nicht zu dicht liegen.
  public static func showsPoints(days: Double, count: Int, span: Double) -> Bool {
    Double(count) * days / max(span, 1) <= 40
  }
}
