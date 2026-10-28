@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech

/// Diktieren auf Deutsch mit der Spracherkennung von Apple. Wenn das Gerät es kann, bleibt die Erkennung auf dem
/// iPhone (`requiresOnDeviceRecognition`); sonst verarbeitet Apple die Aufnahme, wie beim Diktieren der Tastatur.
/// Braucht weder Entitlement noch bezahlten Account – nur die Erlaubnis für Mikrofon und Spracherkennung.
@Observable
final class Dictation {
  private(set) var isRecording = false
  /// Bisher erkannter Text der laufenden Aufnahme (wächst während des Sprechens).
  private(set) var transcript = ""
  private(set) var error: String?
  /// Erkennung läuft auf dem Gerät (nichts verlässt das iPhone).
  private(set) var isOnDevice = false

  private var capture: AudioCapture?

  static var isSupported: Bool { SFSpeechRecognizer(locale: locale) != nil }
  static let locale = Locale(identifier: "de-DE")

  func toggle() async {
    if isRecording { stop() } else { await start() }
  }

  func start() async {
    error = nil
    guard await AudioCapture.authorize() else {
      error = "Mikrofon oder Spracherkennung nicht erlaubt – in den iOS-Einstellungen › IronLudi einschalten."
      return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Self.locale), recognizer.isAvailable else {
      error = "Spracherkennung ist gerade nicht verfügbar."
      return
    }
    transcript = ""
    let capture = AudioCapture()
    do {
      isOnDevice = try capture.start(recognizer: recognizer) { [weak self] text, finished, failure in
        Task { @MainActor in self?.receive(text: text, finished: finished, failure: failure) }
      }
      self.capture = capture
      isRecording = true
    } catch {
      capture.stop()
      self.error = "Aufnahme ließ sich nicht starten: \(error.localizedDescription)"
    }
  }

  func stop() {
    capture?.stop()
    capture = nil
    isRecording = false
  }

  private func receive(text: String?, finished: Bool, failure: String?) {
    if let text { transcript = text }
    // „Kein Sprachsignal“ nach Stopp ist kein Fehler, wenn schon Text da ist.
    if let failure, transcript.isEmpty { error = failure }
    if finished { stop() }
  }

}

/// Mikrofon und Erkennung außerhalb des Main Actors: Der Audio-Tap läuft auf einem Echtzeit-Thread, die Ergebnisse
/// kommen auf einer beliebigen Queue.
private nonisolated final class AudioCapture: @unchecked Sendable {
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  /// Nicht auf dem Main Actor: iOS ruft die Rückfrage auf einer Hintergrund-Queue zurück.
  static func authorize() async -> Bool {
    let speech = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
    }
    guard speech else { return false }
    return await AVAudioApplication.requestRecordPermission()
  }

  /// Gibt zurück, ob die Erkennung auf dem Gerät läuft.
  func start(
    recognizer: SFSpeechRecognizer, update: @escaping @Sendable (String?, Bool, String?) -> Void
  ) throws -> Bool {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    try session.setActive(true, options: .notifyOthersOnDeactivation)

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    let onDevice = recognizer.supportsOnDeviceRecognition
    request.requiresOnDeviceRecognition = onDevice
    self.request = request

    let input = engine.inputNode
    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
      request.append(buffer)
    }
    engine.prepare()
    try engine.start()

    task = recognizer.recognitionTask(with: request) { result, error in
      let text = result?.bestTranscription.formattedString
      update(text, result?.isFinal ?? (error != nil), error.map { _ in "Nichts verstanden – bitte noch einmal." })
    }
    return onDevice
  }

  func stop() {
    if engine.isRunning {
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
    }
    request?.endAudio()
    task?.finish()
    request = nil
    task = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}
