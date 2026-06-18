//
//  CharacterImageStore.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import Foundation
import UIKit

enum CharacterImageStore {
    enum ImageKind: String {
        case original = "Originals"
        case cutout = "Cutouts"
    }

    enum FileKind: String {
        case model = "Models"
    }

    enum DirectoryKind: String {
        case objectCapture = "ObjectCapture"
    }

    enum StoreError: LocalizedError {
        case missingImageData
        case unsupportedModelFile
        case missingSecurityScopedAccess

        var errorDescription: String? {
            switch self {
            case .missingImageData:
                "画像データを書き出せませんでした。"
            case .unsupportedModelFile:
                "USDZモデルを選択してください。"
            case .missingSecurityScopedAccess:
                "選択したファイルへアクセスできませんでした。"
            }
        }
    }

    static func save(_ image: UIImage, kind: ImageKind) throws -> String {
        let fileName = UUID().uuidString + ".png"
        let url = try url(for: fileName, kind: kind)

        guard let data = image.pngData() else {
            throw StoreError.missingImageData
        }

        try data.write(to: url, options: [.atomic])
        return fileName
    }

    static func image(named fileName: String, kind: ImageKind) -> UIImage? {
        guard let url = try? url(for: fileName, kind: kind) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    /// 一覧・サムネ表示用に縮小・キャッシュした画像を返す。
    static func thumbnail(named fileName: String, kind: ImageKind, maxPixelSize: CGFloat) -> UIImage? {
        guard let url = try? url(for: fileName, kind: kind) else {
            return nil
        }

        return ImageThumbnailCache.shared.thumbnail(at: url, maxPixelSize: maxPixelSize)
    }

    static func url(for fileName: String, kind: ImageKind) throws -> URL {
        let directoryURL = try directoryURL(for: kind)
        return directoryURL.appendingPathComponent(fileName)
    }

    static func deleteIfExists(fileName: String, kind: ImageKind) {
        guard let url = try? url(for: fileName, kind: kind) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func saveModel(from sourceURL: URL) throws -> String {
        guard sourceURL.pathExtension.lowercased() == "usdz" else {
            throw StoreError.unsupportedModelFile
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = UUID().uuidString + ".usdz"
        let destinationURL = try fileURL(for: fileName, kind: .model)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return fileName
    }

    static func modelURL(for fileName: String) throws -> URL {
        try fileURL(for: fileName, kind: .model)
    }

    static func newModelURL() throws -> (fileName: String, url: URL) {
        let fileName = UUID().uuidString + ".usdz"
        return (fileName, try fileURL(for: fileName, kind: .model))
    }

    static func deleteModelIfExists(fileName: String?) {
        guard let fileName,
              let url = try? fileURL(for: fileName, kind: .model) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    static func newObjectCaptureDirectory() throws -> (directoryName: String, url: URL) {
        let directoryName = UUID().uuidString
        let directoryURL = try directoryURL(for: directoryName, kind: .objectCapture)

        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return (directoryName, directoryURL)
    }

    static func objectCaptureDirectoryURL(for directoryName: String) throws -> URL {
        try directoryURL(for: directoryName, kind: .objectCapture)
    }

    static func deleteObjectCaptureDirectoryIfExists(directoryName: String?) {
        guard let directoryName,
              let url = try? directoryURL(for: directoryName, kind: .objectCapture) else {
            return
        }

        try? FileManager.default.removeItem(at: url)
    }

    private static func directoryURL(for kind: ImageKind) throws -> URL {
        let directoryURL = try charactersBaseURL()
            .appendingPathComponent(kind.rawValue, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL
    }

    private static func directoryURL(for directoryName: String, kind: DirectoryKind) throws -> URL {
        try charactersBaseURL()
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func fileURL(for fileName: String, kind: FileKind) throws -> URL {
        let directoryURL = try charactersBaseURL()
            .appendingPathComponent(kind.rawValue, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL.appendingPathComponent(fileName)
    }

    private static func charactersBaseURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let directoryURL = baseURL
            .appendingPathComponent("Tsureteku", isDirectory: true)
            .appendingPathComponent("Characters", isDirectory: true)

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        return directoryURL
    }
}
