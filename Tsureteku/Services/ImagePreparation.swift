//
//  ImagePreparation.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import UIKit

enum ImagePreparation {
    static func normalizedAndScaled(_ image: UIImage, maxPixelLength: CGFloat = 1_800) -> UIImage {
        let normalizedImage = normalize(image)
        let longestSide = max(normalizedImage.size.width, normalizedImage.size.height)

        guard longestSide > maxPixelLength else {
            return normalizedImage
        }

        let scale = maxPixelLength / longestSide
        let targetSize = CGSize(
            width: normalizedImage.size.width * scale,
            height: normalizedImage.size.height * scale
        )

        return render(normalizedImage, size: targetSize)
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else {
            return image
        }

        return render(image, size: image.size)
    }

    private static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
