import Foundation

/// Entpackt DEFLATE-Daten (RFC 1951, ohne zlib-Kopf), wie sie in ZIP-Dateien stecken.
///
/// Eigene Umsetzung nach Mark Adlers `puff.c`, damit `CoachCore` ohne Apple-Frameworks (Compression)
/// auskommt und die Tests auf Linux laufen. Für die wenigen FIT-Dateien je Abruf reicht das Tempo.
public enum Inflate {
  public enum Failure: Error, Equatable {
    case truncated
    case invalidBlockType
    case invalidStoredLength
    case invalidCode
    case invalidDistance
    case tooLarge
  }

  /// Obergrenze gegen kaputte oder bösartige Daten (eine FIT-Datei hat selten mehr als ein paar MB).
  public static let maxOutput = 64 * 1024 * 1024

  public static func decompress(_ data: Data) throws -> Data {
    var state = State(input: [UInt8](data))
    var last = false
    while !last {
      last = try state.bits(1) == 1
      switch try state.bits(2) {
      case 0: try state.stored()
      case 1: try state.codes(lengths: Fixed.lengths, distances: Fixed.distances)
      case 2: try state.dynamic()
      default: throw Failure.invalidBlockType
      }
    }
    return Data(state.output)
  }

  // MARK: - Huffman-Tabellen

  struct Huffman {
    /// Anzahl der Codes je Länge (0…15).
    var count = [Int](repeating: 0, count: 16)
    /// Symbole nach Code sortiert.
    var symbol: [Int]

    init(lengths: [Int]) {
      symbol = [Int](repeating: 0, count: lengths.count)
      for length in lengths { count[length] += 1 }
      var offsets = [Int](repeating: 0, count: 16)
      for length in 1..<15 { offsets[length + 1] = offsets[length] + count[length] }
      for (value, length) in lengths.enumerated() where length != 0 {
        symbol[offsets[length]] = value
        offsets[length] += 1
      }
    }
  }

  enum Fixed {
    static let lengths: Huffman = {
      var lengths = [Int](repeating: 8, count: 288)
      for index in 144..<256 { lengths[index] = 9 }
      for index in 256..<280 { lengths[index] = 7 }
      return Huffman(lengths: lengths)
    }()
    static let distances = Huffman(lengths: [Int](repeating: 5, count: 30))
  }

  static let lengthBase = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
  ]
  static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
  static let distanceBase = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097,
    6145, 8193, 12289, 16385, 24577,
  ]
  static let distanceExtra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
  ]
  /// Reihenfolge der Codelängen-Codes im dynamischen Block.
  static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

  // MARK: - Zustand

  struct State {
    let input: [UInt8]
    var position = 0
    var bitBuffer = 0
    var bitCount = 0
    var output: [UInt8] = []

    init(input: [UInt8]) {
      self.input = input
    }

    mutating func bits(_ needed: Int) throws -> Int {
      var value = bitBuffer
      while bitCount < needed {
        guard position < input.count else { throw Failure.truncated }
        value |= Int(input[position]) << bitCount
        position += 1
        bitCount += 8
      }
      bitBuffer = value >> needed
      bitCount -= needed
      return value & ((1 << needed) - 1)
    }

    mutating func stored() throws {
      bitBuffer = 0
      bitCount = 0
      guard position + 4 <= input.count else { throw Failure.truncated }
      let length = Int(input[position]) | Int(input[position + 1]) << 8
      let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
      guard length == (~complement & 0xFFFF) else { throw Failure.invalidStoredLength }
      position += 4
      guard position + length <= input.count else { throw Failure.truncated }
      guard output.count + length <= Inflate.maxOutput else { throw Failure.tooLarge }
      output.append(contentsOf: input[position..<(position + length)])
      position += length
    }

    mutating func decode(_ huffman: Huffman) throws -> Int {
      var code = 0
      var first = 0
      var index = 0
      for length in 1...15 {
        code |= try bits(1)
        let count = huffman.count[length]
        if code - count < first { return huffman.symbol[index + (code - first)] }
        index += count
        first += count
        first <<= 1
        code <<= 1
      }
      throw Failure.invalidCode
    }

    mutating func codes(lengths: Huffman, distances: Huffman) throws {
      while true {
        let symbol = try decode(lengths)
        if symbol < 256 {
          guard output.count < Inflate.maxOutput else { throw Failure.tooLarge }
          output.append(UInt8(symbol))
          continue
        }
        if symbol == 256 { return }
        let lengthIndex = symbol - 257
        guard lengthIndex < Inflate.lengthBase.count else { throw Failure.invalidCode }
        let lengthExtra = try bits(Inflate.lengthExtra[lengthIndex])
        let length = Inflate.lengthBase[lengthIndex] + lengthExtra
        let distanceSymbol = try decode(distances)
        guard distanceSymbol < Inflate.distanceBase.count else { throw Failure.invalidDistance }
        let distanceExtra = try bits(Inflate.distanceExtra[distanceSymbol])
        let distance = Inflate.distanceBase[distanceSymbol] + distanceExtra
        guard distance <= output.count else { throw Failure.invalidDistance }
        guard output.count + length <= Inflate.maxOutput else { throw Failure.tooLarge }
        let start = output.count - distance
        // Überlappende Kopie ist erlaubt (z. B. Abstand 1 = Wiederholung).
        for offset in 0..<length { output.append(output[start + offset]) }
      }
    }

    mutating func dynamic() throws {
      let literalCount = try bits(5) + 257
      let distanceCount = try bits(5) + 1
      let codeCount = try bits(4) + 4
      guard literalCount <= 286, distanceCount <= 30 else { throw Failure.invalidCode }
      var codeLengths = [Int](repeating: 0, count: 19)
      for index in 0..<codeCount { codeLengths[Inflate.codeLengthOrder[index]] = try bits(3) }
      let codeLengthCode = Huffman(lengths: codeLengths)

      var lengths: [Int] = []
      while lengths.count < literalCount + distanceCount {
        let symbol = try decode(codeLengthCode)
        switch symbol {
        case 0..<16:
          lengths.append(symbol)
        case 16:
          guard let previous = lengths.last else { throw Failure.invalidCode }
          let repeats = try bits(2)
          lengths += [Int](repeating: previous, count: 3 + repeats)
        case 17:
          let repeats = try bits(3)
          lengths += [Int](repeating: 0, count: 3 + repeats)
        default:
          let repeats = try bits(7)
          lengths += [Int](repeating: 0, count: 11 + repeats)
        }
      }
      guard lengths.count == literalCount + distanceCount, lengths[256] != 0 else { throw Failure.invalidCode }
      try codes(
        lengths: Huffman(lengths: Array(lengths[0..<literalCount])),
        distances: Huffman(lengths: Array(lengths[literalCount...])))
    }
  }
}
