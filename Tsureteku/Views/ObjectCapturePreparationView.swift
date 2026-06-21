//
//  ObjectCapturePreparationView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import Combine
import RealityKit
import SwiftData
import SwiftUI
import UIKit

struct ObjectCapturePreparationView: View {
    @Bindable var character: ToyCharacter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if ObjectCaptureSession.isSupported {
                tutorialContent
            } else {
                unsupportedContent
            }
        }
        .navigationTitle("3D撮影の準備")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ObjectCaptureSession.isSupported {
                startFooter
            }
        }
    }

    private var tutorialContent: some View {
        List {
            Section {
                header
            }

            Section("始める前に") {
                PreparationChecklistRow(
                    iconName: "light.max",
                    title: "明るい場所に置く",
                    description: "影が強すぎない場所で、推し全体が見えるようにします。"
                )

                PreparationChecklistRow(
                    iconName: "hand.raised",
                    title: "推しは動かさない",
                    description: "撮影中は本体を固定し、iPhoneだけをゆっくり動かします。"
                )

                PreparationChecklistRow(
                    iconName: "photo.stack",
                    title: "20枚以上撮る",
                    description: "少ない枚数では3Dモデル作成に進めません。角度を変えて一周撮ります。"
                )
            }

            Section("撮影の流れ") {
                CaptureTutorialStepRow(
                    number: 1,
                    title: "推しを認識",
                    description: "画面内に全体を入れて、対象を検出します。"
                )

                CaptureTutorialStepRow(
                    number: 2,
                    title: "周りを撮影",
                    description: "推しの周囲をゆっくり回りながら、正面と側面を撮ります。"
                )

                CaptureTutorialStepRow(
                    number: 3,
                    title: "3Dモデルを作成",
                    description: "撮影データからUSDZモデルを作り、AR配置で使えるようにします。"
                )
            }

            Section("うまく作るコツ") {
                PreparationChecklistRow(
                    iconName: "arrow.triangle.2.circlepath.camera",
                    title: "急に動かさない",
                    description: "iPhoneを速く振ると追跡が不安定になります。少しずつ角度を変えます。"
                )

                PreparationChecklistRow(
                    iconName: "square.grid.3x3",
                    title: "背景と少し離す",
                    description: "壁や床と近すぎると形を拾いにくくなります。周りに少し余白を作ります。"
                )

                PreparationChecklistRow(
                    iconName: "sparkles",
                    title: "透明・光沢は苦手",
                    description: "反射する素材や透明パーツは、3D化すると崩れることがあります。"
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            CharacterThumbnailView(character: character)
                .frame(width: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text(character.name)
                    .font(.title3.weight(.semibold))

                Text("撮影画面に進むとカメラが起動します。まず置き方と撮り方を確認してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var startFooter: some View {
        VStack(spacing: 8) {
            NavigationLink {
                // 作成成功時はこの準備画面ごと閉じ、その上の撮影画面も一緒に閉じて詳細画面へ戻す。
                ObjectCaptureWorkflowView(character: character, onModelCreated: { dismiss() })
            } label: {
                Label("撮影を始める", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("撮影中は推しを固定し、iPhoneを動かします。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var unsupportedContent: some View {
        ContentUnavailableView {
            Label("3D撮影はこの端末では使えません", systemImage: "iphone.slash")
        } description: {
            Text("Object Capture対応iPhoneの実機で開いてください。USDZの登録はこのまま利用できます。")
        }
    }
}

struct NewObjectCaptureCharacterView: View {
    @Environment(\.modelContext) private var modelContext

    let characterName: String
    let defaultSizeMeters: Double
    var onCharacterCreated: () -> Void = {}

    @StateObject private var draftStore = ObjectCaptureDraftCharacterStore()
    @State private var isWorkflowActive = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if ObjectCaptureSession.isSupported {
                tutorialContent
            } else {
                unsupportedContent
            }
        }
        .navigationTitle("3D撮影の準備")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if ObjectCaptureSession.isSupported {
                startFooter
            }
        }
        .navigationDestination(isPresented: $isWorkflowActive) {
            if let character = draftStore.character {
                ObjectCaptureWorkflowView(
                    character: character,
                    onModelCreated: { commitDraftCharacter() },
                    onFlowDiscarded: { draftStore.cleanupIfNeeded() }
                )
            } else {
                ContentUnavailableView {
                    Label("撮影を開始できません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("一度戻ってから、もう一度3D撮影を開始してください。")
                }
            }
        }
        .onChange(of: isWorkflowActive) { _, isActive in
            if !isActive {
                draftStore.cleanupIfNeeded()
            }
        }
        .onDisappear {
            if !isWorkflowActive {
                draftStore.cleanupIfNeeded()
            }
        }
    }

    private var tutorialContent: some View {
        List {
            Section {
                header
            }

            Section("始める前に") {
                PreparationChecklistRow(
                    iconName: "light.max",
                    title: "明るい場所に置く",
                    description: "影が強すぎない場所で、推し全体が見えるようにします。"
                )

                PreparationChecklistRow(
                    iconName: "hand.raised",
                    title: "推しは動かさない",
                    description: "撮影中は本体を固定し、iPhoneだけをゆっくり動かします。"
                )

                PreparationChecklistRow(
                    iconName: "photo.stack",
                    title: "20枚以上撮る",
                    description: "少ない枚数では3Dモデル作成に進めません。角度を変えて一周撮ります。"
                )
            }

            Section("撮影の流れ") {
                CaptureTutorialStepRow(
                    number: 1,
                    title: "推しを認識",
                    description: "画面内に全体を入れて、対象を検出します。"
                )

                CaptureTutorialStepRow(
                    number: 2,
                    title: "周りを撮影",
                    description: "推しの周囲をゆっくり回りながら、正面と側面を撮ります。"
                )

                CaptureTutorialStepRow(
                    number: 3,
                    title: "推しとして登録",
                    description: "作成した3Dモデルを、そのまま新しい推しとして保存します。"
                )
            }

            Section("うまく作るコツ") {
                PreparationChecklistRow(
                    iconName: "arrow.triangle.2.circlepath.camera",
                    title: "急に動かさない",
                    description: "iPhoneを速く振ると追跡が不安定になります。少しずつ角度を変えます。"
                )

                PreparationChecklistRow(
                    iconName: "square.grid.3x3",
                    title: "背景と少し離す",
                    description: "壁や床と近すぎると形を拾いにくくなります。周りに少し余白を作ります。"
                )

                PreparationChecklistRow(
                    iconName: "sparkles",
                    title: "透明・光沢は苦手",
                    description: "反射する素材や透明パーツは、3D化すると崩れることがあります。"
                )
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 104, height: 104)

                Image(systemName: "cube.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(characterName)
                    .font(.title3.weight(.semibold))

                Text("写真登録をせずに、3D撮影から新しい推しを作成します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var startFooter: some View {
        VStack(spacing: 8) {
            Button(action: startObjectCapture) {
                Label("撮影を始める", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("撮影完了後に3Dモデルを作成すると、推しとして登録されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var unsupportedContent: some View {
        ContentUnavailableView {
            Label("3D撮影はこの端末では使えません", systemImage: "iphone.slash")
        } description: {
            Text("Object Capture対応iPhoneの実機で開いてください。")
        }
    }

    private func startObjectCapture() {
        do {
            _ = try draftStore.prepareCharacter(
                name: characterName,
                defaultSizeMeters: defaultSizeMeters
            )
            errorMessage = nil
            isWorkflowActive = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitDraftCharacter() {
        do {
            try draftStore.commit(into: modelContext)
            onCharacterCreated()
        } catch {
            errorMessage = error.localizedDescription
            isWorkflowActive = false
        }
    }
}

private struct PreparationChecklistRow: View {
    let iconName: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CaptureTutorialStepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

@MainActor
private final class ObjectCaptureDraftCharacterStore: ObservableObject {
    @Published private(set) var character: ToyCharacter?

    private var didCommit = false

    func prepareCharacter(name: String, defaultSizeMeters: Double) throws -> ToyCharacter {
        if let character {
            return character
        }

        var originalFileName: String?

        do {
            let placeholderImage = ObjectCapturePlaceholderImageFactory.makeImage()
            let savedOriginalFileName = try CharacterImageStore.save(placeholderImage, kind: .original)
            originalFileName = savedOriginalFileName
            let savedCutoutFileName = try CharacterImageStore.save(placeholderImage, kind: .cutout)
            let now = Date()
            let character = ToyCharacter(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                originalImageFileName: savedOriginalFileName,
                cutoutImageFileName: savedCutoutFileName,
                defaultSizeMeters: defaultSizeMeters,
                createdAt: now,
                updatedAt: now
            )

            self.character = character
            return character
        } catch {
            if let originalFileName {
                CharacterImageStore.deleteIfExists(fileName: originalFileName, kind: .original)
            }
            throw error
        }
    }

    func commit(into modelContext: ModelContext) throws {
        guard let character else {
            return
        }

        modelContext.insert(character)
        try modelContext.save()
        didCommit = true
    }

    func cleanupIfNeeded() {
        guard !didCommit, let character else {
            return
        }

        CharacterImageStore.deleteIfExists(fileName: character.originalImageFileName, kind: .original)
        CharacterImageStore.deleteIfExists(fileName: character.cutoutImageFileName, kind: .cutout)
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: character.objectCaptureDirectoryName)
        self.character = nil
    }
}

private enum ObjectCapturePlaceholderImageFactory {
    static func makeImage() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let configuration = UIImage.SymbolConfiguration(pointSize: 190, weight: .semibold)
            let symbol = UIImage(systemName: "cube.fill", withConfiguration: configuration)?
                .withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
            let symbolSize = CGSize(width: 230, height: 230)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )

            symbol?.draw(in: CGRect(origin: symbolOrigin, size: symbolSize))
        }
    }
}

#Preview {
    NavigationStack {
        ObjectCapturePreparationView(
            character: ToyCharacter(
                name: "推し",
                originalImageFileName: "preview-original.png",
                cutoutImageFileName: "preview-cutout.png"
            )
        )
    }
    .modelContainer(for: ToyCharacter.self, inMemory: true)
}
