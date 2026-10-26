import Foundation

/// Wochenrahmen je Phase (`coach_days.jinja` im Altbestand, Stand 14.10.2026): feste Bausteine je Wochentag und
/// Bausteine ohne festen Tag.
public struct WeekFrame: Equatable, Sendable {
  public enum Block: String, Sendable {
    case push, pull, pp, swimlegs, rest
    /// Zwift am Wochenende
    case zwift = "z"
    /// Longrun am Wochenende
    case longRun = "l"
    /// Lange Radeinheit am Wochenende
    case longRide = "zlong"
    /// Zwift-Intervall unter der Woche
    case zwiftInterval = "zi"
    /// Qualitätslauf
    case quality = "q"
    /// Z2-Lauf
    case easy = "e"
  }

  /// Wochentag (0 = Montag) → Bausteine
  public var fixed: [Int: [Block]]
  public var flex: [Block]

  public static func frame(for phase: String) -> WeekFrame {
    let gym: [Int: [Block]] = [0: [.push], 1: [.swimlegs], 2: [.pull], 3: [.swimlegs], 4: [.pp]]
    func with(_ weekend: [Block]) -> [Int: [Block]] {
      gym.merging([5: weekend, 6: weekend]) { _, new in new }
    }
    switch phase {
    case "Marathon-Aufbau", "Marathon-Taper":
      return WeekFrame(fixed: with([.zwift, .longRun]), flex: [.quality, .easy])
    case "Regeneration":
      return WeekFrame(
        fixed: [0: [.rest], 1: [.swimlegs], 2: [.rest], 3: [.swimlegs], 4: [.rest], 5: [.zwift], 6: [.zwift]],
        flex: [.easy])
    case "Almere-Aufbau", "Almere-Peak", "Almere-Taper":
      return WeekFrame(fixed: with([.longRide]), flex: [.quality, .easy, .zwiftInterval])
    default:
      return WeekFrame(fixed: with([.zwift]), flex: [.quality, .easy])
    }
  }
}

/// Die Tagesansicht wie `coach_today()` im Altbestand: heutige Einheiten mit Hinweis je Einheit, offene Läufe ohne
/// festen Tag, Ausfälle am letzten Wochentag und der Rest der Woche. Eine Quelle für alle Hinweise – Karte und
/// Mitteilung zeigen nur an, was hier steht.
public struct TodayPlan: Equatable, Sendable {
  public enum Sport: String, Sendable {
    case swim, bike, run, strength, rest
  }

  public struct Item: Equatable, Sendable, Identifiable {
    public var sport: Sport
    public var title: String
    public var caption: String
    public var detail: String
    public var done: Bool
    /// 2 = hart (Qualität, Test, Intervall) · 1 = gemischt · 0 = locker
    public var hardness: Int
    /// Hinweis bei gelber/roter Tagesampel, z. B. „nicht heute“ oder „⅓ weniger Sätze“
    public var chip: String
    /// Wochentag im Rest der Woche („Do“, „Sa/So“)
    public var day: String?
    public var id: String { "\(day ?? "")-\(sport.rawValue)-\(title)" }
  }

  /// Was diese Woche schon erledigt ist.
  public struct Done: Equatable, Sendable {
    public var swim = 0
    public var run = 0
    public var bike = 0
    public var strength = 0
    public init(swim: Int = 0, run: Int = 0, bike: Int = 0, strength: Int = 0) {
      self.swim = swim
      self.run = run
      self.bike = bike
      self.strength = strength
    }
  }

  public static let dayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

  public var phase: String
  public var focus: String
  public var weekIndex: Int
  public var weekCount: Int
  public var daysLeft: Int
  public var items: [Item]
  public var open: [Item]
  public var skipped: [Item]
  public var rest: [Item]
  public var hint: String
  public var advice: String

