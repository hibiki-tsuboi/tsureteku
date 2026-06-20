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
        paddingRatio: CGFloat = 0.04,
        maxScanDimension: Int = 256
    ) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let fullWidth = cgImage.width
        let fullHeight = cgImage.height
        guard fullWidth > 0, fullHeight > 0 else {
            return nil
        }

        // アルファ境界の検出は縮小版で行い、走査ピクセル数とメモリ確保を大幅に削減する。
        // （元解像度だとスライダー操作のたびに最大数百万ピクセルの走査と十数MBの確保が走る）
        // 検出した範囲は正規化座標へ直し、トリミング自体は元解像度のcgImageに対して行って画質を保つ。
        let scanScale = min(1, CGFloat(maxScanDimension) / CGFloat(max(fullWidth, fullHeight)))
        let scanWidth = max(1, Int((CGFloat(fullWidth) * scanScale).rounded()))
        let scanHeight = max(1, Int((CGFloat(fullHeight) * scanScale).rounded()))

        let bytesPerPixel = 4
        let bytesPerRow = scanWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: scanHeight * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: scanWidth,
                height: scanHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: scanWidth, height: scanHeight))

        var minX = scanWidth
        var minY = scanHeight
        var maxX = -1
        var maxY = -1

        pixels.withUnsafeBufferPointer { buffer in
            for y in 0..<scanHeight {
                let rowStart = y * bytesPerRow
                for x in 0..<scanWidth {
                    let alpha = buffer[rowStart + (x * bytesPerPixel) + 3]
                    if alpha > alphaThreshold {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return image
        }

        // 縮小版の境界を正規化座標へ変換し、余白を加える。座標の対応関係（バッファ座標÷走査サイズ＝
        // 画像座標÷元サイズ）は元実装と同一なので、向き等の挙動は変えずに高速化のみを行う。
        let padding = CGFloat(max(maxX - minX, maxY - minY) + 1) * paddingRatio
        let normalizedRect = CGRect(
            x: (CGFloat(minX) - padding) / CGFloat(scanWidth),
            y: (CGFloat(minY) - padding) / CGFloat(scanHeight),
            width: (CGFloat(maxX - minX + 1) + padding * 2) / CGFloat(scanWidth),
            height: (CGFloat(maxY - minY + 1) + padding * 2) / CGFloat(scanHeight)
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(fullWidth),
            y: normalizedRect.minY * CGFloat(fullHeight),
            width: normalizedRect.width * CGFloat(fullWidth),
            height: normalizedRect.height * CGFloat(fullHeight)
        ).integral

        guard let croppedImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }
}
