import Charts
import CoachCore
import SwiftUI

/// Fitness, Ermüdung und Form aus der Trainingsbelastung der Uhr (wie in TrainingPeaks), mit Einordnung.
struct FitnessFormPage: View {
  let points: [FitnessForm.Point]

  private var recent: [FitnessForm.Point] { Array(points.suffix(90)) }

  var body: some View {
    List {
      if let last = points.last, let percent = last.formPercent, FitnessForm.isReliable(points) {
        let zone = FitnessForm.Zone.of(percent)
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Text(zone.label).font(.title3.bold())
            Text(zone.explanation).font(.subheadline)
          }
          .padding(.vertical, 4)
          LabeledContent("Fitness", value: GermanFormat.number(last.fitness))
          LabeledContent("Ermüdung", value: GermanFormat.number(last.fatigue))
          LabeledContent("Form", value: "\(GermanFormat.number(last.form)) (\(Int(percent.rounded())) %)")
        } header: {
          Text("Heute")
        } footer: {
          Text("Die Grenzen der Einordnung sind Praxiswerte aus Trainingssoftware, keine Studienergebnisse.")
        }
      } else {
        Section {
          Text(
            "Für eine aussagekräftige Kurve braucht die App Trainingsbelastung aus mindestens "
              + "\(FitnessForm.warmUpDays) Tagen. Die Uhr liefert sie zu jeder aufgezeichneten Aktivität."
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
        }
      }
      if !recent.isEmpty {
        Section("Letzte 90 Tage") {
          Chart {
            ForEach(recent) { point in
              BarMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("Form", point.form))
                .foregroundStyle(point.form >= 0 ? Color.green.opacity(0.5) : Color.orange.opacity(0.5))
              LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("Wert", point.fitness))
                .foregroundStyle(by: .value("Kurve", "Fitness"))
              LineMark(x: .value("Tag", point.day.localDate, unit: .day), y: .value("Wert", point.fatigue))
                .foregroundStyle(by: .value("Kurve", "Ermüdung"))
            }
          }
          .chartForegroundStyleScale(["Fitness": Color.blue, "Ermüdung": Color.pink])
          .frame(height: 220)
          .accessibilityLabel("Fitness, Ermüdung und Form der letzten 90 Tage")
        }
      }
      Section {
        Text(
          "Fitness ist der Schnitt deiner Belastung über 42 Tage, Ermüdung über 7 Tage. Form ist die Differenz: "
            + "positiv, wenn du erholter bist, als dein Training gewohnt ist. Nur Aktivitäten mit Belastungswert "
            + "der Uhr zählen."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        EvidenceDisclosure(ruleIDs: ["load.fitness-form"])
      }
    }
    .navigationTitle("Fitness & Form")
  }
}

/// Wochenbericht der letzten Kalenderwoche im Vergleich zur Vorwoche.
struct WeeklyReportPage: View {
  let report: WeeklyReport

  var body: some View {
    List {
      Section {
        if report.highlights.isEmpty {
          Text("Eine ruhige, gleichmäßige Woche – nichts Auffälliges.").font(.subheadline)
        }
        ForEach(report.highlights, id: \.self) { line in
          Label(line, systemImage: "lightbulb").font(.subheadline)
        }
      } header: {
        Text("Woche ab \(GermanFormat.date(report.monday))")
      }
      Section("Zahlen (Vorwoche)") {
        row("Einheiten", report.week.sessions.description, report.previous.sessions.description)
        row("Trainingszeit", minutes(report.week.minutes), minutes(report.previous.minutes))
        row("Belastung", GermanFormat.number(report.week.load), GermanFormat.number(report.previous.load))
        ForEach([GarminActivity.Sport.run, .bike, .swim], id: \.self) { sport in
          if let kilometers = report.week.kilometers[sport] {
            row(
              label(sport), "\(GermanFormat.number(kilometers)) km",
              report.previous.kilometers[sport].map { "\(GermanFormat.number($0)) km" } ?? "–")
          }
        }
        if let change = report.fitnessChange {
          LabeledContent("Fitness", value: (change > 0 ? "+" : "") + GermanFormat.number(change))
        }
      }
      Section("Erholung (Vorwoche)") {
        row(
          "Schlaf", report.week.averageSleepHours.map { "\(GermanFormat.number($0)) h" } ?? "–",
          report.previous.averageSleepHours.map { "\(GermanFormat.number($0)) h" } ?? "–")
        row(
          "HRV", report.week.averageHRV.map { "\(GermanFormat.number($0)) ms" } ?? "–",
          report.previous.averageHRV.map { "\(GermanFormat.number($0)) ms" } ?? "–")
        row(
          "Ruhepuls", report.week.averageRestingHeartRate.map { "\(GermanFormat.number($0)) bpm" } ?? "–",
          report.previous.averageRestingHeartRate.map { "\(GermanFormat.number($0)) bpm" } ?? "–")
      }
    }
    .navigationTitle("Wochenbericht")
  }

  private func row(_ title: String, _ value: String, _ previous: String) -> some View {
    LabeledContent(title) {
      HStack(spacing: 6) {
        Text(value).monospacedDigit()
        Text("(\(previous))").foregroundStyle(.secondary).monospacedDigit()
      }
    }
  }

  private func minutes(_ value: Double) -> String {
    let total = Int(value)
    return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
  }

  private func label(_ sport: GarminActivity.Sport) -> String {
    switch sport {
    case .run: "Laufen"
    case .bike: "Rad"
    case .swim: "Schwimmen"
    case .strength: "Kraft"
    case .other: "Sonstiges"
    }
  }
}
