import Foundation

/// Bundesländer für die gesetzlichen Feiertage.
public enum GermanState: String, Codable, CaseIterable, Sendable, Identifiable {
  case bw, by, be, bb, hb, hh, he, mv, ni, nw, rp, sl, sn, st, sh, th

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .bw: "Baden-Württemberg"
    case .by: "Bayern"
    case .be: "Berlin"
    case .bb: "Brandenburg"
    case .hb: "Bremen"
    case .hh: "Hamburg"
    case .he: "Hessen"
    case .mv: "Mecklenburg-Vorpommern"
    case .ni: "Niedersachsen"
    case .nw: "Nordrhein-Westfalen"
    case .rp: "Rheinland-Pfalz"
    case .sl: "Saarland"
    case .sn: "Sachsen"
    case .st: "Sachsen-Anhalt"
    case .sh: "Schleswig-Holstein"
    case .th: "Thüringen"
    }
  }
}

/// Gesetzliche Feiertage je Bundesland und Jahr. Feiertage, die nur in einzelnen Gemeinden gelten (Fronleichnam in Teilen
/// von Sachsen und Thüringen, Mariä Himmelfahrt in Teilen Bayerns, Augsburger Friedensfest), zählen nicht.
public enum GermanHolidays {
  /// Ostersonntag (Gaußsche Osterformel in der Fassung von Meeus/Jones/Butcher).
  public static func easter(_ year: Int) -> CalendarDay {
    let a = year % 19
    let b = year / 100
    let c = year % 100
    let d = b / 4
    let e = b % 4
    let f = (b + 8) / 25
    let g = (b - f + 1) / 3
    let h = (19 * a + b - d - g + 15) % 30
    let i = c / 4
    let k = c % 4
    let l = (32 + 2 * e + 2 * i - h - k) % 7
    let m = (a + 11 * h + 22 * l) / 451
    let month = (h + l - 7 * m + 114) / 31
    let day = (h + l - 7 * m + 114) % 31 + 1
    return CalendarDay(year: year, month: month, day: day)
  }

  public static func all(year: Int, state: GermanState) -> [CalendarDay: String] {
    func date(_ month: Int, _ day: Int) -> CalendarDay { CalendarDay(year: year, month: month, day: day) }
    let easter = easter(year)
    var result: [CalendarDay: String] = [
      date(1, 1): "Neujahr",
      easter.adding(days: -2): "Karfreitag",
      easter.adding(days: 1): "Ostermontag",
      date(5, 1): "Tag der Arbeit",
      easter.adding(days: 39): "Christi Himmelfahrt",
      easter.adding(days: 50): "Pfingstmontag",
      date(10, 3): "Tag der Deutschen Einheit",
      date(12, 25): "1. Weihnachtstag",
      date(12, 26): "2. Weihnachtstag",
    ]
    if [.bw, .by, .st].contains(state) { result[date(1, 6)] = "Heilige Drei Könige" }
    if (state == .be && year >= 2019) || (state == .mv && year >= 2023) { result[date(3, 8)] = "Frauentag" }
    if [.bw, .by, .he, .nw, .rp, .sl].contains(state) { result[easter.adding(days: 60)] = "Fronleichnam" }
    if state == .sl { result[date(8, 15)] = "Mariä Himmelfahrt" }
    if state == .th, year >= 2019 { result[date(9, 20)] = "Weltkindertag" }
    if [.bb, .mv, .sn, .st, .th].contains(state) || ([.hb, .hh, .ni, .sh].contains(state) && year >= 2018) {
      result[date(10, 31)] = "Reformationstag"
    }
    if [.bw, .by, .nw, .rp, .sl].contains(state) { result[date(11, 1)] = "Allerheiligen" }
    if state == .sn {
      // Mittwoch vor dem 23. November.
      var day = date(11, 22)
      while day.weekdayIndex != 2 { day = day.adding(days: -1) }
      result[day] = "Buß- und Bettag"
    }
    return result
  }

  public static func name(on day: CalendarDay, state: GermanState) -> String? {
    all(year: day.year, state: state)[day]
  }
}
