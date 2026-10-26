import Foundation

/// Ein Begriff aus einer Einheit, kurz erklärt (z. B. „CSS“, „Abschlag“, „Sweet Spot“).
public struct GuideTerm: Equatable, Sendable, Identifiable {
  public var name: String
  public var explanation: String
  public var id: String { name }
}

/// Ausführliche Erklärung einer Einheit: wozu, wie, wie es sich anfühlen soll, typische Fehler, Begriffe.
/// Die Texte sind feste Bausteine; Zahlen kommen nur aus dem Plan bzw. den eigenen Testwerten.
public struct UnitGuide: Equatable, Sendable {
  public var purpose: String
  public var steps: [String]
  public var feel: String
  public var mistakes: [String]
  public var terms: [GuideTerm]
}

public enum UnitGuides {
  // MARK: - Begriffe

  // swift-format-ignore
  public static let glossary: [(keys: [String], term: GuideTerm)] = [
    (["css"], GuideTerm(name: "CSS (kritische Schwimmgeschwindigkeit)", explanation: "Das Tempo pro 100 m, das du lange ohne Einbruch halten kannst – deine Schwelle im Wasser. Es wird aus einem 400-m- und einem 200-m-Test berechnet: (Zeit 400 m − Zeit 200 m) ÷ 2. „CSS +4 s“ heißt 4 Sekunden pro 100 m langsamer, „CSS −2 s“ 2 Sekunden schneller.")),
    (["abschlag"], GuideTerm(name: "Abschlag", explanation: "Technikübung: Ein Arm bleibt vorn gestreckt liegen, bis der andere Arm den Zug beendet hat und ihn vorne „abschlägt“. Schult ein langes Gleiten und das Timing der Arme.")),
    (["zipper"], GuideTerm(name: "Zipper (Reißverschluss)", explanation: "Technikübung: Beim Vorbringen des Arms streift der Daumen an der Körperseite entlang bis zur Achsel – wie ein Reißverschluss. Fördert einen hohen, lockeren Ellbogen über Wasser.")),
    (["seitlage"], GuideTerm(name: "Seitlage mit 6 Beinschlägen", explanation: "Technikübung: Auf der Seite liegen, unterer Arm gestreckt vorn, 6 Beinschläge, dann ein Armzug und auf die andere Seite drehen. Schult Wasserlage, Rotation und ruhiges Atmen zur Seite.")),
    (["pull-buoy", "pull_buoy", "pull buoy"], GuideTerm(name: "Pull-Buoy", explanation: "Schwimmhilfe aus Schaumstoff zwischen den Oberschenkeln. Die Beine treiben oben, der Beinschlag ruht – du trainierst gezielt Arme, Zug und Wasserlage.")),
    (["sighting"], GuideTerm(name: "Sighting", explanation: "Orientierung im Freiwasser: Alle paar Züge kurz die Augen knapp über die Wasserlinie heben („Krokodilaugen“), Ziel anpeilen, dann zur Seite atmen.")),
    (["steigernd"], GuideTerm(name: "Steigernd", explanation: "Von locker zu zügig: innerhalb der Strecke bzw. von Wiederholung zu Wiederholung schneller werden, ohne am Ende zu sprinten.")),
    (["runden-taste"], GuideTerm(name: "Runden-Taste", explanation: "Taste an der Garmin-Uhr, die einen neuen Abschnitt (Runde) startet. So lassen sich Test- und Einschwimmteil später getrennt auswerten.")),
    (["zone 2", "z2"], GuideTerm(name: "Zone 2", explanation: "Lockere Grundlagenintensität: Du kannst dich noch in ganzen Sätzen unterhalten. Die meisten Einheiten der Woche liegen hier.")),
    (["schwelle"], GuideTerm(name: "Schwelle", explanation: "Die höchste Intensität, die du etwa eine Stunde halten kannst – „angenehm hart“: Sprechen geht nur noch in kurzen Worten.")),
    (["hfmax"], GuideTerm(name: "HFmax", explanation: "Deine maximale Herzfrequenz. 90–95 % HFmax heißt: sehr hart, nur wenige Minuten haltbar. Die App nutzt deine gemessenen Werte, keine Formel.")),
    (["trab"], GuideTerm(name: "Trab / Trabpause", explanation: "Ganz lockeres Joggen zwischen den Intervallen, damit Puls und Atmung herunterkommen. Nicht stehen bleiben.")),
    (["marathontempo"], GuideTerm(name: "Marathontempo", explanation: "Das Tempo, das du im Marathon laufen willst. Fühlt sich anfangs leicht an – genau deshalb diszipliniert gleichmäßig bleiben.")),
    (["renntempo"], GuideTerm(name: "Renntempo", explanation: "Das geplante Tempo bzw. die geplante Leistung im Wettkampf. Ziel ist, es zu verinnerlichen, nicht zu überbieten.")),
    (["ftp"], GuideTerm(name: "FTP (funktionelle Schwellenleistung)", explanation: "Die Leistung in Watt, die du auf dem Rad etwa eine Stunde halten kannst. Alle Watt-Angaben im Plan sind Prozente davon.")),
    (["sweet spot"], GuideTerm(name: "Sweet Spot", explanation: "Knapp unter der Schwelle (hier etwa 88–92 % FTP): fordernd, aber lange haltbar – viel Trainingsreiz bei vertretbarer Ermüdung.")),
    (["over-under"], GuideTerm(name: "Over-Under", explanation: "Wechsel zwischen knapp über und knapp unter der FTP innerhalb eines Intervalls. Trainiert, Belastungsspitzen wegzustecken, ohne einzubrechen.")),
    (["vo2max"], GuideTerm(name: "VO2max", explanation: "Maximale Sauerstoffaufnahme – die obere Grenze deiner Ausdauer. VO2max-Intervalle sind kurz und sehr hart (hier 110–115 % FTP).")),
    (["kadenz", "u/min"], GuideTerm(name: "Kadenz", explanation: "Trittfrequenz in Umdrehungen pro Minute. Kurze Abschnitte mit 105+ U/min schulen einen runden, lockeren Tritt.")),
    (["ramp"], GuideTerm(name: "Ramp-Test", explanation: "Die Leistung steigt jede Minute, bis du nicht mehr kannst. Zwift schätzt daraus die FTP. Ausgeruht und immer gleich durchführen, damit Werte vergleichbar bleiben.")),
    (["longrun", "langer lauf"], GuideTerm(name: "Longrun", explanation: "Die längste Laufeinheit der Woche, ruhig in Zone 2. Baut Ausdauer, Fettstoffwechsel und Belastbarkeit von Sehnen und Knochen auf.")),
    (["entlastung"], GuideTerm(name: "Entlastungswoche", explanation: "Eine Woche mit weniger Umfang, damit sich der Körper anpasst. Die Intensität bleibt, nur kürzer – nicht nachholen.")),
    (["taper"], GuideTerm(name: "Taper", explanation: "Die letzten Wochen vor dem Wettkampf: deutlich weniger Umfang bei gleicher Intensität, damit du frisch an den Start gehst.")),
  ]

