import Foundation

/// Ergebnis der Zielprüfung: was die App daraus für die Ernährung macht und was sie dazu sagt.
public struct GoalAssessment: Equatable, Sendable {
  public var nutritionGoal: NutritionGoal
  /// Gewichtsänderung in % des Körpergewichts pro Woche (negativ = abnehmen); `nil` = Gewicht halten.
  public var weeklyChangePercent: Double?
  public var notes: [String]
  public var evidenceIDs: [String]
  /// Das gewünschte Gewichtsziel wird nicht umgesetzt (Sicherheit).
  public var blocksWeightChange: Bool
  /// Schwangerschaft/Stillzeit oder Essstörung: keine Gewichts- oder Kalorienziele, auch keine Vorschläge.
  public var withholdsTargets = false
}

/// Wie weit die App das Körpergewicht beeinflussen darf. Gilt in jedem Pfad, nicht nur beim Speichern des Profils.
public enum WeightGoalGuard: Sendable {
  case free
  /// Unter 18 Jahren oder BMI unter 18,5: kein Defizit.
  case noDeficit
  /// Schwangerschaft/Stillzeit oder Essstörung: keine Ziele und keine Vorschläge.
  case noTargets
}

/// Zielregeln mit Schutzgeländern. Zahlen und Quellen stehen in `docs/decisions.md`.
public enum GoalRules {
  /// Obergrenze beim Abnehmen: 1 % des Körpergewichts pro Woche (Garthe et al. 2011 verglichen 0,7 und 1,4 %).
  public static let maxLossPercentPerWeek = 1.0
  public static let defaultLossPercentPerWeek = 0.5
  /// Langsames Tempo beim gleichzeitigen Muskelaufbau.
  public static let recompositionLossPercentPerWeek = 0.25
  public static let defaultGainPercentPerWeek = 0.25
  public static let maxGainPercentPerWeek = 0.5
  /// Ab diesem Tempo hielt in Garthe et al. 2011 die schnelle Gruppe weniger Muskelmasse.
  public static let slowLossLimitPercentPerWeek = 0.7
  public static let minimumBMI = 18.5
  public static let minimumAge = 18

  public static func bmi(_ body: BodyProfile) -> Double {
    let meters = body.heightCentimeters / 100
    return meters > 0 ? body.weightKilograms / (meters * meters) : 0
  }

  /// Ab diesem BMI gelten Bedarfe je kg nicht mehr für das Gesamtgewicht.
  public static let obesityBMI = 30.0
  /// BMI des Referenzgewichts bei Adipositas.
  static let referenceBMI = 25.0

  /// Gewicht für Protein und Kohlenhydrate je kg: Die Empfehlungen beziehen sich auf die fettfreie Masse (Helms et
  /// al. 2014). Ab BMI 30 rechnet die App deshalb mit dem Gewicht bei BMI 25, als Näherung.
  public static func referenceWeightKilograms(_ body: BodyProfile) -> Double {
    guard bmi(body) >= obesityBMI else { return body.weightKilograms }
    let meters = body.heightCentimeters / 100
    return referenceBMI * meters * meters
  }

  /// Körperfett in %, wenn keines eingetragen ist. Ab BMI 30 nach Deurenberg et al. 1991; darunter pauschal, weil die
  /// Formel bei Schlanken und Sportlichen zu hoch schätzt und die REDs-Untergrenze dann zu niedrig läge.
  static func estimatedBodyFatPercent(_ body: BodyProfile) -> Double {
    let flat = body.isFemale ? 25.0 : 15.0
    let value = bmi(body)
    guard value >= obesityBMI else { return flat }
    return max(flat, min(1.2 * value + 0.23 * Double(body.age) - (body.isFemale ? 0 : 10.8) - 5.4, 60))
  }

  /// Schutzstufe für die aktuellen Körperwerte.
  public static func weightGuard(settings: NutritionSettings, body: BodyProfile) -> WeightGoalGuard {
    if settings.weightTargetsWithheld { return .noTargets }
    let value = bmi(body)
    if body.age < minimumAge || (value > 0 && value < minimumBMI) { return .noDeficit }
    return .free
  }

