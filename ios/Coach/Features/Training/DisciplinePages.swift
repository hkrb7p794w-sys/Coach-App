import Charts
import CoachCore
import SwiftUI

// MARK: - Bausteine

/// Liest „m:ss“ bzw. „h:mm:ss“ in Sekunden.
enum TimeText {
  static func seconds(_ text: String) -> Int? {
    let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
    guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
    let values = parts.compactMap { $0 }
    switch values.count {
    case 2 where values[1] < 60: return values[0] * 60 + values[1]
    case 3 where values[1] < 60 && values[2] < 60: return values[0] * 3600 + values[1] * 60 + values[2]
    default: return nil
    }
  }

  static func hms(_ seconds: Int) -> String {
    String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
  }
}

/// Tabelle aus Tempo- oder Zonenzeilen.
struct PaceTableSection: View {
  let title: String
  let rows: [PaceRow]
  var footer: String?

  var body: some View {
    Section {
      ForEach(rows) { row in
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 1) {
            Text(row.label).font(.subheadline.weight(row.isKey ? .semibold : .regular))
            Text(row.use).font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          Text(row.value)
            .font(.body.monospacedDigit().weight(row.isKey ? .bold : .regular))
        }
      }
    } header: {
      Text(title)
    } footer: {
      if let footer { Text(footer) }
    }
  }
}

/// Verlauf eingetragener Testwerte.
struct TestTrendSection: View {
  let title: String
  let kind: TestRecord.Kind
  let format: (Double) -> String
  /// Kleiner ist besser (Paces): Achse umdrehen, damit „besser“ oben liegt.
  var lowerIsBetter = false
  @Environment(AppModel.self) private var model

  var body: some View {
    let values = TestHistory.values(kind, in: model.settings.tests)
    Section {
      if values.isEmpty {
        Text("Noch kein Test eingetragen.").foregroundStyle(.secondary)
      } else {
        HStack {
          Text("Zuletzt \(values.last.map { Formatters.day($0.day) } ?? "")").font(.subheadline)
          Spacer()
          Text(values.last.map { format($0.value) } ?? "–").font(.title3.weight(.semibold)).monospacedDigit()
        }
        if values.count > 1 {
          Chart(values) { point in
            LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(title, point.value))
            PointMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value(title, point.value))
          }
          .chartYScale(domain: .automatic(includesZero: false, reversed: lowerIsBetter))
          .chartYAxis {
            AxisMarks { value in
              AxisGridLine()
              AxisValueLabel { Text(value.as(Double.self).map(format) ?? "") }
            }
          }
          .frame(height: 120)
        }
      }
    } header: {
      Text(title)
    }
  }
}

/// Eingabe eines Testwerts als Text („8:40“), mit Übernehmen-Knopf.
struct TestEntrySection<Extra: View>: View {
  let title: String
  let fields: [(label: String, placeholder: String)]
  let footer: String
  /// Werte der Felder → Ergebnistext und Übernahme, oder `nil` bei ungültiger Eingabe.
  let evaluate: ([String]) -> (preview: String, apply: () -> Void)?
  @ViewBuilder var extra: () -> Extra
  @State private var inputs: [String] = []
  @State private var applied = false

  var body: some View {
    let result = evaluate(inputs)
    Section {
      ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
        LabeledContent(field.label) {
          TextField(field.placeholder, text: binding(index))
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
        }
      }
      if let result {
        LabeledContent("Ergebnis", value: result.preview).bold()
      }
      Button(applied ? "Übernommen" : "Übernehmen", systemImage: applied ? "checkmark" : "square.and.arrow.down") {
        result?.apply()
        applied = true
        inputs = Array(repeating: "", count: fields.count)
      }
      .disabled(result == nil)
      extra()
    } header: {
      Text(title)
    } footer: {
      Text(footer)
    }
    .onAppear { if inputs.count != fields.count { inputs = Array(repeating: "", count: fields.count) } }
    .onChange(of: inputs) { if inputs.contains(where: { !$0.isEmpty }) { applied = false } }
  }

  private func binding(_ index: Int) -> Binding<String> {
    Binding(
      get: { inputs.indices.contains(index) ? inputs[index] : "" },
      set: { value in
        if inputs.count != fields.count { inputs = Array(repeating: "", count: fields.count) }
        inputs[index] = value
      })
  }
}

extension TestEntrySection where Extra == EmptyView {
  init(
    title: String, fields: [(label: String, placeholder: String)], footer: String,
    evaluate: @escaping ([String]) -> (preview: String, apply: () -> Void)?
  ) {
    self.init(title: title, fields: fields, footer: footer, evaluate: evaluate) { EmptyView() }
  }
}

// MARK: - Schwimmen