  /// Begriffe, die im Text der Einheit vorkommen.
  public static func terms(in text: String) -> [GuideTerm] {
    let lower = text.lowercased()
    return glossary.filter { entry in entry.keys.contains { lower.contains($0) } }.map(\.term)
  }

  // MARK: - Einheiten des Saisonplans

  public static func guide(for unit: PlannedUnit) -> UnitGuide {
    let text = [unit.title, unit.detail, unit.swimSteps.isEmpty ? "" : swimText(unit.swimSteps)]
      .joined(separator: " ")
    var guide: UnitGuide
    switch unit.kind {
    case .swim: guide = swim(title: unit.title, steps: unit.swimSteps)
    case .quality: guide = quality(title: unit.title, detail: unit.detail)
    case .easyRun: guide = easyRun
    case .longRun: guide = longRun
    case .bike, .bikeOptional: guide = bike(code: unit.zwiftCode, title: unit.title)
    case .gym: guide = strength
    }
    guide.terms = terms(in: ([text, guide.purpose] + guide.steps).joined(separator: " "))
    return guide
  }

  static func swimText(_ steps: [SwimStep]) -> String {
    steps.map { [$0.note ?? "", $0.eq ?? "", swimText($0.steps ?? [])].joined(separator: " ") }
      .joined(separator: " ")
  }