  /// Schwangerschaft/Stillzeit oder Essstörung angegeben.
  public static func withholdsTargets(_ profile: UserProfile) -> Bool {
    profile.health.contains(.pregnantOrPostpartum) || profile.health.contains(.eatingDisorder)
  }

  /// Wochentempo, um das Zielgewicht in `weeks` Wochen zu erreichen, begrenzt auf den sicheren Bereich.
  public static func weeklyLossPercent(currentKilograms: Double, targetKilograms: Double, weeks: Int)
    -> (percent: Double, capped: Bool)
  {
    guard currentKilograms > 0, targetKilograms < currentKilograms, weeks > 0 else {
      return (defaultLossPercentPerWeek, false)
    }
    let perWeek = (currentKilograms - targetKilograms) / currentKilograms * 100 / Double(weeks)
    return (min(max(perWeek, recompositionLossPercentPerWeek), maxLossPercentPerWeek), perWeek > maxLossPercentPerWeek)
  }

  public static func weeklyGainPercent(currentKilograms: Double, targetKilograms: Double, weeks: Int)
    -> (percent: Double, capped: Bool)
  {
    guard currentKilograms > 0, targetKilograms > currentKilograms, weeks > 0 else {
      return (defaultGainPercentPerWeek, false)
    }
    let perWeek = (targetKilograms - currentKilograms) / currentKilograms * 100 / Double(weeks)
    return (min(max(perWeek, 0.1), maxGainPercentPerWeek), perWeek > maxGainPercentPerWeek)
  }

