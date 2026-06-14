//
//  SubjectCutoutService.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import CoreImage
import ImageIO
import UIKit
import Vision

enum SubjectCutoutService {
    enum CutoutError: LocalizedError {
        case missingCGImage
        case subjectNotFound
        case renderingFailed

        var errorDescription: String? {
            switch self {
            case .missingCGImage:
                "画像を解析できませんでした。"
            case .subjectNotFound:
                "写真から前景を見つけられませんでした。"
            case .renderingFailed:
                "切り抜き画像を作成できませんでした。"
            }
        }
    }

    static func makeCutout(from image: UIImage) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw CutoutError.missingCGImage
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )

        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw CutoutError.subjectNotFound
        }

        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.workingColorSpace: NSNull()])

        guard let renderedImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw CutoutError.renderingFailed
        }

        return UIImage(cgImage: renderedImage, scale: 1, orientation: .up)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
