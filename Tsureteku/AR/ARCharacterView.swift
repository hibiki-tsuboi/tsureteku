//
//  ARCharacterView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import ARKit
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
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
    let arBrightnessMultiplier: Float
    let modelYawDegrees: Float
    let modelVerticalOffsetMeters: Float
}

struct ARCharacterView: UIViewRepresentable {
    var selectedAsset: CharacterARAsset?
    var isSelfieMode: Bool
    /// 録画中はレティクルが画面収録に写り込まないよう隠すためのフラグ。
    var isRecording: Bool
    @Binding var captureTrigger: Int
    @Binding var resetTrigger: Int
    @Binding var scaleDownTrigger: Int
    @Binding var scaleUpTrigger: Int
    @Binding var rotateLeftTrigger: Int
    @Binding var rotateRightTrigger: Int
    @Binding var faceCameraTrigger: Int
    @Binding var removeSelectedTrigger: Int
    @Binding var clearPlacementSelectionTrigger: Int
    @Binding var selectedPlacementName: String?
    /// シーン上に推しが1体も置かれていないか。配置ヒントの表示判定に使う。
    @Binding var isSceneEmpty: Bool
    /// Apple標準の平面検出コーチングが表示中か。表示中は配置ヒントを出さない。
    @Binding var isCoachingActive: Bool
    var onCapture: (Result<UIImage, Error>) -> Void
    var onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(
            selectedAsset: selectedAsset,
            selectedPlacementName: $selectedPlacementName,
            isSceneEmpty: $isSceneEmpty,
            isCoachingActive: $isCoachingActive,
            onCapture: onCapture,
            onStatus: onStatus
        )
        coordinator.syncTriggerBaselines(
            captureTrigger: captureTrigger,
            resetTrigger: resetTrigger,
            scaleDownTrigger: scaleDownTrigger,
            scaleUpTrigger: scaleUpTrigger,
            rotateLeftTrigger: rotateLeftTrigger,
            rotateRightTrigger: rotateRightTrigger,
            faceCameraTrigger: faceCameraTrigger,
            removeSelectedTrigger: removeSelectedTrigger,
            clearPlacementSelectionTrigger: clearPlacementSelectionTrigger
        )
        return coordinator
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
        context.coordinator.isSceneEmpty = $isSceneEmpty
        context.coordinator.isCoachingActive = $isCoachingActive
        context.coordinator.isRecording = isRecording
        context.coordinator.updateSceneLighting(in: arView)
        context.coordinator.updateSelfieMode(isSelfieMode, in: arView)