  public static func assess(profile: UserProfile, body: BodyProfile) -> GoalAssessment {
    let goal = profile.goal
    var notes: [String] = []
    var evidence: [String] = []
    func hold(_ reasons: [String], _ ids: [String] = []) -> GoalAssessment {
      GoalAssessment(
        nutritionGoal: .maintain, weeklyChangePercent: nil, notes: reasons, evidenceIDs: ids,
        blocksWeightChange: true, withholdsTargets: withholdsTargets(profile))
    }
    func reachedTarget() -> GoalAssessment {
      GoalAssessment(
        nutritionGoal: .maintain, weeklyChangePercent: nil,
        notes: notes + ["Du hast dein Zielgewicht erreicht. Die App hält jetzt dein Gewicht."], evidenceIDs: evidence,
        blocksWeightChange: false)
    }

    let wantsChange = goal.losesWeight || goal.gainsWeight

    if profile.health.contains(.pregnantOrPostpartum) {
      return hold(
        [
          "In Schwangerschaft und Stillzeit gibt die App keine Gewichtsziele vor. Sprich Ernährung und Training "
            + "mit deiner Ärztin oder Hebamme ab; die WHO hat dafür eigene Empfehlungen."
        ], ["activity.who"])
    }
    if profile.health.contains(.eatingDisorder) {
      return hold(
        [
          "Wegen einer Essstörung gibt die App keine Gewichts- oder Kalorienziele vor. Bitte lass Training und "
            + "Ernährung mit deinem Behandlungsteam abstimmen."
        ], ["nutrition.reds"])
    }
    if wantsChange, body.age < minimumAge {
      return hold([
        "Für unter 18-Jährige gibt die App keine Gewichtsziele vor. Sie hält dein Gewicht und "
          + "unterstützt das Training."
      ])
    }
    if goal.losesWeight, bmi(body) < minimumBMI {
      return hold(
        [
          "Dein BMI liegt unter 18,5. Abnehmen ist dann nicht sinnvoll: Die App hält dein "
            + "Gewicht und baut mit dem Training Kraft auf."
        ],
        ["nutrition.reds"])
    }
    if profile.health.contains(.medicalCondition) || profile.health.contains(.injury) {
      notes.append(
        "Du hast eine Erkrankung oder Verletzung angegeben. Lass dir vom Arzt bestätigen, welches Training für dich "
          + "passt, und passe den Plan an.")
      evidence.append("activity.who")
    }

    var assessment: GoalAssessment
    switch goal {
    case .loseWeight:
      if let target = profile.targets.targetWeightKilograms, target >= body.weightKilograms { return reachedTarget() }
      var rate = defaultLossPercentPerWeek
      if let target = profile.targets.targetWeightKilograms, let weeks = profile.targets.weeksToTargetWeight {
        if bmi(
          BodyProfile(
            weightKilograms: target, heightCentimeters: body.heightCentimeters, age: body.age, isFemale: body.isFemale))
          < minimumBMI
        {
          notes.append(
            "Dein Zielgewicht läge unter BMI 18,5. Die App plant daher mit dem Standardtempo und stoppt bei BMI 18,5.")
        } else {
          let result = weeklyLossPercent(currentKilograms: body.weightKilograms, targetKilograms: target, weeks: weeks)
          rate = result.percent
          if result.capped {
            notes.append(
              "Dein Wunschtempo wäre schneller als \(Int(maxLossPercentPerWeek)) % des Körpergewichts pro Woche. "
                + "Die App begrenzt darauf; das Ziel dauert entsprechend länger.")
          }
        }
      }
      if rate > slowLossLimitPercentPerWeek {
        notes.append(
          "Ab etwa 0,7 % pro Woche behielten Athleten in einer Studie weniger Muskelmasse als bei langsamerem Tempo. "
            + "Etwa 0,5 % pro Woche sind ein guter Standard.")
      }
      evidence += ["weightloss.rate", "weightloss.protein", "weightloss.exercise"]
      assessment = GoalAssessment(
        nutritionGoal: .lose, weeklyChangePercent: -rate, notes: notes, evidenceIDs: evidence,
        blocksWeightChange: false)
    case .loseAndBuild:
      notes.append(
        "Fett abbauen und Muskeln aufbauen gelingt am besten mit kleinem Defizit, viel Protein und regelmäßigem "
          + "Krafttraining. Der Fortschritt ist langsamer als bei nur einem der beiden Ziele.")
      evidence += ["weightloss.protein", "weightloss.exercise"]
      assessment = GoalAssessment(
        nutritionGoal: .recomposition, weeklyChangePercent: -recompositionLossPercentPerWeek, notes: notes,
        evidenceIDs: evidence, blocksWeightChange: false)
    case .buildMuscle, .gainWeight:
      if let target = profile.targets.targetWeightKilograms, target <= body.weightKilograms { return reachedTarget() }
      var rate = goal == .gainWeight ? maxGainPercentPerWeek : defaultGainPercentPerWeek
      if let target = profile.targets.targetWeightKilograms, let weeks = profile.targets.weeksToTargetWeight {
        let result = weeklyGainPercent(currentKilograms: body.weightKilograms, targetKilograms: target, weeks: weeks)
        rate = result.percent
        if result.capped {
          notes.append(
            "Dein Wunschtempo ist schneller, als der Körper Muskeln aufbaut. Die App begrenzt "
              + "auf höchstens 0,5 % pro Woche."
          )
        }
      }
      notes.append(
        "Ein kleiner Überschuss genügt: etwa 300–500 kcal pro Tag zusammen mit konsequentem Krafttraining.")
      evidence += ["gain.surplus", "weightloss.protein"]
      assessment = GoalAssessment(
        nutritionGoal: .gain, weeklyChangePercent: rate, notes: notes, evidenceIDs: evidence, blocksWeightChange: false)
    case .improveFitness, .maintain:
      assessment = GoalAssessment(
        nutritionGoal: .maintain, weeklyChangePercent: nil, notes: notes, evidenceIDs: evidence,
        blocksWeightChange: false)
    }
    return assessment
  }

