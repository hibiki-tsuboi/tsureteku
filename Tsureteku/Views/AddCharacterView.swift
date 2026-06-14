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
    @State private var isProcessing = false
    @State private var errorMessage: String?
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
                    Section("切り抜き") {
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
                            applyCutoutRefinement()
                        } label: {
                            Label("自動調整", systemImage: "wand.and.sparkles")
                        }
                        .disabled(isProcessing)

                        Button {
                            isManualTrimPresented = true
                        } label: {
                            Label("手動トリミング", systemImage: "crop")
                        }
                        .disabled(isProcessing)
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

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("推し追加")
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
            .sheet(isPresented: $isCameraPresented) {
                CameraCaptureView { image in
                    process(image)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isManualTrimPresented) {
                if let cutoutImage {
                    ManualTrimView(image: cutoutImage) { trimmedImage in
                        self.cutoutImage = trimmedImage
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
                errorMessage = result.warningMessage

                if characterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    characterName = defaultCharacterName()
                }

                isProcessing = false
                activeProcessingID = nil
            }
        }
    }

    private func applyCutoutRefinement() {
        guard sourceImage != nil || cutoutImage != nil else {
            return
        }

        let processingID = UUID()
        activeProcessingID = processingID
        isProcessing = true
        errorMessage = nil

        let sourceImage = sourceImage
        let cutoutImage = cutoutImage
        let alphaThreshold = UInt8(alphaThreshold * 255)
        let trimPadding = trimPadding

        DispatchQueue.global(qos: .userInitiated).async {
            let refinedImage = CharacterImageProcessor.refineCutout(
                sourceImage: sourceImage,
                cutoutImage: cutoutImage,
                alphaThreshold: alphaThreshold,
                paddingRatio: trimPadding
            )

            DispatchQueue.main.async {
                guard activeProcessingID == processingID else {
                    return
                }

                if let refinedImage {
                    self.cutoutImage = refinedImage
                } else {
                    errorMessage = "切り抜きを調整できませんでした。"
                }

                isProcessing = false
                activeProcessingID = nil
            }
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

        do {
            let originalFileName = try CharacterImageStore.save(sourceImage, kind: .original)
            let cutoutFileName = try CharacterImageStore.save(cutoutImage, kind: .cutout)
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
            try modelContext.save()
            dismiss()
        } catch {
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
                warningMessage: "自動切り抜きに失敗したため、元画像で登録します。"
            )
        }
    }

    static func refineCutout(
        sourceImage: UIImage?,
        cutoutImage: UIImage?,
        alphaThreshold: UInt8,
        paddingRatio: Double
    ) -> UIImage? {
        if let sourceImage,
           let refinedCutout = try? SubjectCutoutService.makeCutout(from: sourceImage),
           let trimmedImage = ImageCropService.trimTransparentPixels(
            refinedCutout,
            alphaThreshold: alphaThreshold,
            paddingRatio: paddingRatio
           ) {
            return trimmedImage
        }

        guard let cutoutImage else {
            return nil
        }

        return ImageCropService.trimTransparentPixels(
            cutoutImage,
            alphaThreshold: alphaThreshold,
            paddingRatio: paddingRatio
        )
    }
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
