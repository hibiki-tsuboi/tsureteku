//
//  CapturedPhotoStore.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

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

    static func image(named fileName: String) -> UIImage? {
        guard let url = try? url(for: fileName) else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
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