  /// - Parameters:
  ///   - level: Tagesampel (`nil` = keine Werte)
  ///   - gymDays: Tage mit Krafteinheit (Garmin oder App)
  ///   - runZones: Intensitätsverteilung der Läufe dieser Woche (Uhr-Zonen)
  public init(
    schedule: SeasonSchedule, config: SeasonConfig, decisions: CompetitionDecisions, today: CalendarDay,
    level: RecoveryLevel?, advice recommendationAdvice: String, done: Done, gymDays: Set<CalendarDay>,
    runZones: IntensityShare?
  ) {
    let weekday = today.weekdayIndex
    let monday = today.adding(days: -weekday)
    let daysLeft = 6 - weekday
    self.daysLeft = daysLeft
    weekCount = schedule.weeks.count
    var items: [Item] = []
    var open: [Item] = []
    var rest: [Item] = []
    var hint = ""

    guard let index = schedule.weeks.firstIndex(where: { $0.monday == monday }) else {
      phase = ""
      focus = ""
      weekIndex = 0
      self.items = []
      self.open = []
      skipped = []
      self.rest = []
      self.hint = ""
      advice = recommendationAdvice
      return
    }
    let week = FilledWeek(schedule.weeks[index], config: config, decisions: decisions)
    let frame = WeekFrame.frame(for: week.phase)
    phase = week.phase
    focus = week.focus
    weekIndex = index + 1
    let gymToday = gymDays.contains(today)
    let gymTuesday = weekday > 1 && gymDays.contains(today.adding(days: -(weekday - 1)))
    let zwiftCode = week.zwiftCode

    func item(_ sport: Sport, _ title: String, _ caption: String, _ detail: String, done: Bool = false, hard: Int = 0)
      -> Item
    {
      Item(sport: sport, title: title, caption: caption, detail: detail, done: done, hardness: hard, chip: "")
    }

    for block in frame.fixed[weekday] ?? [] {
      switch block {
      case .push, .pull, .pp:
        items.append(item(.strength, Self.gymTitle(block), "Home-Gym", "", done: gymToday))
      case .rest:
        items.append(item(.rest, "Ruhetag", "Spazieren, Mobility", ""))
      case .swimlegs:
        if gymToday {
          let detail =
            done.swim >= 1
            ? "" : (weekday == 1 ? "Schwimmen dann am Donnerstag." : "Schwimmen fehlt diese Woche noch.")
          items.append(item(.strength, "Beine", "vor der Arbeit", detail, done: true))
        } else if weekday == 1, done.swim >= 1 {
          items.append(item(.swim, "Schwimmen", week.swimCode, "Beine dann am Donnerstag.", done: true))
        } else if weekday == 1 {
          items.append(item(.swim, "Schwimmen oder Beine", week.swimCode, week.swim + " · Das andere am Donnerstag."))
        } else if gymTuesday, done.swim >= 1 {
          items.append(item(.swim, "Schwimmen", week.swimCode, "Beine am Dienstag erledigt.", done: true))
        } else if gymTuesday {
          items.append(item(.swim, "Schwimmen", week.swimCode, week.swim + " · Beine am Dienstag erledigt."))
        } else if done.swim >= 1 {
          items.append(item(.strength, "Beine", "vor der Arbeit", "Schwimmen ist diese Woche schon erledigt."))
        } else {
          items.append(
            item(
              .swim, "Schwimmen", week.swimCode,
              week.swim + " · Beine nur, falls sie am Dienstag ausgefallen sind."))
        }
      case .zwift:
        let title = weekday == 6 && done.bike >= 1 ? "Zwift – diese Woche schon erledigt" : "Zwift (Sa oder So)"
        items.append(item(.bike, title, zwiftCode, week.zwift, done: done.bike >= 1))
      case .longRun where done.run < 3:
        let isOpen = week.longRunDecision == .open
        let caption = week.longRunKilometers + (isOpen ? " · 🏁 Wettkampf-Abschnitt offen" : "")
        let detail = week.longRun + (isOpen ? " · Bei Ablehnen stattdessen: \(week.longRunAlternative)" : "")
        items.append(item(.run, "Longrun (Sa oder So)", caption, detail))
      case .longRide where !week.zwift2.isEmpty:
        let weekend = week.zwift2.hasPrefix("Sa") || week.zwift2.hasPrefix("So")
        items.append(
          item(
            .bike, weekend ? "Lange Radeinheit (Sa oder So)" : "Rad", "",
            weekend ? String(week.zwift2.dropFirst(4)) : week.zwift2, done: done.bike >= 2))
      default:
        break
      }
    }

    let hasQuality = week.quality != "–"
    let openRuns = max((hasQuality ? 2 : 1) - done.run, 0)
    let qualityOpen = week.qualityDecision == .open
    let qualityItem = item(
      .run, "Qualitätslauf",
      week.qualityCode + (qualityOpen ? " · Wettkampf: im Reiter Plan annehmen oder ablehnen" : ""),
      week.quality + (qualityOpen ? " · Bei Ablehnen stattdessen: \(week.qualityAlternative)" : ""), hard: 2)
    let easyItem = item(.run, "Lockerer Lauf (Z2)", week.easyShort, week.easy)
    if openRuns > 0, frame.flex.contains(.quality) || frame.flex.contains(.easy) {
      if openRuns >= 2 {
        open += [qualityItem, easyItem]
      } else if hasQuality {
        // Welcher Lauf fehlt, verrät die HF-Verteilung der Woche: überwiegend locker → Qualität fehlt.
        if let zones = runZones, zones.easyPercent >= 80 {
          open.append(qualityItem)
        } else if let zones = runZones, zones.moderatePercent + zones.hardPercent >= 40 {
          open.append(easyItem)
        } else {
          open.append(
            item(
              .run, "Noch 1 Lauf", week.qualityCode + " oder Z2 – je nachdem, was fehlt",
              "Qualität: \(week.quality) · Z2: \(week.easy)", hard: 1))
        }
      } else {
        open.append(easyItem)
      }
    }
    if frame.flex.contains(.zwiftInterval), done.bike < 1, weekday < 5 {
      open.append(item(.bike, "Zwift-Intervall", zwiftCode, week.zwift, hard: 2))
    }
    if [1, 3].contains(weekday), open.contains(where: { $0.sport == .run && $0.hardness >= 1 }) {
      hint = "Qualitätslauf nicht am Tag nach Beine und nicht direkt vor dem Longrun."
    }

    // Rest der Woche: alle noch kommenden Einheiten mit festem Tag.
    let legsTuesday = weekday >= 1 && gymDays.contains(today.adding(days: -(weekday - 1)))
    var weekendZwift = false
    var weekendLongRun = false
    var weekendLongRide = false
    for day in (weekday + 1)..<7 {
      for block in frame.fixed[day] ?? [] {
        var entry: Item?
        switch block {
        case .push, .pull, .pp:
          entry = item(.strength, Self.gymTitle(block), "Home-Gym", "")
          entry?.day = Self.dayNames[day]
        case .swimlegs where day == 1:
          entry = item(.swim, "Schwimmen oder Beine", week.swimCode + " · das andere am Donnerstag", week.swim)
          entry?.day = "Di"
        case .swimlegs where day == 3:
          let swimLeft = done.swim < 1
          let legsLeft = !(legsTuesday || (weekday == 1 && gymToday))
          if weekday < 1 {
            entry = item(.strength, "Beine oder Schwimmen", "was am Dienstag nicht dran war", "")
          } else if swimLeft, legsLeft {
            entry = item(.swim, "Schwimmen oder Beine", week.swimCode + " · Schwimmen hat Vorrang", week.swim)
          } else if swimLeft {
            entry = item(.swim, "Schwimmen", week.swimCode, week.swim)
          } else if legsLeft {
            entry = item(.strength, "Beine", "vor der Arbeit", "")
          }
          entry?.day = "Do"
        case .zwift where weekday < 5 && !weekendZwift && done.bike < 1:
          weekendZwift = true
          entry = item(.bike, "Zwift", zwiftCode, week.zwift)
          entry?.day = "Sa/So"
        case .longRun where weekday < 5 && !weekendLongRun && done.run < 3:
          weekendLongRun = true
          entry = item(.run, "Longrun", week.longRunKilometers, week.longRun)
          entry?.day = "Sa/So"
        case .longRide where weekday < 5 && !weekendLongRide && !week.zwift2.isEmpty && done.bike < 2:
          weekendLongRide = true
          entry = item(.bike, "Lange Radeinheit", "", week.zwift2)
          entry?.day = "Sa/So"
        default:
          break
        }
        if let entry { rest.append(entry) }
      }
    }

    // Hinweise je Einheit
    var skipped: [Item] = []
    self.items = items.map { item in
      var item = item
      item.chip = Self.chip(level: level, item: item, isOpen: false, daysLeft: daysLeft)
      return item
    }
    self.open = open.compactMap { item in
      var item = item
      let chip = Self.chip(level: level, item: item, isOpen: true, daysLeft: daysLeft)
      if chip == "skip" {
        skipped.append(item)
        return nil
      }
      item.chip = chip
      return item
    }
    self.skipped = skipped
    self.rest = rest
    self.hint = hint

    let fixed = items.filter { $0.sport != .rest }
    let allDone = !fixed.isEmpty && fixed.allSatisfy(\.done)
    if allDone, level == .locker {
      advice = "Geplante Einheit erledigt – heute nichts Hartes mehr nachlegen."
    } else if allDone, level == .pause {
      advice = "Geplante Einheit erledigt – den Rest des Tages erholen."
    } else {
      advice = recommendationAdvice
    }
  }

