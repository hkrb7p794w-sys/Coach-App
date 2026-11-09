import Foundation

/// Beziehung zu einer anderen Person (wie `worker/src/social.ts`).
public enum SocialRelation: String, Codable, Sendable {
  case me = "self"
  case friends, incoming, outgoing, none, blocked
}

public struct SocialPerson: Codable, Equatable, Sendable, Identifiable, Hashable {
  public var username: String
  public var displayName: String
  public var relation: SocialRelation?
  public var since: String?
  public var id: String { username }

  public init(username: String, displayName: String, relation: SocialRelation? = nil, since: String? = nil) {
    self.username = username
    self.displayName = displayName
    self.relation = relation
    self.since = since
  }

  /// Initial für den Avatar.
  public var initial: String { String((displayName.first ?? username.first ?? "?")).uppercased() }
}

public struct SocialFriends: Codable, Equatable, Sendable {
  public var friends: [SocialPerson]
  public var incoming: [SocialPerson]
  public var outgoing: [SocialPerson]

  public init(friends: [SocialPerson] = [], incoming: [SocialPerson] = [], outgoing: [SocialPerson] = []) {
    self.friends = friends
    self.incoming = incoming
    self.outgoing = outgoing
  }
}

/// Reaktionen wie im Worker (`REACTIONS`).
public enum SocialReaction: String, CaseIterable, Sendable {
  case clap = "👏"
  case fire = "🔥"
  case strong = "💪"
  case yummy = "😋"
  case heart = "❤️"

  public var label: String {
    switch self {
    case .clap: "Applaus"
    case .fire: "Stark"
    case .strong: "Kraft"
    case .yummy: "Lecker"
    case .heart: "Herz"
    }
  }
}

/// Beitrag im Feed. Der Inhalt hängt von der Art ab; unbekannte Arten zeigt die App als Hinweis.
public struct SocialPost: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable {
    case workout, meal, milestone, unknown

    public init(from decoder: any Decoder) throws {
      self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
  }

  public struct Payload: Codable, Equatable, Sendable {
    public var sport: String?
    public var title: String?
    public var durationMin: Double?
    public var distanceKm: Double?
    public var elevationM: Double?
    public var sets: Double?
    public var volumeKg: Double?
    public var exercises: [String]?
    public var records: [String]?
    public var note: String?
    public var meal: SharedMeal?
    public var text: String?
    public var badge: String?

    public init() {}
  }

  public var id: String
  public var kind: Kind
  public var createdAt: String
  public var author: SocialPerson
  public var mine: Bool
  public var payload: Payload
  public var reactions: Int
  public var myReaction: String?
  public var topReactions: String
  public var comments: Int

  public var date: Date? { SocialFormat.date(createdAt) }

  /// Überschrift im Feed, z. B. „Lockerer Lauf“ oder „Overnight Oats“.
  public var headline: String {
    switch kind {
    case .meal: payload.meal?.title ?? "Mahlzeit"
    case .workout, .milestone: payload.title ?? "Beitrag"
    case .unknown: "Beitrag (neuere App-Version nötig)"
    }
  }

  /// Kennzahlen in einer Zeile, z. B. „45 min · 8,2 km“ oder „620 kcal · 42 g Protein“.
  public var facts: String {
    var parts: [String] = []
    switch kind {
    case .workout:
      if let minutes = payload.durationMin { parts.append("\(Int(minutes.rounded())) min") }
      if let km = payload.distanceKm, km > 0 { parts.append("\(GermanFormat.decimal(km)) km") }
      if let up = payload.elevationM, up >= 10 { parts.append("\(Int(up.rounded())) hm") }
      if let sets = payload.sets, sets > 0 { parts.append("\(Int(sets)) Sätze") }
      if let volume = payload.volumeKg, volume > 0 {
        parts.append("\(GermanFormat.number((volume / 100).rounded() * 100)) kg bewegt")
      }
    case .meal:
      if let meal = payload.meal {
        parts.append("\(Int(meal.kilocalories.rounded())) kcal")
        let protein = NutritionSummary.totals(meal.mealItems)[.protein] ?? 0
        if protein > 0 { parts.append("\(Int(protein.rounded())) g Protein") }
      }
    case .milestone:
      if let text = payload.text { parts.append(text) }
    case .unknown: break
    }
    return parts.joined(separator: " · ")
  }

