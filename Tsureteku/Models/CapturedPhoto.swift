//
//  CapturedPhoto.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import Foundation
import SwiftData

/// 履歴に残すメディアの種類。
enum CapturedMediaType: String, Codable, CaseIterable {
    case photo
    case video
}

@Model
final class CapturedPhoto {
    var id: UUID
    /// 写真本体、または動画のポスター画像（サムネイル）のファイル名。
    var imageFileName: String
    /// 動画のときのみ設定される動画ファイル名。
    var videoFileName: String?
    /// 永続化用の生値。表示・分岐には `mediaType` を使う。
    /// 既存データ（生値なし）は写真として扱えるようデフォルト値を持たせ、軽量マイグレーションで吸収する。
    var mediaTypeRawValue: String = CapturedMediaType.photo.rawValue
    var createdAt: Date

    /// 写真か動画か。未知値・既存データは写真として扱う。
    var mediaType: CapturedMediaType {
        get { CapturedMediaType(rawValue: mediaTypeRawValue) ?? .photo }
        set { mediaTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        imageFileName: String,
        videoFileName: String? = nil,
        mediaType: CapturedMediaType = .photo,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.videoFileName = videoFileName
        self.mediaTypeRawValue = mediaType.rawValue
        self.createdAt = createdAt
    }
}
