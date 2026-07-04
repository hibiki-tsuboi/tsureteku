//
//  SceneClassificationService.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/07/04.
//

import ImageIO
import UIKit
import Vision

/// 撮影した写真（動画はポスター画像）をオンデバイスのシーン分類にかけ、
/// `SceneTag` へ集約して返すサービス。通信は発生しない。
enum SceneClassificationService {
    /// 分類ロジックの世代。閾値やキーワード表を変えたらここを上げると、
    /// 履歴画面のバックフィルが既存メディアを再分類する。
    static let classifierVersion = 4

    /// 画像を解析してシーンタグを返す。該当なし・解析失敗時は空配列。
    /// Vision の推論は重いのでバックグラウンドで実行する。
    static func tags(in image: UIImage) async -> [SceneTag] {
        guard let cgImage = image.cgImage else {
            return []
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .utility) {
            classify(cgImage: cgImage, orientation: orientation)
        }.value
    }

    private nonisolated static func classify(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> [SceneTag] {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: orientation,
            options: [:]
        )

        guard (try? handler.perform([request])) != nil,
              let results = request.results else {
            return []
        }

        let observations = results.sorted { $0.confidence > $1.confidence }

        #if DEBUG
        // タグ誤判定の調査用に、モデルの生ラベル上位を出力する。
        let topLabels = observations.prefix(10)
            .map { String(format: "%@ %.2f", $0.identifier, $0.confidence) }
            .joined(separator: ", ")
        print("[SceneClassification] top: \(topLabels)")
        #endif

        // 第1段階: Apple 推奨の precision/recall フィルタで「高精度で言い切れるラベル」だけを残す。
        let confidentIdentifiers = observations
            .filter { (try? $0.hasMinimumRecall(0.01, forPrecision: 0.9)) == true }
            .map { $0.identifier.lowercased() }

        let confidentTags = tags(matching: confidentIdentifiers)
        if !confidentTags.isEmpty {
            return confidentTags
        }

        // 第2段階: 1つも付かなかったときだけ基準を緩め、最有力の1タグだけ採用する。
        // 「タグなし」を減らしつつ、確度の低いタグが複数混ざるのは防ぐ。
        let relaxedIdentifiers = observations
            .filter { (try? $0.hasMinimumRecall(0.01, forPrecision: 0.7)) == true }
            .map { $0.identifier.lowercased() }

        if let fallbackTag = firstTag(matching: relaxedIdentifiers) {
            return [fallbackTag]
        }

        return []
    }

    /// Vision のラベル群を `SceneTag` へ集約する。順序は `SceneTag.allCases` に従う。
    nonisolated static func tags(matching identifiers: [String]) -> [SceneTag] {
        let allWords = identifiers.reduce(into: Set<String>()) { result, identifier in
            result.formUnion(words(from: identifier))
        }

        return SceneTag.allCases.filter { tag in
            !keywords(for: tag).isDisjoint(with: allWords)
        }
    }

    /// 確度順に並んだラベル群から、最初にタグへ対応づくものを1つだけ返す。
    nonisolated static func firstTag(matching identifiers: [String]) -> SceneTag? {
        for identifier in identifiers {
            let identifierWords = words(from: identifier)
            if let tag = SceneTag.allCases.first(where: { !keywords(for: $0).isDisjoint(with: identifierWords) }) {
                return tag
            }
        }

        return nil
    }

    /// 複合ラベル（例: "sunset_sunrise"）にも対応できるよう、アンダースコアで
    /// 分割した語も含めて完全一致で照合する。部分文字列一致は誤爆しやすいので使わない。
    private nonisolated static func words(from identifier: String) -> Set<String> {
        var words: Set<String> = [identifier]
        words.formUnion(identifier.split(separator: "_").map(String.init))
        return words
    }

    private nonisolated static func keywords(for tag: SceneTag) -> Set<String> {
        switch tag {
        case .outdoor:
            ["outdoor", "outdoors", "sky", "cloud", "clouds", "sunset", "sunrise",
             "landscape", "field", "playground"]
        case .indoor:
            ["indoor", "indoors", "room", "furniture", "restaurant", "cafe",
             "museum", "shop", "store", "kitchen", "bedroom"]
        case .nature:
            // "animal" や "bird" はぬいぐるみが動物と判定されたときに誤爆するので入れない。
            ["nature", "plant", "plants", "tree", "trees", "flower", "flowers",
             "forest", "mountain", "mountains", "grass", "garden", "park", "leaf",
             "leaves", "snow"]
        case .water:
            ["water", "beach", "sea", "ocean", "lake", "river", "waterfall",
             "pool", "coast", "shore", "aquarium", "waterfront"]
        case .food:
            // "candy" "snack" "drink" などの間口が広い語は、カラフルなぬいぐるみや
            // 机上のマグカップ程度で誤爆するので、明確に食事とわかる語だけにする。
            ["food", "meal", "dessert", "cake", "fruit", "vegetable", "bread",
             "noodle", "noodles", "rice", "sushi", "pizza"]
        case .night:
            ["night", "nighttime", "fireworks", "moon"]
        case .city:
            ["city", "cityscape", "building", "buildings", "skyscraper", "street",
             "bridge", "tower", "downtown", "station", "train", "road"]
        }
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