  public var symbol: String {
    switch kind {
    case .meal: "fork.knife"
    case .milestone: "trophy.fill"
    case .unknown: "questionmark.circle"
    case .workout:
      switch payload.sport {
      case "run": "figure.run"
      case "bike": "figure.outdoor.cycle"
      case "swim": "figure.pool.swim"
      case "strength": "dumbbell.fill"
      case "walk": "figure.walk"
      case "hike": "figure.hiking"
      case "yoga", "mobility": "figure.yoga"
      default: "figure.mixed.cardio"
      }
    }
  }
}

public struct SocialComment: Codable, Equatable, Sendable, Identifiable {
  public var id: String
  public var text: String
  public var createdAt: String
  public var author: SocialPerson
  public var canDelete: Bool
}

/// Was beim Teilen eines Trainings an Freunde geht – bewusst ohne Körperwerte (Puls, Gewicht, HRV, Schlaf, Kalorien).
public struct WorkoutShare: Codable, Equatable, Sendable {
  public var kind = "workout"
  public var sport: String
  public var title: String
  public var durationMin: Int?
  public var distanceKm: Double?
  public var elevationM: Int?
  public var sets: Int?
  public var volumeKg: Int?
  public var exercises: [String]?
  public var records: [String]?
  public var note: String?

  public init(sport: String, title: String) {
    self.sport = sport
    self.title = title
  }

  /// Krafteinheit: Dauer, Sätze, bewegtes Gewicht, Übungen (höchstens 12) und neue Bestleistungen.
  public static func gym(_ session: GymSession, records: [String] = [], now: Date = .now) -> WorkoutShare {
    var share = WorkoutShare(sport: "strength", title: session.title.isEmpty ? "Krafttraining" : session.title)
    let end = session.end ?? now
    share.durationMin = max(1, Int((end.timeIntervalSince(session.start) / 60).rounded()))
    share.sets = session.doneSetCount
    if session.volumeKg > 0 { share.volumeKg = Int(session.volumeKg.rounded()) }
    let names = session.exercises.filter { !$0.doneSets.isEmpty }.map(\.name)
    if !names.isEmpty { share.exercises = Array(names.prefix(12)) }
    if !records.isEmpty { share.records = Array(records.prefix(10)) }
    return share
  }

  /// Ausdaueraktivität: Sportart, Dauer, Strecke, Höhenmeter – Puls und Kalorien bleiben auf dem Gerät.
  public static func activity(_ activity: GarminActivity) -> WorkoutShare {
    let key = activity.typeKey?.lowercased() ?? ""
    let sport: String =
      switch activity.sport {
      case .run: "run"
      case .bike: "bike"
      case .swim: "swim"
      case .strength: "strength"
      case .other:
        key.contains("hik") ? "hike" : key.contains("walk") ? "walk" : key.contains("yoga") ? "yoga" : "other"
      }
    let fallback: String =
      switch sport {
      case "run": "Lauf"
      case "bike": "Radfahrt"
      case "swim": "Schwimmen"
      case "strength": "Krafttraining"
      case "walk": "Spaziergang"
      case "hike": "Wanderung"
      case "yoga": "Yoga"
      default: "Training"
      }
    let name = activity.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var share = WorkoutShare(sport: sport, title: String((name.isEmpty ? fallback : name).prefix(80)))
    if let seconds = activity.movingSeconds ?? activity.durationSeconds, seconds > 0 {
      share.durationMin = max(1, Int((seconds / 60).rounded()))
    }
    if let meters = activity.distanceMeters, meters >= 100 {
      share.distanceKm = (meters / 100).rounded() / 10
    }
    if let up = activity.elevationGain, up >= 10 { share.elevationM = Int(up.rounded()) }
    return share
  }
}

/// Mahlzeit für den Feed: dieselben Felder wie beim Teilen per Code (`SharedMeal`).
public struct MealPostShare: Codable, Equatable, Sendable {
  public var kind = "meal"
  public var meal: SharedMeal
  public var note: String?

  public init(meal: SharedMeal, note: String? = nil) {
    self.meal = meal
    self.note = note
  }
}

public enum SocialFormat {
  public static func date(_ iso: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
  }

  /// „gerade eben“, „vor 5 Min.“, „vor 3 Std.“, „gestern“, sonst Datum.
  public static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 { return "gerade eben" }
    if seconds < 3_600 { return "vor \(Int(seconds / 60)) Min." }
    if calendar.isDate(date, inSameDayAs: now) { return "vor \(Int(seconds / 3_600)) Std." }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday)
    {
      return "gestern"
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "de_DE")
    formatter.dateFormat = "d. MMM"
    return formatter.string(from: date)
  }
}
