import Foundation

/// Worum es in einer Frage geht. Danach richtet sich, welche Daten die KI bekommt.
public enum ChatTopic: String, CaseIterable, Sendable {
  case strength, endurance, nutrition, recovery, longTerm, app
}

/// Ordnet Fragen Themen zu, ohne KI: Das kostet nichts und ist prüfbar.
public enum ChatRouter {
  private static let keywords: [ChatTopic: [String]] = [
    .strength: [
      "bankdr", "kniebeug", "kreuzheb", "schulterdr", "klimmz", "rudern", "satz", "sätze", "wiederholung", "kraft",
      "gym", "übung", "progression", "deload", "gewicht steiger", "muskel",
    ],
    .endurance: [
      "lauf", "läuf", "jogg", "rennrad", "radfahr", "schwimm", "pace", "ausdauer", "intervall", "marathon", "triathlon",
      "kilometer", "zone 2",
    ],
    .nutrition: [
      "protein", "eiweiß", "eiweiss", "kalorien", "kcal", "essen", "mahlzeit", "ernähr", "kohlenhydr", "makro",
      "hunger",
      "abnehm", "zunehm", "trinken", "frühstück", "abendessen",
    ],
    .recovery: [
      "schlaf", "müde", "erhol", "regener", "hrv", "ruhepuls", "schwer trainieren", "heute trainieren", "belastung",
      "body battery", "krank", "ruhetag", "soll ich heute", "sollte ich heute",
    ],
    .longTerm: [
      "verlauf", "gewicht", "abnehm", "zunehm", "körperfett", "entwickel", "entwickl", "letzten wochen", "monat",
      "fortschritt", "langfrist", "trend", "seit",
    ],
    .app: ["in der app", "einstellung", "wo finde", "wie stelle ich", "widget", "funktion"],
  ]

  public static func topics(question: String, history: [(role: String, text: String)]) -> Set<ChatTopic> {
    var result = match(question)
    if isFollowUp(question) {
      for entry in history.suffix(4) where entry.role == "user" { result.formUnion(match(entry.text)) }
      // Kommt nach einer Antwort „… und morgen?“, gehört der Plan dazu.
      if question.lowercased().contains("training") { result.insert(.recovery) }
    }
    return result
  }

  static func match(_ text: String) -> Set<ChatTopic> {
    let lower = text.lowercased()
    return Set(keywords.filter { _, words in words.contains { lower.contains($0) } }.keys)
  }

  /// Kurze Nachfragen und Sätze, die sich auf das Vorherige beziehen.
  static func isFollowUp(_ question: String) -> Bool {
    let lower = question.lowercased().trimmingCharacters(in: .whitespaces)
    let starts = ["und ", "aber ", "was bedeutet", "was heißt", "warum", "wieso", "dann ", "also ", "dafür", "das "]
    return starts.contains { lower.hasPrefix($0) } || lower.split(separator: " ").count <= 5
  }
}

extension ChatContext {
  /// Eine erfasste Mahlzeit von heute.
  public struct MealLine: Sendable {
    public var title: String
    public var nutrients: NutrientValues

    public init(title: String, nutrients: NutrientValues) {
      self.title = title
      self.nutrients = nutrients
    }
  }

  private static func short(_ day: CalendarDay) -> String { GermanFormat.date(day) }

  private static func grams(_ value: Double?) -> Int { Int((value ?? 0).rounded()) }

  /// Nur die Daten, die zur Frage gehören, mit Herkunft: gemessen, selbst erfasst oder von der App berechnet.
  public static func focusedLines(
    _ facts: Facts, topics: Set<ChatTopic>, question: String, today: CalendarDay
  ) -> [String] {
    var lines = ["Heute ist \(Weekday(day: today).long), \(short(today))."]
    guard !topics.isEmpty, topics != [.app] else { return lines }
    lines += Personalization.contextLines(facts.profile.effectiveGoals(today: today))
    if facts.withholdsWeightTargets {
      lines.append("Keine Gewichts- oder Kalorienziele nennen und nicht zum Abnehmen raten.")
    }
    if topics.contains(.strength) || topics.contains(.endurance) || topics.contains(.recovery) {
      lines += planLines(facts)
    }
    if topics.contains(.strength) { lines += strengthLines(facts, question: question, today: today) }
    if topics.contains(.endurance) { lines += enduranceLines(facts, today: today) }
    if topics.contains(.nutrition) { lines += nutritionLines(facts) }
    if topics.contains(.recovery) { lines += recoveryLines(facts, today: today) }
    if topics.contains(.longTerm) { lines += longTermLines(facts, today: today) }
    lines += recommendationLines(facts, topics: topics)
    return lines
  }

