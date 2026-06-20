//
//  CapturedPhotoStore.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import AVFoundation
import Foundation
import UIKit

enum CapturedPhotoStore {
    enum StoreError: LocalizedError {
        case missingImageData

        var errorDescription: String? {
            switch self {
            case .missingImageData:
                "写真データを書き出せませんでした。"
            }
        }
    }

    static func save(_ image: UIImage) throws -> String {
        let fileName = UUID().uuidString + ".jpg"
        let url = try url(for: fileName)

        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw StoreError.missingImageData
        }

        try data.write(to: url, options: [.atomic])
        return fileName
    }

    /// 録画した動画ファイルを恒久ディレクトリへコピーし、保存後のファイル名を返す。
    static func saveVideo(from sourceURL: URL) throws -> String {
        let fileName = UUID().uuidString + ".mp4"
        let destinationURL = try url(for: fileName)

        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    /// 保存済み動画のファイルURL。存在しない場合は nil。
    static func videoURL(named fileName: String) -> URL? {
        guard let url = try? url(for: fileName),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return url
    }

    /// 動画の先頭フレームからポスター画像（サムネイル）を生成する。失敗時は nil。
    static func makePosterImage(from videoURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let result = try await generator.image(at: .zero)
            return UIImage(cgImage: result.image)
        } catch {
            return nil
        }
    }

    /// ポスター生成に失敗した場合に使う、無地のフォールバック画像。
    static func placeholderPosterImage() -> UIImage {
        let size = CGSize(width: 720, height: 960)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor(white: 0.15, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    static func image(named fileName: String) -> UIImage? {
        guard let url = try? url(for: fileName) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    /// 一覧・サムネ表示用に縮小・キャッシュした画像を返す。
    static func thumbnail(named fileName: String, maxPixelSize: CGFloat) -> UIImage? {
        guard let url = try? url(for: fileName) else {
            return nil
        }

        return ImageThumbnailCache.shared.thumbnail(at: url, maxPixelSize: maxPixelSize)
    }

    static func deleteIfExists(fileName: String?) {
        guard let fileName,
              let url = try? url(for: fileName) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func url(for fileName: String) throws -> URL {
        try directoryURL().appendingPathComponent(fileName)
    }

    private static func directoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = baseURL
            .appendingPathComponent("Tsureteku", isDirectory: true)
            .appendingPathComponent("CapturedPhotos", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL
    }
}
