//
//  SubjectCutoutService.swift
//  Tsureteku
//
//  Lifts the foreground subject(s) from a photo using Vision's
//  VNGenerateForegroundInstanceMaskRequest (iOS 17+). Same quality as the
//  Photos app's "subject lift" feature.
//

import CoreImage
import UIKit
import Vision

enum SubjectCutoutError: Error {
    case invalidImage
    case noSubjectFound
    case maskGenerationFailed
}

enum SubjectCutoutService {
    /// Extracts the foreground subject. The returned UIImage is cropped to the
    /// subject's extent and has an alpha channel (transparent background).
    static func extractForeground(from image: UIImage) async throws -> UIImage {
        let normalized = normalizedOrientation(image)
        guard let cgImage = normalized.cgImage else {
            throw SubjectCutoutError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                let request = VNGenerateForegroundInstanceMaskRequest()
                do {
                    try handler.perform([request])
                    guard let observation = request.results?.first else {
                        continuation.resume(throwing: SubjectCutoutError.noSubjectFound)
                        return
                    }
                    let pixelBuffer = try observation.generateMaskedImage(
                        ofInstances: observation.allInstances,
                        from: handler,
                        croppedToInstancesExtent: true
                    )
                    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                    let context = CIContext()
                    guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else {
                        continuation.resume(throwing: SubjectCutoutError.maskGenerationFailed)
                        return
                    }
                    continuation.resume(returning: UIImage(cgImage: cg))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Vision wants pixel-orientation alignment with the CGImage. Re-draw the
    /// UIImage so its EXIF orientation is baked in as `.up`.
    private static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