  /// Einschätzung eines Ruhepuls-Ziels. Nach einem Jahr Laufen sank der Ruhepuls bei Inaktiven im Schnitt um
  /// etwa 7 Schläge pro Minute (Hespanhol Junior et al. 2015).
  public static func restingHeartRateOutlook(current: Double?, target: Int) -> String {
    guard let current else {
      return "Sobald Garmin deinen Ruhepuls liefert, zeigt die App den Verlauf zu deinem Ziel."
    }
    let difference = current - Double(target)
    if difference <= 0 {
      return "Du liegst schon bei oder unter deinem Ziel. Ziel ist jetzt, den Wert zu halten."
    }
    if difference <= 7 {
      return
        "Realistisch: In Studien sank der Ruhepuls nach einem Jahr regelmäßigem "
        + "Ausdauertraining im Schnitt um etwa 7 Schläge pro Minute."
    }
    let gap = Int(difference.rounded())
    return
      "Dein Ziel liegt \(gap) Schläge unter deinem Wert. Das ist mehr als der Durchschnitt aus Studien "
      + "nach einem Jahr "
      + "(etwa 7). Es ist ambitioniert; die App zeigt dir den Fortschritt."
  }

  /// Überträgt das Ergebnis in die Ernährungseinstellungen.
  public static func apply(_ assessment: GoalAssessment, to settings: inout NutritionSettings) {
    settings.goal = assessment.nutritionGoal
    settings.weeklyWeightChangePercent = assessment.weeklyChangePercent
    settings.weightTargetsWithheld = assessment.withholdsTargets
    if assessment.withholdsTargets {
      settings.energyAdjustmentKilocalories = 0
    } else if assessment.blocksWeightChange {
      settings.energyAdjustmentKilocalories = max(settings.energyAdjustmentKilocalories, 0)
    }
  }

  /// Übernimmt die neueste Wägung als aktuelles Körpergewicht. Eine Eingabe in den Einstellungen bleibt gültig, bis
  /// eine neuere Wägung kommt. `true`, wenn sich etwas geändert hat.
  public static func updateWeight(
    _ settings: inout NutritionSettings, entries: [WeightEntry], today: CalendarDay
  ) -> Bool {
    let recent = WeightTrend.merged(entries).filter { $0.day <= today && $0.day >= today.adding(days: -30) }
    guard let latest = recent.last else { return false }
    if let applied = settings.lastAppliedWeighInDay, latest.day <= applied { return false }
    settings.lastAppliedWeighInDay = latest.day
    settings.weightKilograms = (latest.kilograms * 10).rounded() / 10
    return true
  }

  /// Hat sich geändert, ob das Gewicht gehalten wird (Grenze oder Zielgewicht erreicht bzw. wieder verlassen)? Ein
  /// laufendes Tempo bleibt sonst unangetastet: Neu berechnet würde es mit jedem Kilo langsamer.
  public static func holdChanged(_ assessment: GoalAssessment, settings: NutritionSettings) -> Bool {
    (assessment.weeklyChangePercent == nil) != (settings.weeklyWeightChangePercent == nil)
  }

  /// Profil für KI, Export und Anzeige: Ist das Gewichtsziel gesperrt oder erreicht, darf nirgends mehr „Abnehmen“
  /// oder „Überschuss“ als Auftrag stehen.
  public static func coachingProfile(_ profile: UserProfile, nutrition: NutritionSettings) -> UserProfile {
    let changesWeight = profile.goal.losesWeight || profile.goal.gainsWeight
    let held =
      profile.mode == .personal && changesWeight && nutrition.goal == .maintain
      && nutrition.weeklyWeightChangePercent == nil
    guard nutrition.weightTargetsWithheld || held else { return profile }
    var result = profile
    result.goal = .maintain
    if var goals = result.goals {
      if goals.primary == .fatLoss {
        goals.primary = .health
      } else if goals.primary == .muscleGain {
        goals.primary = .strength
      }
      let primary = goals.primary
      goals.secondary.removeAll { $0 == .fatLoss || $0 == primary }
      result.goals = goals
    }
    return result
  }
}
