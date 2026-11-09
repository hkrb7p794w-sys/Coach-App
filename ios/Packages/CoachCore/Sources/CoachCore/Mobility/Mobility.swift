import Foundation

/// Körperregionen für Beweglichkeit. Gröber als `Muscle`, weil Mobility-Übungen Gelenke und Muskelketten
/// ansprechen.
public enum MobilityArea: String, CaseIterable, Codable, Sendable, Identifiable {
  case ankles, hips, hipFlexors, hamstrings, thoracicSpine, shoulders, lowerBack

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .ankles: "Sprunggelenke und Waden"
    case .hips: "Hüfte und Gesäß"
    case .hipFlexors: "Hüftbeuger und Oberschenkel vorn"
    case .hamstrings: "Oberschenkel hinten"
    case .thoracicSpine: "Brustwirbelsäule"
    case .shoulders: "Schultern und Brust"
    case .lowerBack: "Unterer Rücken"
    }
  }

  /// Regionen, die ein Muskel aus dem Krafttraining mitbeansprucht (Praxis-Zuordnung, keine Messung).
  public static func areas(for muscle: Muscle) -> [MobilityArea] {
    switch muscle {
    case .chest, .frontDelts: [.shoulders, .thoracicSpine]
    case .sideDelts, .rearDelts, .traps, .lats: [.shoulders, .thoracicSpine]
    case .lowerBack: [.lowerBack, .hamstrings]
    case .glutes, .adductors: [.hips]
    case .quads: [.hipFlexors, .ankles]
    case .hamstrings: [.hamstrings, .lowerBack]
    case .calves: [.ankles]
    case .biceps, .triceps, .forearms, .abs, .obliques: []
    }
  }

  /// Regionen, die eine Ausdauersportart besonders fordert.
  public static func areas(for sport: GarminActivity.Sport) -> [MobilityArea] {
    switch sport {
    case .run: [.ankles, .hipFlexors, .hamstrings, .hips]
    case .bike: [.hipFlexors, .thoracicSpine, .hamstrings]
    case .swim: [.shoulders, .thoracicSpine]
    case .strength, .other: []
    }
  }
}

/// Wann die Einheit stattfindet. Vor dem Training nur dynamische Übungen: Langes statisches Dehnen direkt davor
/// kann die Leistung kurz mindern (Behm et al. 2016).
public enum MobilityContext: String, CaseIterable, Codable, Sendable, Identifiable {
  case preTraining, postTraining, restDay

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .preTraining: "Vor dem Training"
    case .postTraining: "Nach dem Training"
    case .restDay: "Ruhetag oder abends"
    }
  }

  public var allowsStatic: Bool { self != .preTraining }
}

public struct MobilityDrill: Sendable, Identifiable, Equatable {
  public enum Style: String, Sendable {
    /// Bewegung durch den Bewegungsumfang, im Wechsel.
    case dynamic
    /// Position halten.
    case hold
  }

  public let id: String
  public let name: String
  public let areas: [MobilityArea]
  public let style: Style
  /// Dauer je Seite bzw. gesamt (ohne Seitenwechsel).
  public let seconds: Int
  public let perSide: Bool
  public let steps: [String]

  /// Gesamtdauer inklusive beider Seiten.
  public var totalSeconds: Int { perSide ? seconds * 2 : seconds }
}

