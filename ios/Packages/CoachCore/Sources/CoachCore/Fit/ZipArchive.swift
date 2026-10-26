import Foundation

/// Liest die FIT-Datei aus Garmins Download (`/download-service/files/activity/{id}` liefert ein ZIP mit
/// einer `.fit`-Datei). Unterstützt die beiden üblichen Verfahren „gespeichert“ (0) und „Deflate“ (8).
public enum ZipArchive {
  public enum Failure: Error, Equatable {
    case notAZip
    case noFitEntry
    case unsupportedMethod(Int)
    case truncated
  }

  /// FIT-Inhalt aus einem ZIP; ist `data` schon eine FIT-Datei, kommt sie unverändert zurück.
  public static func fitData(from data: Data) throws -> Data {
    let bytes = [UInt8](data)
    if FitDecoder.looksLikeFit(bytes) { return data }
    guard bytes.count >= 22, bytes[0] == 0x50, bytes[1] == 0x4B else { throw Failure.notAZip }

    let entries = try centralDirectory(bytes)
    guard let entry = entries.first(where: { $0.name.lowercased().hasSuffix(".fit") }) else {
      throw Failure.noFitEntry
    }
    return try extract(entry, from: bytes)
  }

  struct Entry {
    let name: String
    let method: Int
    let compressedSize: Int
    let localHeaderOffset: Int
  }

  static func centralDirectory(_ bytes: [UInt8]) throws -> [Entry] {
    // Ende des zentralen Verzeichnisses rückwärts suchen (Kommentar am Ende ist bis 64 KB lang).
    let lowest = max(0, bytes.count - 22 - 65_535)
    var end = bytes.count - 22
    while end >= lowest, !(bytes[end] == 0x50 && bytes[end + 1] == 0x4B && bytes[end + 2] == 5 && bytes[end + 3] == 6) {
      end -= 1
    }
    guard end >= lowest else { throw Failure.notAZip }
    let count = uint16(bytes, end + 10)
    var offset = Int(uint32(bytes, end + 16))

    var entries: [Entry] = []
    for _ in 0..<count {
      guard offset + 46 <= bytes.count, uint32(bytes, offset) == 0x0201_4B50 else { throw Failure.truncated }
      let nameLength = uint16(bytes, offset + 28)
      let extraLength = uint16(bytes, offset + 30)
      let commentLength = uint16(bytes, offset + 32)
      guard offset + 46 + nameLength <= bytes.count else { throw Failure.truncated }
      entries.append(
        Entry(
          name: String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self),
          method: uint16(bytes, offset + 10),
          compressedSize: Int(uint32(bytes, offset + 20)),
          localHeaderOffset: Int(uint32(bytes, offset + 42))))
      offset += 46 + nameLength + extraLength + commentLength
    }
    return entries
  }

  static func extract(_ entry: Entry, from bytes: [UInt8]) throws -> Data {
    let header = entry.localHeaderOffset
    guard header + 30 <= bytes.count, uint32(bytes, header) == 0x0403_4B50 else { throw Failure.truncated }
    let start = header + 30 + uint16(bytes, header + 26) + uint16(bytes, header + 28)
    let end = start + entry.compressedSize
    guard end <= bytes.count else { throw Failure.truncated }
    let payload = Data(bytes[start..<end])
    switch entry.method {
    case 0: return payload
    case 8: return try Inflate.decompress(payload)
    default: throw Failure.unsupportedMethod(entry.method)
    }
  }

  static func uint16(_ bytes: [UInt8], _ offset: Int) -> Int {
    Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
  }

  static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
      | UInt32(bytes[offset + 3]) << 24
  }
}
