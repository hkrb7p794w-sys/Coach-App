import CoachCore
import SwiftUI

/// Gezeichnete, animierte Daisy: zotteliger, apricotfarbener Terrier-Mix mit Schlappohren, Bart und
/// wuscheligen Brauen. Die Stimmung bestimmt Bewegung und Zubehör (lila Geschirr beim Losgehen, Blümchen-Halstuch
/// wenn sie stolz ist, „Zzz“ am Ruhetag). Bei „Bewegung reduzieren“ steht sie still.
struct DaisyAvatar: View {
  var mood: CompanionMood
  var size: CGFloat = 64
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
      let pose = DaisyGeometry.pose(
        mood: mood, time: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)
      Canvas { context, canvasSize in
        DaisyPainter.draw(in: context, size: canvasSize, mood: mood, pose: pose)
      }
    }
    .frame(width: size, height: size)
    .background(DaisyPainter.background)
    .clipShape(Circle())
    .accessibilityElement()
    .accessibilityLabel("Daisy")
  }
}

private enum DaisyPainter {
  static let background = Color(hex: 0xFFF4E6)
  static let fur = Color(hex: 0xE2B17A)
  static let light = Color(hex: 0xEFCB98)
  static let cream = Color(hex: 0xF7E6C8)
  static let ear = Color(hex: 0xD29A62)
  static let earTip = Color(hex: 0xB57444)
  static let iris = Color(hex: 0x6E3510)
  static let pupil = Color(hex: 0x2A140A)
  static let nose = Color(hex: 0x2B201D)
  static let line = Color(hex: 0x5A3A2A)

  static func furPath(
    _ x: Double, _ y: Double, _ rx: Double, _ ry: Double, tufts: Int, depth: Double, phase: Double = 0,
    start: Double = 0, end: Double = 2 * .pi
  ) -> Path {
    let fur = DaisyGeometry.fur(
      center: .init(x: x, y: y), radiusX: rx, radiusY: ry, tufts: tufts, depth: depth, phase: phase, start: start,
      end: end)
    var path = Path()
    path.move(to: CGPoint(x: fur.start.x, y: fur.start.y))
    for curve in fur.curves {
      path.addQuadCurve(
        to: CGPoint(x: curve.end.x, y: curve.end.y), control: CGPoint(x: curve.control.x, y: curve.control.y))
    }
    path.closeSubpath()
    return path
  }

