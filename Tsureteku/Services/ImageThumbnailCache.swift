//
//  ImageThumbnailCache.swift
//  Tsureteku
//
//  一覧・サムネ表示用に、画像を縮小デコードしてメモリキャッシュする。
//  フルサイズ画像を毎描画で読み直すコスト（スクロールのカクつき・メモリ圧迫）を避ける。
//

import ImageIO
import UIKit

final class ImageThumbnailCache {
    static let shared = ImageThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {}

    /// `url` の画像を、長辺が最大 `maxPixelSize` ピクセルになるよう縮小して返す。
    /// 同じ URL・サイズの組み合わせは2回目以降キャッシュから返す。
    /// ファイル名はUUIDで上書きされない前提のため、URLをキーにしても古い内容を返すことはない。
    func thumbnail(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let key = "\(url.path)#\(Int(maxPixelSize))" as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = Self.downsample(at: url, maxPixelSize: maxPixelSize) else {
            return nil
        }

        cache.setObject(image, forKey: key)
        return image
    }

    private static func downsample(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
