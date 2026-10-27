import CoachCore
import Foundation
import SwiftData

/// Beispieldaten für die Screenshot-Tests (`-demo`): eine erfundene Musterperson, nur im Speicher, kein Abruf.
/// Im normalen Betrieb nie aktiv.
enum DemoData {
  static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

  /// `-demoScheme dark` bzw. `light` für die Screenshots.
  static var colorScheme: String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-demoScheme"), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
  }

  static func makeModel() -> AppModel {
    let defaults = UserDefaults(suiteName: "coach.demo") ?? .standard
    defaults.removePersistentDomain(forName: "coach.demo")
    let model = AppModel(
      inMemory: true, secrets: InMemorySecretStore([.garminAPIKey: "demo"]), defaults: defaults, isDemo: true)
    seed(model)
    return model
  }

  private static func seed(_ model: AppModel) {
    let today = CalendarDay(date: .now)
    var profile = UserProfile(
      mode: .personal, onboardingDone: true, sports: [.run, .strength], goal: .loseWeight)
    profile.setLevel(.intermediate, for: .run)
    profile.setLevel(.beginner, for: .strength)
    profile.targets.targetWeightKilograms = 68
    profile.targets.weeksToTargetWeight = 16
    profile.event = EventGoal(
      name: "Stadtlauf 10 km", date: today.adding(days: 63), kind: .run10k, targetSeconds: 3_120)
    var schedule = WeekSchedule()
    schedule.set([SessionSlot(.run)], on: .tuesday)
    schedule.set([SessionSlot(.strength, .hard)], on: .wednesday)
    schedule.set([SessionSlot(.run, .hard)], on: .thursday)
    schedule.set([SessionSlot(.strength, .hard)], on: .friday)
    schedule.set([SessionSlot(.run, .long)], on: .sunday)
    profile.schedule = schedule
    model.settings.profile = profile

    var nutrition = model.settings.nutrition
    nutrition.weightKilograms = 72
    nutrition.heightCentimeters = 170
    nutrition.age = 31
    nutrition.isFemale = true
    nutrition.diet = .omnivore
    model.settings.nutrition = nutrition
    model.settings.applyProfileToNutrition(garmin: nil, day: today)
    model.settings.companion.enabled = true
    model.settings.companion.kind = .daisy
    model.settings.companion.name = "Daisy"

    // Wägungen: leicht fallender Trend über vier Wochen.
    model.settings.weights = (0..<28).map { offset in
      let noise = [0.2, -0.1, 0.3, -0.2, 0.0, 0.1, -0.3][offset % 7]
      return WeightEntry(
        day: today.adding(days: offset - 27), kilograms: 73.2 - Double(offset) * 0.05 + noise, source: .manual)
    }

    let context = model.container.mainContext
    for offset in 0..<28 {
      let day = today.adding(days: -offset)
      var metrics = DailyMetrics(day: day)
      let wave = Double((offset * 7) % 11) - 5
      metrics.restingHeartRate = 54 + wave * 0.4
      metrics.hrvLastNightAverage = 62 - wave
      metrics.hrvWeeklyAverage = 61
      metrics.hrvStatus = "BALANCED"
      metrics.hrvBaselineLow = 52
      metrics.hrvBaselineHigh = 70
      metrics.sleepSeconds = (7.2 + wave * 0.08) * 3_600
      metrics.sleepScore = 78 + wave
      metrics.bodyBatteryHigh = 88 + wave
      metrics.bodyBatteryLow = 22
      metrics.bodyBatteryLatest = 64
      metrics.stressAverage = 31
      metrics.steps = 9_400 + wave * 600
      metrics.vo2Max = 47
      metrics.trainingReadiness = 71 + wave * 2
      metrics.trainingReadinessLevel = "HIGH"
      metrics.trainingStatus = "PRODUCTIVE_3"
      context.insert(DailyMetricsRecord(metrics: metrics))
    }

    // Läufe der letzten vier Wochen (Di locker, Do Intervalle, So lang).
    var id: Int64 = 1
    for offset in 1..<28 {
      let day = today.adding(days: -offset)
      let weekday = Weekday(day: day)
      let run: (name: String, minutes: Double, kilometers: Double, heartRate: Double)? =
        switch weekday {
        case .tuesday: ("Lockerer Lauf", 42, 7.1, 138)
        case .thursday: ("Intervalle 5 × 1000 m", 50, 8.4, 152)
        case .sunday: ("Langer Lauf", 80, 13.2, 141)
        default: nil
        }
      guard let run else { continue }
      var activity = GarminActivity(id: id)
      id += 1
      activity.name = run.name
      activity.typeKey = "running"
      activity.startLocal = "\(day.iso) 07:15:00"
      activity.durationSeconds = run.minutes * 60
      activity.distanceMeters = run.kilometers * 1_000
      activity.averageHeartRate = run.heartRate
      activity.maxHeartRate = run.heartRate + 22
      activity.calories = run.minutes * 11
      activity.trainingLoad = run.minutes * 1.6
      activity.aerobicTrainingEffect = 3.1
      context.insert(ActivityRecord(activity: activity))
    }

    // Krafteinheiten (Mi und Fr).
    for offset in 1..<28 {
      let day = today.adding(days: -offset)
      guard [.wednesday, .friday].contains(Weekday(day: day)) else { continue }
      let week = Double(offset / 7)
      let start = Calendar.current.date(byAdding: .hour, value: 18, to: Calendar.current.startOfDay(for: day.localDate))
        ?? day.localDate
      let session = GymSession(
        workoutKey: nil, title: "Ganzkörper", start: start, end: start.addingTimeInterval(55 * 60),
        exercises: [
          LoggedExercise(
            exerciseID: "kniebeuge", name: "Kniebeuge", group: .legs,
            sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 50 - 2.5 * week, rir: 2) }),
          LoggedExercise(
            exerciseID: "bankdruecken", name: "Bankdrücken", group: .chest,
            sets: (0..<3).map { _ in LoggedSet(reps: 8, weightKg: 35 - 2.5 * week, rir: 2) }),
          LoggedExercise(
            exerciseID: "rudern_kabel", name: "Rudern am Kabel", group: .back,
            sets: (0..<3).map { _ in LoggedSet(reps: 10, weightKg: 40, rir: 3) }),
        ])
      context.insert(GymSessionRecord(session: session))
    }

    // Mahlzeiten von heute.
    func item(_ name: String, _ grams: Double, _ values: [Nutrient: Double]) -> MealItem {
      MealItem(name: name, grams: grams, source: .manual, per100g: NutrientValues(values))
    }
    context.insert(
      MealRecord(
        day: today, category: .breakfast, title: "Haferflocken mit Beeren", hint: "",
        items: [
          item("Haferflocken", 70, [.kcal: 370, .protein: 13, .carbs: 59, .fat: 7, .fiber: 10]),
          item("Skyr", 150, [.kcal: 63, .protein: 11, .carbs: 4, .fat: 0.2]),
          item("Heidelbeeren", 100, [.kcal: 42, .protein: 0.7, .carbs: 7.4, .fat: 0.6, .fiber: 4.9]),
        ]))
    context.insert(
      MealRecord(
        day: today, category: .lunch, title: "Linsen-Bowl", hint: "",
        items: [
          item("Rote Linsen, gekocht", 200, [.kcal: 116, .protein: 9, .carbs: 17, .fat: 0.4, .fiber: 8]),
          item("Reis, gekocht", 150, [.kcal: 130, .protein: 2.7, .carbs: 28, .fat: 0.3]),
          item("Paprika", 100, [.kcal: 26, .protein: 1, .carbs: 4.6, .fat: 0.3, .fiber: 2]),
        ]))
    try? context.save()
  }
}
