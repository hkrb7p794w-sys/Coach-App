import Foundation

/// Muskelgruppen für das Wochenvolumen (Sätze je Muskel).
public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
  case chest = "Brust"
  case back = "Rücken"
  case shoulders = "Schultern"
  case biceps = "Bizeps"
  case triceps = "Trizeps"
  case legs = "Beine"
  case core = "Rumpf"
  case forearms = "Unterarme"
  case other = "Sonstige"
}

/// Kanonische Übung mit Wiederholungsbereich und Gewichtssprung (`exercise_names.RULES` im Altbestand).
public struct ExerciseRule: Equatable, Sendable {
  public var id: String
  public var name: String
  public var group: MuscleGroup
  /// Regulärer Ausdruck auf den Garmin-Schlüssel („KATEGORIE_ÜBUNG“, z. B. `BENCH_PRESS_BARBELL_BENCH_PRESS`).
  public var pattern: String
  public var reps: ClosedRange<Int>
  public var compound: Bool
  /// Kleinster Gewichtssprung am Gerät in kg.
  public var step: Double
  /// Angestrebte Steigerung in Prozent.
  public var percent: Double
  /// `true`/`false`: Regel gilt nur mit bzw. ohne Gewicht; `nil`: immer.
  public var weighted: Bool?
  /// Zuordnung ist eine Annahme (z. B. „Row“ ohne genauere Angabe).
  public var assumed: Bool
  public var bodyweightReps: Bool?

  /// Rückfall für unbekannte Übungen.
  public static func fallback(name: String) -> ExerciseRule {
    ExerciseRule(
      id: ExerciseCatalog.slug(name), name: name, group: .other, pattern: "", reps: 8...12, compound: false,
      step: 2.5, percent: 2.5, weighted: nil, assumed: false, bodyweightReps: nil)
  }
}

