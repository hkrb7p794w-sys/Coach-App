import Foundation

/// Musterpersonen für den Prüfbericht und die Tests: Die App rechnet für jede Person alle Empfehlungen durch und
/// prüft feste Regeln (Schutzgrenzen), die nie verletzt werden dürfen.
public struct Persona: Sendable {
  public var name: String
  public var description: String
  public var profile: UserProfile
  public var nutrition: NutritionSettings
  public var predictions: RacePredictions?
  public var recipeAllergens: Set<Allergen>

  public var body: BodyProfile {
    nutrition.profile(garmin: nil, on: PersonaReport.monday)
  }
}

/// Ergebnis einer Schutzregel.
public struct PersonaCheck: Equatable, Sendable {
  public var rule: String
  public var passed: Bool
  public var detail: String
}

public struct PersonaResult: Sendable {
  public var persona: Persona
  public var issues: [InputIssue]
  public var assessment: GoalAssessment
  public var week: [(weekday: Weekday, sessions: [String], targets: NutritionTargets)]
  public var hints: [ScheduleHint]
  public var adviceNormal: ScheduleAdvice?
  public var advicePause: ScheduleAdvice?
  public var routines: [Routine]
  public var checks: [PersonaCheck]
}

public enum PersonaReport {
  /// Montag, 2.11.2026: fester Bezugstag, damit der Bericht reproduzierbar ist.
  public static let monday = CalendarDay(year: 2026, month: 11, day: 2)

  static func schedule(_ plan: [Weekday: [SessionSlot]]) -> WeekSchedule {
    var schedule = WeekSchedule()
    for (weekday, slots) in plan { schedule.set(slots, on: weekday) }
    return schedule
  }

  static func nutrition(weight: Double, height: Double, age: Int, female: Bool, diet: Diet) -> NutritionSettings {
    var settings = NutritionSettings()
    settings.weightKilograms = weight
    settings.heightCentimeters = height
    settings.age = age
    settings.isFemale = female
    settings.diet = diet
    return settings
  }

  public static var personas: [Persona] {
    var runner = UserProfile(mode: .personal, onboardingDone: true, sports: [.run, .strength], goal: .loseWeight)
    runner.setLevel(.beginner, for: .run)
    runner.setLevel(.beginner, for: .strength)
    runner.targets.targetWeightKilograms = 65
    runner.targets.weeksToTargetWeight = 20
    runner.schedule = schedule([
      .tuesday: [SessionSlot(.run)], .thursday: [SessionSlot(.strength, .hard)], .saturday: [SessionSlot(.run, .long)],
    ])

    var season = UserProfile.seasonPlan
    season.onboardingDone = true

    var beginner = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .improveFitness)
    beginner.setLevel(.beginner, for: .run)
    beginner.targets.restingHeartRate = 60
    beginner.schedule = schedule([.wednesday: [SessionSlot(.run)], .sunday: [SessionSlot(.run)]])

    var muscle = UserProfile(mode: .personal, onboardingDone: true, sports: [.strength], goal: .buildMuscle)
    muscle.setLevel(.intermediate, for: .strength)
    muscle.schedule = schedule([
      .monday: [SessionSlot(.strength, .hard)], .tuesday: [SessionSlot(.strength, .hard)],
      .thursday: [SessionSlot(.strength, .hard)], .friday: [SessionSlot(.strength, .hard)],
    ])

    var vegan = UserProfile(mode: .personal, onboardingDone: true, sports: [.run, .bike], goal: .improveFitness)
    vegan.setLevel(.intermediate, for: .run)
    vegan.setLevel(.intermediate, for: .bike)
    vegan.event = EventGoal(
      name: "Stadtlauf Halbmarathon", date: monday.adding(days: 84), kind: .halfMarathon, targetSeconds: 6_600)
    vegan.schedule = schedule([
      .tuesday: [SessionSlot(.run, .hard)], .wednesday: [SessionSlot(.bike)], .thursday: [SessionSlot(.run)],
      .sunday: [SessionSlot(.run, .long)],
    ])
    var veganPredictions = RacePredictions()
    veganPredictions.tenK = 3_240
    veganPredictions.halfMarathon = 7_080

