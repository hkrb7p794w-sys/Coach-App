import Foundation

/// Herkunft eines importierten Datensatzes. Für die Nutzeroberfläche nicht nötig, aber jeder Wert bleibt
/// nachvollziehbar: wer ihn geliefert hat, unter welcher ID, für welche Zeit, wann er kam und ob er noch gilt.
public struct SourceEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
  public enum Status: String, Codable, Sendable {
    /// Aktuell und genutzt.
    case active
    /// Gleiche Einheit von einer bevorzugten Quelle vorhanden – nicht doppelt zählen, nicht neu anlegen.
    case superseded
    /// Beim Anbieter gelöscht.
    case deleted
  }

  public var provider: DataProvider
  /// `nil` = Tageswerte des Anbieters (alle Arten eines Tages in einem Datensatz).
  public var kind: DataKind?
  /// Eindeutige ID beim Anbieter; bei Tageswerten der Tag (`2026-11-02`).
  public var externalID: String
  public var day: CalendarDay
  /// Beginn des Datensatzes (Aktivität, Schlaf), falls bekannt.
  public var start: Date?
  public var importedAt: Date
  public var updatedAt: Date
  /// Prüfsumme des Inhalts, um Änderungen zu erkennen.
  public var contentHash: String
  public var status: Status

  public var id: String { Self.key(provider, kind, externalID) }

  public static func key(_ provider: DataProvider, _ kind: DataKind?, _ externalID: String) -> String {
    "\(provider.rawValue)|\(kind?.rawValue ?? "daily")|\(externalID)"
  }

  public init(
    provider: DataProvider, kind: DataKind?, externalID: String, day: CalendarDay, start: Date? = nil,
    importedAt: Date, updatedAt: Date? = nil, contentHash: String, status: Status = .active
  ) {
    self.provider = provider
    self.kind = kind
    self.externalID = externalID
    self.day = day
    self.start = start
    self.importedAt = importedAt
    self.updatedAt = updatedAt ?? importedAt
    self.contentHash = contentHash
    self.status = status
  }
}

/// Abgleich eines Abrufs mit dem schon Importierten: neu, geändert, unverändert, beim Anbieter gelöscht.
public enum SyncLedger {
  public struct Incoming: Equatable, Sendable {
    public var externalID: String
    public var day: CalendarDay
    public var start: Date?
    public var contentHash: String

    public init(externalID: String, day: CalendarDay, start: Date? = nil, contentHash: String) {
      self.externalID = externalID
      self.day = day
      self.start = start
      self.contentHash = contentHash
    }
  }

  public struct Changes: Equatable, Sendable {
    public var new: [SourceEntry] = []
    public var changed: [SourceEntry] = []
    public var unchanged: [String] = []
    /// Im vollständig abgerufenen Zeitraum nicht mehr geliefert.
    public var deleted: [SourceEntry] = []
    /// Wieder geliefert, war aber als ersetzt markiert – bleibt ersetzt.
    public var skipped: [String] = []

    public var isEmpty: Bool { new.isEmpty && changed.isEmpty && deleted.isEmpty }
  }

  /// `complete`: Der Abruf hat den ganzen Zeitraum `window` geliefert (sonst keine Löschungen ableiten, z. B. wenn
  /// nur eine Seite der Aktivitätsliste kam oder ein Endpunkt ausfiel).
  public static func reconcile(
    known: [SourceEntry], incoming: [Incoming], provider: DataProvider, kind: DataKind?, window: DateRange?,
    complete: Bool, now: Date
  ) -> Changes {
    let mine = known.filter { $0.provider == provider && $0.kind == kind }
    let byID = Dictionary(mine.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
    var changes = Changes()
    var seen = Set<String>()
    for item in incoming where seen.insert(item.externalID).inserted {
      if var entry = byID[item.externalID] {
        if entry.status == .superseded {
          changes.skipped.append(item.externalID)
        } else if entry.contentHash != item.contentHash || entry.status == .deleted {
          entry.contentHash = item.contentHash
          entry.updatedAt = now
          entry.day = item.day
          entry.start = item.start ?? entry.start
          entry.status = .active
          changes.changed.append(entry)
        } else {
          changes.unchanged.append(item.externalID)
        }
      } else {
        changes.new.append(
          SourceEntry(
            provider: provider, kind: kind, externalID: item.externalID, day: item.day, start: item.start,
            importedAt: now, contentHash: item.contentHash))
      }
    }
    if complete, let window {
      for var entry in mine
      where entry.status == .active && !seen.contains(entry.externalID) && window.start <= entry.day
        && entry.day <= window.end
      {
        entry.status = .deleted
        entry.updatedAt = now
        changes.deleted.append(entry)
      }
    }
    return changes
  }

  /// Prüfsumme über die JSON-Darstellung (FNV-1a, 64 Bit; reicht zum Erkennen von Änderungen).
  public static func hash(_ value: some Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(value)) ?? Data()
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in data {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return String(hash, radix: 16)
  }
}

/// Zustand der Synchronisierung je Anbieter: letzter Erfolg, Fehler und wann der nächste Versuch sinnvoll ist.
/// Nach einem Fehlschlag bleibt `lastSuccessDay` stehen, der nächste Abruf holt die Lücke also nach.
public struct ProviderSyncState: Codable, Equatable, Hashable, Sendable {
  public var lastAttempt: Date?
  public var lastSuccess: Date?
  public var lastSuccessDay: CalendarDay?
  public var lastError: String?
  public var failures: Int = 0

  public init() {}

  /// Wartezeit nach `failures` Fehlschlägen: 1, 5, 15, 60 Minuten, danach 6 Stunden.
  public static func backoff(failures: Int) -> TimeInterval {
    switch failures {
    case ...0: 0
    case 1: 60
    case 2: 5 * 60
    case 3: 15 * 60
    case 4: 60 * 60
    default: 6 * 60 * 60
    }
  }

  /// Automatischer Abruf fällig? Manuell („Jetzt abrufen“) geht immer.
  public func isDue(now: Date, minimumInterval: TimeInterval) -> Bool {
    guard let lastAttempt else { return true }
    if now < lastAttempt { return true }
    let wait = failures > 0 ? Self.backoff(failures: failures) : minimumInterval
    return now.timeIntervalSince(lastAttempt) >= wait
  }

  public mutating func recordSuccess(now: Date, day: CalendarDay) {
    lastAttempt = now
    lastSuccess = now
    lastSuccessDay = day
    lastError = nil
    failures = 0
  }

  public mutating func recordFailure(now: Date, error: String) {
    lastAttempt = now
    lastError = error
    failures += 1
  }

  /// Zeitraum des nächsten Abrufs: ab dem letzten erfolgreichen Tag mit Überlappung (Werte kommen nachträglich),
  /// beim ersten Mal `initialDays`, höchstens `maxDays`.
  public func window(today: CalendarDay, initialDays: Int, overlapDays: Int = 3, maxDays: Int = 180) -> DateRange {
    guard let last = lastSuccessDay, last <= today else { return DateRange.last(initialDays, endingOn: today) }
    let start = max(last.adding(days: -overlapDays), today.adding(days: -(maxDays - 1)))
    return DateRange(start: start, end: today)
  }
}