  static func gymTitle(_ block: WeekFrame.Block) -> String {
    switch block {
    case .push: "Push"
    case .pull: "Pull"
    default: "Push + Pull"
    }
  }

  /// Hinweis je Einheit (`_chip` im Altbestand). „skip“: Die Einheit kann diese Woche nicht mehr stattfinden.
  static func chip(level: RecoveryLevel?, item: Item, isOpen: Bool, daysLeft: Int) -> String {
    guard let level, level != .normal, !item.done, item.sport != .rest else { return "" }
    if !isOpen {
      if level == .pause { return "nur locker bewegen" }
      return item.sport == .strength ? "⅓ weniger Sätze" : "locker / kürzer"
    }
    if item.hardness == 0 { return "" }
    if level == .locker, item.hardness == 1 { return "heute nur Z2" }
    return daysLeft > 0 ? "nicht heute" : "skip"
  }
}

/// Eine Planwoche mit eingesetzten Testwerten und Wettkampf-Entscheidungen (wie `coach_plan()` im Altbestand).
struct FilledWeek {
  let phase: String
  let focus: String
  let zwift: String
  let zwift2: String
  let swim: String
  let swimCode: String
  let quality: String
  let qualityCode: String
  let qualityAlternative: String
  let qualityDecision: PlannedUnit.Decision?
  let easy: String
  let longRun: String
  let longRunAlternative: String
  let longRunDecision: PlannedUnit.Decision?
  let longRunKm: Double

