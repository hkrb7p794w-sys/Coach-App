import Foundation

/// Empfehlung für eine Übung – Ergebnis von `evaluate_exercise` im Altbestand.
public struct ExerciseProgress: Equatable, Sendable, Identifiable {
  public enum Status: String, Sendable, Comparable {
    case increase = "erhöhen"
    case restart = "wiedereinstieg"
    case check = "prüfen"
    case build = "aufbauen"
    case baseline = "basis"
    case noWeight = "ohne_gewicht"

    var order: Int {
      switch self {
      case .increase: 0
      case .restart: 1
      case .check: 2
      case .build: 3
      case .baseline: 4
      case .noWeight: 5
      }
    }

    public static func < (lhs: Status, rhs: Status) -> Bool { lhs.order < rhs.order }
  }

  public var exerciseID: String
  public var name: String
  public var group: MuscleGroup
  public var lastDay: CalendarDay
  public var daysSince: Int
  public var weightKg: Double
  public var reps: [Int]
  public var target: ClosedRange<Int>
  public var sessions: Int
  public var nextWeightKg: Double?
  public var increasePercent: Double?
  public var status: Status
  public var headline: String
  public var detail: String
  public var id: String { exerciseID }
}

/// Doppelprogression im Wiederholungsbereich, portiert aus `gym_progress.py`.
///
/// Zuerst die Wiederholungen bis zur Obergrenze steigern, dann das Gewicht erhöhen (2–10 %, mindestens ein
/// Gerätesprung) und wieder unten beginnen. Auslöser: alle Arbeitssätze an der Obergrenze, „2 für 2“ (ACSM 2009,
/// doi:10.1249/MSS.0b013e3181915670) oder zweimal in Folge knapp an der Obergrenze. Die Tagesampel verschiebt nur den
/// Zeitpunkt, nie das Zielgewicht.
public enum GymProgression {
  /// Sätze unter 80 % des schwersten Satzes gelten als Aufwärmen.
  static let warmupFraction = 0.80
  static let minimumWorkingSets = 2
  /// Übungen, die länger nicht gemacht wurden, fallen raus.
  static let relevantDays = 56
  /// Danach: Wiedereinstieg mit reduziertem Gewicht.
  static let breakDays = 21
  static let restartFactor = 0.90
  static let maxIncreasePercent = 10.0
  static let weightTolerance = 0.011

  struct Entry: Equatable {
    var day: CalendarDay
    var weight: Double
    var reps: [Int]
    var minReps: Int { reps.min() ?? 0 }
    var maxReps: Int { reps.max() ?? 0 }
    var lastReps: Int { reps.last ?? 0 }
  }

  /// Arbeitssätze: mindestens 80 % des schwersten Gewichts; ohne Gewicht alle Sätze.
  static func workingSets(_ sets: [LoggedSet]) -> [LoggedSet] {
    let valid = sets.filter { $0.done && $0.reps > 0 }.map { LoggedSet(reps: $0.reps, weightKg: max($0.weightKg, 0)) }
    guard let top = valid.map(\.weightKg).max() else { return [] }
    guard top > 0 else { return valid }
    return valid.filter { $0.weightKg >= top * warmupFraction }
  }

  static func summary(day: CalendarDay, sets: [LoggedSet]) -> Entry? {
    let working = workingSets(sets)
    guard let top = working.map(\.weightKg).max() else { return nil }
    let atTop = top > 0 ? working.filter { abs($0.weightKg - top) <= weightTolerance } : working
    return Entry(day: day, weight: top, reps: atTop.map(\.reps))
  }

  /// Verlauf je Übung (alt → neu); mehrere Einheiten am selben Tag werden zusammengelegt.
  static func history(_ sessions: [GymSession]) -> [String: (name: String, group: MuscleGroup, entries: [Entry])] {
    var perDay: [String: (name: String, group: MuscleGroup, days: [CalendarDay: [LoggedSet]])] = [:]
    for session in sessions {
      for exercise in session.exercises {
        var item = perDay[exercise.exerciseID] ?? (exercise.name, exercise.group, [:])
        item.days[session.day, default: []].append(contentsOf: exercise.sets)
        perDay[exercise.exerciseID] = item
      }
    }
    return perDay.compactMapValues { item in
      let entries = item.days.keys.sorted().compactMap { summary(day: $0, sets: item.days[$0] ?? []) }
      return entries.isEmpty ? nil : (item.name, item.group, entries)
    }
  }

