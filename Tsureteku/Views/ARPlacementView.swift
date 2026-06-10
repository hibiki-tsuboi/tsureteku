//
//  ARPlacementView.swift
//  Tsureteku
//
//  Phase 1 prototype: place a registered companion as a billboard sprite on a
//  horizontal plane via ARKit + RealityKit, and capture the AR scene as a
//  photo to the user's library.
//

import ARKit
import Combine
import Photos
import RealityKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class ARSessionController: ObservableObject {
    @Published var statusMessage: String = "床の上をタップしてキャラを置く"
    @Published var isFlashing: Bool = false
    @Published var selectedCompanionID: PersistentIdentifier?

    var companions: [Companion] = [] {
        didSet {
            if selectedCompanionID == nil, let first = companions.first {
                selectedCompanionID = first.persistentModelID
            }
        }
    }

    var captureHandler: (() -> Void)?

    var selectedCompanion: Companion? {
        if let selectedCompanionID,
           let match = companions.first(where: { $0.persistentModelID == selectedCompanionID }) {
            return match
        }
        return companions.first
    }

    func capture() { captureHandler?() }

    func triggerFlash() {
        isFlashing = true
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            isFlashing = false
        }
    }
}

struct ARPlacementView: View {
    let companions: [Companion]

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = ARSessionController()

    var body: some View {
        ZStack {
            ARContainer(controller: controller, companions: companions)
                .ignoresSafeArea()

            Color.white
                .opacity(controller.isFlashing ? 0.85 : 0)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.16), value: controller.isFlashing)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("閉じる", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                Spacer()
                Text(controller.statusMessage)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)

                if !companions.isEmpty {
                    carousel
                        .padding(.bottom, 8)
                }

                shutterButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }

    private var shutterButton: some View {
        Button {
            controller.capture()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
            }
        }
        .accessibilityLabel("撮影")
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(companions) { companion in
                    thumbnailButton(for: companion)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func thumbnailButton(for companion: Companion) -> some View {
        let isSelected = controller.selectedCompanion?.persistentModelID == companion.persistentModelID
        return Button {
            controller.selectedCompanionID = companion.persistentModelID
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.background.opacity(isSelected ? 0.7 : 0.25))
                if let ui = UIImage(data: companion.imageData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                }
            }
            .frame(width: 60, height: 60)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(companion.name)
    }
}