  init(_ week: PlanWeek, config: SeasonConfig, decisions: CompetitionDecisions) {
    let tokens = PlanTokens(config: config)
    phase = week.ph
    focus = week.f
    zwift = tokens.fill(week.z)
    zwift2 = tokens.fill(week.z2)
    swim = tokens.fill(week.s)
    swimCode = week.sc
    easy = tokens.fill(week.e)
    longRunKm = week.lr

    let qualityKey = SeasonSchedule.decisionKey(week: week, kind: .quality)
    let qualityChoice = week.qw != nil ? decisions[qualityKey] ?? .open : nil
    qualityDecision = qualityChoice
    qualityAlternative = tokens.fill(week.qa ?? "")
    if qualityChoice == .rejected {
      quality = tokens.fill(week.qa ?? week.q)
      qualityCode = week.qca ?? week.qc
    } else {
      quality = tokens.fill(week.q)
      qualityCode = qualityChoice == nil ? week.qc : "🏁 " + week.qc
    }

    let longKey = SeasonSchedule.decisionKey(week: week, kind: .longRun)
    let longChoice = week.lw != nil ? decisions[longKey] ?? .open : nil
    longRunDecision = longChoice
    longRunAlternative = tokens.fill(week.la ?? "")
    if longChoice == .rejected {
      longRun = tokens.fill(week.la ?? week.l)
    } else {
      longRun = (longChoice == nil ? "" : "🏁 ") + tokens.fill(week.l)
    }
  }

  /// „Z03 Sweet Spot 2×20“ ohne „RAMP “
  var zwiftCode: String {
    String(zwift.split(separator: ":", maxSplits: 1).first ?? "").replacingOccurrences(of: "RAMP ", with: "")
  }

  var easyShort: String {
    easy.components(separatedBy: " (").first ?? easy
  }

  var longRunKilometers: String {
    guard longRunKm > 0 else { return "" }
    let text =
      longRunKm == longRunKm.rounded()
      ? String(Int(longRunKm)) : String(longRunKm).replacingOccurrences(of: ".", with: ",")
    return text + " km"
  }
}
