import Foundation

/// Soll gegen Ist je Einheit. „Erledigt“ heißt: gleiche Sportart am selben Tag, mindestens 60 % der geplanten
/// Dauer – nicht nur „an dem Tag war irgendetwas“ (ein Spaziergang hakt keinen Intervalllauf ab).
public enum SessionStatus: String, Codable, Sendable {
  /// Geplante Einheit wie vorgesehen gemacht.
  case done
  /// Gleiche Sportart, aber deutlich kürzer.
  case partial
  /// Andere Ausdauer-Sportart statt der geplanten (z. B. Rad statt Lauf).
  case substituted
  /// Tag vorbei, nichts Passendes.
  case missed
  /// Heute, noch offen.
  case open
  /// Später in der Woche.
  case planned

  public var label: String {
    switch self {
    case .done: "erledigt"
    case .partial: "teilweise"
    case .substituted: "anders gemacht"
    case .missed: "verpasst"
    case .open: "heute"
    case .planned: "geplant"
    }
  }

  /// Zählt für Erinnerungen und Tagesempfehlung als „gemacht“.
  public var counts: Bool { self == .done || self == .partial || self == .substituted }
}

/// Eine geplante Einheit an einem Tag (Wochenplan mit Ausnahmen).
public struct PlannedSession: Equatable, Hashable, Sendable, Identifiable {
  public var day: CalendarDay
  public var slot: SessionSlot
  /// Index unter den Einheiten des Tages (zwei Läufe an einem Tag).
  public var index: Int
  public var targetMinutes: Int

  public init(day: CalendarDay, slot: SessionSlot, index: Int = 0, targetMinutes: Int? = nil) {
    self.day = day
    self.slot = slot
    self.index = index
    self.targetMinutes = targetMinutes ?? SessionMatcher.defaultMinutes(slot)
  }

  public var id: String { "\(day.iso)-\(index)-\(slot.id)" }
}

public struct SessionResult: Equatable, Sendable, Identifiable {
  public var planned: PlannedSession
  public var status: SessionStatus
  public var activityID: Int64?
  public var actualMinutes: Int?
  /// Geplant intensiv, aber locker gemacht (oder umgekehrt).
  public var intensityNote: String?
  public var id: String { planned.id }

  /// „Soll 45 min · Ist 41 min“.
  public var compareText: String {
    guard let actualMinutes else { return "Soll \(planned.targetMinutes) min" }
    return "Soll \(planned.targetMinutes) min · Ist \(actualMinutes) min"
  }
}

public enum SessionMatcher {
  /// Ab diesem Anteil der geplanten Dauer gilt die Einheit als erledigt, darunter als „teilweise“.
  public static let doneShare = 0.6
  /// Kürzere Aktivitäten (Weg zur Arbeit, Einrollen) zählen für keine Einheit.
  public static let minimumSeconds: Double = 900

  /// Dauer, wenn der Plan keine nennt (der Laufplan liefert eigene Minuten).
  public static func defaultMinutes(_ slot: SessionSlot) -> Int {
    switch (slot.sport, slot.intensity) {
    case (.strength, _): 45
    case (.other, _): 30
    case (_, .easy): 45
    case (_, .hard): 50
    case (_, .long): 90
    }
  }

  public static func sport(_ sport: GarminActivity.Sport) -> TrainingSport {
    switch sport {
    case .run: .run
    case .bike: .bike
    case .swim: .swim
    case .strength: .strength
    case .other: .other
    }
  }

  /// Geplante Einheiten der Woche ab `monday`; Laufminuten aus dem Laufplan, falls vorhanden.
  public static func planned(
    schedule: WeekSchedule, monday: CalendarDay, runMinutes: [Weekday: [Int]] = [:]
  ) -> [PlannedSession] {
    Weekday.allCases.flatMap { weekday -> [PlannedSession] in
      let day = monday.adding(days: weekday.rawValue)
      var runIndex = 0
      return schedule.slots(on: weekday).enumerated().map { index, slot in
        var minutes: Int?
        if slot.sport == .run, let list = runMinutes[weekday], list.indices.contains(runIndex) {
          minutes = list[runIndex]
          runIndex += 1
        }
        return PlannedSession(day: day, slot: slot, index: index, targetMinutes: minutes)
      }
    }
  }

