import CoreImage
import CoreVideo
import Foundation
import QuartzCore
import Vision

/// Local computer vision, using only what macOS ships with.
///
/// Two Vision requests do the work:
///
///  * `VNGenerateObjectnessBasedSaliencyImageRequest` proposes the regions of
///    the frame that contain distinct things. This is what gives GlemtDet
///    bounding boxes.
///  * `VNClassifyImageRequest` names what is in a region, and separately what
///    the whole scene looks like. Its taxonomy is roughly 1300 categories and
///    includes the everyday objects a COCO detector misses entirely —
///    eyeglasses, keys, footwear, earphones.
///
/// Nothing is downloaded and no image leaves the process.
final class VisionAnalyzer {

  struct Config {
    var maxRegions = 4
    var labelsPerRegion = 6
    var frameLabels = 10

    /// Regions smaller than this share of the frame are noise.
    var minRegionArea: CGFloat = 0.004

    /// Regions larger than this are "the whole room", not an object.
    var maxRegionArea: CGFloat = 0.92

    /// Context padding added around a salient region before classifying it.
    var regionPadding: CGFloat = 0.06

    /// Vision emits a long tail of near-zero scores; below this they are noise.
    var minConfidence: Float = 0.03
  }

  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
  private let queue = DispatchQueue(label: "dk.glemtdet.vision", qos: .userInitiated)
  var config = Config()

  /// Every label this backend can possibly emit. Used by the diagnostics
  /// screen to verify the Danish taxonomy against reality instead of guesses.
  func vocabulary() -> [String] {
    do {
      let known = try VNClassifyImageRequest.knownClassifications(
        forRevision: VNClassifyImageRequestRevision1)
      return known.map { $0.identifier }.sorted()
    } catch {
      return []
    }
  }

  /// Runs the full pipeline on one frame. Called off the main thread.
  func analyze(buffer: CVPixelBuffer, completion: @escaping ([String: Any]?) -> Void) {
    queue.async { [weak self] in
      guard let self else {
        completion(nil)
        return
      }
      let started = CACurrentMediaTime()
      let image = CIImage(cvPixelBuffer: buffer)
      let extent = image.extent
      guard extent.width > 0, extent.height > 0 else {
        completion(nil)
        return
      }

      let frameLabels = self.classify(image: image, limit: self.config.frameLabels)
      let regions = self.salientRegions(image: image)

      var regionPayload: [[String: Any]] = []
      for region in regions {
        guard let crop = self.crop(image: image, to: region.box) else { continue }
        let labels = self.classify(image: crop, limit: self.config.labelsPerRegion)
        if labels.isEmpty { continue }
        regionPayload.append([
          // Converted to top-left origin here so Dart never has to think about
          // Vision's bottom-left coordinate space.
          "l": Double(region.box.origin.x),
          "t": Double(1.0 - region.box.origin.y - region.box.height),
          "w": Double(region.box.width),
          "h": Double(region.box.height),
          "objectness": Double(region.confidence),
          "labels": labels,
        ])
      }

      let elapsed = Int((CACurrentMediaTime() - started) * 1000)
      completion([
        "ts": Int64(Date().timeIntervalSince1970 * 1000),
        "ms": elapsed,
        "frameLabels": frameLabels,
        "regions": regionPayload,
      ])
    }
  }

  // MARK: - Stages

  private struct Region {
    let box: CGRect  // normalised, Vision orientation (bottom-left origin)
    let confidence: Float
  }

  private func salientRegions(image: CIImage) -> [Region] {
    let request = VNGenerateObjectnessBasedSaliencyImageRequest()
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    guard let observation = request.results?.first as? VNSaliencyImageObservation,
      let objects = observation.salientObjects
    else {
      return []
    }

    let usable =
      objects
      .map { Region(box: $0.boundingBox, confidence: $0.confidence) }
      .filter {
        let area = $0.box.width * $0.box.height
        return area >= config.minRegionArea && area <= config.maxRegionArea
      }
      .sorted { $0.confidence > $1.confidence }

    return Array(usable.prefix(config.maxRegions))
  }

  private func classify(image: CIImage, limit: Int) -> [[String: Any]] {
    let request = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    guard let results = request.results else { return [] }

    return
      results
      .filter { $0.confidence >= config.minConfidence }
      .sorted { $0.confidence > $1.confidence }
      .prefix(limit)
      .map { ["id": $0.identifier, "c": Double($0.confidence)] }
  }

  /// Crops to a normalised Vision rect, with padding, and re-origins the
  /// result so the request handler sees a standalone image.
  private func crop(image: CIImage, to box: CGRect) -> CIImage? {
    let extent = image.extent
    let padded = box.insetBy(
      dx: -box.width * config.regionPadding,
      dy: -box.height * config.regionPadding)

    let rect = CGRect(
      x: extent.origin.x + padded.origin.x * extent.width,
      y: extent.origin.y + padded.origin.y * extent.height,
      width: padded.width * extent.width,
      height: padded.height * extent.height
    ).intersection(extent)

    guard rect.width >= 16, rect.height >= 16 else { return nil }
    return image.cropped(to: rect)
      .transformed(by: CGAffineTransform(translationX: -rect.origin.x, y: -rect.origin.y))
  }
}