  private static func planLines(_ facts: Facts) -> [String] {
    var lines = [
      facts.todaySessions.isEmpty
        ? "Heute ist keine Einheit geplant." : "Heute geplant: \(facts.todaySessions.joined(separator: "; ")).",
      facts.tomorrowSessions.isEmpty
        ? "Morgen ist keine Einheit geplant." : "Morgen geplant: \(facts.tomorrowSessions.joined(separator: "; ")).",
    ]
    if let recommendation = facts.recommendation {
      lines.append("Tagesampel heute (Regel der App): \(recommendation).")
    }
    return lines
  }

  private static func strengthLines(_ facts: Facts, question: String, today: CalendarDay) -> [String] {
    let lower = question.lowercased()
    let start = today.adding(days: -56)
    let sessions = facts.gymSessions.filter { $0.day >= start }.sorted { $0.start < $1.start }
    var lines: [String] = []
    var seen = Set<String>()
    let known = ExerciseLibrary.all.map { (id: $0.id, name: $0.name) }
    let logged = sessions.flatMap(\.exercises).map { (id: $0.exerciseID, name: $0.name) }
    for exercise in known + logged where lower.contains(exercise.name.lowercased()) {
      guard seen.insert(exercise.id).inserted else { continue }
      let history = sessions.compactMap { session -> (CalendarDay, LoggedSet, Int)? in
        guard let entry = session.exercises.first(where: { $0.exerciseID == exercise.id }),
          let best = entry.doneSets.max(by: { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) })
        else { return nil }
        return (session.day, best, entry.doneSets.count)
      }
      guard !history.isEmpty else {
        lines.append("\(exercise.name): keine erfassten Sätze in den letzten 8 Wochen.")
        continue
      }
      func set(_ value: LoggedSet) -> String {
        "\(GermanFormat.number(value.weightKg)) kg für \(value.reps) Wiederholungen"
      }
      for (day, best, count) in history.suffix(8) {
        lines.append("\(exercise.name) am \(short(day)): bester Satz \(set(best)), \(count) Arbeitssätze (erfasst).")
      }
      let recent = history.filter { $0.0 >= today.adding(days: -28) }
      if let first = recent.first, let last = recent.last, recent.count >= 2 {
        let change = last.1.weightKg - first.1.weightKg
        lines.append(
          "\(exercise.name) in den letzten 4 Wochen: von \(set(first.1)) auf \(set(last.1)), "
            + "Differenz \(GermanFormat.number(change)) kg (berechnet aus \(recent.count) Einheiten).")
      } else {
        lines.append("\(exercise.name): zu wenige Einheiten in den letzten 4 Wochen für eine Entwicklung.")
      }
    }
    if lines.isEmpty {
      for session in sessions.suffix(5) {
        let volume = session.exercises.flatMap(\.doneSets).reduce(0) { $0 + $1.loadKg * Double($1.reps) }
        let sets = session.exercises.reduce(0) { $0 + $1.doneSets.count }
        lines.append(
          "Krafteinheit \(short(session.day)) (\(session.title)): \(sets) Arbeitssätze, "
            + "\(GermanFormat.number(volume.rounded())) kg Volumen (erfasst).")
      }
      if sessions.isEmpty { lines.append("Keine Krafteinheiten in den letzten 8 Wochen erfasst.") }
    }
    return lines
  }

  private static func enduranceLines(_ facts: Facts, today: CalendarDay) -> [String] {
    var lines: [String] = []
    if let week = facts.runWeek {
      lines.append(
        "Laufwoche: \(week.phase.label), \(week.totalMinutes) Minuten geplant, Schnitt der letzten vier Wochen "
          + "\(week.baselineMinutes) Minuten.")
    }
    let recent = facts.activities.filter { ($0.day ?? today) >= today.adding(days: -28) }.suffix(8)
    for activity in recent {
      let minutes = Int((activity.durationSeconds ?? 0) / 60)
      let distance = activity.distanceMeters.map { ", \(GermanFormat.decimal($0 / 1000)) km" } ?? ""
      lines.append(
        "\(activity.name ?? "Aktivität") am \(activity.day.map(short) ?? "?"): \(minutes) Minuten\(distance) (gemessen)."
      )
    }
    if recent.isEmpty { lines.append("Keine Ausdaueraktivitäten in den letzten 4 Wochen vorhanden.") }
    return lines
  }

  /// Titel können von anderen Personen stammen (geteilte Mahlzeit). Zahlen darin dürfen nicht als belegt gelten.
  private static func mealTitle(_ meal: MealLine) -> String {
    meal.title.filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces)
  }

  private static func nutritionLines(_ facts: Facts) -> [String] {
    // Schutzgrenze aktiv (z. B. Essstörung): keine Kalorien und Mengen, auch nicht als erfasste Werte.
    if facts.withholdsWeightTargets {
      return facts.todayMeals.prefix(8).map { "Mahlzeit heute: \(mealTitle($0))." }
    }
    var lines: [String] = []
    let eaten = facts.eaten
    if let eaten {
      lines.append(
        "Heute bisher erfasst: \(grams(eaten[.kcal])) kcal, \(grams(eaten[.protein])) g Protein, "
          + "\(grams(eaten[.carbs])) g Kohlenhydrate, \(grams(eaten[.fat])) g Fett (erfasst, teils KI-Schätzung).")
      for meal in facts.todayMeals.prefix(8) {
        lines.append(
          "Mahlzeit heute: \(mealTitle(meal)), \(grams(meal.nutrients[.kcal])) kcal, \(grams(meal.nutrients[.protein])) g Protein."
        )
      }
    } else {
      lines.append("Heute ist noch keine Mahlzeit erfasst.")
    }
    if !facts.withholdsWeightTargets, let targets = facts.targets {
      let goalKcal = grams(targets.values[.kcal])
      let goalProtein = grams(targets.values[.protein])
      lines.append("Tagesziel (Regel der App, \(targets.dayType.label)): \(goalKcal) kcal, \(goalProtein) g Protein.")
      lines.append(
        "Noch offen heute (berechnet): \(max(goalKcal - grams(eaten?[.kcal]), 0)) kcal, "
          + "\(max(goalProtein - grams(eaten?[.protein]), 0)) g Protein.")
    }
    if let average = facts.weekAverage {
      lines.append(
        "Schnitt der letzten 7 erfassten Tage: \(grams(average[.kcal])) kcal, \(grams(average[.protein])) g Protein.")
    }
    return lines
  }

  private static func recoveryLines(_ facts: Facts, today: CalendarDay) -> [String] {
    let full = facts.privacy == .full
    var lines: [String] = []
    if full, !facts.reasons.isEmpty { lines.append("Begründung der Ampel: \(facts.reasons.joined(separator: "; ")).") }
    if let sleep = facts.sleep {
      lines.append(
        full
          ? "Schlaf der letzten \(sleep.nights) Nächte: im Schnitt \(GermanFormat.decimal(sleep.averageHours)) Stunden (gemessen)."
          : "Schlaf der letzten Nächte: \(sleep.averageHours < 7 ? "im Schnitt unter 7 Stunden" : "im Schnitt mindestens 7 Stunden")."
      )
      lines.append("Empfohlene Schlafenszeit heute: \(SleepCoach.clock(sleep.bedtimeMinutes)).")
    } else {
      lines.append("Zu wenige Schlafdaten für eine Einschätzung.")
    }
    if full, let metrics = facts.todayMetrics {
      if let value = metrics.restingHeartRate { lines.append("Ruhepuls heute: \(Int(value)) (gemessen).") }
      if let value = metrics.hrvLastNightAverage { lines.append("HRV letzte Nacht: \(Int(value)) ms (gemessen).") }
    }
    if let zone = facts.formZone { lines.append("Form (Fitness gegen Ermüdung): \(zone.label).") }
    let lastDays = facts.gymSessions.filter { $0.day >= today.adding(days: -3) }
    for session in lastDays.suffix(3) {
      lines.append("Krafteinheit am \(short(session.day)): \(session.title) (erfasst).")
    }
    for activity in facts.activities.filter({ ($0.day ?? today) >= today.adding(days: -3) }).suffix(3) {
      lines.append(
        "\(activity.name ?? "Aktivität") am \(activity.day.map(short) ?? "?"): "
          + "\(Int((activity.durationSeconds ?? 0) / 60)) Minuten (gemessen).")
    }
    return lines
  }

  private static func longTermLines(_ facts: Facts, today: CalendarDay) -> [String] {
    var lines: [String] = []
    let gym = facts.gymSessions.filter { $0.day >= today.adding(days: -28) }.count
    let activities = facts.activities.filter { ($0.day ?? today) >= today.adding(days: -28) }.count
    lines.append("In den letzten 4 Wochen: \(gym) Krafteinheiten, \(activities) Ausdaueraktivitäten.")
    if let trend = facts.weightTrend, !facts.withholdsWeightTargets {
      if facts.privacy == .full {
        lines.append(
          "Gewichtstrend: \(GermanFormat.number(trend.trendKilograms)) kg, \(GermanFormat.number(trend.weeklyPercent)) % pro Woche (berechnet)."
        )
      } else {
        lines.append(
          "Gewichtstrend: \(abs(trend.weeklyPercent) < 0.1 ? "stabil" : trend.weeklyPercent < 0 ? "fallend" : "steigend")."
        )
      }
    }
    if facts.privacy == .full {
      for highlight in facts.weekHighlights.prefix(3) { lines.append("Wochenbericht: \(highlight)") }
    }
    return lines
  }

  /// Frühere Empfehlungen aus dem passenden Bereich und ob sie umgesetzt wurden.
  private static func recommendationLines(_ facts: Facts, topics: Set<ChatTopic>) -> [String] {
    var wanted = Set<InsightCategory>()
    if topics.contains(.strength) { wanted.insert(.strength) }
    if topics.contains(.endurance) { wanted.insert(.endurance) }
    if topics.contains(.nutrition) { wanted.formUnion([.nutrition, .bodyComposition]) }
    if topics.contains(.recovery) { wanted.formUnion([.recovery, .health]) }
    if topics.contains(.longTerm) { wanted.formUnion(InsightCategory.allCases) }
    let visible = facts.insights.filter { facts.privacy == .full || !$0.hasRawHealthValue }
    return visible.filter { wanted.contains($0.category) }.sorted { $0.created > $1.created }.prefix(5).map {
      let state: String
      switch $0.status {
      case .done: state = "umgesetzt"
      case .dismissed: state = "von der Person verworfen"
      default: state = "offen"
      }
      return "Frühere Empfehlung (\(state)): \($0.title)."
    }
  }

  /// Eingabe des Chats: Daten passend zur Frage, die letzten Nachrichten und ältere Fragen in Kurzform.
  public static func focusedInput(
    _ facts: Facts, question: String, history: [(role: String, text: String)], today: CalendarDay
  ) -> [String: JSONValue] {
    let topics = ChatRouter.topics(question: question, history: history)
    let recent = history.suffix(10)
    let older = history.dropLast(recent.count).filter { $0.role == "user" }.map { String($0.text.prefix(80)) }
    return [
      "question": .string(String(question.prefix(600))),
      "history": .array(
        recent.map { .object(["role": .string($0.role), "text": .string(String($0.text.prefix(800)))]) }),
      "olderQuestions": .array(older.suffix(6).map { .string($0) }),
      "facts": .array(focusedLines(facts, topics: topics, question: question, today: today).map { .string($0) }),
      "evidence": CoachingNote.evidenceInput(evidence),
    ]
  }
}