  public struct Week: Equatable, Sendable {
    public var results: [SessionResult]
    /// Außerplanmäßige Aktivitäten (keiner Einheit zugeordnet), ab 10 Minuten.
    public var extraIDs: [Int64]

    public func results(on day: CalendarDay) -> [SessionResult] { results.filter { $0.planned.day == day } }

    /// Alle geplanten Einheiten des Tages gemacht (für Erinnerungen und „Geschafft“).
    public func allCounted(on day: CalendarDay) -> Bool {
      let today = results(on: day)
      return !today.isEmpty && today.allSatisfy(\.status.counts)
    }
  }

  /// Zuordnung je Tag: zuerst gleiche Sportart (längste Aktivität zuerst), dann andere Ausdauer als Ersatz.
  /// Krafteinheiten aus der App (`gymDays`) zählen als Kraft, auch ohne Garmin-Aufzeichnung.
  public static func match(
    planned: [PlannedSession], activities: [GarminActivity], gymDays: Set<CalendarDay> = [], today: CalendarDay
  ) -> Week {
    var results: [SessionResult] = []
    var used = Set<Int64>()
    let days = Set(planned.map(\.day)).union(activities.compactMap(\.day))
    for day in days.sorted() {
      let sessions = planned.filter { $0.day == day }.sorted { $0.index < $1.index }
      let candidates = activities.filter { $0.day == day && ($0.durationSeconds ?? 0) >= minimumSeconds }
        .sorted { ($0.durationSeconds ?? 0) > ($1.durationSeconds ?? 0) }
      var gymAvailable = gymDays.contains(day)
      var open: [PlannedSession] = []
      for session in sessions {
        if let activity = candidates.first(where: { !used.contains($0.id) && sport($0.sport) == session.slot.sport }) {
          used.insert(activity.id)
          results.append(result(session, activity: activity, substituted: false))
        } else if session.slot.sport == .strength, gymAvailable {
          gymAvailable = false
          results.append(
            SessionResult(planned: session, status: .done, activityID: nil, actualMinutes: nil, intensityNote: nil))
        } else {
          open.append(session)
        }
      }
      for session in open {
        // Ersatz: andere Ausdauer-Sportart (Rad statt Lauf), nicht Kraft oder Spaziergang.
        if session.slot.sport.isEndurance,
          let activity = candidates.first(where: {
            !used.contains($0.id) && sport($0.sport).isEndurance
          })
        {
          used.insert(activity.id)
          results.append(result(session, activity: activity, substituted: true))
        } else {
          let status: SessionStatus = day < today ? .missed : day == today ? .open : .planned
          results.append(
            SessionResult(planned: session, status: status, activityID: nil, actualMinutes: nil, intensityNote: nil))
        }
      }
    }
    let extras = activities.filter { !used.contains($0.id) && ($0.durationSeconds ?? 0) >= 600 }.map(\.id)
    return Week(
      results: results.sorted { ($0.planned.day, $0.planned.index) < ($1.planned.day, $1.planned.index) },
      extraIDs: extras)
  }

  static func result(_ session: PlannedSession, activity: GarminActivity, substituted: Bool) -> SessionResult {
    let minutes = Int(((activity.durationSeconds ?? 0) / 60).rounded())
    let short = Double(minutes) < Double(session.targetMinutes) * doneShare
    let status: SessionStatus = substituted ? .substituted : short ? .partial : .done
    var note: String?
    let hard = SessionKind.isHard(activity)
    if session.slot.intensity == .hard, !hard, activity.sport != .strength {
      note = "locker statt intensiv"
    } else if session.slot.intensity == .easy, hard, activity.sport != .strength {
      note = "intensiver als geplant"
    }
    return SessionResult(
      planned: session, status: status, activityID: activity.id, actualMinutes: minutes, intensityNote: note)
  }

  /// Minuten je Sportart: Soll aus dem Plan, Ist aus allen Aktivitäten der Woche bis heute.
  public static func totals(
    planned: [PlannedSession], activities: [GarminActivity], monday: CalendarDay
  ) -> [(sport: TrainingSport, planned: Int, actual: Int)] {
    let end = monday.adding(days: 6)
    let week = activities.filter { ($0.day.map { monday <= $0 && $0 <= end }) ?? false }
    return TrainingSport.allCases.compactMap { sport in
      let plannedMinutes = planned.filter { $0.slot.sport == sport }.reduce(0) { $0 + $1.targetMinutes }
      let actual = Int(
        (week.filter { self.sport($0.sport) == sport }.reduce(0) { $0 + ($1.durationSeconds ?? 0) } / 60).rounded())
      return plannedMinutes == 0 && actual == 0 ? nil : (sport, plannedMinutes, actual)
    }
  }
}

