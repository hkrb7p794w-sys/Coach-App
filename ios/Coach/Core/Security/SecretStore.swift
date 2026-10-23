import Foundation
import Security

/// Schlüssel für Geheimnisse, die nur im Keychain liegen.
enum SecretKey: String, CaseIterable {
  case garminAPIKey
  case garminBearerToken
  case aiAppToken
}

/// Ablage für Geheimnisse; im Test durch einen Speicher im Arbeitsspeicher ersetzt.
protocol SecretStore {
  func string(for key: SecretKey) -> String?
  func set(_ value: String?, for key: SecretKey) throws
}

struct KeychainError: Error, LocalizedError {
  let status: OSStatus

  var errorDescription: String? {
    "Keychain-Fehler \(status)"
  }
}

/// Keychain-Zugriff (generische Passwörter). Lesbar nach dem ersten Entsperren, damit die
/// Hintergrundaktualisierung den Garmin-Key nutzen kann; nicht in Backups anderer Geräte.
struct KeychainStore: SecretStore {
  var service = "io.github.hkrb7p794w.coach"

  private func query(_ key: SecretKey) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]
  }

  func string(for key: SecretKey) -> String? {
    var request = query(key)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func set(_ value: String?, for key: SecretKey) throws {
    let deleteStatus = SecItemDelete(query(key) as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw KeychainError(status: deleteStatus)
    }
    guard let value, !value.isEmpty else { return }
    var item = query(key)
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
}

/// Speicher im Arbeitsspeicher für Tests und Vorschauen.
final class InMemorySecretStore: SecretStore {
  private var values: [SecretKey: String] = [:]

  init(_ values: [SecretKey: String] = [:]) {
    self.values = values
  }

  func string(for key: SecretKey) -> String? {
    values[key]
  }

  func set(_ value: String?, for key: SecretKey) throws {
    values[key] = value?.isEmpty == false ? value : nil
  }
}