  // MARK: Schwimmen

  static func swim(title: String, steps: [SwimStep]) -> UnitGuide {
    let lower = title.lowercased()
    let purpose: String
    let feel: String
    var mistakes = [
      "Zu schnell anfangen: Die erste Wiederholung soll sich eher zu leicht anfühlen.",
      "Pausen verlängern: Die kurzen Pausen sind Teil des Trainingsreizes.",
    ]
    if lower.contains("test") {
      purpose =
        "Bestimmt deine CSS neu. Alle Schwimmtempos im Plan hängen daran – ein ehrlicher Test macht die nächsten "
        + "Wochen passend."
      feel = "Maximal, aber gleichmäßig: Die zweite Hälfte jeder Teststrecke soll nicht langsamer sein als die erste."
      mistakes = [
        "Zu schnell losschwimmen und dann einbrechen – das verfälscht die CSS.",
        "Zwischen 400 m und 200 m zu kurz erholen: Locker ausschwimmen, bis die Atmung ruhig ist.",
      ]
    } else if lower.contains("renn") {
      purpose =
        "Probt den Wettkampf: längere Strecken am Stück im Renntempo, Orientierung (Sighting) und gleichmäßiges "
        + "Einteilen."
      feel = "Kontrolliert zügig – so, dass du danach noch Rad fahren und laufen könntest."
    } else if lower.contains("tempo") {
      purpose = "Kurze, zügige Abschnitte über CSS-Tempo: Sie verbessern Schnelligkeit und Wassergefühl."
      feel = "Die schnellen 50er sind deutlich fordernd; die 100er im CSS-Tempo fühlen sich danach kontrolliert an."
    } else if lower.contains("css") {
      purpose =
        "Training an der Schwelle: Wiederholungen im CSS-Tempo mit kurzen Pausen verschieben genau das Tempo nach "
        + "vorn, das du im Wettkampf lange halten willst."
      feel = "„Angenehm hart“: Alle Wiederholungen gleich schnell, die letzten sind anstrengend, aber noch sauber."
    } else if lower.contains("technik") {
      purpose =
        "Verbindet Technik mit lockerer Ausdauer: Die Übungen verbessern Wasserlage und Armzug, die 400er bauen "
        + "Grundlage auf. Beim Schwimmen bringt Technik oft mehr als Kraft."
      feel = "Ruhig und konzentriert. Bei den Technikübungen geht es um saubere Bewegung, nicht um Tempo."
      mistakes = [
        "Technikübungen hektisch schwimmen – lieber langsam und genau.",
        "Die 400er zu schnell beginnen: Etwas langsamer als CSS ist hier richtig.",
      ]
    } else {
      purpose = "Lockeres Schwimmen zur Erholung und für das Wassergefühl."
      feel = "Entspannt, gleichmäßige Atmung, ohne auf die Uhr zu schauen."
      mistakes = ["Aus Gewohnheit doch Tempo machen – heute zählt Erholung."]
    }
    return UnitGuide(
      purpose: purpose, steps: swimSteps(steps), feel: feel, mistakes: mistakes, terms: [])
  }

  /// Erklärung der Abschnitte aus dem Ablauf (Einschwimmen, Hauptteil, Pausen, Ausschwimmen).
  static func swimSteps(_ steps: [SwimStep]) -> [String] {
    var result: [String] = []
    func describe(_ step: SwimStep, repeats: Int?) {
      switch step.t {
      case "warmup":
        result.append(
          "Einschwimmen\(step.m.map { " (\($0) m)" } ?? ""): locker, Muskeln und Atmung in Gang bringen. "
            + "Kurze Steigerungen am Ende machen dich bereit für den Hauptteil.")
      case "cool":
        result.append(
          "Ausschwimmen\(step.m.map { " (\($0) m)" } ?? ""): ganz locker, gern in einer anderen Lage – "
            + "das hilft der Erholung.")
      case "rep":
        for inner in step.steps ?? [] { describe(inner, repeats: step.n) }
      case "rest", "rec":
        if let seconds = step.s {
          result.append(
            "Pause \(seconds) s: am Beckenrand stehen, ruhig atmen, dann die nächste Wiederholung pünktlich "
              + "starten.")
        }
      default:
        let count = repeats.map { "\($0)× " } ?? ""
        let distance = step.m.map { "\(count)\($0) m" } ?? "Abschnitt"
        result.append("\(distance): \(intensity(low: step.lo, high: step.hi, note: step.note))")
      }
    }
    for step in steps { describe(step, repeats: nil) }
    // Gleiche Erklärungen (z. B. mehrere Pausen) nur einmal zeigen.
    var seen = Set<String>()
    return result.filter { seen.insert($0).inserted }
  }

