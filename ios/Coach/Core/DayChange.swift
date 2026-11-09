import Combine
import CoachCore
import SwiftUI

/// Meldet einen neuen Kalendertag, auch wenn die App über Mitternacht offen bleibt oder aus dem Hintergrund kommt.
private struct DayChangeModifier: ViewModifier {
  let action: (CalendarDay) -> Void
  @Environment(\.scenePhase) private var scenePhase
  @State private var day = CalendarDay(date: .now)

  private func check() {
    let current = CalendarDay(date: .now)
    guard current != day else { return }
    day = current
    action(current)
  }

  func body(content: Content) -> some View {
    content
      .onChange(of: scenePhase) { _, phase in
        if phase == .active { check() }
      }
      .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
        check()
      }
  }
}

extension View {
  func onDayChange(_ action: @escaping (CalendarDay) -> Void) -> some View {
    modifier(DayChangeModifier(action: action))
  }
}
