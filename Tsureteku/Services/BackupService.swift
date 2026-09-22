//
//  BackupService.swift
//  Tsureteku
//
//  Created by Claude on 2026/09/22.
//

import Foundation
import SwiftData

/// 書き出し対象として集めた、推し・撮影履歴とその実ファイル。
nonisolated struct BackupExportPlan: Sendable {
    var manifest: BackupManifest
    var sources: [BackupFileSource]
}

nonisolated struct BackupFileSource: Sendable {
    /// バックアップ内でのパス。3D撮影フォルダなら、中のファイルはこの下に入る。
    var path: String
    var url: URL
    var isObjectCaptureDirectory: Bool
}

nonisolated struct BackupSizeEstimate: Sendable {
    /// 推しの画像・3Dモデル・写真・動画の合計。
    var mediaBytes: Int64
    /// 3D撮影の元データ（撮影フォルダ）の合計。
    var objectCaptureBytes: Int64

    func backupFileBytes(includingObjectCaptureData: Bool) -> Int64 {
        BackupArchive.encodedByteCount(
            forFileBytes: mediaBytes + (includingObjectCaptureData ? objectCaptureBytes : 0)
        )
    }
}

/// 一時フォルダへ展開済みで、アプリへ取り込む直前のバックアップ。
nonisolated struct BackupRestorePayload: Sendable {
    var manifest: BackupManifest
    var stagingDirectory: URL
}

struct BackupRestoreResult {
    var restoredCharacterCount = 0
    var restoredPhotoCount = 0
    /// すでに同じIDのデータがあって取り込まなかった件数。
    var skippedCount = 0
    /// バックアップに入っていなかったファイルの数。
    var missingFileCount = 0
}

