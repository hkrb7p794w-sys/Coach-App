import Foundation

/// Einordnung einer Einheit wie im Altbestand (`tagesform.py`: `_is_hard`, `_kind`).
///
/// Harte Einheiten werden nur mit gleichartigen verglichen: Der Schnitt eines 4×4-Laufs mit Trabpausen
/// ist nicht mit einem Schwellenlauf vergleichbar.
public enum SessionKind: String, Codable, Sendable {
  case easy, test, vo2, threshold, hard, gym

  public static let hardNameKeywords = [
    "intervall", "interval", "schwelle", "threshold", "tempo", "vo2", "sprint", "test", "css", "ftp", "rennen",
    "race", "sweet", "over-under", "overunder", "ramp",
  ]
  /// Reihenfolge = Priorität.
  static let hardKinds: [(SessionKind, [String])] = [
    (.test, ["test", "ramp", "ftp"]),
    (.vo2, ["vo2", "4x4", "sprint", "intervall", "interval"]),
    (.threshold, ["schwelle", "threshold", "tempo", "sweet", "over-under", "overunder", "css"]),
  ]
  /// Ab 15 % der Zeit in Zone 4–5 gilt eine Einheit als hart.
  public static let hardHighZoneShare = 0.15
  /// Rad: auch ab 35 % in Zone 3–5 (Sweet Spot). Beim Laufen nicht, Z3 kommt auch locker vor.
  public static let hardMidZoneShare = 0.35

  public static func isHard(_ activity: GarminActivity) -> Bool {
    let sport = activity.sport
    if sport == .strength { return true }
    let name = activity.name?.lowercased() ?? ""
    if hardNameKeywords.contains(where: { name.contains($0) }) { return true }
    if sport == .swim { return false }  // Handgelenk-HF im Wasser ist zu unzuverlässig
    if let share = AerobicDecoupling.highZoneShare(activity), share >= hardHighZoneShare { return true }
    guard sport == .bike, let zones = activity.secondsInZones else { return false }
    return (zones[2] + zones[3] + zones[4]) / zones.reduce(0, +) >= hardMidZoneShare
  }

  public static func of(_ activity: GarminActivity) -> SessionKind {
    guard isHard(activity) else { return .easy }
    if activity.sport == .strength { return .gym }
    let name = activity.name?.lowercased() ?? ""
    return hardKinds.first(where: { entry in entry.1.contains { name.contains($0) } })?.0 ?? .hard
  }
}
