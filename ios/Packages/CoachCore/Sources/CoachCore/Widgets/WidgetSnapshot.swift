import Foundation

/// Was die Homescreen-Widgets zeigen. Die App schreibt den Stand in die App Group (nach Abruf, beim Verlassen,
/// im Hintergrund), die Widgets lesen nur diese Datei – kein Zugriff auf die Datenbank der App. Werte sind schon
/// formatiert bzw. fertig berechnet; die Widgets rechnen nur Tageswechsel und wartende Wasser-Einträge ein.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
  public static let fileName = "widget-snapshot.json"
  public static let currentVersion = 1

  public var version: Int
  public var createdAt: Date
  /// Tag, für den die Werte gelten.
  public var day: CalendarDay
  public var today: Today
  public var nutrition: Nutrition?
  /// `nil` ohne Krafttraining im Profil.
  public var gym: Gym?
  /// Gesundheitswerte der letzten Nacht in fester Reihenfolge (nur Metriken des Morning Reports).
  public var health: [Health]
  /// Tages-Serie (`DailyStreak`); fehlt in älteren Ständen.
  public var streak: Streak?
  /// Serie der Mahlzeiten: nur Tage mit eingetragener Mahlzeit, lückenlos (ohne Joker, ohne Training von der Uhr).
  /// Für die Mahlzeiten- und Ernährungs-Anzeigen; fehlt in älteren Ständen.
  public var mealStreak: Streak?

  public init(
    createdAt: Date, day: CalendarDay, today: Today, nutrition: Nutrition?, gym: Gym?, health: [Health]
  ) {
    version = Self.currentVersion
    self.createdAt = createdAt
    self.day = day
    self.today = today
    self.nutrition = nutrition
    self.gym = gym
    self.health = health
  }

  /// Tage in Folge mit Training oder Mahlzeit, für die Kopfzeile der Widgets.
  public struct Streak: Codable, Equatable, Sendable {
    public var days: Int
    /// Heute ist schon etwas erfasst.
    public var activeToday: Bool

    public init(days: Int, activeToday: Bool) {
      self.days = days
      self.activeToday = activeToday
    }

    /// Kurzer Satz zur Serie. Kein Druck: Ohne Eintrag heute steht nur, was die Serie fortsetzt.
    public var headline: String {
      if days <= 0 { return "Heute starten – erster Tag!" }
      if !activeToday { return "Heute noch etwas erfassen" }
      if isRunning { return "Serie läuft – weiter so!" }
      return "Guter Start – dranbleiben!"
    }

    /// Erst ab drei Tagen in Folge und mit Eintrag heute ist es eine laufende Serie.
    public var isRunning: Bool { days >= 3 && activeToday
    }
  }

  public struct Today: Codable, Equatable, Sendable {
    /// Tagesampel; `nil` ohne Erholungswerte.
    public var level: RecoveryLevel?
    public var headline: String
    public var sessions: [Session]
    /// „3/5 Einheiten · 140/210 min“
    public var week: String?
    public var weekFraction: Double?

    public init(
      level: RecoveryLevel?, headline: String, sessions: [Session] = [], week: String? = nil,
      weekFraction: Double? = nil
    ) {
      self.level = level
      self.headline = headline
      self.sessions = sessions
      self.week = week
      self.weekFraction = weekFraction
    }

    /// Erste noch offene Einheit des Tages.
    public var nextSession: Session? { sessions.first { !$0.done } }
  }

  public struct Session: Codable, Equatable, Sendable {
    public var title: String
    public var target: String
    public var done: Bool
    /// SF-Symbol der Sportart.
    public var symbol: String

    public init(title: String, target: String, done: Bool, symbol: String) {
      self.title = title
      self.target = target
      self.done = done
      self.symbol = symbol
    }
  }

  public struct Nutrition: Codable, Equatable, Sendable {
    public var kcal: Double
    /// `nil`, wenn kein Ziel berechnet werden konnte (fehlendes Profil).
    public var kcalTarget: Double?
    public var protein: Double
    public var proteinTarget: Double?
    public var waterMilliliters: Double
    public var waterTarget: Double?
    public var lastMeal: LastMeal?
    /// kcal je Mahlzeit (Frühstück, Mittag, Abend, Snacks); `nil` bei Ständen von vor dem Mahlzeiten-Widget.
    public var meals: [MealPart]?

    public init(
      kcal: Double, kcalTarget: Double?, protein: Double, proteinTarget: Double?, waterMilliliters: Double,
      waterTarget: Double?, lastMeal: LastMeal?, meals: [MealPart]? = nil
    ) {
      self.kcal = kcal
      self.kcalTarget = kcalTarget
      self.protein = protein
      self.proteinTarget = proteinTarget
      self.waterMilliliters = waterMilliliters
      self.waterTarget = waterTarget
      self.lastMeal = lastMeal
      self.meals = meals
    }

    /// Übrig (negativ = darüber); `nil` ohne Ziel.
    public var kcalRemaining: Double? { kcalTarget.map { $0 - kcal } }

    public var kcalFraction: Double? { Self.fraction(kcal, kcalTarget) }
    public var proteinFraction: Double? { Self.fraction(protein, proteinTarget) }
    public var waterFraction: Double? { Self.fraction(waterMilliliters, waterTarget) }

    static func fraction(_ value: Double, _ target: Double?) -> Double? {
      guard let target, target > 0 else { return nil }
      return min(max(value / target, 0), 1)
    }
  }

  /// Eine Mahlzeit im Mahlzeiten-Widget: gegessen und Richtwert (Anteil am Tagesziel, `MealSplit`).
  public struct MealPart: Codable, Equatable, Sendable, Identifiable {
    public var category: MealCategory
    public var kcal: Double
    public var target: Double?
    public var id: MealCategory { category }

    public init(category: MealCategory, kcal: Double, target: Double?) {
      self.category = category
      self.kcal = kcal
      self.target = target
    }

    public var fraction: Double? { Nutrition.fraction(kcal, target) }
  }

  public struct LastMeal: Codable, Equatable, Sendable {
    public var title: String
    public var at: Date
    public var kcal: Double

    public init(title: String, at: Date, kcal: Double) {
      self.title = title
      self.at = at
      self.kcal = kcal
    }
  }

  public struct Gym: Codable, Equatable, Sendable {
    /// Nächste geplante Einheit (Routine bzw. Einheit laut Plan).
    public var next: String?
    public var nextDetail: String?
    /// Eine Einheit läuft (mindestens ein Satz).
    public var running: Bool
    public var runningTitle: String?
    public var last: LastSession?
    public var weekDone: Int
    /// Geplante Krafteinheiten dieser Woche; `nil`, wenn der Plan keine Zahl hergibt.
    public var weekPlanned: Int?
    /// `next` gehört zu genau diesem Tag (Plan-Einheit statt Routine) und gilt am Folgetag nicht mehr.
    public var nextIsForDay: Bool?

    public init(
      next: String?, nextDetail: String?, running: Bool, runningTitle: String?, last: LastSession?, weekDone: Int,
      weekPlanned: Int?
    ) {
      self.next = next
      self.nextDetail = nextDetail
      self.running = running
      self.runningTitle = runningTitle
      self.last = last
      self.weekDone = weekDone
      self.weekPlanned = weekPlanned
    }

    /// „2/3 diese Woche“ bzw. „2 diese Woche“.
    public var weekText: String {
      weekPlanned.map { "\(weekDone)/\($0) diese Woche" } ?? "\(weekDone) diese Woche"
    }
  }

  public struct LastSession: Codable, Equatable, Sendable {
    public var title: String
    public var day: CalendarDay
    public var sets: Int
    public var volumeKg: Double

    public init(title: String, day: CalendarDay, sets: Int, volumeKg: Double) {
      self.title = title
      self.day = day
      self.sets = sets
      self.volumeKg = volumeKg
    }
  }

  public struct Health: Codable, Equatable, Sendable {
    public var metric: HealthMetric
    /// Formatiert („7,4 h“, „62 ms“); `nil` = kein Wert.
    public var value: String?
    /// Zahl für Ringe (Body Battery 0–100); sonst `nil`.
    public var gauge: Double?
    public var status: MorningReport.Status
    public var note: String

    public init(metric: HealthMetric, value: String?, gauge: Double?, status: MorningReport.Status, note: String) {
      self.metric = metric
      self.value = value
      self.gauge = gauge
      self.status = status
      self.note = note
    }
  }

  public func health(_ metric: HealthMetric) -> Health? {
    health.first { $0.metric == metric }
  }
}

