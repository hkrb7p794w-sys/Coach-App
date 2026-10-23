// swift-tools-version: 6.0
import PackageDescription

// Reine Logik ohne Apple-Frameworks (kein SwiftUI, HealthKit, SwiftData),
// damit `swift test` auch auf dem Linux-Runner läuft.
let package = Package(
  name: "CoachCore",
  platforms: [.iOS(.v18), .macOS(.v15)],
  products: [
    .library(name: "CoachCore", targets: ["CoachCore"])
  ],
  targets: [
    .target(name: "CoachCore"),
    .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"]),
  ]
)
