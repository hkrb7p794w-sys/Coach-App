import Foundation
import Testing

@testable import CoachCore

struct AIPolicyTests {
  @Test func modesGateTasks() {
    // Voll: alles.
    #expect(AIPolicy.allows(.full, task: "daily_note", trigger: .automatic))
    // Auf Anfrage: nichts Automatisches.
    #expect(!AIPolicy.allows(.onRequest, task: "daily_note", trigger: .automatic))
    #expect(AIPolicy.allows(.onRequest, task: "daily_note", trigger: .user))
    #expect(AIPolicy.allows(.onRequest, task: "meal_analyze", trigger: .user))
    // Keine Empfehlungen: nur Erfassung auf Anfrage.
    #expect(AIPolicy.allows(.captureOnly, task: "meal_analyze", trigger: .user))
    #expect(AIPolicy.allows(.captureOnly, task: "nutrition_label", trigger: .user))
    #expect(!AIPolicy.allows(.captureOnly, task: "coach_chat", trigger: .user))
    #expect(!AIPolicy.allows(.captureOnly, task: "gym_plan", trigger: .user))
    #expect(!AIPolicy.allows(.captureOnly, task: "meal_analyze", trigger: .automatic))
    // Aus: nichts mit Daten; Verbindungstest nur von Hand.
    #expect(!AIPolicy.allows(.off, task: "meal_analyze", trigger: .user))
    #expect(AIPolicy.allows(.off, task: "ping", trigger: .user))
    #expect(!AIPolicy.allows(.full, task: "ping", trigger: .automatic))
    // Unbekannte Aufgaben zählen als Empfehlung.
    #expect(AIPolicy.kind(of: "neu") == .recommendation)
  }

  @Test func settingsDecodeTolerantly() throws {
    let decoded = try JSONDecoder().decode(AISettings.self, from: Data(#"{"mode": "unbekannt"}"#.utf8))
    #expect(decoded == AISettings())
    let stored = AISettings(mode: .captureOnly, provider: .privat)
    #expect(try JSONDecoder().decode(AISettings.self, from: JSONEncoder().encode(stored)) == stored)
  }

  @Test func usageLogPrunesAndSums() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let old = AIUsageEntry(
      date: now.addingTimeInterval(-200 * 86_400), task: "x", trigger: .user, provider: "gemini", model: "m",
      ok: true, milliseconds: 1)
    var log = AIUsageLog.appending(old, to: [])
    let entries = [
      AIUsageEntry(
        date: now, task: "daily_note", trigger: .automatic, provider: "gemini", model: "flash", ok: true,
        inputTokens: 1000, outputTokens: 200, listPriceUsd: 0.0008, milliseconds: 2000),
      AIUsageEntry(
        date: now, task: "coach_chat", trigger: .user, provider: "workers_ai", model: "gemma", ok: true,
        inputTokens: 500, outputTokens: 100, listPriceUsd: 0.00008, milliseconds: 1000),
      AIUsageEntry(
        date: now, task: "coach_chat", trigger: .user, provider: nil, model: nil, ok: false, milliseconds: 500,
        error: String(repeating: "x", count: 500)),
    ]
    for entry in entries { log = AIUsageLog.appending(entry, to: log) }
    #expect(log.count == 3)
    #expect(log.first?.error?.count == 160)
    let summary = AIUsageLog.summary(log, since: now.addingTimeInterval(-30 * 86_400))
    #expect(summary.requests == 3)
    #expect(summary.failures == 1)
    #expect(summary.automatic == 1)
    #expect(summary.byTask.first?.task == "coach_chat")
    #expect(abs(summary.listPriceUsd - 0.00088) < 1e-9)
    #expect(summary.lines.count == 3)
    #expect(AIUsageLog.providerLabel("workers_ai") == "Cloudflare Workers AI")
  }
}
