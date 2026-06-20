//
//  AddCharacterView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddCharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingCharacters: [ToyCharacter]

    @State private var characterName = ""
    @State private var sourceImage: UIImage?
    @State private var cutoutImage: UIImage?
    /// 自動切り抜き直後の（境界・余白で削る前の）元画像。スライダー調整はこれを基準にトリミングする。
    @State private var baseCutoutImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    /// 自動切り抜きに失敗したなど、保存自体はできる注意喚起。エラーと区別して控えめに表示する。
    @State private var warningMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isManualTrimPresented = false
    @State private var alphaThreshold = 0.1
    @State private var trimPadding = 0.04
    @State private var defaultSizeMeters = 0.34
    @State private var activeProcessingID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前", text: $characterName)
                }

                Section {
                    VStack(spacing: 14) {
                        preview

                        HStack(spacing: 12) {
                            Button {
                                isCameraPresented = true
                            } label: {
                                Label("撮影", systemImage: "camera")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Label("選択", systemImage: "photo")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if cutoutImage != nil {
                    Section {
                        HStack {
                            Text("境界")
                            Slider(value: $alphaThreshold, in: 0...0.45)
                            Text(alphaThreshold, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }

                        HStack {
                            Text("余白")
                            Slider(value: $trimPadding, in: 0...0.18)
                            Text(trimPadding, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }

                        Button {
                            isManualTrimPresented = true
                        } label: {
                            Label("手動トリミング", systemImage: "crop")
                        }
                        .disabled(isProcessing)
                    } header: {
                        Text("切り抜き")
                    } footer: {
                        Text("「境界」「余白」を動かすと、切り抜き範囲がすぐに変わります。")
                    }

                    Section("AR") {
                        HStack {
                            Text("初期サイズ")
                            Slider(value: $defaultSizeMeters, in: 0.12...1.2)
                            Text("\(Int(defaultSizeMeters * 100))cm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                if let warningMessage {
                    Section {
                        Label(warningMessage, systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("推しを登録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveCharacter)
                        .disabled(!canSave || isProcessing)
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                CameraCaptureView { image in
                    process(image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isManualTrimPresented) {
                if let cutoutImage {
                    ManualTrimView(image: cutoutImage) { trimmedImage in
                        // 手動トリミング後の画像を以降のスライダー調整の基準にし、手動結果が失われないようにする。
                        self.cutoutImage = trimmedImage
                        self.baseCutoutImage = trimmedImage
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else {
                    return
                }

                Task {
                    await loadPhotoItem(newItem)
                }
            }
            .task(id: CutoutTrimSettings(alphaThreshold: alphaThreshold, paddingRatio: trimPadding)) {
                await retrimCutout()
            }
            .onDisappear {
                activeProcessingID = nil
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)
                .frame(height: 260)

            if let cutoutImage {
                Image(uiImage: cutoutImage)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .frame(maxHeight: 260)
            } else if isProcessing {
                ProgressView()
                    .controlSize(.large)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "teddybear")
                        .font(.system(size: 42))
                    Text("推しの写真")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        cutoutImage != nil && sourceImage != nil && !characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadPhotoItem(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "画像を読み込めませんでした。"
                return
            }

            process(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func process(_ image: UIImage) {
        let processingID = UUID()
        activeProcessingID = processingID
        isProcessing = true
        errorMessage = nil
        warningMessage = nil
        sourceImage = nil
        cutoutImage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = CharacterImageProcessor.process(image)

            DispatchQueue.main.async {
                guard activeProcessingID == processingID else {
                    return
                }

                sourceImage = result.sourceImage
                cutoutImage = result.cutoutImage
                baseCutoutImage = result.cutoutImage
                warningMessage = result.warningMessage

                if characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    characterName = defaultCharacterName()
                }

                isProcessing = false
                activeProcessingID = nil
            }
        }
    }

    /// 境界・余白スライダーの変更を、自動切り抜き直後の画像（baseCutoutImage）を基準に
    /// その場でトリミングし直してプレビューへ即時反映する。
    /// `.task(id:)` がスライダー値の変化ごとに前回分を自動キャンセルするため、
    /// 先頭で少し待つことで連続操作中の無駄な再計算を抑える（簡易デバウンス）。
    private func retrimCutout() async {
        guard let baseCutoutImage else {
            return
        }

        try? await Task.sleep(for: .milliseconds(220))
        if Task.isCancelled {
            return
        }

        let alphaThreshold = UInt8(alphaThreshold * 255)
        let paddingRatio = trimPadding

        let trimmedImage = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    returning: ImageCropService.trimTransparentPixels(
                        baseCutoutImage,
                        alphaThreshold: alphaThreshold,
                        paddingRatio: paddingRatio
                    )
                )
            }
        }

        if Task.isCancelled {
            return
        }

        if let trimmedImage {
            cutoutImage = trimmedImage
        }
    }

    /// 「推し」「推し 2」「推し 3」…と重複しない初期名を返す。
    private func defaultCharacterName() -> String {
        let baseName = "推し"
        let existingNames = Set(existingCharacters.map(\.name))

        if !existingNames.contains(baseName) {
            return baseName
        }

        var index = 2
        while existingNames.contains("\(baseName) \(index)") {
            index += 1
        }

        return "\(baseName) \(index)"
    }

    private func saveCharacter() {
        guard let sourceImage, let cutoutImage else {
            return
        }

        var savedOriginalFileName: String?
        var savedCutoutFileName: String?
        var insertedCharacter: ToyCharacter?

        do {
            let originalFileName = try CharacterImageStore.save(sourceImage, kind: .original)
            savedOriginalFileName = originalFileName
            let cutoutFileName = try CharacterImageStore.save(cutoutImage, kind: .cutout)
            savedCutoutFileName = cutoutFileName
            let now = Date()
            let character = ToyCharacter(
                name: characterName.trimmingCharacters(in: .whitespacesAndNewlines),
                originalImageFileName: originalFileName,
                cutoutImageFileName: cutoutFileName,
                defaultSizeMeters: defaultSizeMeters,
                createdAt: now,
                updatedAt: now
            )

            modelContext.insert(character)
            insertedCharacter = character
            try modelContext.save()
            dismiss()
        } catch {
            // 保存に失敗したら、書き出し済みファイルと挿入済みレコードを後始末し、
            // 孤立ファイルや、削除済みファイルを参照する壊れた推しが残らないようにする。
            if let insertedCharacter {
                modelContext.delete(insertedCharacter)
            }
            if let savedOriginalFileName {
                CharacterImageStore.deleteIfExists(fileName: savedOriginalFileName, kind: .original)
            }
            if let savedCutoutFileName {
                CharacterImageStore.deleteIfExists(fileName: savedCutoutFileName, kind: .cutout)
            }
            errorMessage = error.localizedDescription
        }
    }
}

private enum CharacterImageProcessor {
    static func process(_ image: UIImage) -> CharacterImageProcessingResult {
        let preparedImage = ImagePreparation.normalizedAndScaled(image)

        do {
            let cutoutImage = try SubjectCutoutService.makeCutout(from: preparedImage)
            return CharacterImageProcessingResult(
                sourceImage: preparedImage,
                cutoutImage: cutoutImage,
                warningMessage: nil
            )
        } catch {
            return CharacterImageProcessingResult(
                sourceImage: preparedImage,
                cutoutImage: preparedImage,
                warningMessage: "自動切り抜きできなかったため、元の写真のまま登録します。"
            )
        }
    }

}

/// 境界・余白スライダーの値。`.task(id:)` の識別子に使い、変化したときだけ再トリミングを走らせる。
private struct CutoutTrimSettings: Equatable {
    let alphaThreshold: Double
    let paddingRatio: Double
}

private struct CharacterImageProcessingResult {
    let sourceImage: UIImage
    let cutoutImage: UIImage
    let warningMessage: String?
}

#Preview {
    AddCharacterView()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
