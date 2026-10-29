import CoreVideo
import Foundation

/// Holds the most recent camera frame and the two cheap statistics the Dart
/// sampler needs to decide whether the frame is worth analysing.
///
/// Everything here has to be fast: it runs on the capture queue for every
/// single frame, at ~30 fps. The change signal is a 16x16 grayscale average
/// hash sampled straight out of the BGRA buffer — 256 reads, no allocation, no
/// full-image comparison.
final class FrameStore {

  struct Signal {
    let timestampMs: Int64
    let change: Double
    let brightness: Double
  }

  private let lock = NSLock()
  private var current: CVPixelBuffer?
  private var currentSignature: [Float] = []

  /// Signature of the frame that was last actually analysed, so `change`
  /// measures drift since the last analysis rather than since the last frame.
  private var baselineSignature: [Float] = []

  private static let grid = 16

  // MARK: - Writing (capture queue)

  func store(_ buffer: CVPixelBuffer) -> Signal {
    let signature = Self.signature(of: buffer)
    let brightness = signature.isEmpty
      ? 0
      : Double(signature.reduce(0, +)) / Double(signature.count)

    lock.lock()
    current = buffer
    currentSignature = signature
    let baseline = baselineSignature
    lock.unlock()

    let change = Self.distance(signature, baseline)
    return Signal(
      timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
      change: change,
      brightness: brightness)
  }

  // MARK: - Reading (any queue)

  func latest() -> CVPixelBuffer? {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  /// Marks the current frame as the new baseline. Called right after an
  /// analysis so the next change score is measured from here.
  func markAnalysed() {
    lock.lock()
    baselineSignature = currentSignature
    lock.unlock()
  }

  // MARK: - Maths

  /// Mean luminance of a 16x16 sample grid, normalised to 0...1.
  private static func signature(of buffer: CVPixelBuffer) -> [Float] {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
      return []
    }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    guard width >= grid, height >= grid else { return [] }

    let pointer = base.assumingMemoryBound(to: UInt8.self)
    var out = [Float](repeating: 0, count: grid * grid)

    for gy in 0..<grid {
      let y = (height * gy) / grid + (height / grid) / 2
      let rowStart = y * stride
      for gx in 0..<grid {
        let x = (width * gx) / grid + (width / grid) / 2
        let offset = rowStart + x * 4
        let b = Float(pointer[offset])
        let g = Float(pointer[offset + 1])
        let r = Float(pointer[offset + 2])
        // Rec. 601 luma, cheap and good enough for a change signal.
        out[gy * grid + gx] = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
      }
    }
    return out
  }

  /// Mean absolute difference, 0...1. An empty baseline means "everything is
  /// new", which is the correct answer on the first frame.
  private static func distance(_ a: [Float], _ b: [Float]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 1.0 }
    var sum: Float = 0
    for i in 0..<a.count { sum += abs(a[i] - b[i]) }
    return Double(sum) / Double(a.count)
  }
}
