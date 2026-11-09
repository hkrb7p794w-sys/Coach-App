import Foundation
import Testing

@testable import CoachCore

struct AccountRulesTests {
  @Test func usernamesMatchTheWorker() {
    #expect(AccountRules.usernameProblem("lena") == nil)
    #expect(AccountRules.usernameProblem(" Max_Mustermann.1 ") == nil)
    #expect(AccountRules.usernameProblem("ab") != nil)
    #expect(AccountRules.usernameProblem(".lena") != nil)
    #expect(AccountRules.usernameProblem("lena müller") != nil)
    #expect(AccountRules.usernameProblem("jörg") != nil)
    #expect(AccountRules.usernameProblem("admin") == "Dieser Benutzername ist reserviert.")
  }

  @Test func passwordsMatchTheWorker() {
    #expect(AccountRules.passwordProblem("Sommer-Lauf-2026", username: "lena") == nil)
    #expect(AccountRules.passwordProblem("kurz", username: "lena")?.contains("mindestens 10") == true)
    #expect(AccountRules.passwordProblem("LENA-passwort-1", username: "lena")?.contains("Benutzernamen") == true)
    #expect(AccountRules.passwordProblem("aaaaaaaaaaaa", username: "lena") == "Das Passwort ist zu einfach.")
  }

  @Test func displayNamesAndCodes() {
    #expect(AccountRules.displayName("  Lena   Sommer ") == "Lena Sommer")
    #expect(AccountRules.displayName("   ") == "")
    #expect(AccountRules.displayName(String(repeating: "x", count: 41)) == nil)
    #expect(AccountRules.normalizeCode("abcd-efgh jk") == "ABCDEFGHJK")
  }

  @Test func inviteLinkRoundTrip() throws {
    let invite = AccountInvite(workerURL: "https://coach-ai.example.workers.dev", code: "abcde-fghjk")
    #expect(invite.code == "ABCDEFGHJK")
    let url = try #require(invite.url)
    #expect(AccountInvite(url: url) == invite)
    #expect(invite.shareURL?.absoluteString == "https://coach-ai.example.workers.dev/i/ABCDEFGHJK")
    #expect(AccountInvite(url: URL(string: "coach://account?worker=http://x.dev&invite=ABCDEFGHJK")!) == nil)
    #expect(AccountInvite(url: URL(string: "coach://account?worker=https://x.dev&invite=ABC")!) == nil)
    #expect(AccountInvite(url: URL(string: "coach://join?worker=https://x.dev&invite=ABCDEFGHJK")!) == nil)
  }
}
