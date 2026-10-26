import Foundation
import Testing

@testable import CoachCore

struct UnitGuideTests {
  private func units() throws -> [PlannedUnit] {
    let schedule = try #require(SeasonSchedule.load())
    return schedule.weeks.flatMap { schedule.units(for: $0, config: .standard) }
  }

  @Test func everySeasonUnitHasAFullGuide() throws {
    for unit in try units() {
      let guide = UnitGuides.guide(for: unit)
      #expect(!guide.purpose.isEmpty, "\(unit.title) ohne Zweck")
      #expect(!guide.feel.isEmpty)
      #expect(!guide.steps.isEmpty, "\(unit.title) ohne Ablauf")
      #expect(!guide.steps.contains { $0.contains("§") }, "Platzhalter in \(unit.title)")
    }
  }

  @Test func swimTechniqueExplainsDrillsAndCSS() throws {
    let unit = try #require(try units().first { $0.kind == .swim && $0.title.contains("Technik") })
    let guide = UnitGuides.guide(for: unit)
    let names = guide.terms.map(\.name)
    #expect(names.contains("Abschlag"))
    #expect(names.contains("Zipper (Reißverschluss)"))
    #expect(names.contains("Seitlage mit 6 Beinschlägen"))
    #expect(names.contains("Pull-Buoy"))
    #expect(names.contains("CSS (kritische Schwimmgeschwindigkeit)"))
    #expect(guide.steps.first?.hasPrefix("Einschwimmen") == true)
    #expect(guide.steps.contains { $0.contains("etwas langsamer als CSS") })
    #expect(guide.steps.contains { $0.hasPrefix("Pause 30 s") })
    #expect(guide.steps.last?.hasPrefix("Ausschwimmen") == true)
  }

  @Test func swimIntensityWords() {
    #expect(UnitGuides.intensity(low: -4, high: -2, note: nil).hasPrefix("schneller als dein CSS-Tempo"))
    #expect(UnitGuides.intensity(low: 0, high: 0, note: nil).hasPrefix("im CSS-Tempo"))
    #expect(UnitGuides.intensity(low: 4, high: 6, note: nil).hasPrefix("etwas langsamer als CSS"))
    #expect(UnitGuides.intensity(low: 12, high: 15, note: nil).hasPrefix("locker"))
    #expect(UnitGuides.intensity(low: nil, high: nil, note: "Technik (z. B. Abschlag)").hasPrefix("Technikübungen"))
  }

  @Test func runAndBikeGuidesMatchTheSession() throws {
    let all = try units()
    let interval = try #require(all.first { $0.kind == .quality && $0.title.contains("4×4") })
    #expect(UnitGuides.guide(for: interval).steps.contains { $0.contains("90–95 % HFmax") })
    let test = try #require(all.first { $0.kind == .quality && $0.title.contains("Lauftest") })
    #expect(UnitGuides.guide(for: test).purpose.contains("Schwellenpace"))
    let sweetSpot = try #require(all.first { $0.zwiftCode == "Z01" })
    #expect(UnitGuides.guide(for: sweetSpot).terms.map(\.name).contains("Sweet Spot"))
    let ramp = try #require(all.first { $0.zwiftCode == "RAMP" })
    #expect(UnitGuides.guide(for: ramp).purpose.contains("FTP"))
  }

  @Test func personalSlotsWithoutSeasonValues() {
    for sport in TrainingSport.allCases {
      for intensity in SessionIntensity.allCases {
        let guide = UnitGuides.guide(for: SessionSlot(sport, intensity))
        #expect(!guide.purpose.isEmpty)
        #expect(!guide.steps.isEmpty)
        // Keine Werte aus dem Saisonplan (CSS, FTP, Schwellenpace) für andere Personen.
        let text = ([guide.purpose, guide.feel] + guide.steps).joined(separator: " ")
        #expect(!text.contains("CSS"), "\(sport) \(intensity)")
        #expect(!text.contains("FTP"), "\(sport) \(intensity)")
      }
    }
    #expect(UnitGuides.guide(for: SessionSlot(.run, .hard)).terms.map(\.name).contains("HFmax"))
  }
}