/// Gesundheitswerte, die ein Widget zeigen kann – die Kernwerte des Morning Reports.
public enum HealthMetric: String, Codable, CaseIterable, Sendable {
  case bodyBattery, sleep, hrv, recovery, restingHeartRate, stress

  public var title: String {
    switch self {
    case .bodyBattery: "Body Battery"
    case .sleep: "Schlaf"
    case .hrv: "HRV"
    case .recovery: "Recovery"
    case .restingHeartRate: "Ruhepuls"
    case .stress: "Stress"
    }
  }

  public var symbol: String {
    switch self {
    case .bodyBattery: "battery.75percent"
    case .sleep: "bed.double.fill"
    case .hrv: "waveform.path.ecg"
    case .recovery: "arrow.clockwise.heart"
    case .restingHeartRate: "heart.fill"
    case .stress: "brain.head.profile"
    }
  }

  /// Entsprechender Wert im Morning Report.
  public var reportMetric: MorningReport.Metric {
    switch self {
    case .bodyBattery: .bodyBattery
    case .sleep: .sleepDuration
    case .hrv: .hrv
    case .recovery: .recovery
    case .restingHeartRate: .restingHeartRate
    case .stress: .stress
    }
  }
}

// MARK: - Anzeige

extension WidgetSnapshot {
  /// Stand für die Anzeige an `day`: Am neuen Tag ist nichts gegessen und nichts geplant bekannt (keine Schätzung –
  /// das Widget bittet ums Öffnen der App); Gesundheitswerte gelten ab dem Folgetag als alt. Wartende
  /// Wasser-Einträge aus dem Widget zählen sofort mit.
  public func display(on day: CalendarDay, queue: WidgetActionQueue = WidgetActionQueue()) -> Display {
    var snapshot = self
    let isCurrent = day == self.day
    if !isCurrent {
      // Am Folgetag läuft die Serie weiter, heute ist aber noch nichts erfasst; älter ist sie unbekannt.
      if day == self.day.adding(days: 1) {
        snapshot.streak?.activeToday = false
        snapshot.mealStreak?.activeToday = false
      } else {
        snapshot.streak = nil
        snapshot.mealStreak = nil
      }
      snapshot.today = Today(level: nil, headline: "Neuer Tag – App öffnen")
      snapshot.nutrition = nutrition.map { _ in
        Nutrition(
          kcal: 0, kcalTarget: nil, protein: 0, proteinTarget: nil, waterMilliliters: 0, waterTarget: nil,
          lastMeal: nil, meals: MealSplit.order.map { MealPart(category: $0, kcal: 0, target: nil) })
      }
      if var gym = snapshot.gym {
        gym.running = false
        gym.runningTitle = nil
        if gym.nextIsForDay == true {
          gym.next = "App öffnen"
          gym.nextDetail = nil
        }
        // Neue Woche: Zählung beginnt von vorn.
        if day.adding(days: -day.weekdayIndex) != self.day.adding(days: -self.day.weekdayIndex) { gym.weekDone = 0 }
        snapshot.gym = gym
      }
    }
    let pendingWater = queue.water(on: day)
    if pendingWater > 0, var nutrition = snapshot.nutrition {
      nutrition.waterMilliliters += pendingWater
      snapshot.nutrition = nutrition
    }
    return Display(snapshot: snapshot, isCurrent: isCurrent, healthIsOld: day > self.day)
  }