/// 機種変更用に、全データを1つのJSONファイルへ書き出し・復元する。
///
/// - 書き出し: SwiftData の内容と参照している実ファイルを `BackupArchive` で1ファイルにまとめる。
/// - 復元: いったん一時フォルダへ展開してから、まだないデータだけを追加する（今あるデータは消さない）。
///   同じバックアップを2回復元しても重複しない。
nonisolated enum BackupService {
    // MARK: - 書き出し

    @MainActor
    static func makeExportPlan(from modelContext: ModelContext) throws -> BackupExportPlan {
        let characters = try modelContext.fetch(FetchDescriptor<ToyCharacter>(sortBy: [SortDescriptor(\.createdAt)]))
        let photos = try modelContext.fetch(FetchDescriptor<CapturedPhoto>(sortBy: [SortDescriptor(\.createdAt)]))
        var sources: [BackupFileSource] = []

        for character in characters {
            sources.append(BackupFileSource(
                path: BackupFilePath.characterOriginal(character.originalImageFileName),
                url: try CharacterImageStore.url(for: character.originalImageFileName, kind: .original),
                isObjectCaptureDirectory: false
            ))
            sources.append(BackupFileSource(
                path: BackupFilePath.characterCutout(character.cutoutImageFileName),
                url: try CharacterImageStore.url(for: character.cutoutImageFileName, kind: .cutout),
                isObjectCaptureDirectory: false
            ))

            if let modelFileName = character.modelFileName {
                sources.append(BackupFileSource(
                    path: BackupFilePath.characterModel(modelFileName),
                    url: try CharacterImageStore.modelURL(for: modelFileName),
                    isObjectCaptureDirectory: false
                ))
            }

            if let directoryName = character.objectCaptureDirectoryName {
                sources.append(BackupFileSource(
                    path: BackupFilePath.objectCaptureDirectory(directoryName),
                    url: try CharacterImageStore.objectCaptureDirectoryURL(for: directoryName),
                    isObjectCaptureDirectory: true
                ))
            }
        }

        for photo in photos {
            sources.append(BackupFileSource(
                path: BackupFilePath.capturedMedia(photo.imageFileName),
                url: try CapturedPhotoStore.url(for: photo.imageFileName),
                isObjectCaptureDirectory: false
            ))

            if let videoFileName = photo.videoFileName {
                sources.append(BackupFileSource(
                    path: BackupFilePath.capturedMedia(videoFileName),
                    url: try CapturedPhotoStore.url(for: videoFileName),
                    isObjectCaptureDirectory: false
                ))
            }
        }

        let manifest = BackupManifest(
            format: BackupFormat.identifier,
            formatVersion: BackupFormat.version,
            exportedAt: Date(),
            appVersion: appVersion,
            characters: characters.map(BackupCharacterRecord.init),
            capturedPhotos: photos.map(BackupCapturedPhotoRecord.init)
        )

        return BackupExportPlan(manifest: manifest, sources: sources)
    }

    @concurrent
    static func estimateSize(of plan: BackupExportPlan) async -> BackupSizeEstimate {
        let mediaEntries = archiveEntries(for: plan.sources.filter { !$0.isObjectCaptureDirectory })
        let objectCaptureEntries = archiveEntries(for: plan.sources.filter(\.isObjectCaptureDirectory))

        return BackupSizeEstimate(
            mediaBytes: mediaEntries.reduce(0) { $0 + $1.byteCount },
            objectCaptureBytes: objectCaptureEntries.reduce(0) { $0 + $1.byteCount }
        )
    }

    /// バックアップJSONを一時フォルダに書き出してURLを返す。前回書き出したファイルはここで片付ける。
    @concurrent
    static func export(
        _ plan: BackupExportPlan,
        includingObjectCaptureData: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var manifest = plan.manifest
        var sources = plan.sources

        if !includingObjectCaptureData {
            sources.removeAll(where: \.isObjectCaptureDirectory)
            for index in manifest.characters.indices {
                manifest.characters[index].objectCaptureDirectoryName = nil
            }
        }

        let entries = archiveEntries(for: sources)
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("TsuretekuBackup", isDirectory: true)
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileBytes = entries.reduce(0) { $0 + $1.byteCount }
        try ensureAvailableCapacity(BackupArchive.encodedByteCount(forFileBytes: fileBytes) + (1 << 20), at: directory)

        let outputURL = directory.appendingPathComponent(exportFileName(for: manifest.exportedAt))
        var throttle = ProgressThrottle(report: progress)
        try BackupArchive.write(manifest: manifest, entries: entries, to: outputURL) { value in
            throttle.update(value)
        }

        return outputURL
    }

    // MARK: - 復元

    /// 選んだバックアップJSONを読み、一時フォルダへ展開する。
    /// ここではアプリのデータには触れないので、失敗・キャンセルしても今のデータはそのまま。
    @concurrent
    static func prepareRestore(
        from backupURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> BackupRestorePayload {
        let didStartAccess = backupURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                backupURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let stagingRootURL = try importStagingRootURL()
        // 前回途中で止まった展開が残っていれば片付ける。
        try? fileManager.removeItem(at: stagingRootURL)
        let stagingDirectory = stagingRootURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let manifest = try coordinatedRead(of: backupURL) { readableURL in
                let backupBytes = (try? readableURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
                try ensureAvailableCapacity(backupBytes / 4 * 3, at: stagingDirectory)

                var throttle = ProgressThrottle(report: progress)
                return try BackupArchive.extract(from: readableURL, into: stagingDirectory) { value in
                    throttle.update(value)
                }
            }

            return BackupRestorePayload(manifest: manifest, stagingDirectory: stagingDirectory)
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    /// 展開済みのバックアップのうち、まだないデータだけをアプリへ追加する。一時フォルダは最後に消す。
    @MainActor
    static func restore(_ payload: BackupRestorePayload, into modelContext: ModelContext) throws -> BackupRestoreResult {
        defer {
            discard(payload)
        }

        var knownCharacterIDs = Set(try modelContext.fetch(FetchDescriptor<ToyCharacter>()).map(\.id))
        var knownPhotoIDs = Set(try modelContext.fetch(FetchDescriptor<CapturedPhoto>()).map(\.id))
        var files = StagedFileRestorer(stagingDirectory: payload.stagingDirectory)
        var insertedCharacters: [ToyCharacter] = []
        var insertedPhotos: [CapturedPhoto] = []
        var result = BackupRestoreResult()

        for record in payload.manifest.characters {
            guard knownCharacterIDs.insert(record.id).inserted else {
                result.skippedCount += 1
                continue
            }

            let character = files.makeCharacter(from: record)
            modelContext.insert(character)
            insertedCharacters.append(character)
        }

        for record in payload.manifest.capturedPhotos {
            guard knownPhotoIDs.insert(record.id).inserted else {
                result.skippedCount += 1
                continue
            }

            let photo = files.makePhoto(from: record)
            modelContext.insert(photo)
            insertedPhotos.append(photo)
        }

        do {
            try modelContext.save()
        } catch {
            // 保存できなかったら、追加しかけたデータと取り込んだファイルを戻す。
            modelContext.rollback()
            insertedCharacters.forEach(deleteFiles(of:))
            insertedPhotos.forEach(deleteFiles(of:))
            throw error
        }

        result.restoredCharacterCount = insertedCharacters.count
        result.restoredPhotoCount = insertedPhotos.count
        result.missingFileCount = files.missingFileCount
        return result
    }

    /// 展開した一時フォルダを消す。復元をやめたときにも呼ぶ。
    static func discard(_ payload: BackupRestorePayload) {
        try? FileManager.default.removeItem(at: payload.stagingDirectory)
    }

    // MARK: - 内部

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    /// 書き出すファイルを列挙する。見つからないファイルは飛ばし、撮影フォルダは中身を展開する。
    private static func archiveEntries(for sources: [BackupFileSource]) -> [BackupArchiveEntry] {
        let fileManager = FileManager.default
        var entries: [BackupArchiveEntry] = []

        for source in sources {
            guard source.isObjectCaptureDirectory else {
                guard let attributes = try? fileManager.attributesOfItem(atPath: source.url.path),
                      attributes[.type] as? FileAttributeType == .typeRegular else {
                    continue
                }

                let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                entries.append(BackupArchiveEntry(path: source.path, sourceURL: source.url, byteCount: byteCount))
                continue
            }

            guard let enumerator = fileManager.enumerator(atPath: source.url.path) else {
                continue
            }

            while let relativePath = enumerator.nextObject() as? String {
                guard enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular,
                      !relativePath.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
                    continue
                }

                let byteCount = (enumerator.fileAttributes?[.size] as? NSNumber)?.int64Value ?? 0
                entries.append(BackupArchiveEntry(
                    path: source.path + "/" + relativePath,
                    sourceURL: source.url.appendingPathComponent(relativePath),
                    byteCount: byteCount
                ))
            }
        }

        return entries
    }

    private static func exportFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "Tsureteku-Backup-\(formatter.string(from: date)).json"
    }

    private static func ensureAvailableCapacity(_ requiredBytes: Int64, at url: URL) throws {
        guard let availableBytes = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage,
              availableBytes < requiredBytes else {
            return
        }

        throw BackupError.insufficientStorage(requiredBytes: requiredBytes)
    }

    /// 展開先。取り込み時に移動だけで済むよう、保存領域と同じ Application Support に置く。
    private static func importStagingRootURL() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("Tsureteku", isDirectory: true)
        .appendingPathComponent("ImportStaging", isDirectory: true)
    }

    /// iCloud Drive などのファイルでも読めるよう、ファイルコーディネーター経由で読む。
    private static func coordinatedRead<T>(of url: URL, _ body: (URL) throws -> T) throws -> T {
        var result: Result<T, Error>?
        var coordinationError: NSError?

        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readableURL in
            result = Result { try body(readableURL) }
        }

        if let result {
            return try result.get()
        }

        throw coordinationError ?? BackupError.notBackupFile
    }

    @MainActor
    private static func deleteFiles(of character: ToyCharacter) {
        CharacterImageStore.deleteIfExists(fileName: character.originalImageFileName, kind: .original)
        CharacterImageStore.deleteIfExists(fileName: character.cutoutImageFileName, kind: .cutout)
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: character.objectCaptureDirectoryName)
    }

    @MainActor
    private static func deleteFiles(of photo: CapturedPhoto) {
        CapturedPhotoStore.deleteIfExists(fileName: photo.imageFileName)
        CapturedPhotoStore.deleteIfExists(fileName: photo.videoFileName)
    }
}

