//
//  BackupFormat.swift
//  Tsureteku
//
//  Created by Claude on 2026/09/22.
//

import Foundation

/// 機種変更用バックアップJSONの形式。
///
/// ```
/// {
/// "manifest": { "format": "tsureteku-backup", "formatVersion": 1, "characters": [...], "capturedPhotos": [...], ... },
/// "files": [
/// {"path": "characters/originals/XXXX.png", "data": "<base64>"},
/// ...
/// ]
/// }
/// ```
///
/// `manifest` に SwiftData のレコードを、`files` に画像・動画・3Dモデルなどの実ファイルを base64 で持つ。
/// レコードはファイル名で `files` の `path` を参照する（パスの組み立ては `BackupFilePath`）。
nonisolated enum BackupFormat {
    static let identifier = "tsureteku-backup"
    /// 形式を変えたら上げる。これより新しいバックアップは読み込まない。
    static let version = 1

    static func makeManifestEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    static func makeManifestDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)

            if let date = (try? Date(string, strategy: dateStyle)) ?? (try? Date(string, strategy: .iso8601)) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "日付を読み取れません: \(string)")
        }
        return decoder
    }

    /// 撮影順の並びが入れ替わらないよう、ミリ秒まで残す。
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}

nonisolated struct BackupManifest: Codable, Sendable {
    var format: String
    var formatVersion: Int
    var exportedAt: Date
    var appVersion: String
    var characters: [BackupCharacterRecord]
    var capturedPhotos: [BackupCapturedPhotoRecord]
}

/// `ToyCharacter` の保存内容。
nonisolated struct BackupCharacterRecord: Codable, Sendable {
    var id: UUID
    var name: String
    var originalImageFileName: String
    var cutoutImageFileName: String
    var modelFileName: String?
    var objectCaptureDirectoryName: String?
    var defaultSizeMeters: Double
    var arBrightnessMultiplier: Double
    var modelYawDegrees: Double
    var modelVerticalOffsetMeters: Double
    var isARMotionEnabled: Bool
    var arPlacementMode: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
}

/// `CapturedPhoto` の保存内容。
nonisolated struct BackupCapturedPhotoRecord: Codable, Sendable {
    var id: UUID
    var imageFileName: String
    var videoFileName: String?
    var mediaType: String
    var createdAt: Date
    var sceneTags: [String]
    var sceneClassifierVersion: Int
    var isSceneTagsEditedManually: Bool
}

/// バックアップ内でのファイルの置き場所。アプリ内の保存先ディレクトリ名とは切り離しておく。
nonisolated enum BackupFilePath {
    private static let rootDirectories: Set<String> = ["characters", "capturedPhotos"]

    static func characterOriginal(_ fileName: String) -> String {
        "characters/originals/\(fileName)"
    }

    static func characterCutout(_ fileName: String) -> String {
        "characters/cutouts/\(fileName)"
    }

    static func characterModel(_ fileName: String) -> String {
        "characters/models/\(fileName)"
    }

    /// 3D撮影フォルダ。中のファイルは `<このパス>/<フォルダ内の相対パス>` で入る。
    static func objectCaptureDirectory(_ directoryName: String) -> String {
        "characters/objectCapture/\(directoryName)"
    }

    static func capturedMedia(_ fileName: String) -> String {
        "capturedPhotos/\(fileName)"
    }

    /// バックアップ内のパスを `directory` 配下のURLへ変換する。
    /// 外から持ち込まれたファイルなので、`..` などで `directory` の外を指すパスは受け付けない。
    static func url(for path: String, in directory: URL) -> URL? {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        guard components.count >= 2,
              rootDirectories.contains(components[0]),
              components.allSatisfy(isSafeComponent) else {
            return nil
        }

        return components.reduce(directory) { url, component in
            url.appendingPathComponent(component)
        }
    }

    /// 1階層分のファイル名・フォルダ名として安全か。
    static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && component.utf8.count <= 255
            && !component.contains(where: { $0 == "/" || $0 == "\\" || $0 == "\0" })
    }
}

nonisolated enum BackupError: LocalizedError {
    case notBackupFile
    case unsupportedVersion
    case invalidFormat
    case insufficientStorage(requiredBytes: Int64)
    case cannotCreateFile

    var errorDescription: String? {
        switch self {
        case .notBackupFile:
            "つれてくのバックアップファイルではありません。"
        case .unsupportedVersion:
            "新しいバージョンのつれてくで作られたバックアップです。アプリをアップデートしてから復元してください。"
        case .invalidFormat:
            "バックアップファイルが壊れているか、途中までしか保存されていません。"
        case .insufficientStorage(let requiredBytes):
            "空き容量が足りません。約\(requiredBytes.formatted(.byteCount(style: .file)))の空きが必要です。"
        case .cannotCreateFile:
            "バックアップファイルを作成できませんでした。"
        }
    }
}
