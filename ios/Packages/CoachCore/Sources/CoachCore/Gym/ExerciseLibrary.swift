import Foundation

/// Geräte, mit denen eine Übung ausgeführt wird.
public enum Equipment: String, Codable, CaseIterable, Sendable, Identifiable {
  case barbell, dumbbell, machine, cable, kettlebell, band, pullupBar, bench, bodyweight

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .barbell: "Langhantel"
    case .dumbbell: "Kurzhanteln"
    case .machine: "Maschinen"
    case .cable: "Kabelzug"
    case .kettlebell: "Kettlebell"
    case .band: "Widerstandsband"
    case .pullupBar: "Klimmzugstange"
    case .bench: "Hantelbank"
    case .bodyweight: "Körpergewicht"
    }
  }

  /// Typische Ausstattungen für die Auswahl im Profil.
  public static let gym: Set<Equipment> = Set(allCases)
  public static let homeDumbbells: Set<Equipment> = [.dumbbell, .bench, .band, .bodyweight]
  public static let none: Set<Equipment> = [.bodyweight, .band]
}

/// Wie eine Übung erfasst wird.
public enum ExerciseTracking: String, Codable, Sendable {
  /// Gewicht × Wiederholungen.
  case weightReps
  /// Nur Wiederholungen (Körpergewicht, optional mit Zusatzgewicht).
  case reps
  /// Haltezeit in Sekunden (im Feld „Wiederholungen“).
  case time
}

/// Eine Übung der Bibliothek: Muskeln, Geräte, Anleitung und Regeln für die Progression.
public struct ExerciseInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var group: MuscleGroup
  public var secondary: [MuscleGroup]
  /// Eines davon genügt (z. B. Fliegende mit Kurzhanteln oder am Kabel).
  public var equipment: [Equipment]
  public var tracking: ExerciseTracking
  public var compound: Bool
  public var lowerReps: Int
  public var upperReps: Int
  /// Kleinster Gewichtssprung in kg.
  public var step: Double
  /// Angestrebte Steigerung in Prozent.
  public var percent: Double
  public var instructions: [String]
  /// Selbst angelegt.
  public var isCustom: Bool

  public init(
    id: String, name: String, group: MuscleGroup, secondary: [MuscleGroup] = [], equipment: [Equipment],
    tracking: ExerciseTracking = .weightReps, compound: Bool, lowerReps: Int, upperReps: Int, step: Double = 2.5,
    percent: Double = 2.5, instructions: [String] = [], isCustom: Bool = false
  ) {
    self.id = id
    self.name = name
    self.group = group
    self.secondary = secondary
    self.equipment = equipment
    self.tracking = tracking
    self.compound = compound
    self.lowerReps = lowerReps
    self.upperReps = max(upperReps, lowerReps)
    self.step = step
    self.percent = percent
    self.instructions = instructions
    self.isCustom = isCustom
  }

  public var repRange: ClosedRange<Int> { lowerReps...upperReps }

  /// Mit der vorhandenen Ausstattung machbar.
  public func isAvailable(with available: Set<Equipment>) -> Bool {
    equipment.isEmpty || equipment.contains(.bodyweight) || !available.isDisjoint(with: equipment)
  }

  /// Regel für die Doppelprogression (`GymProgression`).
  public var rule: ExerciseRule {
    ExerciseRule(
      id: id, name: name, group: group, pattern: "", reps: repRange, compound: compound, step: step,
      percent: percent, weighted: nil, assumed: false,
      bodyweightReps: tracking == .reps ? true : (tracking == .time ? false : nil))
  }

  /// Eigene Übung des Nutzers.
  public static func custom(name: String, group: MuscleGroup, equipment: Equipment, tracking: ExerciseTracking)
    -> ExerciseInfo
  {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let isTime = tracking == .time
    return ExerciseInfo(
      id: "eigen_" + ExerciseCatalog.slug(trimmed), name: trimmed, group: group, equipment: [equipment],
      tracking: tracking, compound: false, lowerReps: isTime ? 20 : 8, upperReps: isTime ? 60 : 12,
      step: equipment == .dumbbell ? 1 : 2.5, isCustom: true)
  }
}