/// Eigene Übungsbeschreibungen (keine Inhalte anderer Apps). Halteübungen 45 s je Seite: unter 60 s je Muskel
/// zeigte sich auch direkt vor Belastung kaum ein Leistungsverlust (Behm et al. 2016).
public enum MobilityLibrary {
  // swift-format-ignore
  public static let drills: [MobilityDrill] = [
    MobilityDrill(id: "knee_to_wall_rocks", name: "Knie zur Wand", areas: [.ankles], style: .dynamic, seconds: 40, perSide: true, steps: ["Ausfallschritt vor einer Wand, vordere Ferse bleibt am Boden.", "Knie langsam Richtung Wand schieben und zurück, 10–12 Mal.", "Knie zeigt über die zweite Zehe."]),
    MobilityDrill(id: "calf_wall_stretch", name: "Wadendehnung an der Wand", areas: [.ankles], style: .hold, seconds: 45, perSide: true, steps: ["Hände an die Wand, ein Bein weit nach hinten.", "Hintere Ferse fest auf den Boden, Knie gestreckt.", "Ruhig atmen, Zug in der Wade halten."]),
    MobilityDrill(id: "ankle_circles", name: "Fußkreisen im Stand", areas: [.ankles], style: .dynamic, seconds: 30, perSide: true, steps: ["Auf einem Bein stehen, wenn nötig festhalten.", "Den freien Fuß große Kreise ziehen lassen, je Richtung 8 Mal."]),
    MobilityDrill(id: "world_greatest", name: "Ausfallschritt mit Rotation", areas: [.hipFlexors, .hips, .thoracicSpine], style: .dynamic, seconds: 45, perSide: true, steps: ["Großer Ausfallschritt, Hände innen neben den vorderen Fuß.", "Arm auf der Seite des vorderen Beins zur Decke drehen, Blick folgt.", "Zurück, 5–6 Mal je Seite."]),
    MobilityDrill(id: "half_kneeling_hip_flexor", name: "Hüftbeuger im Halbknien", areas: [.hipFlexors], style: .hold, seconds: 45, perSide: true, steps: ["Ein Knie am Boden, das andere Bein vorne aufgestellt.", "Gesäß anspannen, Becken leicht aufrichten, bis vorne an der Hüfte Zug entsteht.", "Nicht ins Hohlkreuz fallen."]),
    MobilityDrill(id: "couch_stretch", name: "Oberschenkel vorn am Sofa", areas: [.hipFlexors], style: .hold, seconds: 45, perSide: true, steps: ["Knie hinten an Sofa oder Wand, Fußrücken angelehnt.", "Vorderen Fuß aufstellen, Oberkörper langsam aufrichten.", "Nur so weit, wie es ohne Schmerz geht."]),
    MobilityDrill(id: "leg_swings", name: "Beinpendel", areas: [.hipFlexors, .hamstrings, .hips], style: .dynamic, seconds: 30, perSide: true, steps: ["Seitlich an einer Wand festhalten.", "Bein locker vor und zurück schwingen, Ausschlag langsam steigern, 12–15 Mal.", "Danach seitlich vor dem Körper pendeln."]),
    MobilityDrill(id: "hamstring_sweeps", name: "Beinrückseite im Gehen", areas: [.hamstrings], style: .dynamic, seconds: 40, perSide: false, steps: ["Eine Ferse vorne aufsetzen, Zehen hoch, Bein fast gestreckt.", "Hüfte nach hinten schieben und mit den Händen Richtung Boden streichen.", "Aufrichten, Seite wechseln, 8 Mal je Seite."]),
    MobilityDrill(id: "seated_hamstring", name: "Beinrückseite im Sitzen", areas: [.hamstrings, .lowerBack], style: .hold, seconds: 45, perSide: true, steps: ["Ein Bein gestreckt, das andere angewinkelt.", "Mit langem Rücken aus der Hüfte nach vorne neigen.", "Zug hinten im Oberschenkel, nicht in der Kniekehle."]),
    MobilityDrill(id: "ninety_ninety", name: "90/90-Hüftwechsel", areas: [.hips], style: .dynamic, seconds: 45, perSide: false, steps: ["Sitzen, beide Knie 90 Grad gebeugt, eines vorne, eines seitlich.", "Knie langsam zur anderen Seite kippen, ohne die Hände zu Hilfe zu nehmen, wenn es geht.", "8–10 Wechsel."]),
    MobilityDrill(id: "pigeon", name: "Gesäßdehnung in Rückenlage", areas: [.hips, .lowerBack], style: .hold, seconds: 45, perSide: true, steps: ["Rückenlage, einen Knöchel auf das andere Knie legen.", "Das untere Bein zur Brust ziehen.", "Kopf und Schultern bleiben entspannt am Boden."]),
    MobilityDrill(id: "deep_squat_hold", name: "Tiefe Hocke halten", areas: [.hips, .ankles], style: .hold, seconds: 45, perSide: false, steps: ["Füße etwas breiter als hüftbreit, Fersen am Boden.", "Tief in die Hocke, Ellbogen schieben die Knie sanft nach außen.", "Wenn nötig an einem Türrahmen festhalten."]),
    MobilityDrill(id: "cat_cow", name: "Katze und Kuh", areas: [.lowerBack, .thoracicSpine], style: .dynamic, seconds: 40, perSide: false, steps: ["Vierfüßlerstand, Hände unter den Schultern.", "Rücken rund machen, dann langsam ins leichte Hohlkreuz, 8–10 Mal.", "Bewegung Wirbel für Wirbel."]),
    MobilityDrill(id: "thread_needle", name: "Brustwirbelsäule drehen im Vierfüßler", areas: [.thoracicSpine, .shoulders], style: .dynamic, seconds: 40, perSide: true, steps: ["Vierfüßlerstand.", "Einen Arm unter dem Körper durchschieben, dann zur Decke aufdrehen.", "Blick folgt der Hand, 6–8 Mal je Seite."]),
    MobilityDrill(id: "open_book", name: "Offenes Buch", areas: [.thoracicSpine, .shoulders], style: .dynamic, seconds: 40, perSide: true, steps: ["Seitlage, Knie angewinkelt, Arme vorne aufeinander.", "Oberen Arm im Bogen zur anderen Seite öffnen, Knie bleiben liegen.", "Zurück, 6–8 Mal."]),
    MobilityDrill(id: "doorway_pec", name: "Brust im Türrahmen", areas: [.shoulders], style: .hold, seconds: 45, perSide: true, steps: ["Unterarm auf Schulterhöhe an den Türrahmen.", "Mit dem Oberkörper langsam nach vorne drehen, bis vorne an Brust und Schulter Zug entsteht."]),
    MobilityDrill(id: "wall_slides", name: "Arme an der Wand hochschieben", areas: [.shoulders, .thoracicSpine], style: .dynamic, seconds: 40, perSide: false, steps: ["Rücken und Unterarme an die Wand.", "Arme langsam nach oben schieben, ohne dass der untere Rücken abhebt.", "8–10 Mal."]),
    MobilityDrill(id: "lat_stretch_bench", name: "Latissimus an Bank oder Stuhl", areas: [.shoulders, .thoracicSpine], style: .hold, seconds: 45, perSide: false, steps: ["Knien vor einer Bank, Ellbogen darauf, Hände zusammen.", "Gesäß nach hinten zu den Fersen, Brust sinkt nach unten."]),
    MobilityDrill(id: "child_pose", name: "Kindhaltung", areas: [.lowerBack, .hips], style: .hold, seconds: 45, perSide: false, steps: ["Aus dem Vierfüßlerstand das Gesäß auf die Fersen.", "Arme lang nach vorne, Stirn ablegen, ruhig in den Rücken atmen."]),
    MobilityDrill(id: "hip_hinge_good_morning", name: "Hüftbeuge ohne Gewicht", areas: [.hamstrings, .lowerBack], style: .dynamic, seconds: 40, perSide: false, steps: ["Hände an die Hüfte, Knie leicht gebeugt.", "Mit langem Rücken die Hüfte nach hinten schieben, bis hinten Zug entsteht.", "Aufrichten, 10 Mal."]),
  ]