  static func ellipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
    Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
  }

  /// Dreht bzw. skaliert eine Kopie des Kontexts um einen Punkt.
  static func around(
    _ context: GraphicsContext, _ x: Double, _ y: Double, degrees: Double = 0, scaleY: Double = 1
  ) -> GraphicsContext {
    var copy = context
    copy.translateBy(x: x, y: y)
    copy.rotate(by: .degrees(degrees))
    copy.scaleBy(x: 1, y: scaleY)
    copy.translateBy(x: -x, y: -y)
    return copy
  }

  static func draw(in base: GraphicsContext, size: CGSize, mood: CompanionMood, pose: DaisyGeometry.Pose) {
    var context = base
    context.scaleBy(x: size.width / 200, y: size.height / 200)

    // Körper mit Atmung.
    let body = around(context, 100, 200, scaleY: 1 + pose.breath)
    body.fill(furPath(100, 186, 42, 38, tufts: 14, depth: 0.10), with: .color(fur))
    body.fill(furPath(100, 182, 24, 24, tufts: 10, depth: 0.10), with: .color(cream))
    drawAccessory(body, mood: mood)

    // Kopf: hüpft und neigt sich um den Hals.
    var head = context
    head.translateBy(x: 0, y: pose.bounce)
    head = around(head, 100, 140, degrees: pose.headTilt)

    for side in [-1.0, 1.0] {
      let x = 100 + side * 42
      let ear = around(head, x, 68, degrees: side * (-22 + pose.earSwing))
      ear.fill(furPath(x, 96, 15, 30, tufts: 9, depth: 0.18, phase: 1), with: .color(self.ear))
      ear.fill(furPath(x, 112, 13, 14, tufts: 6, depth: 0.22, phase: 2), with: .color(earTip))
    }
    head.fill(furPath(100, 98, 46, 46, tufts: 22, depth: 0.12), with: .color(fur))
    head.fill(furPath(100, 92, 36, 34, tufts: 18, depth: 0.14, phase: 0.5), with: .color(light))
    head.fill(
      furPath(100, 56, 22, 10, tufts: 9, depth: 0.55, phase: 0.3, start: .pi, end: 2 * .pi), with: .color(light))
    for side in [-1.0, 1.0] {
      head.fill(furPath(100 + side * 19, 84, 11, 5, tufts: 6, depth: 0.45, phase: side), with: .color(cream))
    }
    head.fill(furPath(100, 124, 28, 20, tufts: 14, depth: 0.10), with: .color(cream))
    head.fill(furPath(100, 138, 20, 12, tufts: 10, depth: 0.35, phase: 0.7, start: 0, end: .pi), with: .color(cream))

    drawEyes(head, open: pose.eyesOpen)

    var nosePath = Path()
    nosePath.move(to: CGPoint(x: 88, y: 114))
    nosePath.addQuadCurve(to: CGPoint(x: 112, y: 114), control: CGPoint(x: 100, y: 107))
    nosePath.addQuadCurve(to: CGPoint(x: 100, y: 126), control: CGPoint(x: 112, y: 124))
    nosePath.addQuadCurve(to: CGPoint(x: 88, y: 114), control: CGPoint(x: 88, y: 124))
    head.fill(nosePath, with: .color(nose))
    head.fill(ellipse(95, 113, 3.4, 1.8), with: .color(Color(hex: 0x6C5A55)))

    if pose.tongue {
      var tongue = Path()
      tongue.move(to: CGPoint(x: 93, y: 132))
      tongue.addQuadCurve(to: CGPoint(x: 107, y: 132), control: CGPoint(x: 100, y: 138))
      tongue.addQuadCurve(to: CGPoint(x: 93, y: 132), control: CGPoint(x: 100, y: 152))
      head.fill(tongue, with: .color(Color(hex: 0xEF8A95)))
    }
    var mouth = Path()
    mouth.move(to: CGPoint(x: 100, y: 126))
    mouth.addLine(to: CGPoint(x: 100, y: 132))
    mouth.addQuadCurve(to: CGPoint(x: 86, y: 133), control: CGPoint(x: 93, y: 138))
    mouth.move(to: CGPoint(x: 100, y: 132))
    mouth.addQuadCurve(to: CGPoint(x: 114, y: 133), control: CGPoint(x: 107, y: 138))
    head.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    for side in [-1.0, 1.0] {
      head.fill(ellipse(100 + side * 28, 118, 7, 4), with: .color(Color(hex: 0xF3A7A0).opacity(0.45)))
    }

    drawFloats(context, mood: mood, phase: pose.floatPhase)
  }

  static func drawEyes(_ head: GraphicsContext, open: Double) {
    for side in [-1.0, 1.0] {
      let x = 100 + side * 19
      if open < 0.2 {
        var lid = Path()
        lid.move(to: CGPoint(x: x - 8, y: 98))
        lid.addQuadCurve(to: CGPoint(x: x + 8, y: 98), control: CGPoint(x: x, y: 104))
        head.stroke(lid, with: .color(Color(hex: 0x3A1E10)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        continue
      }
      let eye = around(head, x, 98, scaleY: open)
      eye.fill(ellipse(x, 98, 9.5, 9.5), with: .color(iris))
      eye.fill(ellipse(x, 99, 6, 6), with: .color(pupil))
      eye.fill(ellipse(x + 3, 95, 2.8, 2.8), with: .color(.white))
      eye.fill(ellipse(x - 3, 102, 1.2, 1.2), with: .color(.white.opacity(0.7)))
    }
  }

  static func drawAccessory(_ body: GraphicsContext, mood: CompanionMood) {
    switch mood {
    case .excited, .hopeful:
      // Lila Geschirr für den Spaziergang.
      var strap = Path()
      strap.move(to: CGPoint(x: 62, y: 160))
      strap.addQuadCurve(to: CGPoint(x: 138, y: 160), control: CGPoint(x: 100, y: 176))
      body.stroke(strap, with: .color(Color(hex: 0xA77BE0)), style: StrokeStyle(lineWidth: 9, lineCap: .round))
      body.fill(ellipse(100, 171, 5, 5), with: .color(Color(hex: 0x8F63CF)))
    case .proud:
      // Hellblaues Halstuch mit Blümchen.
      var scarf = Path()
      scarf.move(to: CGPoint(x: 58, y: 150))
      scarf.addQuadCurve(to: CGPoint(x: 142, y: 150), control: CGPoint(x: 100, y: 166))
      scarf.addLine(to: CGPoint(x: 100, y: 198))
      scarf.closeSubpath()
      body.fill(scarf, with: .color(Color(hex: 0x9ED3EF)))
      let flowers: [(Double, Double, UInt32)] = [
        (88, 163, 0xF06FA0), (108, 171, 0xF7D046), (100, 184, 0x5B8FE0), (120, 160, 0xF06FA0),
        (78, 157, 0x5B8FE0), (96, 175, 0xF06FA0),
      ]
      for (x, y, color) in flowers {
        body.fill(ellipse(x, y, 2.6, 2.6), with: .color(Color(hex: color)))
      }
    case .happy, .resting, .cozy:
      break
    }
  }

  static func drawFloats(_ context: GraphicsContext, mood: CompanionMood, phase: Double) {
    switch mood {
    case .resting:
      // Drei „z“, die nacheinander aufsteigen und verblassen.
      for index in 0..<3 {
        let local = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let text = Text("z").font(.system(size: 14 + 6 * local, weight: .bold, design: .rounded))
          .foregroundStyle(Color(hex: 0x7C8BD8).opacity(1 - local))
        context.draw(text, at: CGPoint(x: 150 + 14 * local, y: 60 - 40 * local))
      }
    case .proud:
      for (index, point) in [CGPoint(x: 38, y: 40), CGPoint(x: 164, y: 34), CGPoint(x: 170, y: 120)].enumerated() {
        let local = (phase + Double(index) / 3).truncatingRemainder(dividingBy: 1)
        let text = Text("✦").font(.system(size: 12 + 8 * sin(local * .pi)))
          .foregroundStyle(Color(hex: 0xF7C948).opacity(sin(local * .pi)))
        context.draw(text, at: point)
      }
    case .happy, .excited, .hopeful, .cozy:
      break
    }
  }
}

extension Color {
  /// Farbe aus 0xRRGGBB.
  fileprivate init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}
