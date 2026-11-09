import Foundation

/// Einheit als strukturiertes Garmin-Workout für die Uhr – auf Wunsch je Einheit, nie automatisch. Gleiches Format
/// wie die Schwimm-Workouts des Home-Assistant-Add-ons (`garmin_swim.py`, Feldnamen von Garmin Connect,
/// `workout-service`): anlegen (`POST /workout-service/workout`), dann im Kalender einplanen
/// (`POST /workout-service/schedule/{id}`). Inoffizielle Schnittstelle: Garmin kann sie jederzeit ändern.
public enum GarminWorkout {
  public enum Sport: String, Codable, Sendable {
    case run, bike, swim

    public init?(_ sport: TrainingSport) {
      switch sport {
      case .run: self = .run
      case .bike: self = .bike
      case .swim: self = .swim
      case .strength, .other: return nil
      }
    }

    var json: JSONValue {
      switch self {
      case .run: object(["sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1])
      case .bike: object(["sportTypeId": 2, "sportTypeKey": "cycling", "displayOrder": 2])
      case .swim: object(["sportTypeId": 4, "sportTypeKey": "swimming", "displayOrder": 3])
      }
    }
  }

  /// Ende eines Schritts: Zeit, Strecke oder Runden-Taste.
  public enum End: Equatable, Sendable {
    case seconds(Int)
    case meters(Int)
    case lapButton
  }

  public indirect enum Step: Equatable, Sendable {
    case warmup(End, note: String = "")
    case interval(End, note: String = "")
    case recovery(End, note: String = "")
    case rest(seconds: Int)
    case cooldown(End, note: String = "")
    case repeats(Int, [Step])
  }

  public struct Plan: Equatable, Sendable {
    public var name: String
    public var sport: Sport
    public var description: String
    public var steps: [Step]

    public init(name: String, sport: Sport, description: String, steps: [Step]) {
      self.name = name
      self.sport = sport
      self.description = description
      self.steps = steps
    }
  }

  public static let poolLengthMeters = 25

  public static let createPath = "/workout-service/workout"
  public static func schedulePath(workoutID: Int64) -> String { "/workout-service/schedule/\(workoutID)" }
  public static func workoutPath(workoutID: Int64) -> String { "/workout-service/workout/\(workoutID)" }

  // MARK: - Aus dem Plantext

  /// Liest den Plantext („4×2 km @ 4:20 /km, 90 s Trab“, „50 min Zone 2“, „16 km locker“) in Schritte. Was
  /// sich nicht lesen lässt, wird ein Schritt bis zur Runden-Taste mit dem Text als Notiz – die Uhr zeigt ihn an.
  public static func plan(name: String, sport: Sport, text: String) -> Plan {
    let note = String(text.prefix(250))
    let description = String(text.prefix(1000))
    if let repeats = repeatsPattern(in: text) {
      var inner: [Step] = [.interval(repeats.work, note: note)]
      if let recovery = repeats.recoverySeconds { inner.append(.recovery(.seconds(recovery))) }
      return Plan(
        name: name, sport: sport, description: description,
        steps: [
          .warmup(.lapButton, note: "Einlaufen bzw. Einrollen"), .repeats(repeats.count, inner),
          .cooldown(.lapButton, note: "Auslaufen"),
        ])
    }
    if let minutes = firstNumber(in: text, unit: "min") {
      return Plan(
        name: name, sport: sport, description: description,
        steps: [.interval(.seconds(Int((minutes * 60).rounded())), note: note)])
    }
    if let kilometers = firstNumber(in: text, unit: "km") {
      return Plan(
        name: name, sport: sport, description: description,
        steps: [.interval(.meters(Int((kilometers * 1_000).rounded())), note: note)])
    }
    return Plan(name: name, sport: sport, description: description, steps: [.interval(.lapButton, note: note)])
  }

  struct Repeats: Equatable {
    var count: Int
    var work: End
    var recoverySeconds: Int?
  }

  /// „N×M km|min|m|s“ und optional „, P s|min Trab/locker/Pause“ danach.
  static func repeatsPattern(in text: String) -> Repeats? {
    let pattern = #"(\d+)\s*[×x]\s*(\d+(?:[.,]\d+)?)\s*(km|min|m|s)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let countRange = Range(match.range(at: 1), in: text), let valueRange = Range(match.range(at: 2), in: text),
      let unitRange = Range(match.range(at: 3), in: text),
      let count = Int(text[countRange]), count > 1, count <= 50,
      let value = Double(text[valueRange].replacingOccurrences(of: ",", with: "."))
    else { return nil }
    let work: End =
      switch text[unitRange] {
      case "km": .meters(Int((value * 1_000).rounded()))
      case "m": .meters(Int(value.rounded()))
      case "min": .seconds(Int((value * 60).rounded()))
      default: .seconds(Int(value.rounded()))
      }
    let rest = String(text[unitRange.upperBound...])
    let recoveryPattern = #"(\d+(?:[.,]\d+)?)\s*(s|min)\s*(Trab|locker|Pause|Gehpause|lockeres)"#
    var recovery: Int?
    if let regex = try? NSRegularExpression(pattern: recoveryPattern),
      let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
      let numberRange = Range(match.range(at: 1), in: rest), let unit = Range(match.range(at: 2), in: rest),
      let number = Double(rest[numberRange].replacingOccurrences(of: ",", with: "."))
    {
      recovery = Int((rest[unit] == "min" ? number * 60 : number).rounded())
    }
    return Repeats(count: count, work: work, recoverySeconds: recovery)
  }

  /// Erste Zahl vor der Einheit („50 min“, „16 km“); Bereiche wie „60–75 min“ ergeben die untere Grenze.
  static func firstNumber(in text: String, unit: String) -> Double? {
    let pattern = #"(\d+(?:[.,]\d+)?)\s*(?:[–-]\s*\d+(?:[.,]\d+)?\s*)?"# + unit + #"\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let range = Range(match.range(at: 1), in: text)
    else { return nil }
    return Double(text[range].replacingOccurrences(of: ",", with: "."))
  }

  /// Schwimmeinheit aus den Schritten des Saisonplans (Strecke, Pause, Erholung bis zur Taste, Wiederholung).
  public static func swimPlan(name: String, text: String, steps: [SwimStep]) -> Plan {
    func convert(_ steps: [SwimStep]) -> [Step] {
      steps.compactMap { step in
        switch step.t {
        case "rep": return .repeats(step.n ?? 1, convert(step.steps ?? []))
        case "rest": return .rest(seconds: step.s ?? 0)
        case "rec": return .recovery(.lapButton, note: step.note ?? "")
        case "warmup": return .warmup(step.m.map { .meters($0) } ?? .lapButton, note: step.note ?? "")
        case "cool": return .cooldown(step.m.map { .meters($0) } ?? .lapButton, note: step.note ?? "")
        default: return .interval(step.m.map { .meters($0) } ?? .lapButton, note: step.note ?? "")
        }
      }
    }
    return Plan(name: name, sport: .swim, description: String(text.prefix(1000)), steps: convert(steps))
  }

  /// Kurzfassung der Schritte für die Vorschau vor dem Senden.
  public static func summary(_ steps: [Step]) -> [String] {
    func end(_ end: End) -> String {
      switch end {
      case .seconds(let seconds): seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
      case .meters(let meters):
        meters >= 1_000 && meters % 100 == 0
          ? "\(GermanFormat.decimal(Double(meters) / 1_000)) km" : "\(meters) m"
      case .lapButton: "bis Runden-Taste"
      }
    }
    return steps.map { step in
      switch step {
      case .warmup(let value, _): "Aufwärmen: \(end(value))"
      case .cooldown(let value, _): "Ausklang: \(end(value))"
      case .interval(let value, _): "Belastung: \(end(value))"
      case .recovery(let value, _): "Erholung: \(end(value))"
      case .rest(let seconds): "Pause: \(seconds) s"
      case .repeats(let count, let inner): "\(count) × (" + summary(inner).joined(separator: ", ") + ")"
      }
    }
  }

  // MARK: - Garmin-JSON

  public static func payload(_ plan: Plan) -> JSONValue {
    var order = 0
    var groups = 0
    let steps = encode(plan.steps, order: &order, groups: &groups, child: nil)
    var segment: [String: JSONValue] = [
      "segmentOrder": .number(1), "sportType": plan.sport.json, "workoutSteps": .array(steps),
    ]
    var root: [String: JSONValue] = [
      "workoutName": .string(String(plan.name.prefix(80))), "description": .string(plan.description),
      "sportType": plan.sport.json,
    ]
    if plan.sport == .swim {
      for key in ["poolLength"] {
        segment[key] = .number(Double(poolLengthMeters))
        root[key] = .number(Double(poolLengthMeters))
      }
      segment["poolLengthUnit"] = meter
      root["poolLengthUnit"] = meter
    }
    root["workoutSegments"] = .array([.object(segment)])
    return .object(root)
  }

  static let meter = object(["unitId": 1, "unitKey": "meter", "factor": 100.0])
  static let noTarget = object(["workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1])

  static func stepType(_ id: Int, _ key: String) -> JSONValue {
    object(["stepTypeId": id, "stepTypeKey": key, "displayOrder": id])
  }

  static func condition(_ id: Int, _ key: String, displayable: Bool = true) -> JSONValue {
    .object([
      "conditionTypeId": .number(Double(id)), "conditionTypeKey": .string(key), "displayOrder": .number(Double(id)),
      "displayable": .bool(displayable),
    ])
  }

  static func encode(_ steps: [Step], order: inout Int, groups: inout Int, child: Int?) -> [JSONValue] {
    var result: [JSONValue] = []
    for step in steps {
      order += 1
      let current = order
      switch step {
      case .repeats(let count, let inner):
        groups += 1
        let group = groups
        let children = encode(inner, order: &order, groups: &groups, child: group)
        result.append(
          .object([
            "type": .string("RepeatGroupDTO"), "stepOrder": .number(Double(current)),
            "stepType": stepType(6, "repeat"), "childStepId": .number(Double(group)),
            "numberOfIterations": .number(Double(count)),
            "endCondition": condition(7, "iterations", displayable: false),
            "endConditionValue": .number(Double(count)), "smartRepeat": .bool(false),
            "skipLastRestStep": .bool(true), "workoutSteps": .array(children),
          ]))
      case .rest(let seconds):
        result.append(
          executable(
            order: current, child: child, type: stepType(5, "rest"), end: nil, restSeconds: seconds, note: ""))
      case .warmup(let end, let note):
        result.append(executable(order: current, child: child, type: stepType(1, "warmup"), end: end, note: note))
      case .cooldown(let end, let note):
        result.append(executable(order: current, child: child, type: stepType(2, "cooldown"), end: end, note: note))
      case .interval(let end, let note):
        result.append(executable(order: current, child: child, type: stepType(3, "interval"), end: end, note: note))
      case .recovery(let end, let note):
        result.append(executable(order: current, child: child, type: stepType(4, "recovery"), end: end, note: note))
      }
    }
    return result
  }

  static func executable(
    order: Int, child: Int?, type: JSONValue, end: End?, restSeconds: Int? = nil, note: String
  ) -> JSONValue {
    var step: [String: JSONValue] = [
      "type": .string("ExecutableStepDTO"), "stepOrder": .number(Double(order)), "stepType": type,
      "targetType": noTarget,
    ]
    if let child { step["childStepId"] = .number(Double(child)) }
    if !note.isEmpty { step["description"] = .string(String(note.prefix(250))) }
    if let restSeconds {
      step["endCondition"] = condition(8, "fixed.rest")
      step["endConditionValue"] = .number(Double(restSeconds))
    } else {
      switch end ?? .lapButton {
      case .seconds(let seconds):
        step["endCondition"] = condition(2, "time")
        step["endConditionValue"] = .number(Double(seconds))
      case .meters(let meters):
        step["endCondition"] = condition(3, "distance")
        step["endConditionValue"] = .number(Double(meters))
        step["preferredEndConditionUnit"] = meter
      case .lapButton:
        step["endCondition"] = condition(1, "lap.button")
      }
    }
    return .object(step)
  }

  /// `workoutId` aus der Antwort von Garmin.
  public static func workoutID(from response: JSONValue) -> Int64? {
    (response["workoutId"]?.doubleValue).map { Int64($0) }
  }

  public static func scheduleBody(day: CalendarDay) -> JSONValue {
    .object(["date": .string(day.iso)])
  }
}

private func object(_ values: [String: Any]) -> JSONValue {
  .object(
    values.mapValues { value in
      switch value {
      case let int as Int: .number(Double(int))
      case let double as Double: .number(double)
      case let string as String: .string(string)
      case let bool as Bool: .bool(bool)
      default: .null
      }
    })
}

/// Gesendete Workouts (je Einheit und Tag), damit erneutes Senden das alte Workout ersetzt statt zu verdoppeln.
public struct SentWorkouts: Codable, Equatable, Hashable, Sendable {
  public var ids: [String: Int64] = [:]

  public init() {}

  public static func key(name: String, day: CalendarDay) -> String { "\(day.iso)|\(name)" }

  /// Einträge älter als 60 Tage fallen weg.
  public mutating func prune(today: CalendarDay) {
    let cutoff = today.adding(days: -60).iso
    ids = ids.filter { $0.key.prefix(10) >= cutoff }
  }
}