/// Verpasste Einheiten: am nächsten Morgen entscheiden (nachholen, streichen, krank).
public enum MissedSessions {
  /// Höchstens eine Einheit pro Woche nachholen – sonst staut sich die Belastung.
  public static let maxMakeUpsPerWeek = 1
  /// Nach „krank“ so viele Tage nur locker.
  public static let illnessEasyDays = 2

  /// Verpasste, noch nicht entschiedene Einheiten der Woche bis gestern (neueste zuerst).
  public static func open(_ week: SessionMatcher.Week, handled: Set<String>) -> [SessionResult] {
    week.results.filter { $0.status == .missed && !handled.contains($0.id) }
      .sorted { $0.planned.day > $1.planned.day }
  }

  /// Nachholtag in dieser Woche nach heute: kein fordernder Ausdauertag direkt daneben, möglichst frei.
  public static func makeUpDay(
    for session: PlannedSession, schedule: WeekSchedule, profile: UserProfile, today: CalendarDay,
    makeUpsThisWeek: Int
  ) -> Weekday? {
    let sameWeek = PlanAdjustments.monday(of: session.day) == PlanAdjustments.monday(of: today)
    guard makeUpsThisWeek < maxMakeUpsPerWeek, sameWeek else { return nil }
    let candidates = Weekday.allCases.filter { $0.rawValue > today.weekdayIndex }
    return candidates.first { target in
      var moved = schedule
      moved.set(moved.slots(on: target) + [session.slot], on: target)
      let busy = !schedule.slots(on: target).isEmpty
      return !busy && !PlanMoveAdvisor.createsBackToBack(moved, around: target)
    }
      ?? candidates.first { target in
        var moved = schedule
        moved.set(moved.slots(on: target) + [session.slot], on: target)
        return !PlanMoveAdvisor.createsBackToBack(moved, around: target)
      }
  }

  /// Nach Krankheit: Erholung höchstens „locker“ für die nächsten Tage.
  public static func cappedRecovery(_ level: RecoveryLevel?, sickDay: CalendarDay?, today: CalendarDay)
    -> RecoveryLevel?
  {
    guard let sickDay, sickDay <= today, sickDay.days(until: today) <= illnessEasyDays else { return level }
    if level == .pause { return .pause }
    return .locker
  }
}

/// Training ohne Uhr nachtragen (Schwimmen im Urlaub, Fußball): Belastung aus Dauer × Anstrengung (sRPE,
/// Foster et al. 2001), auf die Größenordnung der Garmin-Belastung skaliert.
public enum ManualActivity {
  /// Eigener ID-Bereich unterhalb der Apple-Health-IDs.
  public static let idOffset: Int64 = 1 << 62

  public static func isManual(_ id: Int64) -> Bool { id < -idOffset }

  public static func make(
    sport: TrainingSport, start: Date, minutes: Int, effort: Int, name: String? = nil, timeZone: TimeZone = .current
  ) -> GarminActivity {
    let id = -idOffset - Int64(start.timeIntervalSince1970 / 60) - 1
    var activity = GarminActivity(id: id)
    activity.typeKey = typeKey(sport)
    activity.name = name.flatMap { $0.isEmpty ? nil : $0 } ?? "\(sport.label) (nachgetragen)"
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    activity.startLocal = formatter.string(from: start)
    activity.durationSeconds = Double(max(minutes, 1) * 60)
    activity.trainingLoad = estimatedLoad(minutes: minutes, effort: effort)
    return activity
  }

  /// sRPE = Minuten × Anstrengung (1–10); geteilt durch 4 liegt es grob in der Spanne der Garmin-Belastung.
  public static func estimatedLoad(minutes: Int, effort: Int) -> Double {
    Double(max(minutes, 0) * min(max(effort, 1), 10)) / 4
  }

  static func typeKey(_ sport: TrainingSport) -> String {
    switch sport {
    case .run: "running"
    case .bike: "cycling"
    case .swim: "lap_swimming"
    case .strength: "strength_training"
    case .other: "other"
    }
  }
}