/// Übungsbibliothek mit kurzer Technikanleitung. Übungen aus dem Garmin-Katalog (`ExerciseCatalog`) behalten ihre
/// IDs, damit Verlauf und Progression aus Garmin-Importen weiter zusammenpassen.
public enum ExerciseLibrary {
  // swift-format-ignore
  public static let all: [ExerciseInfo] = [
    // Brust
    item("bankdruecken", "Bankdrücken", .chest, [.triceps, .shoulders], [.barbell], compound: true, 6, 10, ["Auf der Bank liegen, Füße fest am Boden, Schulterblätter zusammen und nach unten ziehen.", "Stange kontrolliert zur unteren Brust senken, Ellbogen etwa 45–70° vom Körper.", "Gerade nach oben drücken, ohne das Gesäß von der Bank zu heben."]),
    item("kurzhantel_bankdruecken", "Kurzhantel-Bankdrücken", .chest, [.triceps, .shoulders], [.dumbbell], compound: true, 6, 10, ["Hanteln auf Brusthöhe, Handflächen zeigen Richtung Füße.", "Hanteln über der Brust zusammenführen, ohne sie anzuschlagen.", "Langsam senken, bis eine leichte Dehnung in der Brust spürbar ist."]),
    item("schraegbankdruecken", "Schrägbankdrücken", .chest, [.shoulders, .triceps], [.barbell], compound: true, 6, 10, ["Bank auf etwa 30° stellen.", "Stange zur oberen Brust senken, Schulterblätter bleiben zurückgezogen.", "Kontrolliert nach oben drücken."]),
    item("kurzhantel_schraegbankdruecken", "Kurzhantel-Schrägbankdrücken", .chest, [.shoulders, .triceps], [.dumbbell], compound: true, 6, 10, ["Bank auf etwa 30° stellen, Hanteln neben der oberen Brust.", "Über der Brust zusammendrücken, Ellbogen leicht angewinkelt lassen.", "Langsam und kontrolliert senken."]),
    item("brustpresse", "Brustpresse", .chest, [.triceps, .shoulders], [.machine], compound: true, 8, 12, step: 5, ["Sitz so einstellen, dass die Griffe auf Höhe der mittleren Brust sind.", "Nach vorn drücken, ohne die Ellbogen ganz durchzustrecken.", "Langsam zurückführen, Rücken bleibt an der Lehne."]),
    item("fliegende", "Fliegende (Brust)", .chest, [.shoulders], [.dumbbell, .cable, .machine], compound: false, 10, 15, step: 1.25, ["Arme leicht gebeugt, Ellbogen bleiben während der Bewegung im gleichen Winkel.", "In einem weiten Bogen öffnen, bis die Brust gedehnt ist.", "Im selben Bogen zusammenführen und die Brust anspannen."]),
    item("liegestuetze", "Liegestütze", .chest, [.triceps, .shoulders, .core], [.bodyweight], tracking: .reps, compound: true, 8, 20, ["Hände etwas breiter als schulterbreit, Körper bildet eine gerade Linie.", "Brust bis knapp über den Boden senken, Ellbogen etwa 45° vom Körper.", "Kräftig hochdrücken. Leichter: Hände erhöht auf einer Bank."]),
    // Rücken
    item("klimmzug", "Klimmzug", .back, [.biceps], [.pullupBar], tracking: .reps, compound: true, 5, 10, ["Stange etwas breiter als schulterbreit greifen, aus dem Hang starten.", "Schulterblätter nach unten ziehen und das Kinn über die Stange ziehen.", "Kontrolliert ganz absenken. Leichter: mit Widerstandsband."]),
    item("latziehen", "Latziehen", .back, [.biceps], [.cable, .machine], compound: true, 6, 10, ["Oberschenkel unter dem Polster fixieren, Stange breit greifen.", "Stange zur oberen Brust ziehen, Ellbogen nach unten und hinten.", "Langsam nach oben führen, bis die Arme gestreckt sind."]),
    item("latziehen_einarmig", "Latziehen einarmig", .back, [.biceps], [.cable], compound: false, 8, 12, ["Griff mit einer Hand fassen, leicht zur Seite lehnen.", "Ellbogen Richtung Hüfte ziehen.", "Langsam strecken und die Dehnung im Rücken spüren."]),
    item("rudern_langhantel", "Langhantelrudern", .back, [.biceps, .legs], [.barbell], compound: true, 6, 10, ["Hüfte beugen, Oberkörper etwa 45° nach vorn, Rücken gerade.", "Stange zum Bauchnabel ziehen, Schulterblätter zusammen.", "Kontrolliert senken, Rücken bleibt neutral."]),
    item("rudern_kurzhantel", "Kurzhantelrudern", .back, [.biceps], [.dumbbell], compound: true, 8, 12, ["Eine Hand und ein Knie auf der Bank, Rücken gerade.", "Hantel zur Hüfte ziehen, Ellbogen nah am Körper.", "Langsam strecken, ohne den Oberkörper zu drehen."]),
    item("rudern_kabel", "Rudern am Kabel", .back, [.biceps], [.cable, .machine], compound: true, 6, 10, ["Aufrecht sitzen, Knie leicht gebeugt.", "Griff zum Bauch ziehen, Schulterblätter zusammen, Brust raus.", "Arme kontrolliert strecken, ohne nach vorn zu kippen."]),
    item("rudern_koerpergewicht", "Rudern mit Körpergewicht", .back, [.biceps], [.bodyweight, .barbell, .band], tracking: .reps, compound: true, 8, 15, ["Unter eine Stange (z. B. im Rack) legen und sie greifen, Körper gestreckt.", "Brust zur Stange ziehen, Schulterblätter zusammen.", "Langsam senken. Leichter: Füße näher, Körper aufrechter."]),
    item("kabel_pullover", "Kabel-Pullover", .back, [], [.cable], compound: false, 10, 15, ["Vor dem Kabelzug stehen, Stange oder Seil mit gestreckten Armen fassen.", "Mit fast gestreckten Armen im Bogen bis zu den Oberschenkeln ziehen.", "Langsam zurück, bis die Arme über Kopfhöhe sind."]),
    item("rueckenstrecker", "Rückenstrecker (Hyperextension)", .back, [.legs], [.bench, .machine, .bodyweight], tracking: .reps, compound: false, 10, 15, ["Hüfte am Polster, Füße fixiert, Rücken gerade.", "Oberkörper aus der Hüfte senken.", "Bis zur geraden Linie aufrichten, nicht ins Hohlkreuz gehen."]),
    // Schultern
    item("schulterdruecken", "Schulterdrücken", .shoulders, [.triceps], [.barbell], compound: true, 6, 10, ["Stehen, Stange auf Höhe der Schlüsselbeine, Bauch und Gesäß fest.", "Stange senkrecht über den Kopf drücken, Kopf leicht zurück.", "Kontrolliert zurück zur Startposition."]),
    item("kurzhantel_schulterdruecken", "Kurzhantel-Schulterdrücken", .shoulders, [.triceps], [.dumbbell], compound: true, 6, 10, ["Sitzend oder stehend, Hanteln auf Schulterhöhe.", "Über den Kopf drücken, ohne die Hanteln anzuschlagen.", "Langsam bis auf Schulterhöhe senken."]),
    item("seitheben", "Seitheben", .shoulders, [], [.dumbbell, .cable, .band], compound: false, 10, 15, step: 1, ["Leicht nach vorn geneigt stehen, Arme minimal gebeugt.", "Arme seitlich bis auf Schulterhöhe heben, Ellbogen führen.", "Langsam senken, ohne Schwung."]),
    item("frontheben", "Frontheben", .shoulders, [], [.dumbbell, .cable, .barbell], compound: false, 8, 12, step: 1, ["Aufrecht stehen, Gewicht vor den Oberschenkeln.", "Mit fast gestreckten Armen bis auf Schulterhöhe heben.", "Kontrolliert senken."]),
    item("reverse_fly", "Reverse Fly", .shoulders, [.back], [.dumbbell, .cable, .machine], compound: false, 10, 15, step: 1, ["Oberkörper nach vorn geneigt, Rücken gerade.", "Arme seitlich nach hinten öffnen, Schulterblätter zusammen.", "Langsam zurückführen."]),
    item("face_pull", "Face Pull", .shoulders, [.back], [.cable, .band], compound: false, 10, 15, ["Seil auf Augenhöhe, mit beiden Händen greifen.", "Zum Gesicht ziehen, Hände auseinander, Ellbogen hoch.", "Kurz halten, dann kontrolliert strecken."]),
    item("aufrechtes_rudern", "Aufrechtes Rudern", .shoulders, [], [.barbell, .dumbbell, .cable], compound: false, 8, 12, ["Gewicht vor dem Körper, Griff etwa schulterbreit.", "Ellbogen seitlich bis knapp unter Schulterhöhe ziehen.", "Langsam senken; bei Schulterbeschwerden lieber Seitheben."]),
    item("shrugs", "Shrugs", .shoulders, [.back], [.barbell, .dumbbell], compound: false, 8, 12, ["Aufrecht stehen, Gewicht an gestreckten Armen.", "Schultern senkrecht zu den Ohren ziehen.", "Kurz halten und langsam senken."]),
    // Bizeps, Trizeps, Unterarme
    item("bizeps_curl", "Bizeps-Curl", .biceps, [.forearms], [.barbell, .cable], compound: false, 8, 12, ["Aufrecht stehen, Ellbogen am Körper.", "Gewicht ohne Schwung zur Schulter beugen.", "Langsam strecken, bis die Arme fast gerade sind."]),
    item("kurzhantel_curl", "Kurzhantel-Curl", .biceps, [.forearms], [.dumbbell], compound: false, 8, 12, step: 1, ["Hanteln seitlich, Handflächen nach vorn.", "Abwechselnd oder gleichzeitig beugen, Ellbogen bleiben am Körper.", "Kontrolliert senken."]),
    item("hammer_curl", "Hammer Curl", .biceps, [.forearms], [.dumbbell, .cable], compound: false, 8, 12, ["Handflächen zeigen zueinander.", "Hanteln zur Schulter beugen, Ellbogen fest am Körper.", "Langsam senken."]),
    item("trizeps_pushdown", "Trizeps-Pushdown", .triceps, [], [.cable, .band], compound: false, 8, 12, ["Am Kabelzug stehen, Ellbogen fest an den Seiten.", "Griff nach unten drücken, bis die Arme gestreckt sind.", "Langsam bis etwa 90° zurück, Ellbogen bleiben ruhig."]),
    item("trizepsstrecken", "Trizepsstrecken", .triceps, [], [.dumbbell, .cable, .barbell], compound: false, 8, 12, ["Gewicht über dem Kopf oder liegend über der Stirn halten.", "Nur im Ellbogen beugen und das Gewicht hinter den Kopf senken.", "Strecken, Oberarme bleiben ruhig."]),
    item("dips", "Dips", .triceps, [.chest, .shoulders], [.bodyweight], tracking: .reps, compound: true, 6, 12, ["An parallelen Holmen oder einer Bank abstützen.", "Senken, bis die Oberarme etwa parallel zum Boden sind.", "Kräftig hochdrücken. Bei Schulterbeschwerden auslassen."]),
    item("handgelenk_curl", "Handgelenk-Curl", .forearms, [], [.dumbbell, .barbell], compound: false, 10, 15, step: 1, ["Unterarme auf den Oberschenkeln, Handgelenke über dem Knie.", "Gewicht nur im Handgelenk anheben.", "Langsam senken."]),
    // Beine
    item("kniebeuge", "Kniebeuge", .legs, [.core], [.barbell], compound: true, 6, 10, ["Stange auf dem oberen Rücken, Füße etwa schulterbreit, Zehen leicht nach außen.", "Hüfte nach hinten und unten, Knie folgen den Zehen, Rücken bleibt gerade.", "So tief wie sauber möglich, dann kraftvoll aufstehen."]),
    item("goblet_squat", "Goblet Squat", .legs, [.core], [.dumbbell, .kettlebell], compound: true, 8, 12, ["Hantel vor der Brust halten, Füße schulterbreit.", "Tief in die Hocke gehen, Ellbogen zwischen den Knien.", "Aufrecht aufstehen. Gut zum Lernen der Kniebeuge."]),
    item("beinpresse", "Beinpresse", .legs, [], [.machine], compound: true, 6, 12, step: 5, ["Füße schulterbreit mittig auf der Platte.", "Schlitten senken, bis die Knie etwa 90° gebeugt sind, Gesäß bleibt am Polster.", "Drücken, ohne die Knie ganz durchzustrecken."]),
    item("ausfallschritt", "Ausfallschritte", .legs, [.core], [.dumbbell, .bodyweight, .barbell], compound: true, 8, 12, ["Großer Schritt nach vorn, Oberkörper aufrecht.", "Hinteres Knie Richtung Boden senken, vorderes Knie über dem Fuß.", "Über die Ferse zurückdrücken; Seiten wechseln."]),
    item("bulgarische_kniebeuge", "Bulgarische Kniebeuge", .legs, [.core], [.dumbbell, .bodyweight, .bench], compound: true, 8, 12, ["Hinterer Fuß auf der Bank, vorderer Fuß weit genug vorn.", "Senkrecht nach unten gehen, bis der vordere Oberschenkel etwa waagerecht ist.", "Über die vordere Ferse hochdrücken."]),
    item("rumaenisches_kreuzheben", "Rumänisches Kreuzheben", .legs, [.back], [.barbell, .dumbbell], compound: true, 6, 10, ["Gewicht vor den Oberschenkeln, Knie leicht gebeugt.", "Hüfte weit nach hinten schieben, Gewicht nah an den Beinen, Rücken gerade.", "Bei Dehnung der Oberschenkelrückseite die Hüfte nach vorn bringen."]),
    item("kreuzheben", "Kreuzheben", .legs, [.back, .forearms], [.barbell], compound: true, 5, 8, step: 5, ["Füße hüftbreit, Stange über der Fußmitte, schulterbreit greifen.", "Rücken gerade, Brust raus, Stange vom Boden drücken und nah am Körper führen.", "Oben aufrecht stehen, kontrolliert ablegen."]),
    item("hueftstoss", "Hüftstoß", .legs, [], [.barbell, .dumbbell, .machine, .bodyweight], compound: true, 8, 12, step: 5, ["Oberer Rücken an der Bank, Gewicht auf der Hüfte, Füße hüftbreit.", "Hüfte hochdrücken, bis Oberkörper und Oberschenkel eine Linie bilden.", "Gesäß oben anspannen, langsam senken."]),
    item("beinstrecken", "Beinstrecken", .legs, [], [.machine], compound: false, 10, 15, step: 2.5, percent: 5, ["Knie auf Höhe der Drehachse, Polster über den Knöcheln.", "Beine strecken und kurz halten.", "Langsam senken."]),
    item("beinbeugen", "Beinbeugen", .legs, [], [.machine], compound: false, 8, 12, step: 2.5, percent: 5, ["Polster knapp über den Fersen.", "Beine gegen den Widerstand beugen.", "Kontrolliert strecken."]),
    item("wadenheben", "Wadenheben", .legs, [], [.machine, .dumbbell, .bodyweight], compound: false, 10, 15, ["Fußballen auf einer Kante, Fersen frei.", "So hoch wie möglich auf die Zehen.", "Langsam senken, bis die Waden gedehnt sind."]),
    item("kettlebell_swing", "Kettlebell Swing", .legs, [.back, .core], [.kettlebell], compound: true, 10, 20, step: 4, ["Kettlebell zwischen den Beinen nach hinten schwingen, Rücken gerade.", "Hüfte explosiv nach vorn strecken, die Arme führen nur.", "Kettlebell bis Brusthöhe schwingen lassen."]),
    // Rumpf
    item("plank", "Plank (Unterarmstütz)", .core, [], [.bodyweight], tracking: .time, compound: false, 20, 60, ["Auf Unterarmen und Zehen, Körper bildet eine gerade Linie.", "Bauch und Gesäß anspannen, Hüfte weder durchhängen noch hochstrecken.", "Ruhig weiteratmen."]),
    item("seitstuetz", "Seitstütz", .core, [], [.bodyweight], tracking: .time, compound: false, 20, 45, ["Auf einem Unterarm, Füße übereinander.", "Hüfte heben, bis der Körper gerade ist.", "Halten, dann Seite wechseln."]),
    item("dead_bug", "Dead Bug", .core, [], [.bodyweight], tracking: .reps, compound: false, 8, 15, ["Rückenlage, Arme nach oben, Beine im 90°-Winkel.", "Gegengleich einen Arm und ein Bein strecken, unterer Rücken bleibt am Boden.", "Zurück und Seite wechseln."]),
    item("crunch", "Crunch", .core, [], [.bodyweight], tracking: .reps, compound: false, 10, 15, ["Rückenlage, Knie gebeugt.", "Oberkörper einrollen, bis die Schulterblätter abheben.", "Langsam ablegen."]),
    item("crunch_geraet", "Crunch am Gerät", .core, [], [.machine, .cable], compound: false, 10, 15, ["Am Gerät oder kniend am Kabel mit Seil.", "Oberkörper einrollen, Bewegung aus dem Bauch.", "Kontrolliert zurück."]),
    item("beinheben", "Beinheben", .core, [], [.pullupBar, .bodyweight], tracking: .reps, compound: false, 10, 15, ["Hängend oder liegend, Beine gestreckt oder angewinkelt.", "Beine heben, ohne zu schwingen.", "Langsam senken."]),
    item("pallof", "Pallof Press", .core, [], [.cable, .band], compound: false, 10, 15, ["Seitlich zum Kabel stehen, Griff vor der Brust.", "Arme nach vorn strecken und der Drehung widerstehen.", "Kurz halten, zurück; Seite wechseln."]),
    item("rotation", "Rumpfrotation", .core, [], [.cable, .band, .dumbbell], compound: false, 10, 15, ["Seitlich zum Kabel, Arme gestreckt.", "Oberkörper kontrolliert drehen, Hüfte bleibt stabil.", "Langsam zurück; Seite wechseln."]),
    // Varianten aus GymBook (Kabel- und Geräteübungen), damit Verlauf und Progression je Variante getrennt bleiben.
    item("fliegende_kabel_hoch", "Flyings am hohen Kabel", .chest, [.shoulders], [.cable], compound: false, 10, 15, step: 1.25, ["Zwischen den Kabeltürmen stehen, Griffe von oben, Arme leicht gebeugt.", "In einem Bogen vor dem Körper nach unten zusammenführen.", "Kontrolliert öffnen, bis die Brust gedehnt ist."]),
    item("reverse_fly_kabel", "Reverse Flyings am hohen Kabel", .shoulders, [.back], [.cable], compound: false, 10, 15, step: 1.25, ["Kabel über Kreuz auf Schulterhöhe greifen.", "Arme seitlich nach hinten öffnen, Schulterblätter zusammen.", "Langsam zurückführen."]),
    item("seitheben_kabel", "Einarmiges Seitheben am tiefen Kabel", .shoulders, [], [.cable], compound: false, 10, 15, step: 1.25, ["Seitlich zum Kabelzug stehen, Griff mit der äußeren Hand von unten.", "Arm seitlich bis Schulterhöhe heben.", "Langsam senken, ohne Schwung."]),
    item("hammer_curl_kabel", "Curls in Hammerhaltung am Kabel", .biceps, [.forearms], [.cable], compound: false, 8, 12, ["Seil am tiefen Kabel, Handflächen zueinander.", "Zur Schulter beugen, Ellbogen bleiben am Körper.", "Langsam strecken."]),
    item("kabel_curl_liegend", "Curls am Kabel liegend", .biceps, [], [.cable, .bench], compound: false, 8, 12, ["Rücklings vor dem Kabelzug liegen, Stange am tiefen Kabel.", "Unterarme zur Schulter beugen, Oberarme bleiben am Boden.", "Kontrolliert strecken."]),
    item("trizeps_kabel_schraegbank", "Armstrecken am tiefen Kabel auf Schrägbank", .triceps, [], [.cable, .bench], compound: false, 10, 15, ["Auf der Schrägbank mit dem Rücken zum tiefen Kabel, Seil über dem Kopf.", "Unterarme nach oben strecken, Ellbogen zeigen nach vorn.", "Langsam beugen, bis der Trizeps gedehnt ist."]),
    item("crunch_kabel", "Crunches am Kabel kniend", .core, [], [.cable], compound: false, 10, 15, ["Vor dem hohen Kabel knien, Seil neben dem Kopf halten.", "Oberkörper einrollen, Ellbogen Richtung Knie.", "Langsam aufrichten, Hüfte bleibt ruhig."]),
    item("dips_barren", "Dips am Barren", .triceps, [.chest, .shoulders], [.bodyweight, .machine], compound: true, 6, 12, ["Wie in GymBook mit Gewichtsangabe (Zusatzgewicht bzw. Unterstützung am Gerät).", "Senken, bis die Oberarme etwa waagerecht sind.", "Kräftig hochdrücken, Schultern bleiben unten."]),
  ]