        if captureTrigger != context.coordinator.lastCaptureTrigger {
            context.coordinator.lastCaptureTrigger = captureTrigger

            if captureTrigger > 0 {
                context.coordinator.capture(in: arView)
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
        coordinator.tearDown()
        arView.session.pause()
    }

    final class Coordinator: NSObject, ARCoachingOverlayViewDelegate {
        var selectedAsset: CharacterARAsset?
        var lastCaptureTrigger = 0
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
        var isSceneEmpty: Binding<Bool>
        var isCoachingActive: Binding<Bool>
        var isSelfieMode = false
        var isRecording = false {
            didSet {
                guard isRecording != oldValue else {
                    return
                }

                updateSelectionMarkerVisibility()
            }
        }
        /// 検出面の中央に出す配置レティクル（吸着リング）とその土台アンカー。
        private var reticleAnchor: AnchorEntity?
        private var reticleEntity: Entity?
        /// 毎フレームのレイキャストでレティクルを更新する購読。
        private var sceneUpdateSubscription: Cancellable?
        /// 撮影スナップショットの瞬間だけレティクルを写さないための一時抑制フラグ。
        private var suppressReticle = false
        private var placements: [PlacedCharacter] = [] {
            didSet {
                // 配置の有無が変わったときだけ SwiftUI 側へ通知し、ヒント表示を更新する。
                let empty = placements.isEmpty
                if empty != isSceneEmpty.wrappedValue {
                    isSceneEmpty.wrappedValue = empty
                }
            }
        }
        private var selectedPlacementID: UUID?
        /// 推しの配置（特に3Dモデルの非同期ロード）中は true。連打による多重配置を防ぐ。
        private var isPlacing = false
        private var placementTask: Task<Void, Never>?
        private weak var coachingOverlay: ARCoachingOverlayView?
        private var selfieRenderedAsset: CharacterARAsset?
        private var selfieSize: Float?
        private var selfieScaleDivisor: Float = 1
        private var selfieUnscaledHeight: Float = 1

        init(
            selectedAsset: CharacterARAsset?,
            selectedPlacementName: Binding<String?>,
            isSceneEmpty: Binding<Bool>,
            isCoachingActive: Binding<Bool>,
            onCapture: @escaping (Result<UIImage, Error>) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.selectedAsset = selectedAsset
            self.selectedPlacementName = selectedPlacementName
            self.isSceneEmpty = isSceneEmpty
            self.isCoachingActive = isCoachingActive
            self.onCapture = onCapture
            self.onStatus = onStatus
        }

        func syncTriggerBaselines(
            captureTrigger: Int,
            resetTrigger: Int,
            scaleDownTrigger: Int,
            scaleUpTrigger: Int,
            rotateLeftTrigger: Int,
            rotateRightTrigger: Int,
            faceCameraTrigger: Int,
            removeSelectedTrigger: Int,
            clearPlacementSelectionTrigger: Int
        ) {
            lastCaptureTrigger = captureTrigger
            lastResetTrigger = resetTrigger
            lastScaleDownTrigger = scaleDownTrigger
            lastScaleUpTrigger = scaleUpTrigger
            lastRotateLeftTrigger = rotateLeftTrigger
            lastRotateRightTrigger = rotateRightTrigger
            lastFaceCameraTrigger = faceCameraTrigger
            lastRemoveSelectedTrigger = removeSelectedTrigger
            lastClearPlacementSelectionTrigger = clearPlacementSelectionTrigger
        }

        func configure(_ arView: ARView) {
            arView.renderOptions.insert(.disableMotionBlur)
            arView.renderOptions.remove(.disableGroundingShadows)

            // 暗い室内でも推し（3Dモデル）が暗く沈まないよう、環境光をやや明るめに底上げする。
            updateSceneLighting(in: arView)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            arView.addGestureRecognizer(tapGesture)

            let coachingOverlay = ARCoachingOverlayView()
            coachingOverlay.session = arView.session
            coachingOverlay.goal = .anyPlane
            coachingOverlay.activatesAutomatically = true
            coachingOverlay.delegate = self
            coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
            arView.addSubview(coachingOverlay)

            NSLayoutConstraint.activate([
                coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
                coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
                coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
                coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
            ])
            self.coachingOverlay = coachingOverlay

            let reticle = makeReticle()
            let reticleAnchor = AnchorEntity(world: matrix_identity_float4x4)
            reticleAnchor.addChild(reticle)
            arView.scene.addAnchor(reticleAnchor)
            self.reticleAnchor = reticleAnchor
            self.reticleEntity = reticle

            // 毎フレーム画面中央から平面へレイキャストし、レティクルを吸着させる。
            sceneUpdateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak arView] _ in
                guard let self, let arView else {
                    return
                }
                self.updateReticle(in: arView)
            }

            if isSelfieMode {
                startSelfieSession(in: arView)
            } else {
                startWorldSession(in: arView)
            }
        }

        // MARK: - コーチング