/// 展開済みのファイルを保存領域へ移しながら、レコードからモデルを作る。
/// ファイル名は取り込み時に振り直す（既存ファイルと衝突させない）。
@MainActor
private struct StagedFileRestorer {
    let stagingDirectory: URL
    private(set) var missingFileCount = 0

    init(stagingDirectory: URL) {
        self.stagingDirectory = stagingDirectory
    }

    mutating func makeCharacter(from record: BackupCharacterRecord) -> ToyCharacter {
        ToyCharacter(
            id: record.id,
            name: record.name,
            originalImageFileName: restoreRequiredFile(
                named: record.originalImageFileName,
                path: BackupFilePath.characterOriginal
            ) { try CharacterImageStore.importImage(movingFrom: $0, kind: .original) },
            cutoutImageFileName: restoreRequiredFile(
                named: record.cutoutImageFileName,
                path: BackupFilePath.characterCutout
            ) { try CharacterImageStore.importImage(movingFrom: $0, kind: .cutout) },
            modelFileName: restoreOptionalFile(
                named: record.modelFileName,
                path: BackupFilePath.characterModel
            ) { try CharacterImageStore.importModel(movingFrom: $0) },
            objectCaptureDirectoryName: restoreOptionalFile(
                named: record.objectCaptureDirectoryName,
                path: BackupFilePath.objectCaptureDirectory,
                isDirectory: true
            ) { try CharacterImageStore.importObjectCaptureDirectory(movingFrom: $0) },
            defaultSizeMeters: record.defaultSizeMeters,
            arBrightnessMultiplier: record.arBrightnessMultiplier,
            modelYawDegrees: record.modelYawDegrees,
            modelVerticalOffsetMeters: record.modelVerticalOffsetMeters,
            isARMotionEnabled: record.isARMotionEnabled,
            arPlacementMode: CharacterARPlacementMode(rawValue: record.arPlacementMode) ?? .model3D,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            lastUsedAt: record.lastUsedAt
        )
    }

