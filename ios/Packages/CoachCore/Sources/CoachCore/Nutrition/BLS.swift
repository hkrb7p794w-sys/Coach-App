import Foundation

/// Ein Lebensmittel aus dem Bundeslebensmittelschlüssel mit Nährwerten je 100 g.
public struct BLSFood: Equatable, Sendable, Identifiable {
  public var code: String
  public var name: String
  public var per100g: NutrientValues
  public var id: String { code }

  public init(code: String, name: String, per100g: NutrientValues) {
    self.code = code
    self.name = name
    self.per100g = per100g
  }

  /// Gerichte und Rezepte (Codes X und Y) statt einzelner Lebensmittel.
  public var isDish: Bool { code.hasPrefix("X") || code.hasPrefix("Y") }

  /// Als Position einer Mahlzeit (Standardmenge 100 g).
  public func item(grams: Double = 100) -> MealItem {
    var item = MealItem(name: name, grams: grams, source: .bls, per100g: per100g)
    item.blsCode = code
    item.isDrink = BLS.isDrink(self)
    return item
  }
}

/// Bundeslebensmittelschlüssel 4.0 (Max Rubner-Institut, frei nutzbar laut Dokumentation, Abschnitt 9.3): rund
/// 7.000 Lebensmittel, offline in der App (`Resources/bls.tsv`, erzeugt mit `tools/bls/convert.py`).
///
/// Regeln entscheiden, KI formuliert: Die KI zerlegt eine Mahlzeit nur in Lebensmittel und nennt je einen
/// Suchbegriff; die Nährwerte kommen aus dem BLS, wenn der Begriff eindeutig genug passt. Sonst bleibt die
/// KI-Schätzung (in der App als „geschätzt“ gekennzeichnet).
public enum BLS {
  /// Zitierweise laut BLS-Dokumentation (Abschnitt 9.2).
  public static let attribution =
    "Max Rubner-Institut (2025): Bundeslebensmittelschlüssel (BLS), Version 4.0. Karlsruhe"
  public static let sourceLabel = "BLS 4.0 (Max Rubner-Institut)"

  public static var foods: [BLSFood] { table.foods }

  public static func food(code: String) -> BLSFood? {
    table.byCode[code].map { table.foods[$0] }
  }

  /// Freie Suche wie in der Suchleiste: alle Wörter müssen vorkommen (Wortanfang), kurze Namen zuerst.
  public static func search(_ query: String, limit: Int = 20) -> [BLSFood] {
    let words = Tokens.words(query).map(\.text).filter { !Tokens.stopwords.contains($0) }
    guard !words.isEmpty, words.joined().count >= 2 else { return [] }
    let scored = table.entries.indices.compactMap { index -> (Int, Int)? in
      let entry = table.entries[index]
      guard words.allSatisfy({ word in entry.tokens.contains { $0.hasPrefix(word) } || entry.joined.contains(word) })
      else { return nil }
      let head = entry.tokens.first.map { Tokens.stem($0) == Tokens.stem(words[0]) } ?? false
      let score = (head ? 0 : 100) + (table.foods[index].isDish ? 20 : 0) + entry.tokens.count
      return (index, score)
    }
    return scored.sorted { ($0.1, table.foods[$0.0].name.count) < ($1.1, table.foods[$1.0].name.count) }
      .prefix(limit).map { table.foods[$0.0] }
  }