  public struct Display: Equatable, Sendable {
    public var snapshot: WidgetSnapshot
    /// Stand ist von heute.
    public var isCurrent: Bool
    /// Gesundheitswerte stammen nicht von der letzten Nacht: Der Stand ist von einem früheren Tag.
    public var healthIsOld: Bool
  }
}

/// Aktionen aus interaktiven Widgets, die die App beim nächsten Öffnen übernimmt (das Widget kann die Datenbank
/// der App nicht schreiben). Heute nur Wasser.
public struct WidgetActionQueue: Codable, Equatable, Sendable {
  public static let fileName = "widget-actions.json"
  /// Ältere Einträge verfallen (App lange nicht geöffnet) statt Tage später aufzutauchen.
  public static let maxAgeDays = 7

  public struct Entry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var day: CalendarDay
    public var at: Date
    public var waterMilliliters: Double

    public init(id: UUID = UUID(), day: CalendarDay, at: Date, waterMilliliters: Double) {
      self.id = id
      self.day = day
      self.at = at
      self.waterMilliliters = waterMilliliters
    }
  }

  public var entries: [Entry]

  public init(entries: [Entry] = []) {
    self.entries = entries
  }

  public mutating func addWater(_ milliliters: Double, at date: Date) {
    guard milliliters > 0, milliliters.isFinite else { return }
    entries.append(Entry(day: CalendarDay(date: date), at: date, waterMilliliters: milliliters))
  }

  public func water(on day: CalendarDay) -> Double {
    entries.filter { $0.day == day }.reduce(0) { $0 + $1.waterMilliliters }
  }

  /// Einträge, die die App übernehmen soll (nicht älter als `maxAgeDays`).
  public func pending(today: CalendarDay) -> [Entry] {
    let oldest = today.adding(days: -Self.maxAgeDays)
    return entries.filter { $0.day >= oldest && $0.day <= today }
  }

  /// Nach dem Übernehmen: genau diese Einträge entfernen (später hinzugekommene bleiben).
  public mutating func remove(_ ids: Set<UUID>) {
    entries.removeAll { ids.contains($0.id) }
  }
}

