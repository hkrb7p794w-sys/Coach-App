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
        blocksWeightChange: true)
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
      return hold(["Für unter 18-Jährige gibt die App keine Gewichtsziele vor. Sie hält dein Gewicht und unterstützt das Training."])
    }
    if goal.losesWeight, bmi(body) < minimumBMI {
      return hold(
        ["Dein BMI liegt unter 18,5. Abnehmen ist dann nicht sinnvoll: Die App hält dein Gewicht und baut mit dem Training Kraft auf."],
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
      var rate = defaultLossPercentPerWeek
      if let target = profile.targets.targetWeightKilograms, let weeks = profile.targets.weeksToTargetWeight {
        if bmi(BodyProfile(weightKilograms: target, heightCentimeters: body.heightCentimeters, age: body.age, isFemale: body.isFemale)) < minimumBMI {
          notes.append("Dein Zielgewicht läge unter BMI 18,5. Die App plant daher mit dem Standardtempo und stoppt bei BMI 18,5.")
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
      var rate = goal == .gainWeight ? maxGainPercentPerWeek : defaultGainPercentPerWeek
      if let target = profile.targets.targetWeightKilograms, let weeks = profile.targets.weeksToTargetWeight {
        let result = weeklyGainPercent(currentKilograms: body.weightKilograms, targetKilograms: target, weeks: weeks)
        rate = result.percent
        if result.capped {
          notes.append("Dein Wunschtempo ist schneller, als der Körper Muskeln aufbaut. Die App begrenzt auf höchstens 0,5 % pro Woche.")
        }
      }
      notes.append("Ein kleiner Überschuss genügt: etwa 300–500 kcal pro Tag zusammen mit konsequentem Krafttraining.")
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
      return "Realistisch: In Studien sank der Ruhepuls nach einem Jahr regelmäßigem Ausdauertraining im Schnitt um etwa 7 Schläge pro Minute."
    }
    let gap = Int(difference.rounded())
    return "Dein Ziel liegt \(gap) Schläge unter deinem Wert. Das ist mehr als der Durchschnitt aus Studien nach einem Jahr "
      + "(etwa 7). Es ist ambitioniert; die App zeigt dir den Fortschritt."
  }

  /// Überträgt das Ergebnis in die Ernährungseinstellungen.
  public static func apply(_ assessment: GoalAssessment, to settings: inout NutritionSettings) {
    settings.goal = assessment.nutritionGoal
    settings.weeklyWeightChangePercent = assessment.weeklyChangePercent
  }
}
