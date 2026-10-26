import CoachCore
import SwiftUI

/// Sportseite für Profile ohne Saisonplan: Umfang pro Woche und die Auswertungen aus Garmin-Daten. Plan-,
/// Test- und Zonenwerte des Saisonplans gehören zu einer Person und tauchen hier nicht auf.
struct PersonalSportPage: View {
  let sport: TrainingSport
  let viewModel: TrainingViewModel

  var body: some View {
    List {
      KilometersSection(viewModel: viewModel, sport: sport.garminSport, color: sport.color)
      switch sport {
      case .run:
        VO2Section(title: "VO2max Laufen (Garmin)", trend: viewModel.vo2Run)
        DecouplingSection(title: "Aerobe Kopplung (Pa:HR)", sport: .run, viewModel: viewModel, showsSkipped: true)
        Section { EvidenceDisclosure(ruleIDs: ["run.progression", "run.minimum", "rhr.endurance"]) }
      case .bike:
        VO2Section(title: "VO2max Rad (Garmin)", trend: viewModel.vo2Bike)
        DecouplingSection(title: "Aerobe Kopplung (Pw:HR)", sport: .ride, viewModel: viewModel)
      default:
        EmptyView()
      }
    }
    .navigationTitle(sport.label)
  }
}