  public static let byID = Dictionary(uniqueKeysWithValues: drills.map { ($0.id, $0) })
}

/// Einfache Selbsttests ohne Kamera. Ergebnis in drei Stufen; die Grenzen sind Praxiswerte zur Orientierung,
/// keine Diagnose.
public struct MobilityTest: Sendable, Identifiable, Equatable {
  public enum Rating: Int, Codable, Sendable, Comparable {
    case limited = 0, moderate = 1, good = 2

    public static func < (lhs: Rating, rhs: Rating) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
      switch self {
      case .limited: "eingeschränkt"
      case .moderate: "mittel"
      case .good: "gut"
      }
    }
  }

  public enum Input: Sendable, Equatable {
    /// Messung in cm, mit Grenzen für „mittel“ und „gut“ (jeweils einschließlich).
    case centimeters(range: ClosedRange<Double>, moderate: Double, good: Double)
    /// Direkte Einschätzung in drei Stufen.
    case levels([String])
  }

  public let id: String
  public let name: String
  public let areas: [MobilityArea]
  public let steps: [String]
  public let input: Input

  public func rating(_ value: Double) -> Rating {
    switch input {
    case .centimeters(_, let moderate, let good):
      value >= good ? .good : value >= moderate ? .moderate : .limited
    case .levels:
      Rating(rawValue: Int(value.rounded()).clamped(0, 2)) ?? .limited
    }
  }

  // swift-format-ignore
  public static let all: [MobilityTest] = [
    MobilityTest(id: "knee_to_wall", name: "Knie zur Wand", areas: [.ankles], steps: ["Barfuß vor eine Wand, Ausfallschritt.", "Knie berührt die Wand, Ferse bleibt am Boden.", "Fuß so weit wie möglich zurücksetzen und den Abstand große Zehe – Wand messen.", "Schlechtere Seite eintragen."], input: .centimeters(range: 0...20, moderate: 6, good: 10)),
    MobilityTest(id: "toe_touch", name: "Zehen berühren", areas: [.hamstrings, .lowerBack], steps: ["Aufrecht stehen, Beine gestreckt, Füße zusammen.", "Langsam nach vorne beugen, nicht wippen.", "Abstand Fingerspitzen – Boden messen: über den Zehen negativ, Zehen erreicht 0, darüber hinaus positiv."], input: .centimeters(range: -40...20, moderate: -10, good: 0)),
    MobilityTest(id: "shoulder_wall", name: "Arme über Kopf an der Wand", areas: [.shoulders, .thoracicSpine], steps: ["Rücken, Hinterkopf und Gesäß an die Wand, Knie leicht gebeugt.", "Gestreckte Arme vor dem Körper nach oben führen.", "Unterer Rücken bleibt an der Wand."], input: .levels(["Hände erreichen die Wand nicht", "Wand nur mit Hohlkreuz erreicht", "Daumen an der Wand, Rücken bleibt angelehnt"])),
    MobilityTest(id: "deep_squat", name: "Tiefe Hocke", areas: [.hips, .ankles], steps: ["Füße hüft- bis schulterbreit.", "Ohne Halt so tief wie möglich in die Hocke und 30 Sekunden bleiben."], input: .levels(["Nur mit Festhalten oder Fersen heben", "Tief, aber unsicher oder Rücken stark rund", "Tief und stabil, Fersen am Boden"])),
  ]

  public static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