struct SwimPage: View {
  let viewModel: TrainingViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    let css = model.settings.season.cssSecondsPer100m
    List {
      KilometersSection(viewModel: viewModel, sport: .swim, color: .blue)
      TestTrendSection(
        title: "CSS · Schwellentempo /100 m", kind: .css, format: { PlanTokens.mmss(Int($0)) },
        lowerIsBetter: true)
      PaceTableSection(title: "Paces aus der CSS", rows: SwimPaces.rows(css: css))
      Section("Technik-Fokus bei 2:00–2:15 /100 m") {
        Label("Ausatmen unter Wasser – ruhig und kontinuierlich, dann reicht das kurze Einatmen.", systemImage: "wind")
        Label(
          "Hoher Ellbogen beim Fassen – Unterarm früh senkrecht stellen, nicht mit gestrecktem Arm drücken.",
          systemImage: "hand.raised")
        Label(
          "Ruhiger Kopf, Blick nach unten – hebt die Beine. Ab Frühjahr: Sighting alle 6–8 Züge.",
          systemImage: "eye")
      }
      .font(.subheadline)
      TestEntrySection(
        title: "CSS-Test eintragen",
        fields: [("400 m maximal", "z. B. 8:40"), ("200 m maximal", "z. B. 4:20")],
        footer:
          "Einschwimmen 400 m, 400 m maximal, 5–10 min locker, 200 m maximal. CSS = (Zeit 400 − Zeit 200) ÷ 2.",
        evaluate: { values in
          guard values.count == 2, let t400 = TimeText.seconds(values[0]), let t200 = TimeText.seconds(values[1]),
            let css = SwimPaces.css(time400: t400, time200: t200)
          else { return nil }
          return ("CSS \(PlanTokens.mmss(css)) /100 m", { model.settings.record(.css, value: Double(css)) })
        })
      Section { EvidenceDisclosure(ruleIDs: ["swim.css", "intensity.distribution"]) }
    }
    .navigationTitle("Schwimmen")
  }
}

// MARK: - Rad

struct BikePage: View {
  let viewModel: TrainingViewModel
  @Environment(AppModel.self) private var model
  @State private var showWorkouts = false

  var body: some View {
    let season = model.settings.season
    List {
      KilometersSection(viewModel: viewModel, sport: .bike, color: .orange)
      TestTrendSection(title: "FTP · Zwift-Test", kind: .ftp, format: { "\(Int($0)) W" })
      VO2Section(title: "VO2max Rad (Garmin)", trend: viewModel.vo2Bike)
      PaceTableSection(
        title: "Zonen aus FTP \(season.ftpWatts) W", rows: BikeZones.rows(ftp: season.ftpWatts),
        footer: "FTP nur als Referenz für Watt-Angaben – keine Umrechnung in km/h.")
      if let schedule = viewModel.schedule {
        Section {
          DisclosureGroup("Zwift-Workouts (\(schedule.zw.count))", isExpanded: $showWorkouts) {
            ForEach(schedule.zw) { workout in
              VStack(alignment: .leading, spacing: 2) {
                Text("\(workout.c) · \(workout.n)").font(.subheadline.weight(.semibold))
                Text(PlanTokens(config: season).fill(workout.t)).font(.footnote).foregroundStyle(.secondary)
              }
            }
          }
        }
      }
      TestEntrySection(
        title: "FTP eintragen", fields: [("FTP in Watt", "z. B. 185")],
        footer: "Zwift ›FTP Ramp Test Lite‹ – gleicher Test wie bisher, damit die Werte vergleichbar bleiben.",
        evaluate: { values in
          guard let watts = values.first.flatMap({ Int($0) }), (80...500).contains(watts) else { return nil }
          return ("\(watts) W", { model.settings.record(.ftp, value: Double(watts)) })
        })
      TestEntrySection(
        title: "Rad-Schnitt für Almere",
        fields: [("km/h auf 94 km", GermanFormat.decimal(season.raceBikeSpeedKmh))],
        footer: "Benchmark aus einer langen Ausfahrt im Renntempo; fließt in die Zielzeit ein.",
        evaluate: { values in
          guard let speed = values.first.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }),
            (15...50).contains(speed)
          else { return nil }
          return ("\(GermanFormat.decimal(speed)) km/h", { model.settings.record(.bikeSpeed, value: speed) })
        })
      Section { EvidenceDisclosure(ruleIDs: ["intensity.distribution"]) }
    }
    .navigationTitle("Rad")
  }
}

// MARK: - Laufen

struct RunPage: View {
  let viewModel: TrainingViewModel
  @Environment(AppModel.self) private var model

