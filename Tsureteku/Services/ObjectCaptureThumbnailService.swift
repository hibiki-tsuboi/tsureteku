//
//  ObjectCaptureThumbnailService.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/22.
//

import UIKit

/// Object Captureの撮影フォルダにある2D写真から、推しのサムネ用画像を作る。
/// 2D登録（写真からの登録）と同じ前処理＋自動切り抜きを使い、見た目をそろえる。
enum ObjectCaptureThumbnailService {
    /// 撮影フォルダから代表写真を1枚選び、元画像と切り抜き画像を作って返す。
    /// 切り抜きに失敗したら、前処理済みの写真をそのまま切り抜き画像として使う（2D登録時の挙動に合わせる）。
    static func makeThumbnailImages(fromCaptureDirectory directoryURL: URL) -> (source: UIImage, cutout: UIImage)? {
        guard let photoURL = representativePhotoURL(in: directoryURL),
              let rawImage = UIImage(contentsOfFile: photoURL.path) else {
            return nil
        }

        let source = ImagePreparation.normalizedAndScaled(rawImage)
        let cutout = (try? SubjectCutoutService.makeCutout(from: source)) ?? source
        return (source, cutout)
    }

    /// 撮影フォルダ直下の画像ファイルのうち、名前順で最初の1枚を代表写真として返す。
    private static func representativePhotoURL(in directoryURL: URL) -> URL? {
        let supportedExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png"]

        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return urls
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }
}