extension Int {
  fileprivate func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}

/// Ein gespeichertes Testergebnis.
public struct MobilityTestResult: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var testID: String
  public var day: CalendarDay
  public var value: Double

  public init(id: UUID = UUID(), testID: String, day: CalendarDay, value: Double) {
    self.id = id
    self.testID = testID
    self.day = day
    self.value = value
  }

  /// Letztes Ergebnis je Test.
  public static func latest(_ results: [MobilityTestResult]) -> [String: MobilityTestResult] {
    var latest: [String: MobilityTestResult] = [:]
    for result in results where (latest[result.testID]?.day ?? CalendarDay(year: 1, month: 1, day: 1)) <= result.day {
      latest[result.testID] = result
    }
    return latest
  }
}

/// Erledigte Mobility-Einheit (für Verlauf und Wochenzählung).
public struct MobilityLogEntry: Codable, Equatable, Hashable, Sendable {
  public var day: CalendarDay
  public var minutes: Int
  public var areas: [MobilityArea]

  public init(day: CalendarDay, minutes: Int, areas: [MobilityArea]) {
    self.day = day
    self.minutes = minutes
    self.areas = areas
  }
}

/// Einstellungen und Verlauf (in der App gespeichert).
public struct MobilitySettings: Codable, Equatable, Hashable, Sendable {
  public var minutes: Int = 10
  public var results: [MobilityTestResult] = []
  public var log: [MobilityLogEntry] = []

