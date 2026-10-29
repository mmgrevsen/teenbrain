import AVFoundation
import AppKit
import CoreImage
import FlutterMacOS
import Foundation
import QuartzCore

/// The AVFoundation capture session behind GlemtDet's scanner.
///
/// Capture runs on its own serial queue and keeps running while the window is
/// hidden — that is what makes "Hukommelse aktiv" work without the app being
/// frontmost. macOS keeps the camera indicator lit the whole time, which is
/// intentional and correct: the user should always be able to see that the
/// camera is on.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

  enum CameraError: Error {
    case noDevice
    case permissionDenied
    case configurationFailed(String)
  }

  private let session = AVCaptureSession()
  private let queue = DispatchQueue(label: "dk.glemtdet.capture", qos: .userInitiated)
  private let output = AVCaptureVideoDataOutput()
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  let frames = FrameStore()
  let texture = CameraTexture()

  private weak var registrar: FlutterTextureRegistry?
  private var textureId: Int64 = -1
  private var running = false

  /// Called on the capture queue with a fresh signal, throttled.
  var onSignal: ((FrameStore.Signal) -> Void)?

  private var lastSignalAt: CFTimeInterval = 0
  private var lastTextureAt: CFTimeInterval = 0

  /// How often the cheap frame signal is forwarded to Dart. The sampler adds
  /// its own, larger intervals on top; this only stops the channel from being
  /// hammered at the full capture rate.
  private let signalInterval: CFTimeInterval = 0.4

  /// Preview refresh cap. The preview is a convenience, not the product.
  private let textureInterval: CFTimeInterval = 1.0 / 24.0

  init(registrar: FlutterTextureRegistry?) {
    self.registrar = registrar
    super.init()
  }

  // MARK: - Permissions

  static func permissionStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return "granted"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "notDetermined"
    }
  }

  static func requestPermission(_ completion: @escaping (String) -> Void) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    guard status == .notDetermined else {
      completion(permissionStatus())
      return
    }
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async { completion(permissionStatus()) }
    }
  }

  // MARK: - Devices

  static func discoverySession() -> AVCaptureDevice.DiscoverySession {
    var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .externalUnknown]
    if #available(macOS 14.0, *) {
      types = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
    }
    return AVCaptureDevice.DiscoverySession(
      deviceTypes: types, mediaType: .video, position: .unspecified)
  }

  static func listDevices() -> [[String: Any]] {
    let devices = discoverySession().devices
    let defaultId = AVCaptureDevice.default(for: .video)?.uniqueID
    return devices.map { device in
      [
        "id": device.uniqueID,
        "name": device.localizedName,
        "isDefault": device.uniqueID == defaultId,
      ]
    }
  }

  // MARK: - Lifecycle

  var isRunning: Bool { running }

  func start(deviceId: String?) throws -> Int64 {
    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
      throw CameraError.permissionDenied
    }
    if running { return textureId }

    let device: AVCaptureDevice?
    if let deviceId {
      device = Self.discoverySession().devices.first { $0.uniqueID == deviceId }
    } else {
      device = AVCaptureDevice.default(for: .video) ?? Self.discoverySession().devices.first
    }
    guard let device else { throw CameraError.noDevice }

    session.beginConfiguration()
    session.sessionPreset = .high

    for input in session.inputs { session.removeInput(input) }
    for out in session.outputs { session.removeOutput(out) }

    do {
      let input = try AVCaptureDeviceInput(device: device)
      guard session.canAddInput(input) else {
        session.commitConfiguration()
        throw CameraError.configurationFailed("Kameraet kunne ikke tilføjes til sessionen.")
      }
      session.addInput(input)
    } catch let error as CameraError {
      throw error
    } catch {
      session.commitConfiguration()
      throw CameraError.configurationFailed(error.localizedDescription)
    }

    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)
    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      throw CameraError.configurationFailed("Videoudgangen kunne ikke tilføjes.")
    }
    session.addOutput(output)
    session.commitConfiguration()

    if textureId < 0, let registrar {
      textureId = registrar.register(texture)
    }

    running = true
    queue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
    return textureId
  }

  func stop() {
    guard running else { return }
    running = false
    queue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  func teardown() {
    stop()
    if textureId >= 0, let registrar {
      registrar.unregisterTexture(textureId)
      textureId = -1
    }
  }

  // MARK: - Frame delivery

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let signal = frames.store(buffer)

    let now = CACurrentMediaTime()
    if now - lastTextureAt >= textureInterval {
      lastTextureAt = now
      texture.push(buffer)
      if textureId >= 0, let registrar {
        registrar.textureFrameAvailable(textureId)
      }
    }
    if now - lastSignalAt >= signalInterval {
      lastSignalAt = now
      onSignal?(signal)
    }
  }

  // MARK: - Stills

  /// JPEG of the current frame, scaled so the long edge is at most `maxWidth`.
  /// Used for the reference image stored with an observation.
  func captureStill(maxWidth: Int, quality: Double) -> Data? {
    guard let buffer = frames.latest() else { return nil }
    var image = CIImage(cvPixelBuffer: buffer)
    let extent = image.extent
    guard extent.width > 0, extent.height > 0 else { return nil }

    let scale = min(1.0, CGFloat(maxWidth) / extent.width)
    if scale < 1.0 {
      image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    guard let cgImage = ciContext.createCGImage(image, from: image.extent) else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(
      using: .jpeg,
      properties: [.compressionFactor: NSNumber(value: quality)])
  }
}
