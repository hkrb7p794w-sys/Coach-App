import CoachCore
import SwiftUI

/// Einrichtung und späteres Bearbeiten des Profils: Sportarten, Ziel, Fokus, Erfahrung, Körperdaten mit
/// Sicherheitscheck und Wochenplan. Die App passt Pläne, Ernährung und Empfehlungen daran an.
struct OnboardingView: View {
  enum Step: Int, CaseIterable {
    case sports, goal, focus, level, body, schedule, summary

    var title: String {
      switch self {
      case .sports: "Was trainierst du?"
      case .goal: "Was ist dein Ziel?"
      case .focus: "Worauf bereitest du dich vor?"
      case .level: "Wie viel Erfahrung hast du?"
      case .body: "Über dich"
      case .schedule: "Dein Wochenplan"
      case .summary: "Alles bereit"
      }
    }
  }

  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  /// Beim Bearbeiten gibt es ein Schließen-Kreuz, beim ersten Start nicht.
  let isEditing: Bool
  /// Ausgangswerte; leer = neues Profil.
  let initial: UserProfile

  @State private var step: Step = .sports
  @State private var draft = UserProfile()
  @State private var loaded = false

  @State private var eventEnabled = false
  @State private var eventName = ""
  @State private var eventDate = Calendar.current.date(byAdding: .month, value: 4, to: .now) ?? .now
  @State private var eventKind: EventKind = .run10k
  @State private var eventTarget = ""
  @State private var runDistance = ""
  @State private var runPace = ""
  @State private var restingHeartRate = ""
  @State private var targetWeight = ""
  @State private var weeks = ""
  @State private var currentRunKilometers = ""

  @State private var weight = ""
  @State private var height = ""
  @State private var age = ""
  @State private var isFemale = true
  @State private var diet: Diet = .omnivore

  @State private var availableDays: Set<Weekday> = []

  init(isEditing: Bool = false, initial: UserProfile = UserProfile()) {
    self.isEditing = isEditing
    self.initial = initial
  }