// MARK: - Aufbau aus den Auswertungen der App

extension WidgetSnapshot {
  /// Gesundheitswerte aus dem Morning Report; Body Battery zusätzlich als Zahl für den Ring.
  public static func health(from report: MorningReport, bodyBattery: Double?) -> [Health] {
    HealthMetric.allCases.compactMap { metric in
      guard let item = report.items.first(where: { $0.metric == metric.reportMetric }) else { return nil }
      let gauge = metric == .bodyBattery && item.status != .missing ? bodyBattery : nil
      return Health(metric: metric, value: item.value, gauge: gauge, status: item.status, note: item.note)
    }
  }

  /// Ernährung des Tages aus Zielen und Summen; Wasser zählt mit, die letzte Mahlzeit ohne reines Wasser.
  public static func nutrition(
    targets: NutrientValues?, totals: NutrientValues, water: Double, lastMeal: LastMeal?,
    mealKilocalories: [MealCategory: Double] = [:]
  ) -> Nutrition {
    let meals = MealSplit.order.map { category in
      MealPart(
        category: category, kcal: (mealKilocalories[category] ?? 0).rounded(),
        target: MealSplit.target(category, dayKilocalories: targets?[.kcal]))
    }
    return Nutrition(
      kcal: totals[.kcal] ?? 0, kcalTarget: targets?[.kcal], protein: totals[.protein] ?? 0,
      proteinTarget: targets?[.protein], waterMilliliters: water, waterTarget: targets?[.water], lastMeal: lastMeal,
      meals: meals)
  }
}

/// Liest die App Groups aus dem eingebetteten Provisioning-Profil (`embedded.mobileprovision`). SideStore hängt bei
/// kostenlosen Konten die Team-ID an (`group.<id>.<TEAMID>`), die App kennt sie also nicht im Voraus.
public enum AppGroupProfile {
  /// Gruppe, die App und Widgets teilen (wie in `project.yml`).
  public static let baseIdentifier = "group.io.github.hkrb7p794w.coach"
  static let entitlementKey = "com.apple.security.application-groups"

  /// Gruppen aus dem Profil (eine CMS-Signatur um eine XML-Plist).
  public static func groups(fromProfile data: Data) -> [String] {
    guard let start = data.range(of: Data("<?xml".utf8)),
      let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
    else { return [] }
    let plist = data.subdata(in: start.lowerBound..<end.upperBound)
    guard
      let root = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any],
      let entitlements = root["Entitlements"] as? [String: Any]
    else { return [] }
    return entitlements[entitlementKey] as? [String] ?? []
  }

  /// Kandidaten in der Reihenfolge der Prüfung: passende Gruppen aus dem Profil (kürzeste zuerst), dann die
  /// unveränderte ID (normale Signatur, Simulator).
  public static func candidates(profileGroups: [String], base: String = baseIdentifier) -> [String] {
    let matching = profileGroups.filter { $0 == base || $0.hasPrefix(base + ".") }
      .sorted { ($0.count, $0) < ($1.count, $1) }
    return matching + (matching.contains(base) ? [] : [base])
  }
}
