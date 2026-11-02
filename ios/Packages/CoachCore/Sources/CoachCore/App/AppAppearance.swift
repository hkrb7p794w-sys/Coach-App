/// Darstellung der App: dem System folgen oder fest hell bzw. dunkel. Gilt nur in der App; Widgets und
/// Live-Aktivität folgen immer dem System (WidgetKit kennt keine Vorgabe der App).
public enum AppAppearance: String, CaseIterable, Sendable, Identifiable {
  case system, light, dark

  public static let storageKey = "appAppearance"

  public var id: Self { self }

  public var title: String {
    switch self {
    case .system: "Wie System"
    case .light: "Hell"
    case .dark: "Dunkel"
    }
  }

  public var symbol: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light: "sun.max"
    case .dark: "moon"
    }
  }

  /// Unbekannte oder fehlende Werte fallen auf „Wie System“ zurück.
  public init(stored: String?) {
    self = stored.flatMap(AppAppearance.init(rawValue:)) ?? .system
  }
}