  /// Tempo relativ zur CSS in Worte gefasst.
  static func intensity(low: Int?, high: Int?, note: String?) -> String {
    let lowerNote = note?.lowercased() ?? ""
    if lowerNote.contains("technik") { return "Technikübungen – langsam und genau, Tempo ist egal." }
    if lowerNote.contains("test") { return "Test: maximal, aber gleichmäßig einteilen." }
    guard let low, let high else {
      return lowerNote.isEmpty ? "locker." : "\(note ?? "")."
    }
    let middle = Double(low + high) / 2
    let base: String =
      if middle <= -1.5 {
        "schneller als dein CSS-Tempo – zügig und fordernd, nur auf kurzen Strecken haltbar."
      } else if middle <= 2 {
        "im CSS-Tempo – an der Schwelle, fordernd, aber alle Wiederholungen gleich schnell."
      } else if middle <= 8 {
        "etwas langsamer als CSS – ruhige, kräftige Ausdauer, du könntest länger so weiterschwimmen."
      } else {
        "locker – deutlich langsamer als CSS."
      }
    return lowerNote.isEmpty ? base : "\(base) Hinweis: \(note ?? "")."
  }

  // MARK: Laufen

  static func quality(title: String, detail: String = "") -> UnitGuide {
    let lower = title.lowercased()
    if detail.trimmingCharacters(in: .whitespaces) == "–" {
      return UnitGuide(
        purpose: "Diese Woche ist kein Qualitätslauf geplant – Erholung hat Vorrang.",
        steps: ["Stattdessen locker laufen oder frei lassen.", "Nicht nachholen: Die Pause ist Teil des Plans."],
        feel: "Locker.", mistakes: ["Aus Gewohnheit doch Tempo laufen."], terms: [])
    }
    if lower.contains("taper") || lower.contains("rennwoche") || lower.contains("lockerung") {
      return UnitGuide(
        purpose:
          "Kurz vor dem Wettkampf: wenig Umfang, aber kurze Abschnitte im Renntempo, damit die Beine spritzig "
          + "bleiben.",
        steps: [
          "Locker einlaufen.",
          "Die kurzen Abschnitte im angegebenen Tempo – nicht schneller.",
          "Locker auslaufen; danach viel schlafen und gut essen.",
        ],
        feel: "Leicht und spritzig – du sollst dich danach frischer fühlen als vorher.",
        mistakes: ["Kurz vor dem Rennen noch Form „beweisen“ wollen – das kostet Frische."], terms: [])
    }
    if lower.contains("4×4") {
      return UnitGuide(
        purpose:
          "Hebt deine maximale Sauerstoffaufnahme (VO2max) – den „Motor“ deiner Ausdauer. 4×4 Minuten sind in "
          + "Studien besonders wirksam.",
        steps: [
          "Etwa 15 Minuten locker einlaufen, ein paar kurze Steigerungen.",
          "4 Minuten hart: Der Puls steigt langsam und soll in der zweiten Hälfte bei 90–95 % HFmax liegen.",
          "3 Minuten locker traben, nicht stehen bleiben.",
          "Insgesamt viermal, danach 10 Minuten auslaufen.",
        ],
        feel: "Sehr hart, aber gleichmäßig: Das vierte Intervall soll genauso schnell sein wie das erste.",
        mistakes: [
          "Das erste Intervall zu schnell – der Puls braucht 1–2 Minuten, um oben anzukommen.",
          "Bei schlechter Erholung trotzdem hart laufen: Dann lieber verschieben.",
        ], terms: [])
    }
    if lower.contains("test") {
      return UnitGuide(
        purpose:
          "Bestimmt deine Schwellenpace neu. Alle Lauf-Paces im Plan hängen daran – deshalb ausgeruht und ehrlich "
          + "laufen.",
        steps: [
          "15 Minuten einlaufen.",
          "30 Minuten so schnell wie gleichmäßig möglich, auf flacher Strecke.",
          "Nach 10 Minuten die Runden-Taste drücken: Die Durchschnittspace der letzten 20 Minuten ist die neue "
            + "Schwellenpace.",
          "Wert unter Einstellungen › Saison & Ziele eintragen.",
        ],
        feel: "Hart und konstant – du solltest am Ende nicht mehr viel schneller werden können.",
        mistakes: ["Zu schnell beginnen und einbrechen – das macht den Wert zu langsam."], terms: [])
    }
    if lower.contains("marathon") || lower.contains("renntempo") {
      return UnitGuide(
        purpose:
          "Gewöhnt Körper und Kopf an dein Wettkampftempo und zeigt, ob das Ziel realistisch ist.",
        steps: [
          "Locker einlaufen.",
          "Die Abschnitte im angegebenen Tempo, möglichst gleichmäßig.",
          "Dazwischen locker traben, am Ende auslaufen.",
          "Optional: Verpflegung wie im Rennen testen.",
        ],
        feel: "Kontrolliert – das Tempo soll sich so anfühlen, als könntest du es noch lange halten.",
        mistakes: ["Schneller laufen als geplant: Das trainiert nicht dein Renntempo, sondern ermüdet nur."],
        terms: [])
    }
    return UnitGuide(
      purpose:
        "Schwellentraining: Längere Abschnitte im Schwellentempo verbessern das Tempo, das du lange halten kannst – "
        + "entscheidend für Halbmarathon und Marathon.",
      steps: [
        "Etwa 15 Minuten locker einlaufen.",
        "Die Abschnitte gleichmäßig im Schwellentempo laufen.",
        "Dazwischen 2–3 Minuten locker traben.",
        "10 Minuten auslaufen.",
      ],
      feel: "„Angenehm hart“: Sprechen geht nur in kurzen Worten, aber du hast alles unter Kontrolle.",
      mistakes: ["Zu schnell – Schwelle heißt kontrolliert, nicht Wettkampf."], terms: [])
  }

