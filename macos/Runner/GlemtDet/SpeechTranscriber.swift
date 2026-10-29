import AVFoundation
import FlutterMacOS
import Foundation
import Speech

/// Live speech-to-text with Apple's on-device recogniser.
///
/// Two things make this worth writing natively rather than reaching for a
/// plugin. First, `SFSpeechRecognizer` can be pinned to the device
/// (`requiresOnDeviceRecognition`), which means the audio never leaves the
/// machine — that is the whole privacy claim behind Live Notes, and it is not
/// something a general-purpose plugin guarantees. Second, this project has no
/// CocoaPods step, and keeping it that way is worth more than the saved lines.
///
/// Danish is supported on-device on recent macOS. Where it is not, the
/// recogniser would silently fall back to Apple's servers — so this refuses to
/// start instead, and the Dart side says why.
final class SpeechTranscriber: NSObject, SFSpeechRecognizerDelegate {

  /// Emitted for every revision the recogniser makes.
  struct Segment {
    let text: String
    let isFinal: Bool
    let confidence: Double?
  }

  var onSegment: ((Segment) -> Void)?
  var onError: ((String, String) -> Void)?
  var onStopped: (() -> Void)?

  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?

  private(set) var isRunning = false

  // MARK: - Permissions

  /// Microphone and speech recognition are separate grants, and the UI has to
  /// be able to tell which one is missing.
  static func permissionStatus() -> [String: String] {
    return [
      "microphone": describe(AVCaptureDevice.authorizationStatus(for: .audio)),
      "speech": describe(SFSpeechRecognizer.authorizationStatus()),
    ]
  }

  private static func describe(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "denied"
    }
  }

  private static func describe(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch status {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "denied"
    }
  }

  /// Asks for both grants in turn, then reports the result. Asking for one the
  /// user already answered is a no-op at the OS level, so this is safe to call
  /// repeatedly.
  static func requestPermission(completion: @escaping ([String: String]) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { _ in
      SFSpeechRecognizer.requestAuthorization { _ in
        DispatchQueue.main.async { completion(permissionStatus()) }
      }
    }
  }

  // MARK: - Session

  func start(localeId: String) throws {
    if isRunning { return }

    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
          SFSpeechRecognizer.authorizationStatus() == .authorized
    else {
      throw Failure(code: "permissionDenied", message: "Der mangler adgang til mikrofon eller talegenkendelse.")
    }

    let locale = Locale(identifier: localeId)
    guard let recognizer = SFSpeechRecognizer(locale: locale) else {
      throw Failure(code: "localeUnsupported", message: "Der er ingen talegenkendelse til \(localeId).")
    }
    guard recognizer.isAvailable else {
      throw Failure(code: "failed", message: "Talegenkendelsen er ikke tilgængelig lige nu.")
    }
    guard recognizer.supportsOnDeviceRecognition else {
      // Falling back to Apple's servers here would quietly break the promise
      // the Privacy page makes, so refuse and let the UI explain.
      throw Failure(
        code: "localeUnsupported",
        message: "\(localeId) kan ikke genkendes lokalt på denne Mac, og TeenBrain sender ikke lyd ud af maskinen.")
    }

    recognizer.delegate = self
    self.recognizer = recognizer

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    // Punctuation makes the transcript usable as note material rather than as
    // one long breathless sentence.
    if #available(macOS 13.0, *) {
      request.addsPunctuation = true
    }
    self.request = request

    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0, format.sampleRate > 0 else {
      throw Failure(code: "noInput", message: "Der er ingen mikrofon at lytte på.")
    }

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }

    task = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }

      if let result {
        let segments = result.bestTranscription.segments
        // SFSpeechRecognizer reports confidence per segment and leaves it at 0
        // until a result is final; averaging the non-zero ones is the closest
        // honest summary.
        let scored = segments.map { Double($0.confidence) }.filter { $0 > 0 }
        let confidence = scored.isEmpty ? nil : scored.reduce(0, +) / Double(scored.count)

        self.onSegment?(Segment(
          text: result.bestTranscription.formattedString,
          isFinal: result.isFinal,
          confidence: confidence))
      }

      if error != nil || (result?.isFinal ?? false) {
        // A recogniser that ends on its own (silence, a time limit, an error)
        // has to tell Dart, or the UI sits there showing a live indicator for
        // a session that is over.
        let wasRunning = self.isRunning
        self.teardown()
        if wasRunning {
          if let error, !(result?.isFinal ?? false) {
            self.onError?("failed", error.localizedDescription)
          }
          self.onStopped?()
        }
      }
    }

    engine.prepare()
    do {
      try engine.start()
    } catch {
      teardown()
      throw Failure(code: "noInput", message: "Kunne ikke starte lydoptagelsen: \(error.localizedDescription)")
    }

    isRunning = true
  }

  func stop() {
    guard isRunning else { return }
    // Ends the audio stream so the recogniser flushes a final result before
    // the task is cancelled; teardown happens in the completion handler.
    request?.endAudio()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    isRunning = false
  }

  private func teardown() {
    if engine.isRunning {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    task?.cancel()
    task = nil
    request = nil
    isRunning = false
  }

  func dispose() {
    teardown()
    recognizer = nil
    onSegment = nil
    onError = nil
    onStopped = nil
  }

  // MARK: - SFSpeechRecognizerDelegate

  func speechRecognizer(_ recognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    guard !available, isRunning else { return }
    teardown()
    onError?("failed", "Talegenkendelsen blev utilgængelig.")
    onStopped?()
  }

  /// Carries a Dart-side reason code alongside the message.
  struct Failure: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
  }
}

/// A stream handler of its own for the transcript.
///
/// The plugin already implements `FlutterStreamHandler` for camera frames, and
/// one object cannot hold two sinks — the second `onListen` would overwrite the
/// first. Transcription gets its own handler so a running scanner and a running
/// transcription do not cut each other off.
final class TranscriptStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func send(_ payload: [String: Any]) {
    sink?(payload)
  }

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}