  /// Bestes BLS-Lebensmittel zu einem Suchbegriff der KI (z. B. „Hühnerei gekocht“) oder `nil`, wenn keins
  /// sicher genug passt. Regeln:
  /// - Das erste Wort (Hauptwort) entspricht dem ersten Wort des BLS-Namens (bei „Karotte/Möhre“ einem davon),
  ///   alle weiteren Wörter kommen im Namen vor.
  /// - Sonderprodukte (glutenfrei, Pulver, Konserve, gesalzen …) und Zusätze nach „mit“ nur, wenn genannt.
  /// - Ein einzelnes Wort passt nur auf Grundeinträge („Apfel roh“), sonst höchstens ein weiteres Merkmal
  ///   (plus eins in Klammern). Unter den Treffern gewinnt der mit den wenigsten Zusätzen.
  public static func match(_ term: String) -> BLSFood? {
    var words = Tokens.words(term).map(\.text).filter { !Tokens.stopwords.contains($0) }
    if let first = words.first, let alias = Tokens.aliases[first] { words = alias + words.dropFirst() }
    guard let headWord = words.first, headWord.count >= 2 else { return nil }
    var best: (index: Int, score: Int)?
    for index in table.entries.indices {
      let entry = table.entries[index]
      guard var used = Tokens.head(headWord, entry: entry) else { continue }
      var matched = true
      for word in words.dropFirst() {
        guard let hit = Tokens.find(word, in: entry.tokens, excluding: used) else {
          matched = false
          break
        }
        used.formUnion(hit)
      }
      guard matched, let extras = Tokens.extras(entry: entry, used: used, singleWord: words.count == 1)
      else { continue }
      let fillers = entry.tokens.count - used.count - extras
      let score = extras * 10 + fillers + (table.foods[index].isDish ? 5 : 0)
      if let current = best,
        score > current.score
          || (score == current.score && table.foods[index].name.count >= table.foods[current.index].name.count)
      {
        continue
      }
      best = (index, score)
    }
    return best.map { table.foods[$0.index] }
  }

  /// Übernimmt die BLS-Nährwerte in eine Position; Werte, die im BLS fehlen, bleiben aus der alten Quelle
  /// (außer die Position kam schon aus dem BLS).
  public static func apply(_ food: BLSFood, to item: MealItem) -> MealItem {
    var result = item
    // Wechsel zwischen BLS-Einträgen: keine Reste des vorigen Eintrags.
    let base = item.source == .bls ? [:] : item.per100g.values
    result.per100g = NutrientValues(base.merging(food.per100g.values) { _, bls in bls })
    result.source = .bls
    result.blsCode = food.code
    return result
  }

  /// KI-Positionen mit passendem BLS-Lebensmittel bekommen dessen Nährwerte. Andere Quellen bleiben unverändert.
  public static func enrich(_ item: MealItem) -> MealItem {
    guard item.source == .ai else { return item }
    let term = [item.searchTerm, item.name].compactMap { $0 }.first { !$0.isEmpty } ?? item.name
    guard let food = match(term) ?? (term == item.name ? nil : match(item.name)) else { return item }
    return apply(food, to: item)
  }

  static func isDrink(_ food: BLSFood) -> Bool {
    let drinkCodes = ["N", "P"]  // N = nichtalkoholische, P = alkoholische Getränke
    return drinkCodes.contains(String(food.code.prefix(1))) || food.name.contains("Getränk")
      || food.name.contains("drink") || food.name.hasSuffix("saft")
  }

  // MARK: - Tabelle

  struct Entry: Sendable {
    var tokens: [String]
    /// Wort steht in Klammern (Erläuterung wie „(Getränk)“).
    var inParens: [Bool]
    var joined: String
  }

  struct Table: Sendable {
    var foods: [BLSFood]
    var entries: [Entry]
    var byCode: [String: Int]

    init(foods: [BLSFood]) {
      self.foods = foods
      entries = foods.map { food in
        let words = Tokens.words(food.name)
        let tokens = words.map(\.text)
        return Entry(tokens: tokens, inParens: words.map(\.inParens), joined: tokens.joined())
      }
      byCode = Dictionary(foods.enumerated().map { ($1.code, $0) }, uniquingKeysWith: { first, _ in first })
    }
  }

  static let table = Table(foods: load())