  var body: some View {
    NavigationStack {
      Group {
        switch step {
        case .sports: sportsStep
        case .goal: goalStep
        case .focus: focusStep
        case .level: levelStep
        case .body: bodyStep
        case .schedule: scheduleStep
        case .summary: summaryStep
        }
      }
      .navigationTitle(step.title)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if step != .sports {
            Button("Zurück", systemImage: "chevron.backward") { go(-1) }
          }
        }
        if isEditing {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Schließen", systemImage: "xmark") { dismiss() }
          }
        }
      }
      .safeAreaInset(edge: .bottom) { bottomBar }
    }
    .interactiveDismissDisabled(!isEditing)
    .task { loadOnce() }
  }

  // MARK: - Schritte

  private var sportsStep: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Wähle alles, was du regelmäßig machst oder machen möchtest. Die App richtet sich danach.")
          .foregroundStyle(.secondary)
        ForEach(TrainingSport.allCases) { sport in
          SelectionCard(
            title: sport.label, detail: nil, symbol: sport.symbol, color: sport.color,
            isSelected: draft.sports.contains(sport)
          ) {
            if let index = draft.sports.firstIndex(of: sport) {
              draft.sports.remove(at: index)
            } else {
              draft.sports.append(sport)
            }
          }
        }
      }
      .padding(16)
    }
  }

  private var goalStep: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Das Hauptziel bestimmt Ernährung, Trainingsverteilung und Empfehlungen.")
          .foregroundStyle(.secondary)
        ForEach(FitnessGoal.allCases) { goal in
          SelectionCard(
            title: goal.label, detail: goal.detail, symbol: goal.symbol, color: .accentColor,
            isSelected: draft.goal == goal
          ) { draft.goal = goal }
        }
      }
      .padding(16)
    }
  }

  private var focusStep: some View {
    Form {
      Section {
        Picker("Fokus", selection: $eventEnabled) {
          Text("Allgemein besser werden").tag(false)
          Text("Wettkampf oder Lauf").tag(true)
        }
        .pickerStyle(.inline)
        .labelsHidden()
      }
      if eventEnabled {
        Section("Wettkampf") {
          TextField("Name (z. B. Stadtlauf)", text: $eventName)
          Picker("Art", selection: $eventKind) {
            ForEach(EventKind.allCases) { Text($0.label).tag($0) }
          }
          DatePicker("Datum", selection: $eventDate, in: Date.now..., displayedComponents: .date)
          TextField("Zielzeit (optional, z. B. 1:45:00)", text: $eventTarget)
            .keyboardType(.numbersAndPunctuation)
        }
      } else {
        Section {
          if draft.trains(.run) {
            TextField("Strecke am Stück in km (z. B. 10)", text: $runDistance)
              .keyboardType(.decimalPad)
            TextField("Wunschtempo in min/km (z. B. 5:45)", text: $runPace)
              .keyboardType(.numbersAndPunctuation)
          }
          TextField("Ruhepuls senken auf … bpm", text: $restingHeartRate)
            .keyboardType(.numberPad)
          if draft.goal.losesWeight || draft.goal.gainsWeight {
            TextField("Zielgewicht in kg", text: $targetWeight)
              .keyboardType(.decimalPad)
            TextField("In wie vielen Wochen? (optional)", text: $weeks)
              .keyboardType(.numberPad)
          }
        } header: {
          Text("Ziele (alles optional)")
        } footer: {
          Text(
            "Das Tempo beim Gewicht begrenzt die App auf einen gesunden Bereich, auch wenn der Wunsch schneller wäre.")
        }
      }
    }
  }

  private var levelStep: some View {
    Form {
      ForEach(draft.sports.filter { $0 != .other }) { sport in
        Section {
          Picker(
            sport.label,
            selection: Binding(get: { draft.level(for: sport) }, set: { draft.setLevel($0, for: sport) })
          ) {
            ForEach(ExperienceLevel.allCases) { level in
              VStack(alignment: .leading) {
                Text(level.label)
                Text(level.detail).font(.caption).foregroundStyle(.secondary)
              }
              .tag(level)
            }
          }
          .pickerStyle(.inline)
          .labelsHidden()
        } header: {
          Label(sport.label, systemImage: sport.symbol)
        }
      }
      if draft.trains(.run) {
        Section {
          TextField("Kilometer pro Woche", text: $currentRunKilometers)
            .keyboardType(.decimalPad)
        } header: {
          Text("Aktuell gelaufen")
        } footer: {
          Text("Leer lassen: Dann nutzt die App deine Garmin-Daten der letzten Wochen.")
        }
      }
    }
  }

  private var bodyStep: some View {
    Form {
      Section {
        TextField("Gewicht in kg", text: $weight).keyboardType(.decimalPad)
        TextField("Größe in cm", text: $height).keyboardType(.numberPad)
        TextField("Alter", text: $age).keyboardType(.numberPad)
        Picker("Geschlecht", selection: $isFemale) {
          Text("Weiblich").tag(true)
          Text("Männlich").tag(false)
        }
        Picker("Ernährung", selection: $diet) {
          ForEach(Diet.allCases, id: \.self) { Text($0.label).tag($0) }
        }
      } header: {
        Text("Körperdaten")
      } footer: {
        Text("Für Kalorien- und Proteinziele. Leer lassen geht nicht; du kannst sie später ändern.")
      }

      Section {
        ForEach(HealthFlag.allCases) { flag in
          Toggle(
            flag.label,
            isOn: Binding(
              get: { draft.health.contains(flag) },
              set: { isOn in
                if isOn { draft.health.append(flag) } else { draft.health.removeAll { $0 == flag } }
              }))
        }
      } header: {
        Text("Sicherheits-Check")
      } footer: {
        Text(
          "Bei diesen Angaben ist die App vorsichtiger und setzt keine Gewichtsziele. Sie "
            + "ersetzt keine ärztliche Beratung."
        )
      }

      if let assessment = currentAssessment, !assessment.notes.isEmpty {
        Section("Hinweise zu deinem Ziel") {
          ForEach(assessment.notes, id: \.self) { Text($0).font(.subheadline) }
          EvidenceDisclosure(ruleIDs: assessment.evidenceIDs)
        }
      }
    }
  }

  private var scheduleStep: some View {
    Form {
      Section {
        HStack(spacing: 6) {
          ForEach(Weekday.allCases) { weekday in
            DayToggle(weekday: weekday, isOn: availableDays.contains(weekday)) {
              if availableDays.contains(weekday) {
                availableDays.remove(weekday)
              } else {
                availableDays.insert(weekday)
              }
            }
          }
        }
        Button {
          draft.schedule = SchedulePlanner.suggest(profile: draft, availableDays: Array(availableDays))
        } label: {
          Label("Wochenplan vorschlagen", systemImage: "wand.and.stars")
        }
        .disabled(availableDays.isEmpty || draft.sports.isEmpty)
      } header: {
        Text("An welchen Tagen hast du Zeit?")
      } footer: {
        Text("Die App verteilt passende Einheiten auf diese Tage. Danach kannst du alles frei ändern.")
      }

      Section {
        ScheduleEditor(schedule: $draft.schedule, sports: draft.sports)
      } header: {
        Text("Was machst du an welchem Tag?")
      }

      ScheduleHintsSection(hints: ScheduleCheck.hints(schedule: draft.schedule, profile: draft))
    }
  }

  private var summaryStep: some View {
    List {
      Section("Dein Profil") {
        LabeledContent("Sportarten", value: draft.sports.map(\.shortLabel).joined(separator: ", "))
        LabeledContent("Ziel", value: draft.goal.label)
        if let event = draft.event {
          LabeledContent("Wettkampf", value: "\(event.name) · \(GermanFormat.date(event.date))")
        }
        LabeledContent("Trainingstage", value: "\(draft.schedule.trainingDays.count) pro Woche")
      }
      if let assessment = currentAssessment, !assessment.notes.isEmpty {
        Section("Gut zu wissen") {
          ForEach(assessment.notes, id: \.self) { Text($0).font(.subheadline) }
        }
      }
      Section {
        Text(
          "Die App prüft täglich deine Erholung (Garmin) gegen deinen Wochenplan und schlägt vor, Einheiten zu "
            + "verschieben oder lockerer zu machen. Ruhetage und Ziele kannst du jederzeit in den "
            + "Einstellungen ändern."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: - Navigation

  private var bottomBar: some View {
    VStack(spacing: 8) {
      ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
        .accessibilityLabel("Schritt \(step.rawValue + 1) von \(Step.allCases.count)")
      Button {
        if step == .summary { finish() } else { go(1) }
      } label: {
        Text(step == .summary ? "Los geht’s" : "Weiter")
          .font(.headline)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canContinue)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(.bar)
  }

  private var canContinue: Bool {
    switch step {
    case .sports: !draft.sports.isEmpty
    case .body: bodyIsValid
    case .schedule: !draft.schedule.isEmpty
    default: true
    }
  }

  private func go(_ direction: Int) {
    if direction > 0 { commit(step) }
    guard let next = Step(rawValue: step.rawValue + direction) else { return }
    // Ohne Ausdauersportart gibt es keine Wettkampfwahl für Läufe; der Schritt bleibt aber für Ruhepuls und Gewicht.
    withAnimation { step = next }
  }

  // MARK: - Daten

  private func loadOnce() {
    guard !loaded else { return }
    loaded = true
    draft = initial
    if let event = initial.event {
      eventEnabled = true
      eventName = event.name
      eventDate = event.date.localDate
      eventKind = event.kind
      eventTarget = event.targetSeconds.map(TimeText.hms) ?? ""
    }
    let targets = initial.targets
    runDistance = targets.runDistanceKilometers.map { GermanFormat.decimal($0) } ?? ""
    runPace = targets.runPaceSecondsPerKilometer.map { GermanFormat.minutesSeconds($0) } ?? ""
    restingHeartRate = targets.restingHeartRate.map(String.init) ?? ""
    targetWeight = targets.targetWeightKilograms.map { GermanFormat.decimal($0) } ?? ""
    weeks = targets.weeksToTargetWeight.map(String.init) ?? ""
    currentRunKilometers = initial.currentRunKilometersPerWeek.map { GermanFormat.decimal($0) } ?? ""
    availableDays = Set(initial.schedule.trainingDays)

    let known = model.settings.nutrition
    let bodyProfile = known.profile(garmin: model.sync.profile, on: CalendarDay(date: .now))
    if known.weightKilograms != nil || model.sync.profile != nil || isEditing {
      weight = GermanFormat.decimal(bodyProfile.weightKilograms)
      height = String(Int(bodyProfile.heightCentimeters.rounded()))
      age = String(bodyProfile.age)
      isFemale = bodyProfile.isFemale
      diet = known.diet
    }
  }

  private func number(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
  }

  private var bodyIsValid: Bool {
    guard let weight = number(weight), let height = number(height), let age = Int(age) else { return false }
    return (30...250).contains(weight) && (120...230).contains(height) && (14...100).contains(age)
  }

  private var currentAssessment: GoalAssessment? {
    guard bodyIsValid, let weight = number(weight), let height = number(height), let age = Int(age) else { return nil }
    return GoalRules.assess(
      profile: draft,
      body: BodyProfile(weightKilograms: weight, heightCentimeters: height, age: age, isFemale: isFemale))
  }

  /// Übernimmt die Eingaben eines Schritts ins Profil.
  private func commit(_ step: Step) {
    switch step {
    case .focus:
      if eventEnabled {
        draft.event = EventGoal(
          name: eventName.trimmingCharacters(in: .whitespaces).isEmpty ? eventKind.label : eventName,
          date: CalendarDay(date: eventDate), kind: eventKind, targetSeconds: TimeText.seconds(eventTarget))
      } else {
        draft.event = nil
      }
      var targets = ImprovementTargets()
      if !eventEnabled {
        targets.runDistanceKilometers = number(runDistance)
        targets.runPaceSecondsPerKilometer = TimeText.seconds(runPace)
      }
      targets.restingHeartRate = Int(restingHeartRate)
      targets.targetWeightKilograms = number(targetWeight)
      targets.weeksToTargetWeight = Int(weeks)
      draft.targets = targets
    case .level:
      draft.currentRunKilometersPerWeek = number(currentRunKilometers)
    default:
      break
    }
  }

  private func finish() {
    commit(.focus)
    commit(.level)
    draft.mode = .personal
    draft.onboardingDone = true
    var nutrition = model.settings.nutrition
    nutrition.weightKilograms = number(weight)
    nutrition.heightCentimeters = number(height)
    nutrition.age = Int(age)
    nutrition.isFemale = isFemale
    nutrition.diet = diet
    model.settings.nutrition = nutrition
    model.settings.profile = draft
    model.settings.applyProfileToNutrition(garmin: model.sync.profile)
    dismiss()
  }
}

// MARK: - Bausteine

/// Große, gut tippbare Auswahlkarte.
private struct SelectionCard: View {
  let title: String
  let detail: String?
  let symbol: String
  let color: Color
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        SportIcon(symbol: symbol, color: color, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
          if let detail {
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.title3)
          .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
      }
      .padding(14)
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
    .sensoryFeedback(.selection, trigger: isSelected)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

private struct DayToggle: View {
  let weekday: Weekday
  let isOn: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(weekday.short)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(isOn ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(weekday.long)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}