private struct ARContainer: UIViewRepresentable {
    let controller: ARSessionController
    let companions: [Companion]

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        config.environmentTexturing = .automatic
        arView.session.run(config)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tap)

        controller.companions = companions
        context.coordinator.attach(to: arView, controller: controller)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        controller.companions = companions
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var arView: ARView?
        private weak var controller: ARSessionController?
        private var placedEntities: [Entity] = []
        private var updateSubscription: Cancellable?

        // User-applied roll around the entity's local +Z (its facing axis after
        // the yaw billboard), per entity id. Re-applied each frame on top of
        // the camera-facing orientation.
        private var userRoll: [UInt64: Float] = [:]

        // Transient gesture state.
        private var pinchTarget: Entity?
        private var pinchBaseScale: Float = 1
        private var rotationTarget: Entity?
        private var rotationBaseRoll: Float = 0
        private var panTarget: Entity?
        private var panAnchor: Entity?

        func attach(to arView: ARView, controller: ARSessionController) {
            self.arView = arView
            self.controller = controller

            controller.captureHandler = { [weak self] in
                self?.captureSnapshot()
            }

            let pinch = UIPinchGestureRecognizer(
                target: self, action: #selector(handlePinch(_:))
            )
            let rotation = UIRotationGestureRecognizer(
                target: self, action: #selector(handleRotation(_:))
            )
            let pan = UIPanGestureRecognizer(
                target: self, action: #selector(handlePan(_:))
            )
            // Single-finger drag — 2-finger pan is reserved for pinch/rotation.
            pan.maximumNumberOfTouches = 1
            pinch.delegate = self
            rotation.delegate = self
            pan.delegate = self
            arView.addGestureRecognizer(pinch)
            arView.addGestureRecognizer(rotation)
            arView.addGestureRecognizer(pan)

            updateSubscription = arView.scene.subscribe(
                to: SceneEvents.Update.self
            ) { [weak self] _ in
                self?.alignBillboards()
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow only pinch + rotation to run together (so the user can
            // scale and rotate in one continuous motion). Pan stays exclusive
            // — it's single-finger and shouldn't fire alongside multi-finger
            // manipulation.
            func isMultiTouchManip(_ g: UIGestureRecognizer) -> Bool {
                g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer
            }
            return isMultiTouchManip(gestureRecognizer)
                && isMultiTouchManip(otherGestureRecognizer)
        }

        // MARK: - Tap to place

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = gesture.location(in: arView)
            // Skip placement if the tap lands on an already-placed entity so
            // the user doesn't accidentally drop a duplicate while trying to
            // manipulate one.
            if arView.entity(at: location) != nil { return }

            guard let companion = controller?.selectedCompanion else {
                controller?.statusMessage = "先にキャラを登録してください"
                return
            }
            guard let result = arView.raycast(
                from: location,
                allowing: .estimatedPlane,
                alignment: .horizontal
            ).first else {
                controller?.statusMessage = "床が検出できませんでした。少し動かしてもう一度"
                return
            }

            let anchor = AnchorEntity(world: result.worldTransform)
            let entity = makeBillboardEntity(for: companion)
            entity.generateCollisionShapes(recursive: false)
            // Position so the bottom edge sits on the detected plane.
            entity.position.y = currentBillboardHeight(for: companion) / 2
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            placedEntities.append(entity)
            controller?.statusMessage = "ドラッグで移動 / 二本指で拡大・回転 / シャッターで撮影"
        }

        // MARK: - Pinch / rotate

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let arView else { return }
            switch gesture.state {
            case .began:
                let pt = gesture.location(in: arView)
                guard let target = arView.entity(at: pt),
                      placedEntities.contains(where: { $0 === target }) else { return }
                pinchTarget = target
                pinchBaseScale = target.scale.x
            case .changed:
                guard let target = pinchTarget else { return }
                let scale = max(0.2, min(4.0, pinchBaseScale * Float(gesture.scale)))
                target.scale = SIMD3(repeating: scale)
            case .ended, .cancelled, .failed:
                pinchTarget = nil
            default:
                break
            }
        }

        @objc func handleRotation(_ gesture: UIRotationGestureRecognizer) {
            guard let arView else { return }
            switch gesture.state {
            case .began:
                let pt = gesture.location(in: arView)
                guard let target = arView.entity(at: pt),
                      placedEntities.contains(where: { $0 === target }) else { return }
                rotationTarget = target
                rotationBaseRoll = userRoll[target.id] ?? 0
            case .changed:
                guard let target = rotationTarget else { return }
                // Two-finger CCW gesture has positive `rotation` (UIKit convention),
                // and a positive quaternion rotation around local +Z is CCW from
                // the camera's POV after look(at:) — so the two agree directly.
                userRoll[target.id] = rotationBaseRoll + Float(gesture.rotation)
            case .ended, .cancelled, .failed:
                rotationTarget = nil
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let arView else { return }
            switch gesture.state {
            case .began:
                let pt = gesture.location(in: arView)
                guard let target = arView.entity(at: pt),
                      placedEntities.contains(where: { $0 === target }),
                      let anchor = target.parent else { return }
                panTarget = target
                panAnchor = anchor
            case .changed:
                guard let anchor = panAnchor else { return }
                let pt = gesture.location(in: arView)
                guard let result = arView.raycast(
                    from: pt,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                ).first else { return }
                let t = result.worldTransform.columns.3
                // Anchor's local position == world position (it's a scene-root
                // child). Entity's local Y offset is preserved, so the bottom
                // edge re-aligns to whatever floor the raycast hit.
                anchor.position = SIMD3<Float>(t.x, t.y, t.z)
            case .ended, .cancelled, .failed:
                panTarget = nil
                panAnchor = nil
            default:
                break
            }
        }

        // MARK: - Capture

        private func captureSnapshot() {
            guard let arView else { return }
            guard !placedEntities.isEmpty else {
                controller?.statusMessage = "先にキャラを置いてください"
                return
            }
            controller?.triggerFlash()
            arView.snapshot(saveToHDR: false) { [weak self] image in
                guard let self else { return }
                guard let image else {
                    self.controller?.statusMessage = "撮影に失敗しました"
                    return
                }
                self.saveToPhotos(image)
            }
        }

        private func saveToPhotos(_ image: UIImage) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                guard status == .authorized || status == .limited else {
                    Task { @MainActor [weak self] in
                        self?.controller?.statusMessage = "写真への保存が許可されていません"
                    }
                    return
                }
                PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                } completionHandler: { success, _ in
                    Task { @MainActor [weak self] in
                        self?.controller?.statusMessage = success
                            ? "写真に保存しました"
                            : "保存に失敗しました"
                    }
                }
            }
        }

        // MARK: - Billboard maintenance

        private func alignBillboards() {
            guard let frame = arView?.session.currentFrame else { return }
            let cameraPos = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            for entity in placedEntities {
                let entityPos = entity.position(relativeTo: nil)
                var lookDir = entityPos - cameraPos
                lookDir.y = 0  // yaw only — keep upright
                guard simd_length(lookDir) > 1e-4 else { continue }
                let mirror = entityPos + lookDir
                // look(at:) orients -Z toward target; plane's visible face is +Z,
                // so aiming at the mirrored point makes the front face the camera.
                // Scale is preserved by look(at:), so pinch-applied scale survives.
                entity.look(at: mirror, from: entityPos, relativeTo: nil)

                // Layer the user's roll on top in local space (around +Z, which
                // is the entity's facing axis once the look-at runs).
                if let roll = userRoll[entity.id], roll != 0 {
                    let rollQuat = simd_quatf(angle: roll, axis: SIMD3<Float>(0, 0, 1))
                    entity.orientation = entity.orientation * rollQuat
                }
            }
        }

        // MARK: - Entity construction

        // ~20cm long-edge so it reads as a real plushie sitting in the world.
        private let billboardLongEdge: Float = 0.22

        private func currentBillboardHeight(for companion: Companion) -> Float {
            sizeForCompanion(companion).y
        }

        private func sizeForCompanion(_ companion: Companion) -> SIMD2<Float> {
            guard let ui = UIImage(data: companion.imageData) else {
                return SIMD2(billboardLongEdge, billboardLongEdge)
            }
            let aspect = Float(ui.size.width / max(ui.size.height, 1))
            if aspect >= 1 {
                return SIMD2(billboardLongEdge, billboardLongEdge / aspect)
            } else {
                return SIMD2(billboardLongEdge * aspect, billboardLongEdge)
            }
        }

        private func makeBillboardEntity(for companion: Companion) -> ModelEntity {
            let size = sizeForCompanion(companion)
            let mesh = MeshResource.generatePlane(width: size.x, height: size.y)
            let material: any RealityKit.Material = makeMaterial(for: companion)
            return ModelEntity(mesh: mesh, materials: [material])
        }

        private func makeMaterial(for companion: Companion) -> any RealityKit.Material {
            if let ui = UIImage(data: companion.imageData),
               let cg = ui.cgImage,
               let texture = try? TextureResource(image: cg, options: .init(semantic: .color)) {
                var unlit = UnlitMaterial()
                unlit.color = .init(tint: .white, texture: .init(texture))
                // PNG cutouts have an alpha channel — enable alpha blending so
                // the transparent background renders correctly.
                unlit.blending = .transparent(opacity: .init(floatLiteral: 1.0))
                return unlit
            }
            return UnlitMaterial(color: .systemPink)
        }
    }
}

#Preview {
    ARPlacementView(companions: [])
}
