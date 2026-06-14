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
    final class Coordinator: NSObject {
        private weak var arView: ARView?
        private weak var controller: ARSessionController?
        private var placedEntities: [Entity] = []
        private var updateSubscription: Cancellable?

        func attach(to arView: ARView, controller: ARSessionController) {
            self.arView = arView
            self.controller = controller

            controller.captureHandler = { [weak self] in
                self?.captureSnapshot()
            }

            updateSubscription = arView.scene.subscribe(
                to: SceneEvents.Update.self
            ) { [weak self] _ in
                self?.alignBillboards()
            }
        }

        // MARK: - Tap to place

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            guard let companion = controller?.selectedCompanion else {
                controller?.statusMessage = "先にキャラを登録してください"
                return
            }
            let location = gesture.location(in: arView)
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
            // Position so the bottom edge sits on the detected plane.
            entity.position.y = currentBillboardHeight(for: companion) / 2
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)

            placedEntities.append(entity)
            controller?.statusMessage = "置きました。シャッターで一緒に撮影"
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
                entity.look(at: mirror, from: entityPos, relativeTo: nil)
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