  static func load() -> [BLSFood] {
    guard let url = Bundle.module.url(forResource: "bls", withExtension: "tsv"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return parse(text)
  }

  /// Liest die Tabelle: Kommentarzeile, Kopfzeile mit Nährstoff-Schlüsseln, dann eine Zeile je Lebensmittel.
  static func parse(_ text: String) -> [BLSFood] {
    var lines = text.split(separator: "\n", omittingEmptySubsequences: true).filter { !$0.hasPrefix("#") }
    guard !lines.isEmpty else { return [] }
    let header = lines.removeFirst().split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    let nutrients = header.dropFirst(2).map { Nutrient(rawValue: $0) }
    return lines.compactMap { line in
      let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard fields.count >= 2 else { return nil }
      var values: [Nutrient: Double] = [:]
      for (offset, nutrient) in nutrients.enumerated() {
        guard let nutrient, offset + 2 < fields.count, let value = Double(fields[offset + 2]) else { continue }
        values[nutrient] = value
      }
      return BLSFood(code: String(fields[0]), name: String(fields[1]), per100g: NutrientValues(values))
    }
  }
}

/// Wortzerlegung für BLS-Namen und Suchbegriffe: Kleinbuchstaben, Umlaute ausgeschrieben, Dezimalkomma als Punkt.
enum Tokens {
  struct Word: Equatable {
    var text: String
    var inParens = false
  }

  /// Steht zwischen erstem und zweitem Wort, wenn der BLS-Name Alternativen nennt („Karotte/Möhre“).
  static let alternative = "/"

  static let stopwords: Set<String> = ["mit", "und", "der", "die", "das", "von", "vom", "zum", "zur", "ca"]

  /// Zusätze, die die Nährwerte kaum ändern oder Standard sind (zählen nicht als Merkmal).
  static let fillers: Set<String> = [
    "roh", "frisch", "pasteurisiert", "mind", "max", "fett", "i", "tr", "bis", "getraenk", "ungesuesst", "natur",
    "zubereitet", "verzehrfertig", "suess", "reif", "ganz", "geschaelt", "geroestet", "mild", "gesaeuert",
  ]

  /// Sonderprodukte: nur, wenn der Suchbegriff sie nennt.
  static let markers: Set<String> = [
    "glutenfrei", "laktosefrei", "kohlenhydratreduziert", "energiereduziert", "riegel", "misch", "einlauf",
    "suppeneinlage", "pulver", "instantpulver", "getrocknet", "konserve", "angereichert", "trockenprodukt",
    "gesalzen", "gesuesst", "alkoholfrei", "entkoffeiniert", "koffeinreduziert",
  ]

  /// Alltagswörter, die im BLS anders heißen.
  static let aliases: [String: [String]] = [
    "ei": ["huehnerei"], "eier": ["huehnerei"], "nudeln": ["teigwaren", "eifrei"],
    "spaghetti": ["teigwaren", "eifrei"], "pasta": ["teigwaren", "eifrei"], "brokkoli": ["broccoli"],
    "ketchup": ["tomatenketchup"],
  ]

  static func isFiller(_ token: String) -> Bool {
    token == "mit" || fillers.contains(token) || token.allSatisfy { $0.isNumber || $0 == "." }
  }

  static func words(_ text: String) -> [Word] {
    let characters = Array(FoodSearch.normalized(text))
    var words: [Word] = []
    var current = ""
    var depth = 0
    func flush() {
      if !current.isEmpty { words.append(Word(text: current, inParens: depth > 0)) }
      current = ""
    }
    for (index, character) in characters.enumerated() {
      if character == ",", index > 0, index + 1 < characters.count, characters[index - 1].isNumber,
        characters[index + 1].isNumber
      {
        current.append(".")
        continue
      }
      if character.isLetter || character.isNumber {
        current.append(character)
        continue
      }
      flush()
      if character == "/", depth == 0, words.count == 1 { words.append(Word(text: alternative)) }
      if character == "(" { depth += 1 }
      if character == ")" { depth = max(0, depth - 1) }
    }
    flush()
    return words
  }

