/// Kurzpläne je Phase und Disziplin (`PHASE_PLAN` im Altbestand). Watt und Pace rechnen sich aus den
/// Testwerten, damit ein neuer Test nur an einer Stelle eingetragen werden muss.
enum PhasePlanTexts {
  static func text(for phase: TrainingPhase, pace p: TestPaces) -> PhasePlanText {
    switch phase {
    case .grundlage:
      return PhasePlanText(
        run: "Z2-Lauf mit Partnerin 50 → 90 min (HF Zone 2) · Qualitätslauf im Wechsel: Schwelle (z. B. 3×2 km @ "
          + "\(p.run()) /km) und 4×4-min-Intervall (90–95 % HFmax, Richtwert \(p.run(-23))–\(p.run(-18)) /km, "
          + "3 min Trab) · 30-min-Lauftest Mitte Dezember",
        swim: "CSS-Serien im 4-Wochen-Wechsel: 100er @ \(p.swim()), 200er–400er @ \(p.swim(1))–\(p.swim(4)), "
          + "Technik + Ausdauer, Tempo-50er @ \(p.swim(-4))–\(p.swim(-2)) /100 m · CSS-Test 30.11.",
        bike: "1x Zwift: Sweet Spot 3×10 → 2×20 min @ \(p.watts(88))–\(p.watts(94)) W, dann Schwelle "
          + "\(p.watts(98)) W und Over-Under · FTP-Test 07.12. · optional 1x Z2 \(p.watts(65))–\(p.watts(70)) W",
        strength: "Mo Push · Mi Pull · Fr Push+Pull · Beine Di oder Do"
      )
    case .marathonAufbau:
      return PhasePlanText(
        run: "So Longrun 16 → 32 km (\(p.run(65))–\(p.run(100)) /km, Spitze 11.04.) · unter der Woche Schwelle @ "
          + "\(p.run()) oder Marathontempo @ \(p.marathon) /km im Wechsel + locker mit Partnerin · "
          + "Halbmarathon-Test 14.03.",
        swim: "1x CSS-Serie wie bisher (@ \(p.swim()) /100 m), Wiederholungen steigern, Pausen kürzen",
        bike: "1x Zwift am Wochenende zum Erhalt: Sweet Spot @ \(p.watts(90))–\(p.watts(94)) W, in "
          + "Entlastungswochen Z2 · FTP-Tests 01.02. und 29.03.",
        strength: "Home-Gym wie gewohnt · Beine schwer und kurz (2-3 Sätze à 4-6 Wdh.), 48 h Abstand zu "
          + "Longrun/Qualität"
      )
    case .marathonTaper:
      return PhasePlanText(
        run: "Longrun 24 → 16 km, Marathontempo kurz @ \(p.marathon) /km · Rennen So 02.05., 60-90 g KH/h",
        swim: "kurz und locker, ein paar zügige 50er",
        bike: "Zwift kurz mit Aktivierung (3×3 min @ \(p.watts(80)) W)",
        strength: "Volumen reduzieren, letzte schwere Beine-Einheit ca. 10 Tage vor dem Rennen"
      )
    case .regeneration:
      return PhasePlanText(
        run: "ab Tag 5 sehr locker 20-30 min, Woche 2: 2× 30-40 min locker",
        swim: "locker, Technik",
        bike: "Zwift locker Z2 (\(p.watts(65))–\(p.watts(70)) W)",
        strength: "Oberkörper leicht, Beine erst in Woche 2 leicht"
      )
    case .almereAufbau:
      return PhasePlanText(
        run: "Qualitätslauf im Wechsel Schwelle @ \(p.run()) /km und Renn-Laufpace · So Z2 mit Partnerin · "
          + "Koppellauf nach jeder langen Radeinheit",
        swim: "CSS-Serien und Renn-Simulation 1200 → 1900 m @ \(p.swim(1))–\(p.swim(3)) /100 m (1,9 km ≈ CSS bis "
          + "+3 s), Sighting, ab Juni Freiwasser mit Neo",
        bike: "Zwift-Intervall unter der Woche (Sweet Spot, Renntempo 2×30 / 3×20 min @ \(p.watts(77))–"
          + "\(p.watts(78)) W) · Wochenende lange Ausfahrt 2:00 → 3:00 h mit Renntempo-Blöcken + Koppellauf",
        strength: "Home-Gym wie gewohnt, Beine 1x"
      )
    case .almerePeak:
      return PhasePlanText(
        run: "Renn-Laufpace 2×5 km / 3×3 km, Koppelläufe 20-30 min",
        swim: "Freiwasser 1500-2000 m am Stück mit Neo",
        bike: "Rennsimulation 94 km @ \(p.watts(75))–\(p.watts(78)) W + 30 min Koppellauf · Formtest (z. B. "
          + "Olympische Distanz)",
        strength: "Erhalt: 1-2 Sätze pro Übung, keine neuen Reize"
      )
    case .almereTaper:
      return PhasePlanText(
        run: "kürzer (30-40 min) mit kurzen Renntempo-Abschnitten, kein Longrun",
        swim: "8×50 m zügig, viel Pause",
        bike: "Aktivierung 35 min (3×3 min @ \(p.watts(80)) W) · Rennen: \(p.watts(75))–\(p.watts(78)) W",
        strength: "Volumen -40 bis -60 %, letzte Einheit ca. 5 Tage vor dem Rennen"
      )
    }
  }
}
