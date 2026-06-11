//
//  ARCharacterView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import ARKit
import RealityKit
import SwiftUI
import UIKit
import simd

struct CharacterARAsset: Equatable {
    let id: UUID
    let name: String
    let cutoutImageFileName: String
    let modelFileName: String?
    let defaultSizeMeters: Float
}

struct ARCharacterView: UIViewRepresentable {
    var selectedAsset: CharacterARAsset?
    @Binding var captureTrigger: Int
    @Binding var removeLastTrigger: Int
    @Binding var resetTrigger: Int
    var onCapture: (Result<Void, Error>) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedAsset: selectedAsset, onCapture: onCapture, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.configure(arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.selectedAsset = selectedAsset
        context.coordinator.onCapture = onCapture
        context.coordinator.onStatus = onStatus

        if captureTrigger != context.coordinator.lastCaptureTrigger {
            context.coordinator.lastCaptureTrigger = captureTrigger

            if captureTrigger > 0 {
                context.coordinator.capture(in: arView)
            }
        }

        if removeLastTrigger != context.coordinator.lastRemoveLastTrigger {
            context.coordinator.lastRemoveLastTrigger = removeLastTrigger

            if removeLastTrigger > 0 {
                context.coordinator.removeLastPlacement(in: arView)
            }
        }

        if resetTrigger != context.coordinator.lastResetTrigger {
            context.coordinator.lastResetTrigger = resetTrigger

            if resetTrigger > 0 {
                context.coordinator.resetPlacements(in: arView)
            }
        }
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    final class Coordinator: NSObject {
        var selectedAsset: CharacterARAsset?
        var lastCaptureTrigger = 0
        var lastRemoveLastTrigger = 0
        var lastResetTrigger = 0
        var onCapture: (Result<Void, Error>) -> Void
        var onStatus: (String) -> Void
        private var placedAnchors: [AnchorEntity] = []

        init(
            selectedAsset: CharacterARAsset?,
            onCapture: @escaping (Result<Void, Error>) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.selectedAsset = selectedAsset
            self.onCapture = onCapture
            self.onStatus = onStatus
        }

        func configure(_ arView: ARView) {
            arView.renderOptions.insert(.disableMotionBlur)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapGesture)

            guard ARWorldTrackingConfiguration.isSupported else {
                onStatus("この端末ではARを利用できません。")
                return
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            configuration.environmentTexturing = .automatic
            arView.session.run(configuration)

            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.goal = .horizontalPlane
            coachingOverlay.activatesAutomatically = true
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            arView.addSubview(coachingOverlay)

            NSLayoutConstraint.activate([
                coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
                coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
            ])
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView = recognizer.view as? ARView else {
                return
            }

            guard let selectedAsset else {
                onStatus("キャラを選択してください。")
                return
            }

            let location = recognizer.location(in: arView)
            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)

            guard let result = results.first else {
                onStatus("平面が見つかりません。")
                return
            }

            do {
                try place(selectedAsset, at: result, in: arView)
                onStatus("\(selectedAsset.name)を配置しました。")
            } catch {
                onStatus(error.localizedDescription)
            }
        }

        func capture(in arView: ARView) {
            arView.snapshot(saveToHDR: false) { [weak self] image in
                guard let self else {
                    return
                }

                guard let image else {
                    onCapture(.failure(ARCaptureError.snapshotFailed))
                    return
                }

                PhotoLibrarySaver.save(image) { result in
                    self.onCapture(result)
                }
            }
        }

        private func place(_ asset: CharacterARAsset, at result: ARRaycastResult, in arView: ARView) throws {
            if let modelFileName = asset.modelFileName {
                try placeModel(asset, modelFileName: modelFileName, at: result, in: arView)
            } else {
                try placeCutout(asset, at: result, in: arView)
            }
        }

        func removeLastPlacement(in arView: ARView) {
            guard let anchor = placedAnchors.popLast() else {
                onStatus("削除できるキャラがありません。")
                return
            }

            arView.scene.removeAnchor(anchor)
            onStatus("最後のキャラを削除しました。")
        }

        func resetPlacements(in arView: ARView) {
            guard !placedAnchors.isEmpty else {
                onStatus("リセットできるキャラがありません。")
                return
            }

            for anchor in placedAnchors {
                arView.scene.removeAnchor(anchor)
            }

            placedAnchors.removeAll()
            onStatus("配置をリセットしました。")
        }

        private func placeCutout(_ asset: CharacterARAsset, at result: ARRaycastResult, in arView: ARView) throws {
            let imageURL = try CharacterImageStore.url(for: asset.cutoutImageFileName, kind: .cutout)
            let texture = try TextureResource.load(
                contentsOf: imageURL,
                withName: asset.id.uuidString,
                options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            )

            let aspectRatio = max(0.25, min(4.0, Float(texture.width) / Float(max(texture.height, 1))))
            let height = asset.defaultSizeMeters
            let width = height * aspectRatio
            let mesh = MeshResource.generatePlane(width: width, height: height)

            var material = UnlitMaterial(texture: texture)
            material.blending = .transparent(opacity: 1.0)
            material.opacityThreshold = 0.01
            material.faceCulling = .none

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.name = asset.name
            entity.position.y = height / 2
            entity.orientation = orientationFacingCamera(from: result.worldTransform, arView: arView)
            entity.generateCollisionShapes(recursive: false)

            let anchor = AnchorEntity(raycastResult: result)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            placedAnchors.append(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
        }

        private func placeModel(
            _ asset: CharacterARAsset,
            modelFileName: String,
            at result: ARRaycastResult,
            in arView: ARView
        ) throws {
            let modelURL = try CharacterImageStore.modelURL(for: modelFileName)
            let entity = try ModelEntity.loadModel(contentsOf: modelURL, withName: asset.id.uuidString)
            let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            let scale = maxExtent > 0 ? asset.defaultSizeMeters / maxExtent : asset.defaultSizeMeters

            entity.name = asset.name
            entity.scale = SIMD3<Float>(repeating: scale)
            entity.position.y = max(0, -bounds.min.y * scale)
            entity.orientation = orientationFacingCamera(from: result.worldTransform, arView: arView)
            entity.generateCollisionShapes(recursive: true)

            let anchor = AnchorEntity(raycastResult: result)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            placedAnchors.append(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
        }

        private func orientationFacingCamera(from worldTransform: simd_float4x4, arView: ARView) -> simd_quatf {
            let anchorPosition = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
            let cameraPosition = arView.cameraTransform.translation
            let direction = SIMD3<Float>(
                cameraPosition.x - anchorPosition.x,
                0,
                cameraPosition.z - anchorPosition.z
            )

            guard simd_length(direction) > 0.001 else {
                return simd_quatf(angle: 0, axis: [0, 1, 0])
            }

            let normalizedDirection = simd_normalize(direction)
            let yaw = atan2(normalizedDirection.x, normalizedDirection.z)
            return simd_quatf(angle: yaw, axis: [0, 1, 0])
        }
    }
}

private enum ARCaptureError: LocalizedError {
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .snapshotFailed:
            "AR写真を作成できませんでした。"
        }
    }
}
