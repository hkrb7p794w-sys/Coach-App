import Foundation
import Testing

@testable import CoachCore

/// Audit 03.11.2026 (WRK-03): Eine Einladung ohne Token darf nicht angenommen werden. Sonst setzt
/// `LeagueService.accept` → `AIClient.configure(url:token:)` nur die neue Worker-Adresse und behält das gespeicherte
/// (Haupt-)Token – die nächste Anfrage schickt es als Bearer-Token an die fremde Adresse.
struct AuditWorkerProtocolTests {
  @Test func inviteWithoutTokenIsRejected() throws {
    let url = try #require(URL(string: "coach://join?worker=https://fremd.example&league=team-abc234"))
    #expect(LeagueInvite(url: url) == nil)
    let blank = try #require(URL(string: "coach://join?worker=https://fremd.example&token=&league=team-abc234"))
    #expect(LeagueInvite(url: blank) == nil)
  }
}
