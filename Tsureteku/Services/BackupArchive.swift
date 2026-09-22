//
//  BackupArchive.swift
//  Tsureteku
//
//  Created by Claude on 2026/09/22.
//

import Foundation

/// バックアップJSONに入れるファイル1つ分。
nonisolated struct BackupArchiveEntry: Sendable {
    /// バックアップ内でのパス（`BackupFilePath`）。
    var path: String
    var sourceURL: URL
    var byteCount: Int64
}

/// バックアップJSON（`BackupFormat`）の書き出しと展開。SwiftData やアプリの保存領域には触れない。
/// どちらもファイルを少しずつ読み書きし、メモリに全体を載せない。重いので呼び出し側でメインスレッド外から呼ぶ。
nonisolated enum BackupArchive {
    /// 3の倍数にして、チャンクごとの base64 をつなげても途中に `=` が入らないようにする。
    private static let encodeChunkSize = 3 << 18

    /// base64 にしたときのおおよそのバイト数。
    static func encodedByteCount(forFileBytes byteCount: Int64) -> Int64 {
        (byteCount + 2) / 3 * 4
    }

    // MARK: - 書き出し

    /// - Parameter progress: 0〜1 の進捗。
    static func write(
        manifest: BackupManifest,
        entries: [BackupArchiveEntry],
        to outputURL: URL,
        progress: (Double) -> Void
    ) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: outputURL)

        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw BackupError.cannotCreateFile
        }

        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer {
                try? output.close()
            }

            let manifestData = try BackupFormat.makeManifestEncoder().encode(manifest)
            let pathEncoder = JSONEncoder()
            pathEncoder.outputFormatting = [.withoutEscapingSlashes]

            let totalBytes = max(entries.reduce(0) { $0 + $1.byteCount }, 1)
            var writtenBytes: Int64 = 0

            try output.write(contentsOf: Data("{\n\"manifest\": ".utf8))
            try output.write(contentsOf: manifestData)
            try output.write(contentsOf: Data(",\n\"files\": [\n".utf8))

            for (index, entry) in entries.enumerated() {
                try output.write(contentsOf: Data((index == 0 ? "" : ",\n").utf8))
                try output.write(contentsOf: Data("{\"path\": ".utf8))
                try output.write(contentsOf: pathEncoder.encode(entry.path))
                try output.write(contentsOf: Data(", \"data\": \"".utf8))
                try writeBase64(of: entry.sourceURL, to: output) { byteCount in
                    writtenBytes += byteCount
                    progress(min(Double(writtenBytes) / Double(totalBytes), 1))
                }
                try output.write(contentsOf: Data("\"}".utf8))
            }

            try output.write(contentsOf: Data("\n]\n}\n".utf8))
            progress(1)
        } catch {
            try? fileManager.removeItem(at: outputURL)
            throw error
        }
    }

    private static func writeBase64(
        of sourceURL: URL,
        to output: FileHandle,
        didRead: (Int64) -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? input.close()
        }

        // 読み込みが3の倍数で区切れなかった分は次へ持ち越す。
        var carry = Data()

        while true {
            try Task.checkCancellation()

            let isFinished = try autoreleasepool { () -> Bool in
                let chunk = try input.read(upToCount: encodeChunkSize) ?? Data()
                let isEndOfFile = chunk.isEmpty
                var bytes = carry
                bytes.append(chunk)

                let encodableCount = isEndOfFile ? bytes.count : bytes.count - bytes.count % 3
                if encodableCount > 0 {
                    try output.write(contentsOf: bytes.prefix(encodableCount).base64EncodedData())
                }
                carry = Data(bytes.dropFirst(encodableCount))
                didRead(Int64(chunk.count))
                return isEndOfFile
            }

            if isFinished {
                return
            }
        }
    }

    // MARK: - 展開

    /// バックアップJSONを読み、`files` を `stagingDirectory` 配下へ展開して manifest を返す。
    /// 展開先は `BackupFilePath` のパスそのまま（`BackupFilePath.url(for:in:)` で引ける）。
    /// - Parameter progress: 0〜1 の進捗。
    static func extract(
        from backupURL: URL,
        into stagingDirectory: URL,
        progress: @escaping (Double) -> Void
    ) throws -> BackupManifest {
        let totalBytes = max(fileSize(at: backupURL) ?? 0, 1)
        let reader = try BackupJSONReader(url: backupURL) { readBytes in
            progress(min(Double(readBytes) / Double(totalBytes), 1))
        }

        var manifest: BackupManifest?

        do {
            try reader.readObject { key in
                switch key {
                case "manifest":
                    let data = try reader.readRawValue(maxLength: 64 << 20)
                    manifest = try decodeManifest(from: data)
                case "files":
                    try reader.readArray {
                        try extractFile(from: reader, into: stagingDirectory)
                    }
                default:
                    try reader.skipValue()
                }
            }
            try reader.expectEnd()
        } catch is BackupJSONReader.ReadError {
            // 先頭からJSONとして読めなければ、別のファイルを選んだとみなす。
            throw manifest == nil ? BackupError.notBackupFile : BackupError.invalidFormat
        } catch is DecodingError {
            throw BackupError.invalidFormat
        }

        guard let manifest else {
            throw BackupError.notBackupFile
        }

        progress(1)
        return manifest
    }

    private static func decodeManifest(from data: Data) throws -> BackupManifest {
        struct Header: Decodable {
            var format: String?
            var formatVersion: Int?
        }

        let decoder = BackupFormat.makeManifestDecoder()

        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == BackupFormat.identifier,
              let formatVersion = header.formatVersion else {
            throw BackupError.notBackupFile
        }

        guard formatVersion <= BackupFormat.version else {
            throw BackupError.unsupportedVersion
        }

        return try decoder.decode(BackupManifest.self, from: data)
    }

    /// `files` の要素1つを読み、`stagingDirectory` 配下の `path` へ書き出す。
    private static func extractFile(from reader: BackupJSONReader, into stagingDirectory: URL) throws {
        let fileManager = FileManager.default
        var path: String?
        var partialURL: URL?

        defer {
            if let partialURL {
                try? fileManager.removeItem(at: partialURL)
            }
        }

        try reader.readObject { key in
            switch key {
            case "path":
                path = try reader.readString(maxLength: 4096)
            case "data":
                // `path` が後ろに来ても書き出せるよう、いったん仮のファイルへデコードする。
                let url = stagingDirectory.appendingPathComponent("partial-\(UUID().uuidString)")
                if let partialURL {
                    try? fileManager.removeItem(at: partialURL)
                }
                partialURL = url

                guard fileManager.createFile(atPath: url.path, contents: nil) else {
                    throw BackupError.cannotCreateFile
                }

                let output = try FileHandle(forWritingTo: url)
                defer {
                    try? output.close()
                }
                try reader.readBase64String(into: output)
            default:
                try reader.skipValue()
            }
        }

        // 置き場所が不正なファイルは取り込まない（仮ファイルは defer で消える）。
        guard let path,
              let completedURL = partialURL,
              let destinationURL = BackupFilePath.url(for: path, in: stagingDirectory) else {
            return
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: completedURL, to: destinationURL)
        partialURL = nil
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }

        return Int64(size)
    }
}
