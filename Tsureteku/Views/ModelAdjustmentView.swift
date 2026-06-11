//
//  ModelAdjustmentView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import RealityKit
import SwiftData
import SwiftUI
import UIKit

struct ModelAdjustmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var character: ToyCharacter

    private var modelURL: URL? {
        guard let modelFileName = character.modelFileName else {
            return nil
        }

        return try? CharacterImageStore.modelURL(for: modelFileName)
    }

    var body: some View {
        Form {
            Section {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets())
            }

            Section("AR表示") {
                HStack {
                    Text("サイズ")
                    Slider(value: $character.defaultSizeMeters, in: 0.12...1.2)
                        .onChange(of: character.defaultSizeMeters) { _, _ in
                            save()
                        }

                    Text("\(Int(character.defaultSizeMeters * 100))cm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Text("向き")
                    Slider(value: $character.modelYawDegrees, in: -180...180, step: 5)
                        .onChange(of: character.modelYawDegrees) { _, _ in
                            save()
                        }

                    Text("\(Int(character.modelYawDegrees))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                HStack {
                    Text("上下")
                    Slider(value: $character.modelVerticalOffsetMeters, in: -0.2...0.2, step: 0.01)
                        .onChange(of: character.modelVerticalOffsetMeters) { _, _ in
                            save()
                        }

                    Text("\(Int(character.modelVerticalOffsetMeters * 100))cm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Button {
                    resetAdjustments()
                } label: {
                    Label("調整をリセット", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("3Dモデル調整")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack(alignment: .bottom) {
            Color(.secondarySystemGroupedBackground)

            if let modelURL {
                ModelPreview3DView(
                    modelURL: modelURL,
                    modelSizeMeters: character.defaultSizeMeters,
                    yawDegrees: character.modelYawDegrees,
                    verticalOffsetMeters: character.modelVerticalOffsetMeters
                )
            } else {
                ContentUnavailableView {
                    Label("3Dモデルなし", systemImage: "cube.transparent")
                }
            }

            FloorGridView()
                .frame(height: 108)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
        }
    }

    private func resetAdjustments() {
        character.modelYawDegrees = 0
        character.modelVerticalOffsetMeters = 0
        save()
    }

    private func save() {
        character.updatedAt = Date()
        try? modelContext.save()
    }
}

private struct FloorGridView: View {
    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else {
                return
            }

            let horizonY = size.height * 0.12
            let bottomY = size.height
            let centerX = size.width / 2
            let farHalfWidth = size.width * 0.12
            let nearHalfWidth = size.width * 0.48
            let lineColor = Color.secondary.opacity(0.18)

            for index in 0...8 {
                let progress = CGFloat(index) / 8
                let perspectiveProgress = CGFloat(pow(Double(progress), 1.75))
                let y = horizonY + (bottomY - horizonY) * perspectiveProgress
                let halfWidth = farHalfWidth + (nearHalfWidth - farHalfWidth) * perspectiveProgress

                var path = Path()
                path.move(to: CGPoint(x: centerX - halfWidth, y: y))
                path.addLine(to: CGPoint(x: centerX + halfWidth, y: y))
                context.stroke(path, with: .color(lineColor), lineWidth: index == 0 ? 1.2 : 0.8)
            }

            for index in -4...4 {
                let ratio = CGFloat(index) / 4
                var path = Path()
                path.move(to: CGPoint(x: centerX + farHalfWidth * ratio, y: horizonY))
                path.addLine(to: CGPoint(x: centerX + nearHalfWidth * ratio, y: bottomY))
                context.stroke(path, with: .color(lineColor), lineWidth: index == 0 ? 1.1 : 0.75)
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.8), location: 0.18),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ModelPreview3DView: UIViewRepresentable {
    let modelURL: URL
    let modelSizeMeters: Double
    let yawDegrees: Double
    let verticalOffsetMeters: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.isOpaque = true
        arView.backgroundColor = .secondarySystemGroupedBackground
        arView.environment.background = .color(.secondarySystemGroupedBackground)
        context.coordinator.configure(arView)
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.update(
            modelURL: modelURL,
            modelSizeMeters: modelSizeMeters,
            yawDegrees: yawDegrees,
            verticalOffsetMeters: verticalOffsetMeters
        )
    }

    final class Coordinator {
        private let anchor = AnchorEntity(world: .zero)
        private let camera = PerspectiveCamera()
        private var modelEntity: Entity?
        private var loadedModelURL: URL?
        private var normalizedPreviewScale: Float = 1
        private var modelCenterY: Float = 0

        func configure(_ arView: ARView) {
            arView.renderOptions.insert(.disableMotionBlur)
            arView.scene.addAnchor(anchor)

            camera.position = [0, 0.12, 1.8]
            camera.look(at: [0, 0.08, 0], from: camera.position, relativeTo: nil)
            anchor.addChild(camera)

            let light = DirectionalLight()
            light.light.intensity = 1_700
            light.orientation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
            anchor.addChild(light)
        }

        func update(modelURL: URL, modelSizeMeters: Double, yawDegrees: Double, verticalOffsetMeters: Double) {
            if loadedModelURL != modelURL {
                loadModel(from: modelURL)
            }

            applyTransform(
                modelSizeMeters: modelSizeMeters,
                yawDegrees: yawDegrees,
                verticalOffsetMeters: verticalOffsetMeters
            )
        }

        private func loadModel(from modelURL: URL) {
            modelEntity?.removeFromParent()
            loadedModelURL = nil

            guard let entity = try? Entity.load(contentsOf: modelURL) else {
                modelEntity = nil
                return
            }

            let bounds = entity.visualBounds(recursive: true, relativeTo: entity)
            let maxExtent = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
            normalizedPreviewScale = maxExtent > 0 ? 0.82 / maxExtent : 1
            modelCenterY = (bounds.min.y + bounds.max.y) / 2

            anchor.addChild(entity)
            modelEntity = entity
            loadedModelURL = modelURL
        }

        private func applyTransform(modelSizeMeters: Double, yawDegrees: Double, verticalOffsetMeters: Double) {
            guard let modelEntity else {
                return
            }

            let sizeScale = max(0.25, min(3.5, Float(modelSizeMeters / 0.34)))
            let previewScale = normalizedPreviewScale * sizeScale
            modelEntity.scale = SIMD3<Float>(repeating: previewScale)
            modelEntity.orientation = simd_quatf(angle: Float(yawDegrees) * .pi / 180, axis: [0, 1, 0])
            modelEntity.position = [
                0,
                -(modelCenterY * previewScale) + Float(verticalOffsetMeters) * 1.6,
                0
            ]
        }
    }
}

#Preview {
    NavigationStack {
        ModelAdjustmentView(
            character: ToyCharacter(
                name: "ぬいぐるみ",
                originalImageFileName: "preview-original.png",
                cutoutImageFileName: "preview-cutout.png",
                modelFileName: "preview.usdz"
            )
        )
    }
    .modelContainer(for: ToyCharacter.self, inMemory: true)
}