    mutating func makePhoto(from record: BackupCapturedPhotoRecord) -> CapturedPhoto {
        let photo = CapturedPhoto(
            id: record.id,
            imageFileName: restoreRequiredFile(
                named: record.imageFileName,
                path: BackupFilePath.capturedMedia
            ) { try CapturedPhotoStore.importFile(movingFrom: $0) },
            videoFileName: restoreOptionalFile(
                named: record.videoFileName,
                path: BackupFilePath.capturedMedia
            ) { try CapturedPhotoStore.importFile(movingFrom: $0) },
            mediaType: CapturedMediaType(rawValue: record.mediaType) ?? .photo,
            createdAt: record.createdAt
        )
        photo.sceneTagRawValues = record.sceneTags
        photo.sceneClassifierVersion = record.sceneClassifierVersion
        photo.isSceneTagsEditedManually = record.isSceneTagsEditedManually
        return photo
    }

    /// 画像など、モデル上 nil にできないファイル。見つからなければ元の名前のまま残し、表示側の代替表示に任せる。
    private mutating func restoreRequiredFile(
        named fileName: String,
        path: (String) -> String,
        importFile: (URL) throws -> String
    ) -> String {
        if let restoredFileName = restoreOptionalFile(named: fileName, path: path, importFile: importFile) {
            return restoredFileName
        }

        // 外から持ち込まれた名前なので、後で削除するときに保存領域の外を指さないようにしておく。
        return BackupFilePath.isSafeComponent(fileName) ? fileName : "missing-\(UUID().uuidString)"
    }

    /// 3Dモデルや動画など、なければ nil にできるファイル。
    private mutating func restoreOptionalFile(
        named fileName: String?,
        path: (String) -> String,
        isDirectory: Bool = false,
        importFile: (URL) throws -> String
    ) -> String? {
        guard let fileName else {
            return nil
        }

        var isExistingDirectory: ObjCBool = false
        guard let stagedURL = BackupFilePath.url(for: path(fileName), in: stagingDirectory),
              FileManager.default.fileExists(atPath: stagedURL.path, isDirectory: &isExistingDirectory),
              isExistingDirectory.boolValue == isDirectory,
              let restoredFileName = try? importFile(stagedURL) else {
            missingFileCount += 1
            return nil
        }

        return restoredFileName
    }
}

@MainActor
private extension BackupCharacterRecord {
    init(_ character: ToyCharacter) {
        self.init(
            id: character.id,
            name: character.name,
            originalImageFileName: character.originalImageFileName,
            cutoutImageFileName: character.cutoutImageFileName,
            modelFileName: character.modelFileName,
            objectCaptureDirectoryName: character.objectCaptureDirectoryName,
            defaultSizeMeters: character.defaultSizeMeters,
            arBrightnessMultiplier: character.arBrightnessMultiplier,
            modelYawDegrees: character.modelYawDegrees,
            modelVerticalOffsetMeters: character.modelVerticalOffsetMeters,
            isARMotionEnabled: character.isARMotionEnabled,
            arPlacementMode: character.arPlacementModeRawValue,
            createdAt: character.createdAt,
            updatedAt: character.updatedAt,
            lastUsedAt: character.lastUsedAt
        )
    }
}

@MainActor
private extension BackupCapturedPhotoRecord {
    init(_ photo: CapturedPhoto) {
        self.init(
            id: photo.id,
            imageFileName: photo.imageFileName,
            videoFileName: photo.videoFileName,
            mediaType: photo.mediaTypeRawValue,
            createdAt: photo.createdAt,
            sceneTags: photo.sceneTagRawValues,
            sceneClassifierVersion: photo.sceneClassifierVersion,
            isSceneTagsEditedManually: photo.isSceneTagsEditedManually
        )
    }
}

/// 進捗の通知を間引き、メインスレッドへの更新を増やしすぎない。
private nonisolated struct ProgressThrottle {
    let report: @Sendable (Double) -> Void
    private var lastReportedValue = -1.0

    init(report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    mutating func update(_ value: Double) {
        guard value >= 1 || value - lastReportedValue >= 0.005 else {
            return
        }

        lastReportedValue = value
        report(value)
    }
}
