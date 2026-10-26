import Foundation

/// Geometrie des gezeichneten Avatars „Daisy“ (zotteliger, apricotfarbener Terrier-Mix) in einem 200 × 200
/// großen Koordinatensystem. Die App zeichnet daraus Pfade; hier liegt nur die Rechnung, damit sie testbar ist.
public enum DaisyGeometry {
  public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  /// Ein Fellstück: Anfangspunkt und pro Zottel eine quadratische Kurve (Kontrollpunkt = Fellspitze).
  public struct Fur: Equatable, Sendable {
    public var start: Point
    public var curves: [(control: Point, end: Point)]

    public static func == (lhs: Fur, rhs: Fur) -> Bool {
      lhs.start == rhs.start && lhs.curves.elementsEqual(rhs.curves) { $0.control == $1.control && $0.end == $1.end }
    }
  }

  /// Ellipse mit weichen Fellzotteln. `depth` = wie weit die Spitzen über den Rand stehen (Anteil des Radius),
  /// `phase` variiert die Länge der Zotteln, `start`/`end` begrenzen den Bogen (Bogenmaß).
  public static func fur(
    center: Point, radiusX: Double, radiusY: Double, tufts: Int, depth: Double, phase: Double = 0,
    start: Double = 0, end: Double = 2 * .pi
  ) -> Fur {
    let count = max(tufts, 1) * 2
    let points = (0...count).map { index -> Point in
      let angle = start + (end - start) * Double(index) / Double(count)
      let scale = index.isMultiple(of: 2) ? 1 : 1 + depth * (0.75 + 0.25 * sin(Double(index) * 1.7 + phase))
      return Point(x: center.x + radiusX * scale * cos(angle), y: center.y + radiusY * scale * sin(angle))
    }
    let curves = stride(from: 1, to: count, by: 2).map { (control: points[$0], end: points[$0 + 1]) }
    return Fur(start: points[0], curves: curves)
  }

  /// Animationszustand zu einem Zeitpunkt (Sekunden). Werte in Grad bzw. Einheiten des 200er-Rasters.
  public struct Pose: Equatable, Sendable {
    public var headTilt: Double
    public var earSwing: Double
    public var bounce: Double
    public var breath: Double
    public var eyesOpen: Double
    public var tongue: Bool
    /// 0…1, für aufsteigende „Zzz“ bzw. funkelnde Sterne.
    public var floatPhase: Double
  }

  public static func pose(mood: CompanionMood, time: Double, reduceMotion: Bool = false) -> Pose {
    let t = reduceMotion ? 0 : time
    // Alle 4 Sekunden kurz blinzeln (nicht im Schlaf).
    let blink = t.truncatingRemainder(dividingBy: 4) > 3.85 ? 0.1 : 1
    let breath = sin(t * 2) * 0.015
    switch mood {
    case .excited:
      return Pose(
        headTilt: sin(t * 1.5) * 4, earSwing: sin(t * 7) * 9, bounce: -abs(sin(t * 3.5)) * 4, breath: breath,
        eyesOpen: blink, tongue: false, floatPhase: 0)
    case .happy:
      return Pose(
        headTilt: sin(t * 2) * 3, earSwing: sin(t * 5) * 6, bounce: -abs(sin(t * 3)) * 3, breath: breath,
        eyesOpen: blink, tongue: true, floatPhase: 0)
    case .proud:
      return Pose(
        headTilt: -6 + sin(t) * 2, earSwing: sin(t * 2) * 3, bounce: 0, breath: breath, eyesOpen: blink,
        tongue: false, floatPhase: (t / 2).truncatingRemainder(dividingBy: 1))
    case .hopeful:
      // Daisys typisches Kopfschiefhalten.
      return Pose(
        headTilt: 10 * sin(t * 0.8), earSwing: sin(t * 2) * 4, bounce: 0, breath: breath, eyesOpen: blink,
        tongue: false, floatPhase: 0)
    case .resting:
      return Pose(
        headTilt: 4, earSwing: 0, bounce: 0, breath: sin(t * 1.2) * 0.03, eyesOpen: 0, tongue: false,
        floatPhase: (t / 3).truncatingRemainder(dividingBy: 1))
    case .cozy:
      return Pose(
        headTilt: 6, earSwing: sin(t) * 2, bounce: 0, breath: sin(t * 1.2) * 0.025, eyesOpen: 0.35 * blink,
        tongue: false, floatPhase: 0)
    }
  }
}