        func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
            isCoachingActive.wrappedValue = true
        }

        func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
            isCoachingActive.wrappedValue = false
        }

        // MARK: - カメラモード

        func updateSelfieMode(_ selfie: Bool, in arView: ARView) {
            if selfie != isSelfieMode {
                isSelfieMode = selfie
                removeAllPlacements(in: arView)
                selfieRenderedAsset = nil
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
            configuration.isLightEstimationEnabled = true

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
                selfieRenderedAsset = nil
                selfieSize = nil
                return
            }

            updateSceneLighting(in: arView)

            // 見た目に関わる設定が同じなら、サイズ変更だけ反映して作り直さない。
            if let selfieRenderedAsset,
               isSameRenderableSelfieAsset(asset, selfieRenderedAsset) {
                if selfieSize != asset.defaultSizeMeters, let placement = placements.first {
                    let scale = asset.defaultSizeMeters / selfieScaleDivisor
                    placement.entity.scale = SIMD3<Float>(repeating: scale)
                    placement.entity.position = selfiePosition(scaledHeight: selfieUnscaledHeight * scale)
                    selfieSize = asset.defaultSizeMeters
                }
                self.selfieRenderedAsset = asset
                return
            }

            removeAllPlacements(in: arView)

            do {
                let placement = try placeSelfieCharacter(asset, in: arView)
                placements.append(placement)
                selectPlacement(placement)
                selfieRenderedAsset = asset
                selfieSize = asset.defaultSizeMeters
            } catch {
                onStatus(error.localizedDescription)
            }
        }

        private func isSameRenderableSelfieAsset(_ lhs: CharacterARAsset, _ rhs: CharacterARAsset) -> Bool {
            lhs.id == rhs.id &&
                lhs.cutoutImageFileName == rhs.cutoutImageFileName &&
                lhs.modelFileName == rhs.modelFileName &&
                lhs.arBrightnessMultiplier == rhs.arBrightnessMultiplier &&
                lhs.modelYawDegrees == rhs.modelYawDegrees &&
                lhs.modelVerticalOffsetMeters == rhs.modelVerticalOffsetMeters
        }

        private func placeSelfieCharacter(_ asset: CharacterARAsset, in arView: ARView) throws -> PlacedCharacter {
            let entity: ModelEntity
            let divisor: Float
            let unscaledHeight: Float

            if let modelFileName = asset.modelFileName {
                let modelURL = try CharacterImageStore.modelURL(for: modelFileName)
                let loaded = try ModelEntity.loadModel(contentsOf: modelURL, withName: asset.id.uuidString)
                let bounds = loaded.visualBounds(recursive: true, relativeTo: loaded)
                let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
                divisor = maxExtent > 0 ? maxExtent : 1
                unscaledHeight = max(bounds.extents.y, 0.01)

                // モデルの中心を原点に合わせ、拡大・回転がぶれないようにする。
                let center = (bounds.min + bounds.max) / 2
                loaded.position = -center

                let container = ModelEntity()
                container.addChild(loaded)
                container.orientation = simd_quatf(angle: asset.modelYawDegrees * .pi / 180, axis: [0, 1, 0])
                entity = container
            } else {
                let imageURL = try CharacterImageStore.url(for: asset.cutoutImageFileName, kind: .cutout)
                let texture = try brightenedColorTexture(
                    contentsOf: imageURL,
                    name: asset.id.uuidString,
                    brightnessMultiplier: asset.arBrightnessMultiplier
                )

                let aspectRatio = max(0.25, min(4.0, Float(texture.width) / Float(max(texture.height, 1))))
                let mesh = MeshResource.generatePlane(width: aspectRatio, height: 1.0)

                var material = UnlitMaterial(texture: texture)
                material.blending = .transparent(opacity: 1.0)
                material.opacityThreshold = 0.01
                material.faceCulling = .none

                entity = ModelEntity(mesh: mesh, materials: [material])
                divisor = 1.0
                unscaledHeight = 1.0
            }

            entity.name = asset.name
            let scale = asset.defaultSizeMeters / divisor
            entity.scale = SIMD3<Float>(repeating: scale)
            // 顔トラッキングでは肩そのものは取れないため、顔アンカーから肩寄りの固定位置へ置く。
            entity.position = selfiePosition(scaledHeight: unscaledHeight * scale)
            entity.generateCollisionShapes(recursive: true)

            let anchor = AnchorEntity(.face)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            arView.installGestures([.translation, .rotation, .scale], for: entity)
            startIdleAnimation(for: entity)

            selfieScaleDivisor = divisor
            selfieUnscaledHeight = unscaledHeight

            return PlacedCharacter(
                anchor: anchor,
                entity: entity,
                name: asset.name,
                baseScale: entity.scale,
                yawCorrectionDegrees: asset.modelYawDegrees,
                selectionMarker: Entity()
            )
        }

        private func selfiePosition(scaledHeight: Float) -> SIMD3<Float> {
            let shoulderLineY: Float = -0.10
            return [0.18, shoulderLineY + scaledHeight * 0.45, 0.035]
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

            guard !isPlacing else {
                return
            }

            isPlacing = true
            let asset = selectedAsset
            onStatus("\(asset.name)を読み込み中…")

            place(asset, at: result, in: arView) { [weak self] outcome in
                guard let self else {
                    return
                }
                self.isPlacing = false

                switch outcome {
                case .success(let placement):
                    self.selectPlacement(placement)
                    self.onStatus("\(placement.name)を配置しました。")
                case .failure(let error):
                    self.onStatus(error.localizedDescription)
                }
            }
        }

        func capture(in arView: ARView) {
            let marker = selectedPlacement?.selectionMarker
            let wasMarkerEnabled = marker?.isEnabled ?? false
            marker?.isEnabled = false

            // 配置レティクルも写真に写り込まないよう、撮影の間だけ抑制する。
            suppressReticle = true
            setReticleVisible(false)

            // isEnabled=false の変更が描画へ反映されるのは次のレンダリング更新のため、
            // ここで即 snapshot すると選択枠が写り込むことがある（特にモデル配置直後）。
            // 次の SceneEvents.Update を一度だけ待ってから撮影し、枠が確実に消えた状態を撮る。
            var subscription: Cancellable?
            subscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                subscription?.cancel()
                subscription = nil

                arView.snapshot(saveToHDR: false) { [weak self] image in
                    marker?.isEnabled = wasMarkerEnabled

                    guard let self else {
                        return
                    }
                    self.suppressReticle = false

                    guard let image else {
                        self.onCapture(.failure(ARCaptureError.snapshotFailed))
                        return
                    }

                    self.onCapture(.success(image))
                }
            }
        }

        // MARK: - 配置レティクル

        /// ARView破棄時に毎フレーム購読を止める。
        func tearDown() {
            sceneUpdateSubscription?.cancel()
            sceneUpdateSubscription = nil
            placementTask?.cancel()
            placementTask = nil
        }

        /// 毎フレーム画面中央から平面へレイキャストし、レティクルを吸着させる。
        /// 着地点を常に示すため毎回の配置で表示し、自撮り・録画中・撮影中・
        /// コーチング中・配置処理中だけ隠す（写真・動画には写さない）。
        private func updateReticle(in arView: ARView) {
            guard !isSelfieMode,
                  !isRecording,
                  !suppressReticle,
                  !isPlacing,
                  !isCoachingActive.wrappedValue,
                  selectedAsset != nil else {
                setReticleVisible(false)
                return
            }

            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let result = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .any).first else {
                setReticleVisible(false)
                return
            }

            reticleEntity?.setTransformMatrix(result.worldTransform, relativeTo: nil)
            setReticleVisible(true)
        }

        private func setReticleVisible(_ visible: Bool) {
            if reticleEntity?.isEnabled != visible {
                reticleEntity?.isEnabled = visible
            }
        }

        /// 検出面に水平に寝かせる白いリング＋中心点。
        /// 配置済みの選択リング（makeSelectionMarker）と同じ白で見た目を揃え、
        /// 「狙い→着地」の連続性を出す。
        private func makeReticle() -> Entity {
            let ringColor = UIColor.white
            var material = UnlitMaterial(color: ringColor.withAlphaComponent(0.9))
            material.blending = .transparent(opacity: 0.9)
            material.faceCulling = .none

            let reticle = Entity()
            reticle.name = "placement-reticle"
            reticle.isEnabled = false

            let radius: Float = 0.09
            let lineThickness: Float = 0.012
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
                reticle.addChild(segment)
            }

            // 中心点（平らな円盤）で正確な着地位置を示す。
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [material])
            dot.scale = [radius * 0.3, lineHeight, radius * 0.3]
            reticle.addChild(dot)

            return reticle
        }

        private func place(
            _ asset: CharacterARAsset,
            at result: ARRaycastResult,
            in arView: ARView,
            completion: @escaping (Result<PlacedCharacter, Error>) -> Void
        ) {
            applySceneLighting(for: asset, in: arView)

            if let modelFileName = asset.modelFileName {
                placeModel(asset, modelFileName: modelFileName, at: result, in: arView, completion: completion)
            } else {
                // 写真切り抜きは軽量なので同期のまま実行し、結果をコールバックへ渡す。
                completion(Result { try placeCutout(asset, at: result, in: arView) })
            }
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
            selectedPlacementID = nil
            selectedPlacementName.wrappedValue = nil
            updateSelectionMarkerVisibility()
        }

        private var selectedPlacement: PlacedCharacter? {
            guard let selectedPlacementID else {
                return nil
            }

            return placements.first { $0.id == selectedPlacementID }
        }

        private func placeCutout(_ asset: CharacterARAsset, at result: ARRaycastResult, in arView: ARView) throws -> PlacedCharacter {
            let imageURL = try CharacterImageStore.url(for: asset.cutoutImageFileName, kind: .cutout)
            let texture = try brightenedColorTexture(
                contentsOf: imageURL,
                name: asset.id.uuidString,
                brightnessMultiplier: asset.arBrightnessMultiplier
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
            in arView: ARView,
            completion: @escaping (Result<PlacedCharacter, Error>) -> Void
        ) {
            let modelURL: URL
            do {
                modelURL = try CharacterImageStore.modelURL(for: modelFileName)
            } catch {
                completion(.failure(error))
                return
            }

            // 同期ロードはメインスレッドを固めるため、ロード中は isPlacing ガードで追加タップを無視する。
            placementTask = Task { [weak self] in
                do {
                    let entity = try await ModelEntity(contentsOf: modelURL, withName: asset.id.uuidString)
                    guard !Task.isCancelled, let self else {
                        return
                    }

                    self.placementTask = nil
                    let placement = self.assemblePlacement(entity, asset: asset, at: result, in: arView)
                    completion(.success(placement))
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }

                    self?.placementTask = nil
                    completion(.failure(error))
                }
            }
        }

        /// ロード済みの ModelEntity を整え、シーンへ配置して PlacedCharacter を返す。
        private func assemblePlacement(
            _ entity: ModelEntity,
            asset: CharacterARAsset,
            at result: ARRaycastResult,
            in arView: ARView
        ) -> PlacedCharacter {
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
            // USDZは子Entity側にメッシュを持つことがあるため、階層全体に接地影を付ける。
            applyGroundingShadow(to: entity)

            let selectionMarker = makeSelectionMarker(width: width * 1.08, depth: depth * 1.08, baseY: baseY)
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
                yawCorrectionDegrees: asset.modelYawDegrees,
                selectionMarker: selectionMarker
            )
            placements.append(placement)
            return placement
        }

        private func applyGroundingShadow(to entity: Entity) {
            entity.components.set(
                GroundingShadowComponent(
                    castsShadow: true,
                    receivesShadow: true,
                    fadeBehaviorNearPhysicalObjects: .constant
                )
            )

            for child in entity.children {
                applyGroundingShadow(to: child)
            }
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
            selectedPlacementID = placement.id
            selectedPlacementName.wrappedValue = placement.name
            updateSelectionMarkerVisibility()
        }

        private func updateSelectionMarkerVisibility() {
            placements.forEach { placement in
                placement.selectionMarker.isEnabled = !isRecording && placement.id == selectedPlacementID
            }
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

        // MARK: - 明るさ補正

        /// 推し詳細の「明るさ」が100%の時に使う3Dモデル向け環境光の強さ。
        private static let baseModelLightingIntensityExponent: Float = 1.9
        /// 推し詳細の「明るさ」が100%の時に使う写真切り抜き向け露出補正値（EV）。
        private static let baseCutoutExposureBoost: Float = 0.8
        private static let brightnessMultiplierRange: ClosedRange<Float> = 0.6...1.6
        private static let imageContext = CIContext()

        func updateSceneLighting(in arView: ARView) {
            applySceneLighting(for: selectedAsset, in: arView)
        }

        private func applySceneLighting(for asset: CharacterARAsset?, in arView: ARView) {
            let multiplier = Self.normalizedBrightnessMultiplier(asset?.arBrightnessMultiplier ?? 1)
            arView.environment.lighting.intensityExponent = Self.baseModelLightingIntensityExponent * multiplier
        }

        private static func normalizedBrightnessMultiplier(_ multiplier: Float) -> Float {
            min(max(multiplier, brightnessMultiplierRange.lowerBound), brightnessMultiplierRange.upperBound)
        }

        /// 切り抜き画像を露出補正してからテクスチャ化する。補正に失敗した場合は元画像をそのまま読み込む。
        private func brightenedColorTexture(
            contentsOf url: URL,
            name: String,
            brightnessMultiplier: Float
        ) throws -> TextureResource {
            let options = TextureResource.CreateOptions(semantic: .color, mipmapsMode: .allocateAndGenerateAll)
            let exposureBoost = Self.baseCutoutExposureBoost * Self.normalizedBrightnessMultiplier(brightnessMultiplier)

            guard exposureBoost != 0,
                  let source = UIImage(contentsOfFile: url.path)?.cgImage else {
                return try TextureResource.load(contentsOf: url, withName: name, options: options)
            }

            let ciImage = CIImage(cgImage: source)
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = ciImage
            filter.ev = exposureBoost

            guard let output = filter.outputImage,
                  let adjusted = Self.imageContext.createCGImage(output, from: ciImage.extent) else {
                return try TextureResource.load(contentsOf: url, withName: name, options: options)
            }

            return try TextureResource(image: adjusted, withName: name, options: options)
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
            // アプリアイコンに合わせ、白で足元に丸いリングを描き、選択中を柔らかく示す。
            let ringColor = UIColor.white
            var material = UnlitMaterial(color: ringColor.withAlphaComponent(0.85))
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