  public static let byID: [String: ExerciseInfo] = Dictionary(
    all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

  /// Übung zur ID: Bibliothek, dann eigene Übungen, dann Garmin-Katalog.
  public static func info(_ id: String, custom: [ExerciseInfo] = []) -> ExerciseInfo? {
    if let known = byID[id] { return known }
    if let own = custom.first(where: { $0.id == id }) { return own }
    guard let rule = ExerciseCatalog.rulesByID[id] else { return nil }
    return ExerciseInfo(
      id: rule.id, name: rule.name, group: rule.group, equipment: [], compound: rule.compound,
      lowerReps: rule.reps.lowerBound, upperReps: rule.reps.upperBound, step: rule.step, percent: rule.percent)
  }

  /// Regel für die Progression: Garmin-Katalog bevorzugt (gleiche Werte wie bisher), sonst Bibliothek.
  public static func rule(_ id: String, name: String, custom: [ExerciseInfo] = []) -> ExerciseRule {
    if let rule = ExerciseCatalog.rulesByID[id] { return rule }
    if let info = info(id, custom: custom) { return info.rule }
    return .fallback(name: name)
  }

  /// Suche über Name und Muskel, nach Muskelgruppe sortiert.
  public static func search(_ text: String, custom: [ExerciseInfo] = [], available: Set<Equipment>? = nil)
    -> [ExerciseInfo]
  {
    let query = text.trimmingCharacters(in: .whitespaces).lowercased()
    return (all + custom).filter { item in
      (available.map(item.isAvailable(with:)) ?? true)
        && (query.isEmpty || item.name.lowercased().contains(query) || item.group.rawValue.lowercased().contains(query))
    }
  }

  private static func item(
    _ id: String, _ name: String, _ group: MuscleGroup, _ secondary: [MuscleGroup], _ equipment: [Equipment],
    tracking: ExerciseTracking = .weightReps, compound: Bool, _ lower: Int, _ upper: Int, step: Double? = nil,
    percent: Double? = nil, _ instructions: [String]
  ) -> ExerciseInfo {
    // Für Übungen aus dem Garmin-Katalog gelten dessen Sprünge, damit sich die Progression nicht ändert.
    let catalog = ExerciseCatalog.rulesByID[id]
    return ExerciseInfo(
      id: id, name: name, group: group, secondary: secondary, equipment: equipment, tracking: tracking,
      compound: compound, lowerReps: lower, upperReps: upper, step: step ?? catalog?.step ?? 2.5,
      percent: percent ?? catalog?.percent ?? 2.5, instructions: instructions)
  }
}