  static let easyRun = UnitGuide(
    purpose:
      "Grundlage: Lockere Läufe machen den Großteil des Trainings aus. Sie verbessern Ausdauer und Erholung, ohne "
      + "dich zu ermüden.",
    steps: [
      "Ruhig loslaufen, die ersten Minuten bewusst langsam.",
      "Nach Herzfrequenz (Zone 2) bzw. Gefühl laufen, nicht nach Pace.",
      "Mit Begleitung: Das gemeinsame Tempo ist richtig, auch wenn es langsamer ist.",
    ],
    feel: "Du kannst dich in ganzen Sätzen unterhalten.",
    mistakes: ["Zu schnell – der häufigste Fehler. Locker ist lockerer, als man denkt."], terms: [])

  static let longRun = UnitGuide(
    purpose:
      "Die wichtigste Einheit für Marathon und Langdistanz: Sie baut Ausdauer, Fettstoffwechsel und die "
      + "Belastbarkeit von Muskeln und Sehnen auf.",
    steps: [
      "Ruhig in Zone 2 laufen, gleichmäßig über die ganze Strecke.",
      "Bei Läufen über etwa eine Stunde unterwegs trinken und Kohlenhydrate zu dir nehmen – das trainiert auch "
        + "die Verdauung fürs Rennen.",
      "Die letzten Kilometer dürfen sich anstrengend anfühlen, das Tempo bleibt trotzdem ruhig.",
    ],
    feel: "Anfangs fast zu leicht, gegen Ende fordernd.",
    mistakes: ["Zu schnell starten und am Ende einbrechen.", "Ohne Verpflegung laufen."], terms: [])

  // MARK: Rad

  static let personalBike = [
    "10 Minuten locker einrollen.",
    "Hauptteil wie geplant, möglichst gleichmäßig.",
    "Ausrollen und genug trinken.",
  ]

