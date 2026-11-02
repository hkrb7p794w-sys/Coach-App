import Foundation

/// Morning Report: die wichtigsten Werte der Nacht, eingeordnet gegen den eigenen Normalbereich, mit einer
/// Empfehlung nach festen Regeln (`RecoveryEvaluator` plus persönliche Abweichungen). Fehlende Werte werden genannt,
/// nie geschätzt; mit wenigen Daten bleibt der Bericht kurz und sagt das.
public struct MorningReport: Equatable, Sendable {
  public enum Status: String, Equatable, Sendable {
    case good, normal, attention, missing
  }

  public enum Metric: String, CaseIterable, Sendable {
    case sleepDuration, sleepQuality, sleepStages, restingHeartRate, hrv, stress, bodyBattery, recovery, load

    public var title: String {
      switch self {
      case .sleepDuration: "Schlafdauer"
      case .sleepQuality: "Schlafqualität"
      case .sleepStages: "Schlafphasen"
      case .restingHeartRate: "Ruhepuls"
      case .hrv: "HRV"
      case .stress: "Stress"
      case .bodyBattery: "Body Battery"
      case .recovery: "Erholung"
      case .load: "Trainingsbelastung"
      }
    }
  }

  public struct Item: Equatable, Sendable, Identifiable {
    public var metric: Metric
    public var value: String?
    public var status: Status
    /// Einordnung in einem Satz („2 bpm über deinem üblichen Bereich“).
    public var note: String
    public var id: String { metric.rawValue }
    public var title: String { metric.title }
  }

  /// Geplante Einheit des Tages (aus „Jetzt dran“).
  public struct Session: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var target: String
    public var demanding: Bool