    var underweight = UserProfile(mode: .personal, onboardingDone: true, sports: [.run], goal: .loseWeight)
    underweight.setLevel(.beginner, for: .run)
    underweight.schedule = schedule([
      .monday: [SessionSlot(.run)], .tuesday: [SessionSlot(.run, .hard)], .wednesday: [SessionSlot(.run, .hard)],
      .thursday: [SessionSlot(.run)], .friday: [SessionSlot(.run)], .saturday: [SessionSlot(.run, .long)],
      .sunday: [SessionSlot(.run)],
    ])

    return [
      Persona(
        name: "Läuferin, möchte abnehmen", description: "30 Jahre, 170 cm, 72 kg, Laufen + Gym, Einsteigerin",
        profile: runner, nutrition: nutrition(weight: 72, height: 170, age: 30, female: true, diet: .omnivore),
        predictions: nil, recipeAllergens: []),
      Persona(
        name: "Saisonplan (Triathlon)", description: "35 Jahre, 180 cm, 78 kg, Saisonplan Marathon und Almere",
        profile: season, nutrition: nutrition(weight: 78, height: 180, age: 35, female: false, diet: .pescetarian),
        predictions: nil, recipeAllergens: []),
      Persona(
        name: "Einsteiger Fitness", description: "45 Jahre, 178 cm, 90 kg, 2× Laufen, Ruhepuls-Ziel 60",
        profile: beginner, nutrition: nutrition(weight: 90, height: 178, age: 45, female: false, diet: .omnivore),
        predictions: nil, recipeAllergens: []),
      Persona(
        name: "Muskelaufbau", description: "25 Jahre, 180 cm, 70 kg, 4× Kraft, Fortgeschritten",
        profile: muscle, nutrition: nutrition(weight: 70, height: 180, age: 25, female: false, diet: .omnivore),
        predictions: nil, recipeAllergens: []),
      Persona(
        name: "Vegane Halbmarathonläuferin", description: "28 Jahre, 165 cm, 58 kg, Ziel 1:50 h, Nussallergie",
        profile: vegan, nutrition: nutrition(weight: 58, height: 165, age: 28, female: true, diet: .vegan),
        predictions: veganPredictions, recipeAllergens: [.nuts]),
      Persona(
        name: "Untergewicht will abnehmen", description: "22 Jahre, 172 cm, 52 kg (BMI 17,6), 7 Lauftage",
        profile: underweight, nutrition: nutrition(weight: 52, height: 172, age: 22, female: true, diet: .vegetarian),
        predictions: nil, recipeAllergens: []),
    ]
  }

  public static func evaluate(_ persona: Persona) -> PersonaResult {
    let profile = persona.profile
    let body = persona.body
    var settings = persona.nutrition
    let assessment = GoalRules.assess(profile: profile, body: body)
    if profile.mode == .personal { GoalRules.apply(assessment, to: &settings) }
    let issues =
      InputCheck.body(body)
      + InputCheck.goals(profile: profile, body: body, predictions: persona.predictions, today: monday)

    let week = Weekday.allCases.map { weekday -> (Weekday, [String], NutritionTargets) in
      let day = monday.adding(days: weekday.rawValue)
      let items: [TemplateItem]
      let sessions: [String]
      if profile.mode == .season {
        items = SeasonPlan.state(today: day, config: .standard, week: WeeklyVolume()).todayFixed
        sessions = items.map(\.text)
      } else {
        items = profile.schedule.templateItems(on: weekday)
        sessions = profile.schedule.slots(on: weekday).map(\.title)
      }
      let targets = NutritionPlanner.compute(
        activities: [], planItems: items, settings: settings, garminProfile: nil, day: day, hasGarminData: false)
      return (weekday, sessions, targets)
    }

    var hints: [ScheduleHint] = []
    var normal: ScheduleAdvice?
    var pause: ScheduleAdvice?
    var routines: [Routine] = []
    if profile.mode == .personal {
      hints = ScheduleCheck.hints(schedule: profile.schedule, profile: profile)
      let day = monday.adding(days: profile.schedule.trainingDays.first?.rawValue ?? 0)
      normal = ScheduleAdvisor.advice(profile: profile, day: day, recovery: .normal, trainedToday: false)
      pause = ScheduleAdvisor.advice(profile: profile, day: day, recovery: .pause, trainedToday: false)
      if profile.trains(.strength) {
        routines = RoutineTemplates.suggest(profile: profile, equipment: Equipment.gym)
      }
    }

    let result = PersonaResult(
      persona: persona, issues: issues, assessment: assessment, week: week, hints: hints, adviceNormal: normal,
      advicePause: pause, routines: routines, checks: [])
    var withChecks = result
    withChecks.checks = checks(result, settings: settings)
    return withChecks
  }

  /// Schutzregeln, die für jede Person gelten müssen.
  static func checks(_ result: PersonaResult, settings: NutritionSettings) -> [PersonaCheck] {
    let persona = result.persona
    let body = persona.body
    var checks: [PersonaCheck] = []
    let bodyFat = settings.bodyFatPercent ?? (body.isFemale ? 25 : 15)
    let floor = 30 * body.weightKilograms * (1 - bodyFat / 100)
    let lowest = result.week.map { $0.targets.values[.kcal] ?? 0 }.min() ?? 0
    checks.append(
      PersonaCheck(
        rule: "Energie nie unter der REDs-Untergrenze (30 kcal/kg fettfreie Masse)", passed: lowest >= floor - 1,
        detail: "niedrigster Tag \(Int(lowest)) kcal, Untergrenze \(Int(floor.rounded())) kcal"))

    let rate = result.assessment.weeklyChangePercent ?? 0
    checks.append(
      PersonaCheck(
        rule: "Abnehmen höchstens 1 % pro Woche, Zunehmen höchstens 0,5 %",
        passed: rate >= -GoalRules.maxLossPercentPerWeek && rate <= GoalRules.maxGainPercentPerWeek,
        detail: "geplant \(GermanFormat.number(rate)) % pro Woche"))

    let proteins = result.week.map { ($0.targets.values[.protein] ?? 0) / body.weightKilograms }
    checks.append(
      PersonaCheck(
        rule: "Protein 1,4–2,2 g je kg", passed: proteins.allSatisfy { (1.39...2.21).contains($0) },
        detail: "\(GermanFormat.number(((proteins.first ?? 0) * 10).rounded() / 10)) g/kg"))

    // Makros müssen zur Energie passen und Fett im Bereich 20–35 % liegen (ACSM 2016).
    let shares = result.week.map { day -> (fat: Double, gap: Double) in
      let values = day.targets.values
      let kcal = max(values[.kcal] ?? 1, 1)
      let fromMacros = 4 * (values[.protein] ?? 0) + 4 * (values[.carbs] ?? 0) + 9 * (values[.fat] ?? 0)
      return (9 * (values[.fat] ?? 0) / kcal, abs(fromMacros - kcal))
    }
    let lowestFat = shares.map(\.fat).min() ?? 0
    checks.append(
      PersonaCheck(
        rule: "Fett 20–35 % der Energie, Makros ergeben die Tagesenergie",
        passed: shares.allSatisfy { (0.195...0.355).contains($0.fat) && $0.gap <= 15 },
        detail: "niedrigster Fettanteil \(Int((lowestFat * 100).rounded())) %"))

    if GoalRules.bmi(body) < GoalRules.minimumBMI, persona.profile.goal.losesWeight {
      checks.append(
        PersonaCheck(
          rule: "Kein Abnehmziel bei BMI unter 18,5", passed: result.assessment.blocksWeightChange,
          detail: result.assessment.blocksWeightChange ? "Ziel wird gehalten statt umgesetzt" : "Ziel wird umgesetzt"))
    }

    if persona.profile.mode == .personal {
      let schedule = persona.profile.schedule
      let restOK = !schedule.restDays.isEmpty || result.hints.contains { $0.id == "rest" && $0.severity == .warning }
      checks.append(
        PersonaCheck(
          rule: "Mindestens ein Ruhetag oder eine deutliche Warnung", passed: restOK,
          detail: "\(schedule.restDays.count) Ruhetage"))
      if let pause = result.advicePause {
        checks.append(
          PersonaCheck(
            rule: "Bei schlechter Erholung keine harte Einheit empfehlen",
            passed: pause.mode == .rest || pause.mode == .restDay,
            detail: pause.headline))
      }
      let hardDays = schedule.demandingEnduranceDays
      let backToBack = hardDays.contains { hardDays.contains($0.next) }
      checks.append(
        PersonaCheck(
          rule: "Zwei harte Ausdauertage hintereinander werden gemeldet",
          passed: !backToBack || result.hints.contains { $0.id.hasPrefix("back-to-back") },
          detail: backToBack ? "kommt vor" : "kommt nicht vor"))
    }

    let samples: [(String, Bool)] = [
      ("Hähnchenbrust", persona.nutrition.diet != .omnivore),
      ("Basilikumpesto", persona.nutrition.diet == .vegan || persona.recipeAllergens.contains(.nuts)),
      ("Walnusskerne", persona.recipeAllergens.contains(.nuts)),
    ]
    let recipeOK = samples.allSatisfy { name, mustFail in
      RecipePlanner.violations(name, diet: persona.nutrition.diet, allergens: persona.recipeAllergens).isEmpty
        != mustFail
    }
    checks.append(
      PersonaCheck(
        rule: "Rezept-Prüfung erkennt Ernährungsweise und Allergene (auch versteckte)", passed: recipeOK,
        detail: samples.map(\.0).joined(separator: ", ")))
    return checks
  }

  // MARK: - Markdown

  public static func markdown(_ results: [PersonaResult]) -> String {
    var lines = [
      "# Prüfbericht: Musterpersonen",
      "",
      "Woche ab \(Weekday.monday.long), \(monday.iso). Alle Werte stammen aus denselben Regeln wie die App.",
      "",
    ]
    let failed = results.flatMap(\.checks).filter { !$0.passed }
    lines.append(failed.isEmpty ? "**Alle Schutzregeln eingehalten.**" : "**\(failed.count) Schutzregeln verletzt!**")
    for result in results {
      let persona = result.persona
      lines += ["", "## \(persona.name)", "", "_\(persona.description)_", ""]
      lines.append("### Schutzregeln")
      for check in result.checks {
        lines.append("- \(check.passed ? "✅" : "❌") \(check.rule) – \(check.detail)")
      }
      if !result.issues.isEmpty {
        lines += ["", "### Eingaben"]
        for issue in result.issues { lines.append("- \(symbol(issue.severity)) \(issue.message)") }
      }
      lines += ["", "### Ziel", ""]
      let assessment = result.assessment
      let rate = assessment.weeklyChangePercent.map { ", \(GermanFormat.number($0)) % pro Woche" } ?? ""
      lines.append("- Ernährung: \(assessment.nutritionGoal.label)\(rate)")
      for note in assessment.notes { lines.append("- \(note)") }
      lines += [
        "", "### Woche", "", "| Tag | Einheiten | Tagestyp | kcal | Protein | KH | Fett |",
        "|---|---|---|---|---|---|---|",
      ]
      for day in result.week {
        let values = day.targets.values
        func value(_ nutrient: Nutrient) -> String { "\(Int(values[nutrient] ?? 0))" }
        let sessions = day.sessions.isEmpty ? "frei" : day.sessions.joined(separator: " + ")
        lines.append(
          "| \(day.weekday.short) | \(sessions) | \(day.targets.dayType.label) | \(value(.kcal)) | "
            + "\(value(.protein)) g | \(value(.carbs)) g | \(value(.fat)) g |")
      }
      if !result.hints.isEmpty {
        lines += ["", "### Hinweise zum Wochenplan"]
        for hint in result.hints { lines.append("- \(hint.severity == .warning ? "⚠️" : "💡") \(hint.message)") }
      }
      if let normal = result.adviceNormal, let pause = result.advicePause {
        lines += [
          "", "### Tagesempfehlung (erster Trainingstag)",
          "- Erholung gut: **\(normal.headline)** – \(normal.detail)",
          "- Erholung schlecht: **\(pause.headline)** – \(pause.detail)",
        ]
      }
      if !result.routines.isEmpty {
        lines += ["", "### Vorgeschlagene Routinen"]
        for routine in result.routines {
          let items = routine.items.map { "\($0.name) \($0.sets)×\($0.lowerReps)–\($0.upperReps)" }
          lines.append("- \(routine.name): \(items.joined(separator: ", "))")
        }
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }

  static func symbol(_ severity: InputIssue.Severity) -> String {
    switch severity {
    case .warning: "⚠️"
    case .tip: "💡"
    case .info: "ℹ️"
    }
  }

  public static func run() -> String {
    markdown(personas.map(evaluate))
  }
}