  static func bike(code: String?, title: String, steps: [String]? = nil) -> UnitGuide {
    let lower = title.lowercased()
    let base =
      steps ?? [
        "10 Minuten locker einrollen.",
        "Hauptteil wie im Zwift-Workout angegeben; Zwift führt durch die Abschnitte.",
        "Ausrollen und viel trinken – auf der Rolle schwitzt man stark.",
      ]
    if code == "RAMP" || lower.contains("ramp") {
      return UnitGuide(
        purpose: "Bestimmt deine FTP neu. Alle Watt-Angaben im Plan hängen daran.",
        steps: [
          "Ausgeruht starten, Ventilator an, Getränk bereit.",
          "Zwift-Workout wie angegeben fahren, bis es nicht mehr geht.",
          "Den neuen Wert unter Einstellungen › Saison & Ziele eintragen.",
        ],
        feel: "Am Ende maximal – genau dafür ist der Test da.",
        mistakes: ["Müde testen: Das senkt die FTP und macht alle Einheiten zu leicht."], terms: [])
    }
    if lower.contains("vo2max") {
      return UnitGuide(
        purpose: "Kurze, sehr harte Intervalle heben die maximale Sauerstoffaufnahme.", steps: base,
        feel: "Sehr hart; die letzten 30 Sekunden jedes Intervalls sind ein Kampf.",
        mistakes: ["Die ersten Intervalle überziehen und die letzten nicht schaffen."], terms: [])
    }
    if lower.contains("schwelle") || lower.contains("over-under") {
      return UnitGuide(
        purpose: "Training an der Schwelle hebt die FTP – die Leistung, die du lange halten kannst.", steps: base,
        feel: "Hart, aber konstant; reden geht kaum noch.",
        mistakes: ["Trittfrequenz zu niedrig: lieber 85–95 U/min als schweres Treten."], terms: [])
    }
    if lower.contains("sweet spot") {
      return UnitGuide(
        purpose: "Viel Trainingsreiz knapp unter der Schwelle – effizient, wenn wenig Zeit ist.", steps: base,
        feel: "Fordernd, aber du könntest jedes Intervall noch etwas länger halten.",
        mistakes: ["Über die Vorgabe fahren – dann wird es Schwellentraining und die Erholung leidet."], terms: [])
    }
    if lower.contains("renntempo") {
      return UnitGuide(
        purpose: "Gewöhnt dich an lange Zeit im Renntempo und an die Verpflegung auf dem Rad.", steps: base,
        feel: "Gleichmäßig und kontrolliert, so dass danach noch ein Lauf möglich wäre.",
        mistakes: ["Zu wenig essen und trinken: regelmäßig etwas zu dir nehmen, nicht erst bei Hunger."], terms: [])
    }
    if lower.contains("aktivierung") {
      return UnitGuide(
        purpose: "Kurz vor dem Wettkampf: Die Beine bleiben wach, ohne zu ermüden.", steps: base,
        feel: "Locker mit ein paar kurzen, zügigen Abschnitten – danach fühlst du dich frischer.",
        mistakes: ["Mehr fahren als geplant."], terms: [])
    }
    if lower.contains("lang") {
      return UnitGuide(
        purpose: "Lange, lockere Ausfahrt: baut Grundlage und Sitzfleisch für lange Strecken auf.",
        steps: base, feel: "Locker in Zone 2 – du könntest dich die ganze Zeit unterhalten.",
        mistakes: ["Zu wenig essen und trinken: regelmäßig etwas zu dir nehmen, nicht erst bei Hunger."], terms: [])
    }
    return UnitGuide(
      purpose: "Lockere Grundlage auf dem Rad, teils mit Kadenzübungen für einen runden Tritt.", steps: base,
      feel: "Locker, unterhaltsam – du könntest stundenlang so fahren.",
      mistakes: ["Zu viel Watt aus Ehrgeiz – Zone 2 ist absichtlich leicht."], terms: [])
  }

