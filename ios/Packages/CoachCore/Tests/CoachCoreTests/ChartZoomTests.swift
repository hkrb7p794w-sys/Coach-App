import Foundation
import Testing

@testable import CoachCore

struct ChartZoomTests {
  let start = Date(timeIntervalSince1970: 1_700_000_000)

  func date(_ day: Double) -> Date { start.addingTimeInterval(day * 86_400) }

  @Test func zoomStaysBetweenTwoWeeksAndEverything() {
    let span = ChartZoom.spanDays([date(0), date(600)])
    #expect(span == 601)
    #expect(ChartZoom.clamp(3, span: span) == 14)
    #expect(ChartZoom.clamp(2_000, span: span) == 601)
    #expect(ChartZoom.initialDays(span: span) == 91)
    #expect(ChartZoom.initialDays(span: ChartZoom.spanDays([date(0), date(20)])) == 21)
  }

  @Test func yAxisFollowsVisiblePoints() {
    let points = [(date: date(0), value: 40.0), (date: date(300), value: 60.0), (date: date(330), value: 62.0)]
    let visible = ChartZoom.yDomain(points, from: date(290), days: 60)
    #expect(visible.lowerBound > 50 && visible.upperBound < 70)
    let all = ChartZoom.yDomain(points, from: date(-10), days: 400)
    #expect(all.lowerBound < 40 && all.upperBound > 62)
    let volume = ChartZoom.yDomain(points, from: date(290), days: 60, includesZero: true)
    #expect(volume.lowerBound == 0)
  }

  @Test func pointsHideWhenDense() {
    #expect(ChartZoom.showsPoints(days: 91, count: 170, span: 1_000))
    #expect(!ChartZoom.showsPoints(days: 1_000, count: 170, span: 1_000))
  }
}
