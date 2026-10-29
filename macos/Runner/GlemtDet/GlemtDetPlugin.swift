import AVFoundation
import FlutterMacOS
import Foundation

/// Wires the native camera and Vision stack to the Dart side.
///
/// Channel names are mirrored in `lib/vision/apple/apple_channels.dart`.
public class GlemtDetPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

  private var controller: CameraController?
  private let analyzer = VisionAnalyzer()
  private var eventSink: FlutterEventSink?
  private let transcriber = SpeechTranscriber()
  private let transcriptStream = TranscriptStreamHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = GlemtDetPlugin()
    instance.controller = CameraController(registrar: registrar.textures)

    let camera = FlutterMethodChannel(
      name: "dk.glemtdet/camera", binaryMessenger: registrar.messenger)
    let vision = FlutterMethodChannel(
      name: "dk.glemtdet/vision", binaryMessenger: registrar.messenger)
    let system = FlutterMethodChannel(
      name: "dk.glemtdet/system", binaryMessenger: registrar.messenger)
    let frames = FlutterEventChannel(
      name: "dk.glemtdet/frames", binaryMessenger: registrar.messenger)
    let speech = FlutterMethodChannel(
      name: "dk.glemtdet/speech", binaryMessenger: registrar.messenger)
    let transcript = FlutterEventChannel(
      name: "dk.glemtdet/transcript", binaryMessenger: registrar.messenger)

    registrar.addMethodCallDelegate(instance, channel: camera)
    registrar.addMethodCallDelegate(instance, channel: vision)
    registrar.addMethodCallDelegate(instance, channel: system)
    registrar.addMethodCallDelegate(instance, channel: speech)
    frames.setStreamHandler(instance)
    transcript.setStreamHandler(instance.transcriptStream)

    instance.wireTranscriber()
  }

  /// Routes recogniser output to the transcript stream. Set up once, so a
  /// restarted session does not stack duplicate handlers.
  private func wireTranscriber() {
    transcriber.onSegment = { [weak self] segment in
      DispatchQueue.main.async {
        self?.transcriptStream.send([
          "type": "segment",
          "text": segment.text,
          "isFinal": segment.isFinal,
          "confidence": segment.confidence as Any,
          "ts": Int(Date().timeIntervalSince1970 * 1000),
        ])
      }
    }
    transcriber.onError = { [weak self] code, message in
      DispatchQueue.main.async {
        self?.transcriptStream.send(["type": "error", "code": code, "message": message])
      }
    }
    transcriber.onStopped = { [weak self] in
      DispatchQueue.main.async {
        self?.transcriptStream.send(["type": "stopped"])
      }
    }
  }

  // MARK: - Method calls

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    // ---- camera ----------------------------------------------------
    case "permissionStatus":
      result(CameraController.permissionStatus())

    case "requestPermission":
      CameraController.requestPermission { result($0) }

    case "listDevices":
      result(CameraController.listDevices())

    case "start":
      let args = call.arguments as? [String: Any]
      let deviceId = args?["deviceId"] as? String
      guard let controller else {
        result(FlutterError(code: "unsupported", message: "Kameraet er ikke klar.", details: nil))
        return
      }
      controller.onSignal = { [weak self] signal in
        DispatchQueue.main.async {
          self?.eventSink?([
            "ts": signal.timestampMs,
            "change": signal.change,
            "brightness": signal.brightness,
          ])
        }
      }
      do {
        let textureId = try controller.start(deviceId: deviceId)
        result(["textureId": textureId])
      } catch CameraController.CameraError.permissionDenied {
        result(
          FlutterError(
            code: "permission_denied",
            message: "GlemtDet har ikke adgang til kameraet.", details: nil))
      } catch CameraController.CameraError.noDevice {
        result(
          FlutterError(
            code: "no_device",
            message: "Der blev ikke fundet noget kamera på denne computer.", details: nil))
      } catch CameraController.CameraError.configurationFailed(let message) {
        result(FlutterError(code: "failed", message: message, details: nil))
      } catch {
        result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }

    case "stop":
      controller?.stop()
      result(nil)

    case "captureStill":
      let args = call.arguments as? [String: Any]
      let maxWidth = args?["maxWidth"] as? Int ?? 960
      let quality = args?["quality"] as? Double ?? 0.72
      guard let data = controller?.captureStill(maxWidth: maxWidth, quality: quality) else {
        result(nil)
        return
      }
      result(FlutterStandardTypedData(bytes: data))

    // ---- vision ----------------------------------------------------
    case "initialize":
      if let args = call.arguments as? [String: Any] {
        var config = VisionAnalyzer.Config()
        config.maxRegions = args["maxRegions"] as? Int ?? config.maxRegions
        config.labelsPerRegion = args["labelsPerRegion"] as? Int ?? config.labelsPerRegion
        config.frameLabels = args["frameLabels"] as? Int ?? config.frameLabels
        analyzer.config = config
      }
      result(true)

    case "vocabulary":
      result(analyzer.vocabulary())

    case "analyze":
      guard let controller, let buffer = controller.frames.latest() else {
        result(nil)
        return
      }
      analyzer.analyze(buffer: buffer) { payload in
        controller.frames.markAnalysed()
        DispatchQueue.main.async { result(payload) }
      }

    // ---- system ----------------------------------------------------
    case "downloadsDirectory":
      result(SystemPaths.downloadsDirectory())

    case "applicationSupportDirectory":
      result(SystemPaths.applicationSupportDirectory())

    // ---- speech ----------------------------------------------------
    case "speechPermissionStatus":
      result(SpeechTranscriber.permissionStatus())

    case "speechRequestPermission":
      SpeechTranscriber.requestPermission { result($0) }

    case "speechStart":
      let args = call.arguments as? [String: Any]
      let localeId = args?["localeId"] as? String ?? "da-DK"
      do {
        try transcriber.start(localeId: localeId)
        result(true)
      } catch let failure as SpeechTranscriber.Failure {
        result(FlutterError(code: failure.code, message: failure.message, details: nil))
      } catch {
        result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
      }

    case "speechStop":
      transcriber.stop()
      result(nil)

    case "speechIsRunning":
      result(transcriber.isRunning)

    // ---- secrets ---------------------------------------------------
    case "secretRead":
      let args = call.arguments as? [String: Any]
      guard let account = args?["account"] as? String else {
        result(FlutterError(code: "bad_args", message: "Mangler account.", details: nil))
        return
      }
      result(SecretStore.read(account: account))

    case "secretWrite":
      let args = call.arguments as? [String: Any]
      guard let account = args?["account"] as? String,
            let value = args?["value"] as? String else {
        result(FlutterError(code: "bad_args", message: "Mangler account eller value.", details: nil))
        return
      }
      if SecretStore.write(account: account, value: value) {
        result(true)
      } else {
        result(FlutterError(
          code: "keychain", message: "Nøgleringen afviste at gemme værdien.", details: nil))
      }

    case "secretDelete":
      let args = call.arguments as? [String: Any]
      guard let account = args?["account"] as? String else {
        result(FlutterError(code: "bad_args", message: "Mangler account.", details: nil))
        return
      }
      result(SecretStore.delete(account: account))

    case "reveal":
      let path = (call.arguments as? [String: Any])?["path"] as? String
      result(path.map { SystemPaths.reveal(path: $0) } ?? false)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Event channel

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}