  static let strength = UnitGuide(
    purpose:
      "Krafttraining macht Muskeln und Sehnen belastbarer und verbessert die Laufökonomie – wichtig neben dem "
      + "Ausdauertraining.",
    steps: [
      "5 Minuten aufwärmen, für die erste Übung 1–2 leichte Sätze.",
      "Sätze sauber ausführen, die letzten Wiederholungen sollen schwer sein.",
      "Das Gewicht nach dem Hinweis der App steigern (Reiter Gym).",
    ],
    feel: "Anstrengend in den letzten Wiederholungen, aber mit sauberer Technik.",
    mistakes: ["Schwung statt Kontrolle.", "Am Vortag einer harten Laufeinheit schwere Beine trainieren."],
    terms: [])

  // MARK: - Eigener Wochenplan

  public static func guide(for slot: SessionSlot) -> UnitGuide {
    var guide: UnitGuide
    switch (slot.sport, slot.intensity) {
    case (.run, .easy): guide = easyRun
    case (.run, .long): guide = longRun
    case (.run, .hard):
      guide = UnitGuide(
        purpose: "Eine Qualitätseinheit pro Woche verbessert Tempo und Fitness; der Rest bleibt locker.",
        steps: [
          "Etwa 10–15 Minuten locker einlaufen.",
          "Hauptteil, z. B. 4×4 Minuten hart (in der zweiten Hälfte 90–95 % HFmax) mit 3 Minuten Trabpause.",
          "10 Minuten auslaufen.",
        ],
        feel: "Hart, aber gleichmäßig – das letzte Intervall so schnell wie das erste.",
        mistakes: ["Bei niedriger Erholung trotzdem hart laufen – dann lieber verschieben."], terms: [])
    case (.swim, .hard):
      guide = UnitGuide(
        purpose: "Zügige Abschnitte verbessern Schnelligkeit und Wassergefühl.",
        steps: [
          "Locker einschwimmen, ein paar Bahnen steigernd.",
          "Mehrere kurze, zügige Strecken; dazwischen am Beckenrand kurz erholen.",
          "Locker ausschwimmen.",
        ],
        feel: "Fordernd, aber jede Strecke gleich schnell und mit sauberer Technik.",
        mistakes: ["Die ersten Strecken zu schnell – dann bricht die Technik ein."], terms: [])
    case (.swim, .easy):
      guide = UnitGuide(
        purpose: "Lockeres Schwimmen für Ausdauer, Wassergefühl und Erholung.",
        steps: [
          "Ein paar Bahnen ganz locker einschwimmen.",
          "Gleichmäßig schwimmen, zwischendurch kurz am Rand verschnaufen, wenn nötig.",
          "Auf ruhige Atmung und lange Züge achten.",
        ],
        feel: "Entspannt, du könntest noch lange so weiterschwimmen.",
        mistakes: ["Aus Ehrgeiz doch schnell werden."], terms: [])
    case (.swim, .long):
      guide = UnitGuide(
        purpose: "Längere, ruhige Strecken am Stück bauen Ausdauer im Wasser auf.",
        steps: [
          "Locker einschwimmen.",
          "Längere Strecken gleichmäßig, mit kurzen Pausen am Beckenrand.",
          "Zum Schluss locker ausschwimmen.",
        ],
        feel: "Ruhig und gleichmäßig; die letzte Strecke so schnell wie die erste.",
        mistakes: ["Zu schnell anfangen und später nur noch kämpfen."], terms: [])
    case (.bike, .easy): guide = bike(code: nil, title: "Z2", steps: personalBike)
    case (.bike, .hard): guide = bike(code: nil, title: "Sweet Spot", steps: personalBike)
    case (.bike, .long): guide = bike(code: nil, title: "Lang", steps: personalBike)
    case (.strength, _): guide = strength
    case (.other, _):
      guide = UnitGuide(
        purpose: "Beweglichkeit und aktive Erholung: Das hält dich geschmeidig und unterstützt die Regeneration.",
        steps: ["Ruhig beginnen, nichts erzwingen.", "Auf Atmung und Körpergefühl achten."],
        feel: "Wohltuend, nicht anstrengend.", mistakes: ["Zu ehrgeizig dehnen."], terms: [])
    }
    guide.terms = terms(in: [slot.title, guide.purpose, guide.steps.joined(separator: " ")].joined(separator: " "))
    return guide
  }
}
