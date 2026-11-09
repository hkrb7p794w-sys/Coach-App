import Foundation
import Testing

@testable import CoachCore

struct AppBackupTests {
  let now = Date(timeIntervalSince1970: 1_793_500_000)

  func sample() -> AppBackup {
    AppBackup(
      createdAt: now,
      settings: [
        "coach.profile": .data(Data("{\"a\":1}".utf8)), "coach.privacy": .string("reduced"),
        "coach.showsEvidence": .bool(true), "coach.count": .int(3), "coach.factor": .double(1.5),
      ],
      gym: [AppBackup.Gym(id: UUID(), payload: Data("{}".utf8), savedToHealth: true, uploadedToGarmin: false)],
      meals: [
        AppBackup.Meal(
          id: UUID(), dayKey: "2026-11-09", createdAt: now, category: "lunch", title: "Nudeln", hint: "",
          items: Data("[]".utf8))
      ],
      foods: [AppBackup.Food(key: "x", name: "Haferflocken", payload: Data("{}".utf8), lastUsed: now, useCount: 4)])
  }

  @Test func roundTripKeepsEverything() throws {
    let backup = sample()
    let decoded = try AppBackup.decode(try backup.encoded())
    #expect(decoded == backup)
    #expect(decoded.summary == "1 Krafteinheiten, 1 Mahlzeiten, 1 eigene Lebensmittel, 5 Einstellungen")
  }

  @Test func onlyAppSettingsAreBackedUp() {
    #expect(AppBackup.isBackedUp(key: "coach.gym"))
    #expect(AppBackup.isBackedUp(key: "coach.mobility"))
    #expect(AppBackup.isBackedUp(key: "ai.workerURL"))
    #expect(!AppBackup.isBackedUp(key: "coach.wakeAlarm"))
    #expect(!AppBackup.isBackedUp(key: "garmin.lastSync"))
    #expect(!AppBackup.isBackedUp(key: "health.lastImport"))
    #expect(!AppBackup.isBackedUp(key: "gym.activeSession"))
    #expect(!AppBackup.isBackedUp(key: "backup.folderBookmark"))
  }

  @Test func rejectsForeignAndNewerFiles() {
    #expect(throws: AppBackup.Failure.unreadable) { try AppBackup.decode(Data("hallo".utf8)) }
    #expect(throws: AppBackup.Failure.unreadable) { try AppBackup.decode(Data("{\"version\":1}".utf8)) }
    #expect(throws: AppBackup.Failure.newerVersion(9)) { try AppBackup.decode(Data("{\"version\":9}".utf8)) }
  }

  @Test func autoBackupInterval() {
    #expect(AppBackup.isDue(last: nil, now: now))
    #expect(!AppBackup.isDue(last: now.addingTimeInterval(-3_600), now: now))
    #expect(AppBackup.isDue(last: now.addingTimeInterval(-21 * 3_600), now: now))
    // Uhr zurückgestellt: lieber sichern als nie wieder.
    #expect(AppBackup.isDue(last: now.addingTimeInterval(3_600), now: now))
  }

  @Test func mergeAddsOnlyMissingAndNoDuplicates() {
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let items = [a, b, b, c]
    let result = AppBackup.missing(items, key: { $0 }, existing: [a])
    #expect(result == [b, c])
  }
}
