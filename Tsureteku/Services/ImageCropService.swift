//
//  ImageCropService.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import CoreGraphics
import UIKit

enum ImageCropService {
    static func crop(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let clampedRect = normalizedRect
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        guard clampedRect.width > 0.01, clampedRect.height > 0.01 else {
            return image
        }

        let pixelRect = CGRect(
            x: clampedRect.minX * CGFloat(cgImage.width),
            y: clampedRect.minY * CGFloat(cgImage.height),
            width: clampedRect.width * CGFloat(cgImage.width),
            height: clampedRect.height * CGFloat(cgImage.height)
        ).integral

        guard let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    static func trimTransparentPixels(
        _ image: UIImage,
        alphaThreshold: UInt8 = 24,
        paddingRatio: CGFloat = 0.04
    ) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = height * bytesPerRow
        var pixels = [UInt8](repeating: 0, count: byteCount)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var foundPixel = false

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[(y * bytesPerRow) + (x * bytesPerPixel) + 3]
                guard alpha > alphaThreshold else {
                    continue
                }

                foundPixel = true
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard foundPixel else {
            return image
        }

        let padding = Int(CGFloat(max(maxX - minX, maxY - minY)) * paddingRatio)
        minX = max(0, minX - padding)
        minY = max(0, minY - padding)
        maxX = min(width - 1, maxX + padding)
        maxY = min(height - 1, maxY + padding)

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )

        guard let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }
}
