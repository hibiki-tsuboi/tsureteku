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
    let modelYawDegrees: Float
    let modelVerticalOffsetMeters: Float
}

struct ARCharacterView: UIViewRepresentable {
    var selectedAsset: CharacterARAsset?
    var isSelfieMode: Bool
    @Binding var captureTrigger: Int
    @Binding var removeLastTrigger: Int
    @Binding var resetTrigger: Int
    @Binding var scaleDownTrigger: Int
    @Binding var scaleUpTrigger: Int
    @Binding var rotateLeftTrigger: Int
    @Binding var rotateRightTrigger: Int
    @Binding var faceCameraTrigger: Int
    @Binding var removeSelectedTrigger: Int
    @Binding var clearPlacementSelectionTrigger: Int
    @Binding var selectedPlacementName: String?
    var onCapture: (Result<UIImage, Error>) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            selectedAsset: selectedAsset,
            selectedPlacementName: $selectedPlacementName,
            onCapture: onCapture,
            onStatus: onStatus
        )
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.isSelfieMode = isSelfieMode
        context.coordinator.configure(arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.selectedAsset = selectedAsset
        context.coordinator.onCapture = onCapture
        context.coordinator.onStatus = onStatus
        context.coordinator.selectedPlacementName = $selectedPlacementName
        context.coordinator.updateSelfieMode(isSelfieMode, in: arView)

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

        if scaleDownTrigger != context.coordinator.lastScaleDownTrigger {
            context.coordinator.lastScaleDownTrigger = scaleDownTrigger

            if scaleDownTrigger > 0 {
                context.coordinator.scaleSelectedPlacement(by: 0.9)
            }
        }

        if scaleUpTrigger != context.coordinator.lastScaleUpTrigger {
            context.coordinator.lastScaleUpTrigger = scaleUpTrigger

            if scaleUpTrigger > 0 {
                context.coordinator.scaleSelectedPlacement(by: 1.1)
            }
        }

        if rotateLeftTrigger != context.coordinator.lastRotateLeftTrigger {
            context.coordinator.lastRotateLeftTrigger = rotateLeftTrigger

            if rotateLeftTrigger > 0 {
                context.coordinator.rotateSelectedPlacement(by: Float.pi / 12)
            }
        }

        if rotateRightTrigger != context.coordinator.lastRotateRightTrigger {
            context.coordinator.lastRotateRightTrigger = rotateRightTrigger

            if rotateRightTrigger > 0 {
                context.coordinator.rotateSelectedPlacement(by: -Float.pi / 12)
            }
        }

        if faceCameraTrigger != context.coordinator.lastFaceCameraTrigger {
            context.coordinator.lastFaceCameraTrigger = faceCameraTrigger

            if faceCameraTrigger > 0 {
                context.coordinator.faceSelectedPlacementToCamera(in: arView)
            }
        }

        if removeSelectedTrigger != context.coordinator.lastRemoveSelectedTrigger {
            context.coordinator.lastRemoveSelectedTrigger = removeSelectedTrigger

            if removeSelectedTrigger > 0 {
                context.coordinator.removeSelectedPlacement(in: arView)
            }
        }

        if clearPlacementSelectionTrigger != context.coordinator.lastClearPlacementSelectionTrigger {
            context.coordinator.lastClearPlacementSelectionTrigger = clearPlacementSelectionTrigger

            if clearPlacementSelectionTrigger > 0 {
                context.coordinator.clearSelectedPlacement()
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
        var lastScaleDownTrigger = 0
        var lastScaleUpTrigger = 0
        var lastRotateLeftTrigger = 0
        var lastRotateRightTrigger = 0
        var lastFaceCameraTrigger = 0
        var lastRemoveSelectedTrigger = 0
        var lastClearPlacementSelectionTrigger = 0
        var onCapture: (Result<UIImage, Error>) -> Void
        var onStatus: (String) -> Void
        var selectedPlacementName: Binding<String?>
        var isSelfieMode = false
        private var placements: [PlacedCharacter] = []
        private var selectedPlacementID: UUID?
        private weak var coachingOverlay: ARCoachingOverlayView?
        private var selfieAssetID: UUID?
        private var selfieSize: Float?
        private var selfieScaleDivisor: Float = 1

        init(
            selectedAsset: CharacterARAsset?,
            selectedPlacementName: Binding<String?>,
            onCapture: @escaping (Result<UIImage, Error>) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.selectedAsset = selectedAsset
            self.selectedPlacementName = selectedPlacementName
            self.onCapture = onCapture
            self.onStatus = onStatus
        }

        func configure(_ arView: ARView) {
            arView.renderOptions.insert(.disableMotionBlur)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapGesture)

            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.goal = .anyPlane
            coachingOverlay.activatesAutomatically = true
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            arView.addSubview(coachingOverlay)

            NSLayoutConstraint.activate([
                coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
                coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
            ])
            self.coachingOverlay = coachingOverlay

            if isSelfieMode {
                startSelfieSession(in: arView)
            } else {
                startWorldSession(in: arView)
            }
        }

        // MARK: - カメラモード

        func updateSelfieMode(_ selfie: Bool, in arView: ARView) {
            if selfie != isSelfieMode {
                isSelfieMode = selfie
                removeAllPlacements(in: arView)
                selfieAssetID = nil
                selfieSize = nil

                if selfie {
                    startSelfieSession(in: arView)
                } else {
                    startWorldSession(in: arView)
                }
            } else if selfie {
                refreshSelfieCharacter(in: arView)
            }
        }

        private func startWorldSession(in arView: ARView) {
            guard ARWorldTrackingConfiguration.isSupported else {
                onStatus("この端末ではARを利用できません。")
                return
            }

            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic

            // 対応端末では人物オクルージョンを有効にし、人の前後に推しが自然に回り込むようにする。
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                configuration.frameSemantics.insert(.personSegmentationWithDepth)
            }

            arView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])

            coachingOverlay?.goal = .anyPlane
            coachingOverlay?.activatesAutomatically = true
        }

        private func startSelfieSession(in arView: ARView) {
            guard ARFaceTrackingConfiguration.isSupported else {
                onStatus("この端末では自撮りARを利用できません。")
                return
            }

            coachingOverlay?.activatesAutomatically = false
            coachingOverlay?.setActive(false, animated: false)

            let configuration = ARFaceTrackingConfiguration()
            configuration.maximumNumberOfTrackedFaces = 1
            configuration.isLightEstimationEnabled = true
            arView.session.run(configuration, options: [.removeExistingAnchors, .resetTracking])

            onStatus("顔が映ると、選んだ推しが隣に現れます。")
            refreshSelfieCharacter(in: arView)
        }

        private func refreshSelfieCharacter(in arView: ARView) {
            guard isSelfieMode else {
                return
            }

            guard let asset = selectedAsset else {
                removeAllPlacements(in: arView)
                selfieAssetID = nil
                selfieSize = nil
                return
            }

            // 同じ推しならサイズ変更だけ反映して作り直さない。
            if asset.id == selfieAssetID {
                if selfieSize != asset.defaultSizeMeters, let placement = placements.first {
                    let scale = asset.defaultSizeMeters / selfieScaleDivisor
                    placement.entity.scale = SIMD3<Float>(repeating: scale)
                    selfieSize = asset.defaultSizeMeters
                }
                return
            }

            removeAllPlacements(in: arView)

            do {
                let placement = try placeSelfieCharacter(asset, in: arView)
                placements.append(placement)
                selectPlacement(placement)
                selfieAssetID = asset.id
                selfieSize = asset.defaultSizeMeters
            } catch {
                onStatus(error.localizedDescription)
            }
        }

        private func placeSelfieCharacter(_ asset: CharacterARAsset, in arView: ARView) throws -> PlacedCharacter {
            let entity: ModelEntity
            let divisor: Float

            if let modelFileName = asset.modelFileName {
                let modelURL = try CharacterImageStore.modelURL(for: modelFileName)
                let loaded = try ModelEntity.loadModel(contentsOf: modelURL, withName: asset.id.uuidString)
                let bounds = loaded.visualBounds(recursive: true, relativeTo: loaded)
                let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
                divisor = maxExtent > 0 ? maxExtent : 1

                // モデルの中心を原点に合わせ、拡大・回転がぶれないようにする。
                let center = (bounds.min + bounds.max) / 2
                loaded.position = -center

                let container = ModelEntity()
                container.addChild(loaded)
                // モデルの正面（-Z）をカメラ（顔アンカーの+Z）へ向ける。
                container.orientation = simd_quatf(angle: (asset.modelYawDegrees + 180) * .pi / 180, axis: [0, 1, 0])
                entity = container
            } else {
                let imageURL = try CharacterImageStore.url(for: asset.cutoutImageFileName, kind: .cutout)
                let texture = try TextureResource.load(
                    contentsOf: imageURL,
                    withName: asset.id.uuidString,
                    options: .init(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
                )

                let aspectRatio = max(0.25, min(4.0, Float(texture.width) / Float(max(texture.height, 1))))
                let mesh = MeshResource.generatePlane(width: aspectRatio, height: 1.0)

                var material = UnlitMaterial(texture: texture)
                material.blending = .transparent(opacity: 1.0)
                material.opacityThreshold = 0.01
                material.faceCulling = .none

                entity = ModelEntity(mesh: mesh, materials: [material])
                divisor = 1.0
            }

            entity.name = asset.name
            let scale = asset.defaultSizeMeters / divisor
            entity.scale = SIMD3<Float>(repeating: scale)
            // 顔の横、少し手前に配置する。
            entity.position = [0.16, 0, 0.06]
            entity.generateCollisionShapes(recursive: true)

            let anchor = AnchorEntity(.face)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
            startIdleAnimation(for: entity)

            selfieScaleDivisor = divisor

            return PlacedCharacter(
                anchor: anchor,
                entity: entity,
                name: asset.name,
                baseScale: entity.scale,
                yawCorrectionDegrees: asset.modelYawDegrees,
                selectionMarker: Entity()
            )
        }

        private func removeAllPlacements(in arView: ARView) {
            for placement in placements {
                arView.scene.removeAnchor(placement.anchor)
            }

            placements.removeAll()
            clearSelectedPlacement()
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard !isSelfieMode else {
                return
            }

            guard let arView = recognizer.view as? ARView else {
                return
            }

            guard let selectedAsset else {
                onStatus("推しを選択してください。")
                return
            }

            let location = recognizer.location(in: arView)

            if let tappedEntity = arView.entity(at: location),
               let placement = placement(containing: tappedEntity) {
                selectPlacement(placement)
                onStatus("\(placement.name)を選択しました。")
                return
            }

            let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)

            guard let result = results.first else {
                onStatus("平面が見つかりません。床や壁にカメラを向けてください。")
                return
            }

            do {
                let placement = try place(selectedAsset, at: result, in: arView)
                selectPlacement(placement)
                onStatus("\(selectedAsset.name)を配置しました。")
            } catch {
                onStatus(error.localizedDescription)
            }
        }

        func capture(in arView: ARView) {
            let marker = selectedPlacement?.selectionMarker
            let wasMarkerEnabled = marker?.isEnabled ?? false
            marker?.isEnabled = false

            arView.snapshot(saveToHDR: false) { [weak self] image in
                guard let self else {
                    return
                }

                marker?.isEnabled = wasMarkerEnabled

                guard let image else {
                    onCapture(.failure(ARCaptureError.snapshotFailed))
                    return
                }

                self.onCapture(.success(image))
            }
        }

        @discardableResult
        private func place(_ asset: CharacterARAsset, at result: ARRaycastResult, in arView: ARView) throws -> PlacedCharacter {
            if let modelFileName = asset.modelFileName {
                try placeModel(asset, modelFileName: modelFileName, at: result, in: arView)
            } else {
                try placeCutout(asset, at: result, in: arView)
            }
        }

        func removeLastPlacement(in arView: ARView) {
            guard let placement = placements.popLast() else {
                onStatus("削除できる推しがありません。")
                return
            }

            arView.scene.removeAnchor(placement.anchor)
            if selectedPlacementID == placement.id {
                clearSelectedPlacement()
            }
            onStatus("最後の推しを削除しました。")
        }

        func resetPlacements(in arView: ARView) {
            guard !placements.isEmpty else {
                onStatus("リセットできる推しがありません。")
                return
            }

            for placement in placements {
                arView.scene.removeAnchor(placement.anchor)
            }

            placements.removeAll()
            clearSelectedPlacement()
            onStatus("配置をリセットしました。")
        }

        func scaleSelectedPlacement(by factor: Float) {
            guard let placement = selectedPlacement else {
                onStatus("調整する推しを選択してください。")
                return
            }

            let newScale = placement.entity.scale * factor
            let relativeScale = relativeScale(for: newScale, baseScale: placement.baseScale)

            guard (0.25...4.0).contains(relativeScale) else {
                onStatus("これ以上サイズを変更できません。")
                return
            }

            placement.entity.scale = newScale
        }

        func rotateSelectedPlacement(by angle: Float) {
            guard let placement = selectedPlacement else {
                onStatus("回転する推しを選択してください。")
                return
            }

            let rotation = simd_quatf(angle: angle, axis: [0, 1, 0])
            placement.entity.orientation = simd_mul(placement.entity.orientation, rotation)
        }

        func faceSelectedPlacementToCamera(in arView: ARView) {
            guard let placement = selectedPlacement else {
                onStatus("向きを変える推しを選択してください。")
                return
            }

            let anchorPosition = placement.anchor.position(relativeTo: nil)
            placement.entity.orientation = orientationFacingCamera(
                anchorPosition: anchorPosition,
                arView: arView,
                yawDegrees: placement.yawCorrectionDegrees
            )
            onStatus("カメラの方向に向けました。")
        }

        func removeSelectedPlacement(in arView: ARView) {
            guard let selectedPlacementID,
                  let index = placements.firstIndex(where: { $0.id == selectedPlacementID }) else {
                onStatus("削除する推しを選択してください。")
                return
            }

            let placement = placements.remove(at: index)
            arView.scene.removeAnchor(placement.anchor)
            clearSelectedPlacement()
            onStatus("\(placement.name)を削除しました。")
        }

        func clearSelectedPlacement() {
            selectedPlacement?.selectionMarker.isEnabled = false
            selectedPlacementID = nil
            selectedPlacementName.wrappedValue = nil
        }

        private var selectedPlacement: PlacedCharacter? {
            guard let selectedPlacementID else {
                return nil
            }

            return placements.first { $0.id == selectedPlacementID }
        }

        private func placeCutout(_ asset: CharacterARAsset, at result: ARRaycastResult, in arView: ARView) throws -> PlacedCharacter {
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

            let baseY = -height / 2
            let shadow = makeContactShadow(width: width * 0.9, depth: max(0.08, width * 0.22), baseY: baseY)
            let selectionMarker = makeSelectionMarker(width: width * 1.08, depth: max(0.1, width * 0.28), baseY: baseY)
            entity.addChild(shadow)
            entity.addChild(selectionMarker)

            let anchor = AnchorEntity(raycastResult: result)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
            startIdleAnimation(for: entity)

            let placement = PlacedCharacter(
                anchor: anchor,
                entity: entity,
                name: asset.name,
                baseScale: entity.scale,
                yawCorrectionDegrees: 0,
                selectionMarker: selectionMarker
            )
            placements.append(placement)
            return placement
        }

        private func placeModel(
            _ asset: CharacterARAsset,
            modelFileName: String,
            at result: ARRaycastResult,
            in arView: ARView
        ) throws -> PlacedCharacter {
            let modelURL = try CharacterImageStore.modelURL(for: modelFileName)
            let entity = try ModelEntity.loadModel(contentsOf: modelURL, withName: asset.id.uuidString)
            let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            let scale = maxExtent > 0 ? asset.defaultSizeMeters / maxExtent : asset.defaultSizeMeters

            entity.name = asset.name
            entity.scale = SIMD3<Float>(repeating: scale)
            entity.position.y = max(0, -bounds.min.y * scale) + asset.modelVerticalOffsetMeters
            entity.orientation = modelOrientationFacingCamera(from: result.worldTransform, arView: arView, yawDegrees: asset.modelYawDegrees)
            entity.generateCollisionShapes(recursive: true)

            let baseY = bounds.min.y
            let width = max(bounds.extents.x, asset.defaultSizeMeters / scale) * 1.08
            let depth = max(bounds.extents.z, bounds.extents.x * 0.5, asset.defaultSizeMeters / scale * 0.28)
            let selectionMarker = makeSelectionMarker(width: width * 1.08, depth: depth * 1.08, baseY: baseY)
            entity.addChild(selectionMarker)

            // 3Dモデルは床面に実際の影を落とす（疑似的な接地影より自然）。
            entity.components.set(GroundingShadowComponent(castsShadow: true))

            let anchor = AnchorEntity(raycastResult: result)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
            startIdleAnimation(for: entity)

            let placement = PlacedCharacter(
                anchor: anchor,
                entity: entity,
                name: asset.name,
                baseScale: entity.scale,
                yawCorrectionDegrees: asset.modelYawDegrees,
                selectionMarker: selectionMarker
            )
            placements.append(placement)
            return placement
        }

        private func orientationFacingCamera(from worldTransform: simd_float4x4, arView: ARView) -> simd_quatf {
            let anchorPosition = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
            return orientationFacingCamera(anchorPosition: anchorPosition, arView: arView)
        }

        private func orientationFacingCamera(anchorPosition: SIMD3<Float>, arView: ARView) -> simd_quatf {
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

        private func modelOrientationFacingCamera(
            from worldTransform: simd_float4x4,
            arView: ARView,
            yawDegrees: Float
        ) -> simd_quatf {
            let anchorPosition = SIMD3<Float>(
                worldTransform.columns.3.x,
                worldTransform.columns.3.y,
                worldTransform.columns.3.z
            )
            return orientationFacingCamera(anchorPosition: anchorPosition, arView: arView, yawDegrees: yawDegrees)
        }

        private func orientationFacingCamera(
            anchorPosition: SIMD3<Float>,
            arView: ARView,
            yawDegrees: Float
        ) -> simd_quatf {
            let baseOrientation = orientationFacingCamera(anchorPosition: anchorPosition, arView: arView)
            let adjustment = simd_quatf(angle: yawDegrees * .pi / 180, axis: [0, 1, 0])
            return simd_mul(baseOrientation, adjustment)
        }

        private func selectPlacement(_ placement: PlacedCharacter) {
            placements.forEach { $0.selectionMarker.isEnabled = false }
            placement.selectionMarker.isEnabled = true
            selectedPlacementID = placement.id
            selectedPlacementName.wrappedValue = placement.name
        }

        /// 置いた推しに“動き”をつける。USDZにアニメーションがあれば再生し、
        /// 無ければふわふわ浮くアイドルモーションを加算アニメで再生する（移動・拡大・回転の操作と競合しない）。
        private func startIdleAnimation(for entity: Entity) {
            // USDZにアニメーションがある場合のみ再生する。
            // （手続き的な浮遊アニメは transform を壊して巨大化・位置ずれを招くため使わない）
            if let clip = idleAnimationClip(in: entity) {
                clip.entity.playAnimation(clip.resource.repeat(), transitionDuration: 0.4)
            }
        }

        /// USDZに埋め込まれた再生可能なアニメーションを、自身または直下の子から探す。
        private func idleAnimationClip(in entity: Entity) -> (entity: Entity, resource: AnimationResource)? {
            if let resource = entity.availableAnimations.first {
                return (entity, resource)
            }

            for child in entity.children {
                if let resource = child.availableAnimations.first {
                    return (child, resource)
                }
            }

            return nil
        }

        private func makeContactShadow(width: Float, depth: Float, baseY: Float) -> ModelEntity {
            var material = UnlitMaterial(color: UIColor.black.withAlphaComponent(0.18))
            material.blending = .transparent(opacity: 0.18)
            material.faceCulling = .none

            let shadow = ModelEntity(
                mesh: .generateSphere(radius: 0.5),
                materials: [material]
            )
            shadow.name = "contact-shadow"
            shadow.position = [0, baseY + 0.002, 0]
            shadow.scale = [max(width, 0.08), 0.003, max(depth, 0.06)]
            return shadow
        }

        private func makeSelectionMarker(width: Float, depth: Float, baseY: Float) -> Entity {
            // ブランドのミント (#3FE0B8) で足元に丸いリングを描き、選択中を柔らかく示す。
            let mint = UIColor(red: 0.247, green: 0.878, blue: 0.722, alpha: 1.0)
            var material = UnlitMaterial(color: mint.withAlphaComponent(0.85))
            material.blending = .transparent(opacity: 0.85)
            material.faceCulling = .none

            let marker = Entity()
            marker.name = "selection-marker"
            marker.position = [0, baseY + 0.008, 0]
            marker.isEnabled = false

            // フットプリントの大きい方の寸法をわずかに上回る半径で全体を囲う。
            let radius = max(max(width, depth) * 0.55, 0.05)
            let lineThickness = max(min(width, depth) * 0.05, 0.006)
            let lineHeight: Float = 0.004
            let segmentCount = 48
            // 隣り合うセグメントを少し重ねて、継ぎ目のない滑らかなリングにする。
            let segmentLength = (2 * .pi * radius) / Float(segmentCount) * 1.2

            for index in 0..<segmentCount {
                let angle = (2 * .pi) * Float(index) / Float(segmentCount)
                let segment = ModelEntity(
                    mesh: .generateBox(width: segmentLength, height: lineHeight, depth: lineThickness),
                    materials: [material]
                )
                segment.position = [radius * cos(angle), 0, radius * sin(angle)]
                // ボックスの長辺を円の接線方向に向ける。
                segment.orientation = simd_quatf(angle: -(angle + .pi / 2), axis: [0, 1, 0])
                marker.addChild(segment)
            }

            return marker
        }

        private func placement(containing entity: Entity) -> PlacedCharacter? {
            var currentEntity: Entity? = entity

            while let candidate = currentEntity {
                if let placement = placements.first(where: { $0.entity === candidate }) {
                    return placement
                }

                currentEntity = candidate.parent
            }

            return nil
        }

        private func relativeScale(for scale: SIMD3<Float>, baseScale: SIMD3<Float>) -> Float {
            let x = relativeAxisScale(scale.x, baseScale.x)
            let y = relativeAxisScale(scale.y, baseScale.y)
            let z = relativeAxisScale(scale.z, baseScale.z)
            return (x + y + z) / 3
        }

        private func relativeAxisScale(_ value: Float, _ baseValue: Float) -> Float {
            guard abs(baseValue) > 0.0001 else {
                return 1
            }

            return abs(value / baseValue)
        }

        private struct PlacedCharacter {
            let id = UUID()
            let anchor: AnchorEntity
            let entity: Entity
            let name: String
            let baseScale: SIMD3<Float>
            let yawCorrectionDegrees: Float
            let selectionMarker: Entity
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