  public init() {}

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    minutes = (try? container.decode(Int.self, forKey: .minutes)) ?? 10
    results = (try? container.decode([MobilityTestResult].self, forKey: .results)) ?? []
    log = (try? container.decode([MobilityLogEntry].self, forKey: .log)) ?? []
  }

  /// Einheiten in den sieben Tagen bis `today` (einschließlich).
  public func sessions(inWeekEnding today: CalendarDay) -> Int {
    let start = today.adding(days: -6)
    return Set(log.filter { $0.day >= start && $0.day <= today }.map(\.day)).count
  }
}

public struct MobilityRoutine: Equatable, Sendable {
  public struct Block: Equatable, Sendable, Identifiable {
    public var drill: MobilityDrill
    public var area: MobilityArea
    public var id: String { drill.id }
  }

  public var context: MobilityContext
  public var minutes: Int
  public var focus: [MobilityArea]
  /// Begründung je Schwerpunkt, z. B. „Laufen gestern 50 min“.
  public var reasons: [String]
  public var blocks: [Block]

  public var totalSeconds: Int { blocks.reduce(0) { $0 + $1.drill.totalSeconds + MobilityPlanner.transitionSeconds } }
}

/// Regeln entscheiden: Schwerpunkte aus Krafttraining (Sätze je Muskel), Ausdauer (Minuten je Sportart) und den
/// eigenen Testergebnissen. Kein KI-Aufruf.
public enum MobilityPlanner {
  public static let transitionSeconds = 10
  static let balancedReason = "Keine Belastung oder Testergebnisse – ausgewogene Einheit für den ganzen Körper."
  public static let durations = [5, 10, 20]
  /// Belastung, ab der eine Region voll zählt.
  static let fullSets = 6.0
  static let fullMinutes = 60.0

  public struct Score: Equatable, Sendable {
    public var area: MobilityArea
    public var points: Double
    public var reasons: [String]
  }

  /// `recentSets`: effektive Sätze je Muskel der letzten 48 Stunden. `enduranceMinutes`: Minuten je Sportart
  /// gestern und heute.
  public static func scores(
    recentSets: [Muscle: Double], enduranceMinutes: [GarminActivity.Sport: Double], results: [MobilityTestResult]
  ) -> [Score] {
    var points: [MobilityArea: Double] = [:]
    var reasons: [MobilityArea: [String]] = [:]

    var gymByArea: [MobilityArea: Double] = [:]
    for (muscle, sets) in recentSets where sets > 0 {
      for area in MobilityArea.areas(for: muscle) { gymByArea[area, default: 0] += sets }
    }
    for (area, sets) in gymByArea {
      points[area, default: 0] += min(sets / fullSets, 1) * 2
      reasons[area, default: []].append("Krafttraining: \(Int(sets.rounded())) Sätze in den letzten 2 Tagen")
    }

    for sport in [GarminActivity.Sport.run, .bike, .swim] {
      guard let minutes = enduranceMinutes[sport], minutes >= 15 else { continue }
      for area in MobilityArea.areas(for: sport) {
        points[area, default: 0] += min(minutes / fullMinutes, 1) * 2
        reasons[area, default: []].append("\(sportLabel(sport)) \(Int(minutes.rounded())) min seit gestern")
      }
    }

    for (testID, result) in MobilityTestResult.latest(results) {
      guard let test = MobilityTest.byID[testID] else { continue }
      let rating = test.rating(result.value)
      guard rating < .good else { continue }
      for area in test.areas {
        points[area, default: 0] += rating == .limited ? 3 : 1.5
        reasons[area, default: []].append("Test „\(test.name)“: \(rating.label)")
      }
    }

    // Stabile Reihenfolge: Punkte absteigend, bei Gleichstand die Reihenfolge der Regionen.
    return MobilityArea.allCases.enumerated()
      .map { index, area in (index, Score(area: area, points: points[area] ?? 0, reasons: reasons[area] ?? [])) }
      .sorted { $0.1.points != $1.1.points ? $0.1.points > $1.1.points : $0.0 < $1.0 }
      .map(\.1)
  }

