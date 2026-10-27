import XCTest

/// Screenshots aller Hauptbereiche mit Beispieldaten (`-demo`) in hell, dunkel und großer Schrift.
/// Läuft nur im Workflow „Screenshots“; die Bilder landen als Anhänge im Ergebnis und von dort in einem Release.
@MainActor
final class ScreenshotTests: XCTestCase {
  private struct Variant {
    let name: String
    let arguments: [String]
  }

  private let variants = [
    Variant(name: "hell", arguments: ["-demoScheme", "light"]),
    Variant(name: "dunkel", arguments: ["-demoScheme", "dark"]),
    Variant(
      name: "grosse-schrift",
      arguments: ["-demoScheme", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]),
  ]

  override func setUp() {
    continueAfterFailure = true
  }

  func testCaptureMainScreens() {
    for variant in variants {
      let app = XCUIApplication()
      app.launchArguments = ["-demo"] + variant.arguments
      app.launch()
      var index = 0
      func shot(_ screen: String) {
        index += 1
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(variant.name)-\(String(format: "%02d", index))-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
      }
      func scrollShot(_ screen: String) {
        shot(screen)
        app.swipeUp()
        shot("\(screen)-unten")
        app.swipeDown()
        app.swipeDown()
      }

      _ = app.tabBars.firstMatch.waitForExistence(timeout: 15)
      sleep(2)
      scrollShot("heute")
      for tab in ["Plan", "Training", "Ernährung", "Gym"] {
        let button = app.tabBars.buttons[tab]
        guard button.waitForExistence(timeout: 5) else { continue }
        button.tap()
        sleep(1)
        scrollShot(tab.lowercased())
      }

      // Unterseiten der Ernährung.
      app.tabBars.buttons["Ernährung"].tap()
      for link in ["Gewichtsverlauf", "Rezeptideen für die kommende Woche"] {
        let button = app.buttons[link]
        var tries = 0
        while !button.isHittable && tries < 4 {
          app.swipeUp()
          tries += 1
        }
        guard button.exists else { continue }
        button.tap()
        sleep(1)
        shot(link.split(separator: " ").first.map(String.init)?.lowercased() ?? "seite")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
      }
      app.terminate()
    }
  }
}