  /// Wie `_round_to` im Altbestand (Python rundet halbe Werte zur geraden Zahl).
  static func round(_ value: Double, to step: Double) -> Double {
    ((value / step).rounded(.toNearestOrEven) * step * 100).rounded() / 100
  }

  /// Nächstes Gewicht: ca. `percent` % mehr, mindestens ein Gerätesprung, höchstens 10 % (sofern der Sprung kleiner
  /// geht). Gibt Gewicht und tatsächliche Steigerung in Prozent zurück.
  public static func nextWeight(_ weight: Double, step: Double, percent: Double) -> (Double, Double)? {
    guard weight > 0 else { return nil }
    var increase = max(weight * percent / 100, step)
    increase = round(increase, to: step)
    if increase == 0 { increase = step }
    let cap = weight * maxIncreasePercent / 100
    if increase > cap, cap >= step { increase = (cap / step).rounded(.down) * step }
    let next = ((weight + increase) * 100).rounded() / 100
    return (next, (increase / weight * 1000).rounded() / 10)
  }

  static func kg(_ value: Double) -> String {
    GermanFormat.number(value)
  }

  static func repsText(_ reps: [Int]) -> String {
    reps.map(String.init).joined(separator: "/")
  }

  static func evaluate(
    rule: ExerciseRule, range: ClosedRange<Int>, entries: [Entry], today: CalendarDay, recovered: Bool?
  ) -> ExerciseProgress? {
    guard let last = entries.last else { return nil }
    let previous = entries.count >= 2 ? entries[entries.count - 2] : nil
    let low = range.lowerBound
    let high = range.upperBound
    let daysSince = last.day.days(until: today)
    let weight = last.weight
    var result = ExerciseProgress(
      exerciseID: rule.id, name: rule.name, group: rule.group, lastDay: last.day, daysSince: daysSince,
      weightKg: weight, reps: last.reps, target: range, sessions: entries.count, nextWeightKg: nil,
      increasePercent: nil, status: .baseline, headline: "", detail: "")

    func set(_ status: ExerciseProgress.Status, _ headline: String, _ detail: String) -> ExerciseProgress {
      result.status = status
      result.headline = headline
      result.detail = detail
      return result
    }

    if high <= 1 {
      return set(.noWeight, "Haltübung", "Keine Wiederholungsprogression – Zeit statt Gewicht steigern.")
    }
    if weight <= 0 {
      if last.minReps >= high {
        return set(
          .increase, "Zusatzgewicht beginnen",
          "Alle Sätze mit \(repsText(last.reps)) Wdh. (Ziel \(low)–\(high)) – nächstes Mal mit kleinem Zusatzgewicht "
            + "starten.")
      }
      return set(.build, "Wiederholungen steigern", "\(repsText(last.reps)) Wdh. – Ziel: alle Sätze auf \(high).")
    }
    if daysSince > breakDays {
      let restart = round(weight * restartFactor, to: rule.step)
      result.nextWeightKg = restart
      return set(
        .restart, "Wiedereinstieg mit ca. \(kg(restart)) kg",
        "Letzte Einheit vor \(daysSince) Tagen mit \(kg(weight)) kg × \(repsText(last.reps)). Nach Pause ~10 % "
          + "weniger ansetzen und in 1–2 Einheiten wieder hocharbeiten (Erfahrungswert).")
    }

    let next = nextWeight(weight, step: rule.step, percent: rule.percent)
    let sameWeightPrevious = previous.map { abs($0.weight - weight) <= weightTolerance } ?? false
    // A: alle Arbeitssätze an der Obergrenze
    let ruleA = last.reps.count >= minimumWorkingSets && last.minReps >= high
    // B (2 für 2): letzte Serie in zwei Einheiten in Folge ≥ Ziel + 1
    let ruleB = sameWeightPrevious && last.lastReps >= high + 1 && (previous?.lastReps ?? 0) >= high + 1
    // C: zweimal in Folge knapp an der Obergrenze (jeder Satz ≥ Ziel − 1, mindestens einer am Ziel)
    let ruleC =
      sameWeightPrevious && last.reps.count >= minimumWorkingSets && last.minReps >= high - 1
      && (previous?.minReps ?? 0) >= high - 1 && last.maxReps >= high
    // Warnsignal: zweimal mindestens 2 Wdh. unter der Untergrenze bei gleichem oder höherem Gewicht
    let drop =
      previous.map { last.minReps <= low - 2 && $0.minReps <= low - 2 && last.weight >= $0.weight - weightTolerance }
      ?? false

    if ruleA || ruleB || ruleC, let next {
      let (nextKg, percent) = next
      let why: String
      if ruleA {
        why = "alle \(last.reps.count) Arbeitssätze bei \(repsText(last.reps)) Wdh. (Ziel \(low)–\(high))"
      } else if ruleB {
        why =
          "letzte Serie in zwei Einheiten in Folge mit \(previous?.lastReps ?? 0) bzw. \(last.lastReps) Wdh. "
          + "(Ziel \(high))"
      } else {
        why =
          "zwei Einheiten in Folge knapp an der Obergrenze (\(repsText(previous?.reps ?? [])) → "
          + "\(repsText(last.reps)) Wdh., Ziel \(high))"
      }
      let gate = recovered == false ? " Erholung aktuell eingeschränkt: Steigerung erst bei guter Tagesform." : ""
      var detail = "\(kg(weight)) kg: \(why). Danach wieder bei \(low) Wdh. beginnen.\(gate)"
      if percent > maxIncreasePercent {
        detail +=
          " Kleinster Sprung ist größer als 10 %: erst Zwischenschritt (z. B. Mikroscheiben) oder nur den ersten "
          + "Satz steigern."
      }
      result.nextWeightKg = nextKg
      result.increasePercent = percent
      return set(.increase, "Erhöhen auf \(kg(nextKg)) kg (+\(kg(percent)) %)", detail)
    }
    if drop, let previous {
      return set(
        .check, "Gewicht halten oder senken",
        "Zwei Einheiten in Folge mindestens 2 Wdh. unter dem Ziel \(low)–\(high) (\(repsText(previous.reps)) → "
          + "\(repsText(last.reps))) bei \(kg(weight)) kg. Gewicht nicht erhöhen; bei weiterer Stagnation 5–10 % "
          + "reduzieren. Erholung und Reihenfolge im Training mitprüfen.")
    }
    if entries.count == 1 {
      return set(
        .baseline, "Ausgangswert \(kg(weight)) kg",
        "\(repsText(last.reps)) Wdh. – eine Einheit reicht noch nicht für eine Empfehlung. Ziel: alle Sätze auf "
          + "\(high) Wdh.")
    }
    let left = max(0, high - last.minReps)
    result.nextWeightKg = next?.0
    result.increasePercent = next?.1
    return set(
      .build, "Bei \(kg(weight)) kg bleiben",
      "\(repsText(last.reps)) Wdh. – noch \(left) Wdh. bis zur Obergrenze \(high) im schwächsten Satz. Dann auf "
        + "\(kg(next?.0 ?? weight)) kg gehen.")
  }

  /// Empfehlungen je Übung der letzten 8 Wochen, „erhöhen“ zuerst.
  /// - Parameter recovered: `false`, wenn die Tagesampel nicht grün ist (Steigerung erst bei guter Tagesform).
  public static func evaluate(
    sessions: [GymSession], plan: GymPlan, today: CalendarDay, recovered: Bool? = nil
  ) -> [ExerciseProgress] {
    let planRanges = plan.repRanges
    var result: [ExerciseProgress] = []
    for (id, item) in history(sessions) {
      guard let last = item.entries.last, last.day.days(until: today) <= relevantDays else { continue }
      var rule = ExerciseCatalog.rulesByID[id] ?? .fallback(name: item.name)
      rule.id = id
      rule.name = item.name
      rule.group = item.group
      let range = planRanges[id] ?? rule.reps
      if let progress = evaluate(
        rule: rule, range: range, entries: item.entries, today: today, recovered: recovered)
      {
        result.append(progress)
      }
    }
    return result.sorted { ($0.status, $1.lastDay) < ($1.status, $0.lastDay) }
  }
}