/// Zuordnung von Garmin-Übungsnamen zu kanonischen Übungen.
///
/// Reihenfolge und Muster unverändert aus dem Altbestand (`exercise_names.py`): Beine zuerst (Garmin-Kategorien sind
/// dort oft falsch), Spezialfälle vor allgemeinen Regeln.
public enum ExerciseCatalog {
  // swift-format-ignore
  public static let rules: [ExerciseRule] = [
    rule("beinpresse", "Beinpresse", .legs, #"LEG_PRESS"#, 6...12, compound: true, step: 5, percent: 5),
    rule("beinstrecken", "Beinstrecken", .legs, #"LEG_EXTENSION"#, 10...15, compound: false, step: 2.5, percent: 5),
    rule("beinbeugen", "Beinbeugen", .legs, #"LEG_CURL"#, 8...12, compound: false, step: 2.5, percent: 5),
    rule(
      "rumaenisches_kreuzheben", "Rumänisches Kreuzheben", .legs, #"ROMANIAN|STIFF_LEG"#,
      6...10, compound: true, step: 2.5, percent: 5),
    rule("kreuzheben", "Kreuzheben", .legs, #"DEADLIFT"#, 5...8, compound: true, step: 5, percent: 5),
    rule(
      "ausfallschritt", "Ausfallschritte", .legs, #"LUNGE|SPLIT_SQUAT|STEP_UP"#,
      8...12, compound: true, step: 2.5, percent: 5),
    rule("kniebeuge", "Kniebeuge", .legs, #"SQUAT"#, 6...10, compound: true, step: 2.5, percent: 5),
    rule("wadenheben", "Wadenheben", .legs, #"CALF"#, 10...15, compound: false, step: 2.5, percent: 5),
    rule(
      "hueftstoss", "Hüftstoß", .legs, #"HIP_THRUST|GLUTE_BRIDGE|HIP_RAISE"#,
      8...12, compound: true, step: 5, percent: 5),
    rule("plank", "Plank", .core, #"PLANK"#, 1...1, compound: false, step: 2.5, percent: 0, bodyweightReps: false),
    rule("pallof", "Pallof Press", .core, #"PALLOF"#, 10...15, compound: false, step: 2.5, percent: 2.5),
    rule(
      "rotation", "Rumpfrotation", .core, #"RUSSIAN_TWIST|WOOD_?CHOP|ROTATION"#,
      10...15, compound: false, step: 2.5, percent: 2.5),
    rule(
      "beinheben", "Beinheben", .core, #"LEG_RAISE|KNEE_RAISE|HANGING"#,
      10...15, compound: false, step: 2.5, percent: 2.5),
    rule(
      "crunch_geraet", "Crunch am Gerät", .core, #"(^|_)WEIGHTED_CRUNCH$"#,
      10...15, compound: false, step: 2.5, percent: 2.5),
    rule("crunch", "Crunch", .core, #"CRUNCH|SIT_UP"#, 10...15, compound: false, step: 2.5, percent: 2.5),
    rule(
      "reverse_fly", "Reverse Fly", .shoulders, #"REVERSE_FL|REAR_DELT"#,
      10...15, compound: false, step: 1, percent: 2.5),
    rule("face_pull", "Face Pull", .shoulders, #"FACE_PULL"#, 10...15, compound: false, step: 2.5, percent: 2.5),
    rule("frontheben", "Frontheben", .shoulders, #"FRONT_RAISE"#, 8...12, compound: false, step: 1, percent: 2.5),
    rule("seitheben", "Seitheben", .shoulders, #"LATERAL_RAISE"#, 10...15, compound: false, step: 1, percent: 2.5),
    rule(
      "aufrechtes_rudern", "Aufrechtes Rudern", .shoulders, #"UPRIGHT_ROW"#,
      8...12, compound: false, step: 2.5, percent: 2.5),
    rule(
      "kurzhantel_schulterdruecken", "Kurzhantel-Schulterdrücken", .shoulders,
      #"DUMBBELL.*(SHOULDER_PRESS|OVERHEAD_PRESS)|ARNOLD"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "schulterdruecken", "Schulterdrücken", .shoulders, #"OVERHEAD_PRESS|SHOULDER_PRESS|MILITARY"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule("shrugs", "Shrugs", .shoulders, #"SHRUG"#, 8...12, compound: false, step: 2.5, percent: 2.5),
    rule("dips", "Dips", .triceps, #"(^|_)DIPS?($|_)"#, 6...12, compound: true, step: 2.5, percent: 2.5),
    rule(
      "trizeps_pushdown", "Trizeps-Pushdown", .triceps, #"PUSHDOWN|PRESSDOWN|PRESS_DOWN"#,
      8...12, compound: false, step: 2.5, percent: 2.5),
    rule(
      "trizepsstrecken", "Trizepsstrecken", .triceps, #"TRICEPS|SKULL|KICKBACK"#,
      8...12, compound: false, step: 2.5, percent: 2.5),
    rule(
      "handgelenk_curl", "Handgelenk-Curl", .forearms, #"WRIST_CURL"#, 10...15, compound: false, step: 1, percent: 2.5),
    rule("hammer_curl", "Hammer Curl", .biceps, #"HAMMER_CURL"#, 8...12, compound: false, step: 2.5, percent: 2.5),
    rule(
      "kurzhantel_curl", "Kurzhantel-Curl", .biceps, #"DUMBBELL.*CURL|CURL.*DUMBBELL"#,
      8...12, compound: false, step: 1, percent: 2.5),
    rule("bizeps_curl", "Bizeps-Curl", .biceps, #"CURL"#, 8...12, compound: false, step: 2.5, percent: 2.5),
    rule(
      "kurzhantel_schraegbankdruecken", "Kurzhantel-Schrägbankdrücken", .chest, #"INCLINE.*DUMBBELL|DUMBBELL.*INCLINE"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "schraegbankdruecken", "Schrägbankdrücken", .chest, #"INCLINE.*(BENCH|PRESS)"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "kurzhantel_bankdruecken", "Kurzhantel-Bankdrücken", .chest,
      #"DUMBBELL_(BENCH|CHEST|PRESS)|DUMBBELL.*BENCH_PRESS"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "brustpresse", "Brustpresse", .chest, #"CHEST_PRESS|MACHINE_PRESS"#,
      8...12, compound: true, step: 5, percent: 2.5),
    rule(
      "bankdruecken", "Bankdrücken", .chest, #"BENCH_PRESS|BENCH$"#, 6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "liegestuetze", "Liegestütze", .chest, #"PUSH_UP|PUSHUP"#,
      8...20, compound: false, step: 2.5, percent: 2.5, bodyweightReps: true),
    rule(
      "fliegende", "Fliegende (Brust)", .chest, #"(^|_)FLY(E|ES)?($|_)|PEC_DECK|CROSSOVER"#,
      10...15, compound: false, step: 1.25, percent: 2.5),
    rule("kabel_pullover", "Kabel-Pullover", .back, #"PULLOVER"#, 10...15, compound: false, step: 2.5, percent: 2.5),
    rule(
      "latziehen_einarmig", "Latziehen einarmig", .back,
      #"_30_DEGREE_LAT_PULLDOWN|KNEELING(_UNDERHAND_GRIP)?_LAT_PULLDOWN|SINGLE_ARM.*PULLDOWN"#,
      8...12, compound: false, step: 2.5, percent: 2.5),
    rule("latziehen", "Latziehen", .back, #"PULLDOWN|PULL_DOWN"#, 6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "latziehen", "Latziehen", .back, #"^(PULL_UP|CHIN_UP)$"#,
      6...10, compound: true, step: 2.5, percent: 2.5, weighted: true, assumed: true),
    rule(
      "klimmzug", "Klimmzug", .back, #"PULL_UP|CHIN_UP"#,
      5...10, compound: true, step: 2.5, percent: 2.5, bodyweightReps: true),
    rule(
      "rudern_kurzhantel", "Kurzhantelrudern", .back, #"DUMBBELL_ROW|ONE_ARM_ROW|SINGLE_ARM_ROW"#,
      8...12, compound: true, step: 2.5, percent: 2.5),
    rule(
      "rudern_langhantel", "Langhantelrudern", .back, #"BARBELL_ROW|BENT_OVER|T_BAR|PENDLAY"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "rudern_kabel", "Rudern am Kabel", .back, #"SEATED_CABLE_ROW|CABLE_ROW|SEATED_ROW|MACHINE_ROW"#,
      6...10, compound: true, step: 2.5, percent: 2.5),
    rule(
      "rudern_kabel", "Rudern am Kabel", .back, #"(^|_)ROW($|_)"#,
      6...10, compound: true, step: 2.5, percent: 2.5, assumed: true),
  ]

  public static let rulesByID: [String: ExerciseRule] = Dictionary(
    rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

  private static func rule(
    _ id: String, _ name: String, _ group: MuscleGroup, _ pattern: String, _ reps: ClosedRange<Int>,
    compound: Bool, step: Double, percent: Double, weighted: Bool? = nil, assumed: Bool = false,
    bodyweightReps: Bool? = nil
  ) -> ExerciseRule {
    ExerciseRule(
      id: id, name: name, group: group, pattern: pattern, reps: reps, compound: compound, step: step,
      percent: percent, weighted: weighted, assumed: assumed, bodyweightReps: bodyweightReps)
  }

  /// „Row (SEATED_CABLE_ROW)“ → „ROW_SEATED_CABLE_ROW“.
  public static func key(_ label: String) -> String {
    let upper = label.uppercased()
    let spaced = upper.map { "()-/,".contains($0) ? " " : String($0) }.joined()
    return spaced.split(whereSeparator: \.isWhitespace).joined(separator: "_")
  }

  public static func slug(_ text: String) -> String {
    let replaced = text.lowercased()
      .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
      .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
    var result = ""
    var lastWasSeparator = false
    for character in replaced {
      if character.isASCII, character.isLetter || character.isNumber {
        result.append(character)
        lastWasSeparator = false
      } else if !lastWasSeparator {
        result.append("_")
        lastWasSeparator = true
      }
    }
    let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "uebung" : trimmed
  }

  /// Ordnet einen Garmin-Namen einer Regel zu. `hasWeight`: ob die Sätze Gewicht haben (`nil` = unbekannt).
  public static func classify(_ label: String, hasWeight: Bool? = nil) -> ExerciseRule {
    let key = key(label)
    for rule in rules {
      if let weighted = rule.weighted {
        guard let hasWeight, hasWeight == weighted else { continue }
      }
      if key.range(of: rule.pattern, options: .regularExpression) != nil { return rule }
    }
    let name = label.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return .fallback(name: name)
  }
}