    public init(id: String, title: String, target: String, demanding: Bool) {
      self.id = id
      self.title = title
      self.target = target
      self.demanding = demanding
    }
  }

  public var day: CalendarDay
  /// Tag der Werte; `day − 1`, wenn heute noch nichts synchronisiert ist.
  public var dataDay: CalendarDay?
  public var items: [Item]
  /// `nil` = zu wenig Daten für eine Empfehlung.
  public var level: RecoveryLevel?
  public var headline: String
  /// Auffälligkeiten als kurze Sätze.
  public var findings: [String]
  public var recommendation: String
  public var sleepAdvice: String?
  public var sessions: [Session]
  /// Werte, die heute fehlen.
  public var missing: [String]

  public var isFromYesterday: Bool { dataDay.map { $0 < day } ?? false }

  /// Ab so vielen persönlichen Auffälligkeiten mindestens „locker“, auch wenn keine Einzelregel greift.
  public static let attentionForEasy = 2

  public static func make(
    days: [DailyMetrics], today: CalendarDay, sleep: SleepSettings, goal: FitnessGoal? = nil,
    sessions: [Session] = [], form: FitnessForm.Point? = nil
  ) -> MorningReport {
    let sorted = days.sorted { $0.day < $1.day }
    let metrics =
      sorted.last { $0.day == today && hasNight($0) } ?? sorted.last { $0.day == today.adding(days: -1) && hasNight($0) }
    let reference = metrics?.day ?? today
    let previous = sorted.filter { $0.day < reference }
    func norm(_ field: (DailyMetrics) -> Double?) -> PersonalNorm? {
      PersonalNorm.of(previous, today: reference, field)
    }

    var items: [Item] = []
    items.append(sleepDuration(metrics, need: sleep.targetHours, norm: norm { $0.sleepHours }))
    items.append(sleepQuality(metrics))
    items.append(sleepStages(metrics, deepNorm: norm { $0.deepSleepSeconds }))
    items.append(restingHeartRate(metrics, norm: norm { $0.restingHeartRate }))
    items.append(hrv(metrics, norm: norm { $0.hrvLastNightAverage }))
    // Stress des Vortags: der heutige Tagesschnitt ist am Morgen noch nicht aussagekräftig.
    let stressDay = sorted.last { $0.day == reference.adding(days: -1) }
    items.append(
      stress(
        stressDay?.stressAverage, sleepStress: metrics?.sleepStress,
        norm: PersonalNorm.of(sorted.filter { $0.day < reference.adding(days: -1) }, today: reference.adding(days: -1)) {
          $0.stressAverage
        }))
    items.append(
      bodyBattery(
        metrics.flatMap(BodyBatteryAnalysis.wakeValue), norm: norm(BodyBatteryAnalysis.wakeValue)))

    let restingAverage = RecoveryEvaluator.average(
      { $0.restingHeartRate }, in: sorted, daysBefore: 1...7, today: reference)
    let evaluated = metrics.map { RecoveryEvaluator.evaluate($0, restingHeartRate7DayAverage: restingAverage) }
    items.append(recovery(metrics, evaluated: evaluated))
    items.append(load(metrics, form: form))

    let measured = items.filter { $0.status != .missing && $0.metric != .recovery && $0.metric != .load }
    let attention = items.filter { $0.status == .attention }
    var level = evaluated?.level
    if measured.count < 2 {
      level = nil
    } else if attention.filter({ $0.metric != .load }).count >= attentionForEasy {
      level = max(level ?? .normal, .locker)
    }

    let findings = attention.map(\.note)
    let report = SleepCoach.report(days: sorted, settings: sleep, goal: goal, today: today)
    let sleepAdvice = report.map {
      "Heute Abend gegen \(SleepCoach.clock($0.bedtimeMinutes)) Uhr ins Bett – "
        + "\(GermanFormat.decimal(Double($0.tonightMinutes) / 60)) h Schlafbedarf bis \(SleepCoach.clock(sleep.wakeMinutes)) Uhr."
    }
    return MorningReport(
      day: today, dataDay: metrics?.day, items: items, level: level, headline: headline(level),
      findings: findings, recommendation: recommendation(level, sessions: sessions),
      sleepAdvice: sleepAdvice, sessions: sessions,
      missing: items.filter { $0.status == .missing }.map(\.title))
  }

  private static func hasNight(_ metrics: DailyMetrics) -> Bool {
    metrics.sleepSeconds != nil || metrics.restingHeartRate != nil || metrics.hrvLastNightAverage != nil
      || metrics.hrvStatus != nil || metrics.bodyBatteryAtWake != nil || metrics.bodyBatteryCurve != nil
  }

  // MARK: - Einordnung

  static func sleepDuration(_ metrics: DailyMetrics?, need: Double, norm: PersonalNorm?) -> Item {
    guard let hours = metrics?.sleepHours else {
      return Item(metric: .sleepDuration, value: nil, status: .missing, note: "Keine Schlafdaten")
    }
    let value = hoursText(hours)
    let needText = GermanFormat.decimal(need)
    if hours < need - 0.5 {
      let short = Int(((need - hours) * 60).rounded())
      return Item(
        metric: .sleepDuration, value: value, status: .attention,
        note: "Schlaf war \(short) min kürzer als dein Bedarf (\(needText) h).")
    }
    if hours >= need {
      return Item(metric: .sleepDuration, value: value, status: .good, note: "Bedarf von \(needText) h erreicht.")
    }
    let usual = norm.map { $0.position(hours) == .below ? " und kürzer als sonst" : "" } ?? ""
    return Item(
      metric: .sleepDuration, value: value, status: .normal, note: "Knapp unter deinem Bedarf\(usual).")
  }

  /// Garmin-Schlaf-Score: 90+ ausgezeichnet, 80–89 gut, 60–79 ordentlich, unter 60 schwach.
  static func sleepQuality(_ metrics: DailyMetrics?) -> Item {
    guard let score = metrics?.sleepScore else {
      return Item(metric: .sleepQuality, value: nil, status: .missing, note: "Kein Schlaf-Score")
    }
    let value = String(Int(score))
    switch score {
    case 80...: return Item(metric: .sleepQuality, value: value, status: .good, note: "Gute Schlafqualität.")
    case 60..<80: return Item(metric: .sleepQuality, value: value, status: .normal, note: "Ordentliche Schlafqualität.")
    default: return Item(metric: .sleepQuality, value: value, status: .attention, note: "Schlafqualität war schwach.")
    }
  }

  static func sleepStages(_ metrics: DailyMetrics?, deepNorm: PersonalNorm?) -> Item {
    guard let metrics, let deep = metrics.deepSleepSeconds, let rem = metrics.remSleepSeconds else {
      return Item(metric: .sleepStages, value: nil, status: .missing, note: "Keine Schlafphasen")
    }
    let value = "Tief \(durationText(deep)) · REM \(durationText(rem))"
    if let deepNorm, deepNorm.position(deep) == .below {
      return Item(metric: .sleepStages, value: value, status: .attention, note: "Weniger Tiefschlaf als sonst.")
    }
    return Item(metric: .sleepStages, value: value, status: .normal, note: "Phasen im üblichen Rahmen.")
  }

  static func restingHeartRate(_ metrics: DailyMetrics?, norm: PersonalNorm?) -> Item {
    guard let value = metrics?.restingHeartRate else {
      return Item(metric: .restingHeartRate, value: nil, status: .missing, note: "Kein Ruhepuls")
    }
    let text = "\(Int(value)) bpm"
    guard let norm else {
      return Item(
        metric: .restingHeartRate, value: text, status: .normal,
        note: "Eigener Bereich ab \(PersonalNorm.minimumDays) Tagen mit Werten.")
    }
    switch norm.position(value) {
    case .above:
      return Item(
        metric: .restingHeartRate, value: text, status: .attention,
        note: "Ruhepuls \(Int((value - norm.high).rounded(.up))) bpm über deinem üblichen Bereich.")
    case .below:
      return Item(metric: .restingHeartRate, value: text, status: .good, note: "Ruhepuls niedriger als sonst.")
    case .within:
      return Item(metric: .restingHeartRate, value: text, status: .normal, note: "Im üblichen Bereich.")
    }
  }

  /// Garmins HRV-Status (7-Tage-Schnitt gegen Baseline) zuerst, sonst die Nacht gegen den eigenen Bereich.
  static func hrv(_ metrics: DailyMetrics?, norm: PersonalNorm?) -> Item {
    let night = metrics?.hrvLastNightAverage
    let value = night.map { "\(Int($0)) ms" }
    switch metrics?.hrvStatus?.uppercased() {
    case "LOW"?, "POOR"?:
      return Item(metric: .hrv, value: value, status: .attention, note: "HRV liegt unter deinem Normalbereich.")
    case "UNBALANCED"?:
      if let weekly = metrics?.hrvWeeklyAverage, let low = metrics?.hrvBaselineLow, weekly < low {
        return Item(metric: .hrv, value: value, status: .attention, note: "HRV liegt unter deinem Normalbereich.")
      }
      return Item(metric: .hrv, value: value, status: .normal, note: "HRV unausgeglichen, aber nicht zu niedrig.")
    case "BALANCED"?:
      if let night, let low = metrics?.hrvBaselineLow, night < low {
        return Item(
          metric: .hrv, value: value, status: .normal, note: "Letzte Nacht niedrig, Wochenschnitt ausgeglichen.")
      }
      return Item(metric: .hrv, value: value, status: .good, note: "HRV ausgeglichen.")
    default:
      break
    }
    guard let night else { return Item(metric: .hrv, value: nil, status: .missing, note: "Keine HRV") }
    guard let norm else {
      return Item(
        metric: .hrv, value: value, status: .normal, note: "Eigener Bereich ab \(PersonalNorm.minimumDays) Nächten.")
    }
    switch norm.position(night) {
    case .below: return Item(metric: .hrv, value: value, status: .attention, note: "HRV liegt unter deinem Normalbereich.")
    case .within: return Item(metric: .hrv, value: value, status: .normal, note: "HRV im üblichen Bereich.")
    case .above: return Item(metric: .hrv, value: value, status: .good, note: "HRV höher als sonst.")
    }
  }

  static func stress(_ average: Double?, sleepStress: Double?, norm: PersonalNorm?) -> Item {
    guard let average else {
      if let sleepStress {
        return Item(
          metric: .stress, value: "Nacht \(Int(sleepStress))", status: .normal, note: "Stress im Schlaf.")
      }
      return Item(metric: .stress, value: nil, status: .missing, note: "Kein Stresswert")
    }
    let value = "Ø \(Int(average))"
    if let norm, norm.position(average) == .above {
      return Item(metric: .stress, value: value, status: .attention, note: "Stress gestern höher als sonst.")
    }
    // Garmin: 0–25 Ruhe, 26–50 niedrig, 51–75 mittel, 76–100 hoch.
    if average > 50 {
      return Item(metric: .stress, value: value, status: .attention, note: "Stress gestern im mittleren Bereich oder höher.")
    }
    return Item(metric: .stress, value: value, status: .normal, note: "Stress gestern im üblichen Rahmen.")
  }

  static func bodyBattery(_ wake: Double?, norm: PersonalNorm?) -> Item {
    guard let wake else {
      return Item(metric: .bodyBattery, value: nil, status: .missing, note: "Keine Body Battery (nur Garmin)")
    }
    let value = String(Int(wake))
    if let norm {
      switch norm.position(wake) {
      case .below:
        return Item(
          metric: .bodyBattery, value: value, status: .attention, note: "Body Battery ist vergleichsweise niedrig.")
      case .above:
        return Item(metric: .bodyBattery, value: value, status: .good, note: "Body Battery höher als sonst.")
      case .within:
        return Item(metric: .bodyBattery, value: value, status: .normal, note: "Body Battery im üblichen Bereich.")
      }
    }
    if wake < 26 {
      return Item(metric: .bodyBattery, value: value, status: .attention, note: "Body Battery ist niedrig.")
    }
    return Item(
      metric: .bodyBattery, value: value, status: wake >= 76 ? .good : .normal,
      note: "Body Battery \(BodyBatteryAnalysis.band(wake)).")
  }

  static func recovery(_ metrics: DailyMetrics?, evaluated: Recommendation?) -> Item {
    var parts: [String] = []
    if let readiness = metrics?.trainingReadiness { parts.append("Readiness \(Int(readiness))") }
    if let hours = metrics?.recoveryHours { parts.append(hours == 0 ? "erholt" : "noch \(Int(hours.rounded())) h") }
    guard let evaluated else {
      return Item(metric: .recovery, value: parts.first, status: .missing, note: "Keine Erholungswerte")
    }
    let status: Status =
      switch evaluated.level {
      case .normal: .good
      case .locker, .pause: .attention
      }
    let value = parts.isEmpty ? evaluated.label : parts.joined(separator: " · ")
    return Item(
      metric: .recovery, value: value, status: status,
      note: evaluated.level == .normal ? "Erholungswerte unauffällig." : "Erholung: \(evaluated.label.lowercased()).")
  }

  /// Akute zu chronischer Last der Uhr (0,8–1,3 üblich, über 1,5 deutlich mehr als gewohnt; Gabbett 2016), sonst die
  /// Form aus den eigenen Aktivitäten.
  static func load(_ metrics: DailyMetrics?, form: FitnessForm.Point?) -> Item {
    if let acute = metrics?.acuteLoad, let chronic = metrics?.chronicLoad, chronic > 0 {
      let ratio = acute / chronic
      let value = "\(Int(acute)) / \(Int(chronic))"
      if ratio > 1.5 {
        return Item(metric: .load, value: value, status: .attention, note: "Belastung deutlich über deinem Gewohnten.")
      }
      if ratio < 0.8 {
        return Item(metric: .load, value: value, status: .normal, note: "Weniger Belastung als gewohnt.")
      }
      return Item(metric: .load, value: value, status: .normal, note: "Belastung im gewohnten Rahmen.")
    }
    if let percent = form?.formPercent {
      let zone = FitnessForm.Zone.of(percent)
      return Item(
        metric: .load, value: zone.label, status: zone == .high ? .attention : .normal,
        note: zone == .high ? "Sehr hohe Belastung in den letzten Tagen." : zone.explanation)
    }
    return Item(metric: .load, value: nil, status: .missing, note: "Keine Belastungswerte")
  }

  // MARK: - Texte

  static func headline(_ level: RecoveryLevel?) -> String {
    switch level {
    case .normal?: "Bereit für dein Training"
    case .locker?: "Heute eher locker"
    case .pause?: "Heute Erholung"
    case nil: "Zu wenig Daten für eine Einschätzung"
    }
  }

  static func recommendation(_ level: RecoveryLevel?, sessions: [Session]) -> String {
    guard let level else {
      return "Es fehlen zu viele Werte. Richte dich heute nach deinem Gefühl."
    }
    var text: String
    switch level {
    case .normal: text = "Empfehlung: Training wie geplant."
    case .locker: text = "Empfehlung: Heute eher eine lockere Trainingseinheit."
    case .pause: text = "Empfehlung: Ruhetag oder höchstens 20–30 min sehr locker."
    }
    if level != .normal, let hard = sessions.first(where: \.demanding) {
      text += " „\(hard.title)“ lieber kürzer oder locker."
    } else if level == .normal, sessions.isEmpty {
      text = "Kein Training geplant – die Werte erlauben aber Belastung."
    }
    return text
  }

  static func hoursText(_ hours: Double) -> String {
    durationText(hours * 3_600)
  }

  static func durationText(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
  }
}