  var body: some View {
    List {
      KilometersSection(viewModel: viewModel, sport: .run, color: .green)
      TestTrendSection(
        title: "Schwellenpace", kind: .threshold, format: { "\(PlanTokens.mmss(Int($0))) /km" }, lowerIsBetter: true)
      VO2Section(title: "VO2max Laufen (Garmin)", trend: viewModel.vo2Run)
      PaceTableSection(
        title: "Paces", rows: RunPaces.rows(config: model.settings.season),
        footer: "Läufe nur als Zone 2, Schwelle oder 4×4 min – keine anderen Intervallformen.")
      TestEntrySection(
        title: "30-min-Test eintragen", fields: [("Ø-Pace letzte 20 min", "z. B. 4:50")],
        footer:
          "15 min einlaufen, 30 min so schnell wie gleichmäßig möglich; die Ø-Pace der letzten 20 min ist die neue "
          + "Schwelle. Die Ø-Herzfrequenz derselben 20 min ist die Schwellen-HF (unter Herzfrequenz eintragen).",
        evaluate: { values in
          guard let pace = values.first.flatMap(TimeText.seconds), (150...480).contains(pace) else { return nil }
          return ("\(PlanTokens.mmss(pace)) /km", { model.settings.record(.threshold, value: Double(pace)) })
        })
      TestEntrySection(
        title: "Renn-Laufpace (nach dem Rad)", fields: [("Pace /km", "z. B. 5:42")],
        footer: "Benchmark aus einem Koppellauf im Renntempo; fließt in die Zielzeit Almere ein.",
        evaluate: { values in
          guard let pace = values.first.flatMap(TimeText.seconds), (150...600).contains(pace) else { return nil }
          return ("\(PlanTokens.mmss(pace)) /km", { model.settings.record(.racePace, value: Double(pace)) })
        })
      Section {
        Text(
          "Die aerobe Kopplung (HF-Pace-Drift) aus dem alten Dashboard folgt, sobald die App die FIT-Dateien der "
            + "Läufe auswertet."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        EvidenceDisclosure(ruleIDs: ["run.4x4", "intensity.distribution", "hr.threshold-zones"])
      }
    }
    .navigationTitle("Laufen")
  }
}

// MARK: - Almere

struct AlmerePage: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let settings = model.settings
    let estimate = RaceEstimate(config: settings.season, tests: settings.tests, today: CalendarDay(date: .now))
    List {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(settings.season.mainRaceDescription).font(.footnote).foregroundStyle(.secondary)
          Text("\(RaceEstimate.hoursMinutes(estimate.totalMinutes)) h").font(.largeTitle.bold()).monospacedDigit()
          if estimate.allFresh {
            Text(estimate.corridorText).font(.subheadline)
          } else {
            Label(
              "Keine Aussage zum Zielkorridor – mindestens ein Wert ist ungetestet oder älter als 8 Wochen.",
              systemImage: "exclamationmark.triangle"
            )
            .font(.subheadline)
            .foregroundStyle(.orange)
          }
        }
        .padding(.vertical, 4)
      }
      Section("Abschnitte") {
        ForEach(estimate.legs) { leg in
          LabeledContent {
            Text(RaceEstimate.hoursMinutes(leg.minutes)).monospacedDigit()
          } label: {
            VStack(alignment: .leading) {
              Text(leg.label)
              Text(leg.assumption).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }
      Section("Aktualität der Benchmarks") {
        ForEach(estimate.freshness) { item in
          LabeledContent(item.label) {
            if let age = item.age {
              Text(item.isFresh ? "vor \(age) Tagen ✓" : "\(age) Tage alt – fällig")
                .foregroundStyle(item.isFresh ? Color.secondary : Color.orange)
            } else {
              Text("kein Test").foregroundStyle(.orange)
            }
          }
        }
      }
      Section {
        LabeledContent("Schwimmen 5 s/100 m schneller", value: minutes(estimate.savings.swim))
        LabeledContent("Rad 1 km/h schneller", value: minutes(estimate.savings.bike))
        LabeledContent("Lauf 10 s/km schneller", value: minutes(estimate.savings.run))
      } header: {
        Text("Was bringt eine Verbesserung?")
      } footer: {
        Text(
          "Wechselzeiten sind Annahmen. Die Tabelle zeigt nur die Wirkung, nicht den Aufwand. Beim 70.3 ist das Rad "
            + "der größte Hebel; mehr Zeit braucht es dafür nicht, nur Umschichten.")
      }
    }
    .navigationTitle("Almere")
  }

  private func minutes(_ value: Double) -> String {
    "\(GermanFormat.decimal(value)) min"
  }
}

// MARK: - Marathon

struct MarathonPage: View {
  @Environment(AppModel.self) private var model
  @State private var schedule = SeasonSchedule.load()