  /// Einfache Grundform für Mehrzahl und Beugung („Kartoffeln“ = „Kartoffel“, „Erdnüsse“ = „Erdnuss“).
  static func stem(_ word: String) -> String {
    var result = word.replacingOccurrences(of: "ae", with: "a").replacingOccurrences(of: "oe", with: "o")
      .replacingOccurrences(of: "ue", with: "u")
    if result.count > 4, let suffix = ["en", "n", "e"].first(where: { result.hasSuffix($0) }) {
      result.removeLast(suffix.count)
    }
    if result.count > 4, result.hasSuffix("s"), !result.hasSuffix("ss") { result.removeLast() }
    return result
  }

  /// Wie viele Namenswörter ab `from` dem Wort entsprechen: eins bei gleichem Wort, mehrere bei getrennt
  /// geschriebenen Zusammensetzungen („Haferflocken“ = „Hafer Flocken“). `exact: false` erlaubt Wortanfänge.
  static func matchLength(_ word: String, tokens: [String], from start: Int, exact: Bool) -> Int? {
    guard start < tokens.count else { return nil }
    let target = stem(word)
    if stem(tokens[start]) == target || (!exact && word.count >= 4 && tokens[start].hasPrefix(word)) { return 1 }
    var joined = tokens[start]
    for end in (start + 1)..<min(start + 3, tokens.count) where tokens[end] != alternative {
      joined += tokens[end]
      if stem(joined) == target { return end - start + 1 }
    }
    return nil
  }

  /// Verbrauchte Namenswörter für das Hauptwort (bei Alternativen samt Schrägstrich und zweitem Namen).
  static func head(_ word: String, entry: BLS.Entry) -> Set<Int>? {
    let tokens = entry.tokens
    let hasAlternative = tokens.count > 2 && tokens[1] == alternative
    if let length = matchLength(word, tokens: tokens, from: 0, exact: true) {
      return Set(0..<length).union(hasAlternative ? [1, 2] : [])
    }
    if hasAlternative, let length = matchLength(word, tokens: tokens, from: 2, exact: true) {
      return Set(0..<(2 + length))
    }
    return nil
  }

  /// Fundstelle eines Worts irgendwo im Namen (ohne schon verbrauchte Wörter).
  static func find(_ word: String, in tokens: [String], excluding used: Set<Int>) -> Set<Int>? {
    for start in tokens.indices where !used.contains(start) {
      if let length = matchLength(word, tokens: tokens, from: start, exact: false) {
        let range = Set(start..<(start + length))
        if range.isDisjoint(with: used) { return range }
      }
    }
    return nil
  }

  /// Zahl der echten Zusatzmerkmale im BLS-Namen oder `nil`, wenn der Eintrag nicht passen darf.
  static func extras(entry: BLS.Entry, used: Set<Int>, singleWord: Bool) -> Int? {
    let rest = entry.tokens.indices.filter { !used.contains($0) }
    if rest.contains(where: { markers.contains(entry.tokens[$0]) }) { return nil }
    // „Bier mit Sekt“: alles nach „mit“ (außerhalb von Klammern) muss im Suchbegriff stehen.
    if let with = rest.first(where: { entry.tokens[$0] == "mit" && !entry.inParens[$0] }),
      rest.contains(where: { $0 > with && !entry.inParens[$0] && !isFiller(entry.tokens[$0]) })
    {
      return nil
    }
    let plain = rest.filter { !entry.inParens[$0] && !isFiller(entry.tokens[$0]) }.count
    let inParens = rest.filter { entry.inParens[$0] && !isFiller(entry.tokens[$0]) }.count
    if singleWord && plain + inParens > 0 { return nil }
    if plain > 1 || plain + inParens > 2 { return nil }
    return plain + inParens
  }
}
