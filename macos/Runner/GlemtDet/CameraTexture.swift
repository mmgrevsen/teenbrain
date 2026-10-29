import CoreVideo
import FlutterMacOS
import Foundation

/// Bridges the capture buffer to Flutter's compositor.
///
/// Flutter pulls from `copyPixelBuffer` on its raster thread whenever it has
/// been told a frame is available, so the preview costs one retained buffer and
/// no copying, encoding or channel traffic.
final class CameraTexture: NSObject, FlutterTexture {

  private let lock = NSLock()
  private var pending: CVPixelBuffer?

  func push(_ buffer: CVPixelBuffer) {
    lock.lock()
    pending = buffer
    lock.unlock()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let buffer = pending else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  func onTextureUnregistered(_ texture: FlutterTexture) {
    lock.lock()
    pending = nil
    lock.unlock()
  }
}
