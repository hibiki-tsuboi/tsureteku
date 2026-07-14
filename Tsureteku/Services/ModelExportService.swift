//
//  ModelExportService.swift
//  Tsureteku
//
//  Created by Codex on 2026/07/14.
//

import Foundation
import ModelIO
import SceneKit
import simd

enum ModelExportService {
    /// アプリ内で調整した正面方向を反映したUSDZを作る。
    /// サイズと上下位置はAR配置用の設定なので、モデルファイルには適用しない。
    nonisolated static func exportModel(
        from sourceURL: URL,
        to destinationURL: URL,
        yawDegrees: Double
    ) throws {
        let fileManager = FileManager.default

        // 回転調整がない場合は再変換せず、元のUSDZをそのまま共有する。
        guard abs(yawDegrees) > 0.0001 else {
            try replaceItem(at: destinationURL, withCopyOf: sourceURL, fileManager: fileManager)
            return
        }

        let workingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TsuretekuModelExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: workingDirectory)
        }

        let intermediateURL = workingDirectory.appendingPathComponent("oriented.usdc")
        let convertedURL = workingDirectory.appendingPathComponent("oriented.usdz")
        let scene = try SCNScene(url: sourceURL, options: nil)

        guard !scene.rootNode.childNodes.isEmpty else {
            throw ModelExportError.modelIsEmpty
        }

        // ルートの子を回転ノードで包み、メッシュ・マテリアル・アニメーションの
        // 階層を保ったまま正面方向だけを変更する。
        let orientationNode = SCNNode()
        orientationNode.name = "TsuretekuOrientation"
        orientationNode.simdOrientation = simd_quatf(
            angle: Float(yawDegrees) * .pi / 180,
            axis: SIMD3<Float>(0, 1, 0)
        )

        for node in scene.rootNode.childNodes {
            node.removeFromParentNode()
            orientationNode.addChildNode(node)
        }
        scene.rootNode.addChildNode(orientationNode)

        var writeError: Error?
        let didWriteIntermediate = scene.write(
            to: intermediateURL,
            options: nil,
            delegate: nil
        ) { _, error, stop in
            guard let error else {
                return
            }

            writeError = error
            stop.pointee = true
        }

        if let writeError {
            throw writeError
        }

        guard didWriteIntermediate else {
            throw ModelExportError.intermediateWriteFailed
        }

        MDLUtility.convert(toUSDZ: intermediateURL, writeTo: convertedURL)

        guard let attributes = try? fileManager.attributesOfItem(atPath: convertedURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value > 0 else {
            throw ModelExportError.usdzConversionFailed
        }

        try replaceItem(at: destinationURL, withCopyOf: convertedURL, fileManager: fileManager)
    }

    private nonisolated static func replaceItem(
        at destinationURL: URL,
        withCopyOf sourceURL: URL,
        fileManager: FileManager
    ) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }
}

private enum ModelExportError: LocalizedError {
    case modelIsEmpty
    case intermediateWriteFailed
    case usdzConversionFailed

    var errorDescription: String? {
        switch self {
        case .modelIsEmpty:
            "3Dモデルの内容を読み込めませんでした。"
        case .intermediateWriteFailed:
            "3Dモデルへ向きを反映できませんでした。"
        case .usdzConversionFailed:
            "向きを反映したUSDZを作成できませんでした。"
        }
    }
}