  var body: some View {
    let settings = model.settings
    let season = settings.season
    let outlook = MarathonOutlook(
      config: season, halfMarathonSeconds: settings.halfMarathonSeconds, schedule: schedule,
      today: CalendarDay(date: .now))
    List {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(outlook.daysToRace >= 0 ? "Noch \(outlook.daysToRace) Tage" : "Marathon geschafft 🏅")
            .font(.largeTitle.bold())
          Text(GermanFormat.date(season.marathonDate)).foregroundStyle(.secondary)
          Text(
            "Zielpace \(PlanTokens.mmss(season.marathonPaceSecondsPerKm)) /km → ca. "
              + "\(MarathonOutlook.hoursMinutes(seconds: outlook.targetSeconds)) h"
          )
          .font(.headline)
        }
        .padding(.vertical, 4)
        if let predicted = outlook.predicted {
          Text(
            "Halbmarathon-Test → realistisch \(MarathonOutlook.hoursMinutes(seconds: predicted.lowerBound))–"
              + "\(MarathonOutlook.hoursMinutes(seconds: predicted.upperBound)) h (Pace "
              + "\(MarathonOutlook.pace(seconds: Double(predicted.lowerBound) / MarathonOutlook.marathonKilometers))–"
              + "\(MarathonOutlook.pace(seconds: Double(predicted.upperBound) / MarathonOutlook.marathonKilometers)) /km)."
          )
          .font(.subheadline)
          if outlook.targetTooFast {
            Label("Die Zielpace ist schneller als der Test hergibt.", systemImage: "exclamationmark.triangle")
              .foregroundStyle(.orange)
          }
        } else {
          Text(
            "Die Zielpace ist vorläufig. Der Halbmarathon-Test bestätigt oder korrigiert sie (Praxiswert: "
              + "Marathon ≈ HM × 2,15–2,2; die Riegel-Formel mit × 2,09 ist für Debütanten meist zu optimistisch)."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      TestEntrySection(
        title: "Halbmarathon-Test eintragen", fields: [("Zeit (h:mm:ss)", "z. B. 1:45:00")],
        footer: "Geplant am 14.03.2027 im Marathonblock.",
        evaluate: { values in
          guard let seconds = values.first.flatMap(TimeText.seconds), (3600...14_400).contains(seconds) else {
            return nil
          }
          return (TimeText.hms(seconds), { model.settings.record(.halfMarathon, value: Double(seconds)) })
        })
      Section {
        ForEach(outlook.ladder) { week in
          HStack {
            Text(week.isCurrent ? "▶ " + Formatters.shortDate(week.sunday) : Formatters.shortDate(week.sunday))
              .monospacedDigit()
              .frame(width: 72, alignment: .leading)
              .foregroundStyle(week.isPast ? .secondary : .primary)
            Text(week.longRun).fontWeight(week.longRun.contains("Marathon") ? .bold : .regular)
            Spacer()
            Text(week.quality).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          .font(.subheadline)
        }
      } header: {
        Text("Longrun-Leiter")
      } footer: {
        Text(
          "Longrun höchstens 2–3 km pro Woche steigern, jede 4. Woche Entlastung. Spitze 32 km drei Wochen vor dem "
            + "Rennen, dann 3 Wochen Taper mit weniger Umfang bei gleichem Tempo.")
      }
      Section("Rennen & Verpflegung") {
        InfoLine(
          title: "Pacing",
          text: "Erste 5 km 5–10 s/km langsamer als \(PlanTokens.mmss(season.marathonPaceSecondsPerKm)) /km, bis km 30 "
            + "gleichmäßig, erst danach zulegen.")
        InfoLine(
          title: "Verpflegung",
          text: "60–90 g Kohlenhydrate pro Stunde aus Gel und Getränk, alle 15–20 min. Jeder Longrun ab 25 km ist "
            + "Generalprobe – am Renntag nichts Neues.")
        InfoLine(title: "Taper", text: "3 Wochen, Umfang −25 / −40 / −60 %, das Tempo bleibt.")
        InfoLine(
          title: "Kraft",
          text: "Beine schwer und kurz (2–3 Sätze à 4–6 Wdh.), mindestens 48 h Abstand zu Longrun und "
            + "Qualitätslauf.")
        InfoLine(
          title: "Stoppsignal",
          text: "Schmerz, der beim Laufen zunimmt oder humpeln lässt → abbrechen, 2–3 Tage Pause.")
        EvidenceDisclosure(ruleIDs: ["taper", "nutrition.carbs", "strength.economy"])
      }
    }
    .navigationTitle("Marathon")
  }
}

private struct InfoLine: View {
  let title: String
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).font(.subheadline.weight(.semibold))
      Text(text).font(.footnote)
    }
  }
}