  static func sportLabel(_ sport: GarminActivity.Sport) -> String {
    switch sport {
    case .run: "Laufen"
    case .bike: "Radfahren"
    case .swim: "Schwimmen"
    case .strength: "Krafttraining"
    case .other: "Training"
    }
  }

  /// Zahl der Schwerpunkte je Dauer.
  static func focusCount(minutes: Int) -> Int {
    minutes <= 5 ? 2 : minutes <= 10 ? 3 : 5
  }

  public static func routine(
    context: MobilityContext, minutes: Int, recentSets: [Muscle: Double],
    enduranceMinutes: [GarminActivity.Sport: Double], results: [MobilityTestResult]
  ) -> MobilityRoutine {
    let ranked = scores(recentSets: recentSets, enduranceMinutes: enduranceMinutes, results: results)
    let focus = Array(ranked.prefix(focusCount(minutes: minutes)))
    let budget = minutes * 60
    var used = Set<String>()
    var blocks: [MobilityRoutine.Block] = []
    var spent = 0

    func candidates(_ area: MobilityArea) -> [MobilityDrill] {
      let fitting = MobilityLibrary.drills.filter { $0.areas.contains(area) && !used.contains($0.id) }
      let allowed = context.allowsStatic ? fitting : fitting.filter { $0.style == .dynamic }
      // Nach dem Training und am Ruhetag zuerst halten (größere Wirkung auf die Beweglichkeit, Konrad et al.
      // 2023), vor dem Training nur dynamisch.
      return allowed.sorted { lhs, rhs in
        let lhsFirst = context.allowsStatic ? lhs.style == .hold : lhs.style == .dynamic
        let rhsFirst = context.allowsStatic ? rhs.style == .hold : rhs.style == .dynamic
        if lhsFirst != rhsFirst { return lhsFirst }
        // Hauptregion zuerst, dann Bibliotheksreihenfolge.
        let lhsMain = lhs.areas.first == area
        let rhsMain = rhs.areas.first == area
        return lhsMain && !rhsMain
      }
    }

    var progress = true
    while progress {
      progress = false
      for score in focus {
        // Höchstens 30 Sekunden über der gewählten Dauer.
        guard
          let drill = candidates(score.area).first(where: {
            spent + $0.totalSeconds + transitionSeconds <= budget + 30
          })
        else { continue }
        let cost = drill.totalSeconds + transitionSeconds
        used.insert(drill.id)
        blocks.append(MobilityRoutine.Block(drill: drill, area: score.area))
        spent += cost
        progress = true
      }
    }

    let reasons = focus.compactMap { score -> String? in
      guard let first = score.reasons.first else { return nil }
      return "\(score.area.label): \(first)"
    }
    return MobilityRoutine(
      context: context, minutes: minutes, focus: focus.map(\.area),
      reasons: reasons.isEmpty ? [balancedReason] : reasons,
      blocks: blocks)
  }

  /// Effektive Sätze je Muskel in den 48 Stunden vor `now`.
  public static func recentSets(sessions: [GymSession], now: Date, custom: [ExerciseInfo] = []) -> [Muscle: Double] {
    let since = now.addingTimeInterval(-48 * 3_600)
    var result: [Muscle: Double] = [:]
    for session in sessions where session.start >= since && session.start <= now {
      for (muscle, sets) in MuscleLoad.session(session, custom: custom) { result[muscle, default: 0] += sets }
    }
    return result
  }

  /// Minuten je Sportart gestern und heute.
  public static func enduranceMinutes(
    activities: [GarminActivity], today: CalendarDay
  ) -> [GarminActivity.Sport: Double] {
    let yesterday = today.adding(days: -1)
    var result: [GarminActivity.Sport: Double] = [:]
    for activity in activities {
      guard let day = activity.day, day >= yesterday, day <= today, let seconds = activity.durationSeconds else {
        continue
      }
      result[activity.sport, default: 0] += seconds / 60
    }
    return result
  }
}
