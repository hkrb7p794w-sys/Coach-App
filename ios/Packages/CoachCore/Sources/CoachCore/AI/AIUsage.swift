import Foundation

/// Eine KI-Anfrage im internen Protokoll (Einstellungen › KI › Nutzung): wer, womit, wie viel – keine Inhalte.
public struct AIUsageEntry: Codable, Equatable, Sendable {
  public var date: Date
  public var task: String
  public var trigger: AITrigger
  public var provider: String?
  public var model: String?
  public var ok: Bool
  public var inputTokens: Int?
  public var outputTokens: Int?
  /// Listenpreis in US-Dollar, falls die Anfrage bezahlt würde (im kostenlosen Kontingent 0 € tatsächlich).
  public var listPriceUsd: Double?
  public var milliseconds: Int
  /// Kurzer Fehlertext (ohne Daten).
  public var error: String?

  public init(
    date: Date, task: String, trigger: AITrigger, provider: String?, model: String?, ok: Bool,
    inputTokens: Int? = nil, outputTokens: Int? = nil, listPriceUsd: Double? = nil, milliseconds: Int,
    error: String? = nil
  ) {
    self.date = date
    self.task = task
    self.trigger = trigger
    self.provider = provider
    self.model = model
    self.ok = ok
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.listPriceUsd = listPriceUsd
    self.milliseconds = milliseconds
    self.error = error.map { String($0.prefix(160)) }
  }
}

public enum AIUsageLog {
  public static let maxEntries = 1_000
  public static let maxAge: TimeInterval = 180 * 86_400

  /// Neuer Eintrag vorne; zu alte und überzählige fallen weg.
  public static func appending(_ entry: AIUsageEntry, to entries: [AIUsageEntry]) -> [AIUsageEntry] {
    let cutoff = entry.date.addingTimeInterval(-maxAge)
    return Array(([entry] + entries).filter { $0.date >= cutoff }.prefix(maxEntries))
  }

  public struct Line: Equatable, Sendable, Identifiable {
    public var provider: String
    public var model: String
    public var requests: Int
    public var failures: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var listPriceUsd: Double
    public var averageSeconds: Double
    public var id: String { "\(provider)|\(model)" }
  }

  public struct Summary: Equatable, Sendable {
    public var lines: [Line]
    public var requests: Int
    public var failures: Int
    public var automatic: Int
    public var listPriceUsd: Double
    public var byTask: [(task: String, count: Int)]

    public static func == (lhs: Summary, rhs: Summary) -> Bool {
      lhs.lines == rhs.lines && lhs.requests == rhs.requests && lhs.failures == rhs.failures
        && lhs.listPriceUsd == rhs.listPriceUsd && lhs.byTask.map(\.task) == rhs.byTask.map(\.task)
        && lhs.byTask.map(\.count) == rhs.byTask.map(\.count) && lhs.automatic == rhs.automatic
    }
  }

  public static func summary(_ entries: [AIUsageEntry], since: Date) -> Summary {
    let recent = entries.filter { $0.date >= since }
    let groups = Dictionary(grouping: recent) { "\($0.provider ?? "–")|\($0.model ?? "–")" }
    let lines = groups.map { key, group -> Line in
      let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
      return Line(
        provider: parts.first ?? "–", model: parts.count > 1 ? parts[1] : "–", requests: group.count,
        failures: group.filter { !$0.ok }.count, inputTokens: group.compactMap(\.inputTokens).reduce(0, +),
        outputTokens: group.compactMap(\.outputTokens).reduce(0, +),
        listPriceUsd: group.compactMap(\.listPriceUsd).reduce(0, +),
        averageSeconds: Double(group.map(\.milliseconds).reduce(0, +)) / Double(max(group.count, 1)) / 1000)
    }
    .sorted { ($0.requests, $0.id) > ($1.requests, $1.id) }
    let tasks = Dictionary(grouping: recent, by: \.task).map { (task: $0.key, count: $0.value.count) }
      .sorted { ($0.count, $1.task) > ($1.count, $0.task) }
    return Summary(
      lines: lines, requests: recent.count, failures: recent.filter { !$0.ok }.count,
      automatic: recent.filter { $0.trigger == .automatic }.count,
      listPriceUsd: lines.map(\.listPriceUsd).reduce(0, +), byTask: tasks)
  }

  /// Anzeigename des Anbieters aus der Worker-Kennung.
  public static func providerLabel(_ id: String) -> String {
    AIProviderChoice(rawValue: id)?.label ?? (id == "–" ? "ohne Antwort" : id)
  }
}
