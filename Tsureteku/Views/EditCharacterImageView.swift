//
//  EditCharacterImageView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/21.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct EditCharacterImageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var character: ToyCharacter

    @State private var sourceImage: UIImage?
    @State private var cutoutImage: UIImage?
    @State private var baseCutoutImage: UIImage?
    @State private var currentCutoutImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var warningMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isManualTrimPresented = false
    @State private var alphaThreshold = 0.1
    @State private var trimPadding = 0.04
    @State private var activeProcessingID: UUID?

    var body: some View {
        NavigationStack {
            Form {
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("切り抜きの強さ")
                                Spacer()
                                Text(alphaThreshold, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $alphaThreshold, in: 0...0.45)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("まわりの余白")
                                Spacer()
                                Text(trimPadding, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $trimPadding, in: 0...0.18)
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
                        Text("保存すると、一覧や推し選択で使う画像だけが差し替わります。3Dモデルは変更されません。")
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
            .navigationTitle("2D画像を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveImage)
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
                        self.cutoutImage = trimmedImage
                        self.baseCutoutImage = trimmedImage
                    }
                }
            }
            .onAppear(perform: loadCurrentImageIfNeeded)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else {
                    return
                }

                Task {
                    await loadPhotoItem(newItem)
                }
            }
            .task(id: CharacterImageTrimSettings(alphaThreshold: alphaThreshold, paddingRatio: trimPadding)) {
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
            } else if let currentCutoutImage {
                Image(uiImage: currentCutoutImage)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .frame(maxHeight: 260)
                    .opacity(0.76)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 42))
                    Text("新しい画像")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var canSave: Bool {
        sourceImage != nil && cutoutImage != nil
    }

    private func loadCurrentImageIfNeeded() {
        guard currentCutoutImage == nil else {
            return
        }

        currentCutoutImage = CharacterImageStore.image(
            named: character.cutoutImageFileName,
            kind: .cutout
        )
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
        baseCutoutImage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ReplacementCharacterImageProcessor.process(image)

            DispatchQueue.main.async {
                guard activeProcessingID == processingID else {
                    return
                }

                sourceImage = result.sourceImage
                cutoutImage = result.cutoutImage
                baseCutoutImage = result.cutoutImage
                warningMessage = result.warningMessage
                isProcessing = false
                activeProcessingID = nil
            }
        }
    }

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

    private func saveImage() {
        guard let sourceImage, let cutoutImage else {
            return
        }

        let previousOriginalFileName = character.originalImageFileName
        let previousCutoutFileName = character.cutoutImageFileName
        var savedOriginalFileName: String?
        var savedCutoutFileName: String?

        do {
            let originalFileName = try CharacterImageStore.save(sourceImage, kind: .original)
            savedOriginalFileName = originalFileName
            let cutoutFileName = try CharacterImageStore.save(cutoutImage, kind: .cutout)
            savedCutoutFileName = cutoutFileName

            character.originalImageFileName = originalFileName
            character.cutoutImageFileName = cutoutFileName
            character.updatedAt = Date()

            do {
                try modelContext.save()
                CharacterImageStore.deleteIfExists(fileName: previousOriginalFileName, kind: .original)
                CharacterImageStore.deleteIfExists(fileName: previousCutoutFileName, kind: .cutout)
                dismiss()
            } catch {
                character.originalImageFileName = previousOriginalFileName
                character.cutoutImageFileName = previousCutoutFileName
                try? modelContext.save()
                throw error
            }
        } catch {
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

private enum ReplacementCharacterImageProcessor {
    static func process(_ image: UIImage) -> ReplacementCharacterImageProcessingResult {
        let preparedImage = ImagePreparation.normalizedAndScaled(image)

        do {
            let cutoutImage = try SubjectCutoutService.makeCutout(from: preparedImage)
            return ReplacementCharacterImageProcessingResult(
                sourceImage: preparedImage,
                cutoutImage: cutoutImage,
                warningMessage: nil
            )
        } catch {
            return ReplacementCharacterImageProcessingResult(
                sourceImage: preparedImage,
                cutoutImage: preparedImage,
                warningMessage: "自動切り抜きできなかったため、元の写真のまま保存します。"
            )
        }
    }
}

private struct CharacterImageTrimSettings: Equatable {
    let alphaThreshold: Double
    let paddingRatio: Double
}

private struct ReplacementCharacterImageProcessingResult {
    let sourceImage: UIImage
    let cutoutImage: UIImage
    let warningMessage: String?
}

#Preview {
    EditCharacterImageView(
        character: ToyCharacter(
            name: "推し",
            originalImageFileName: "preview-original.png",
            cutoutImageFileName: "preview-cutout.png"
        )
    )
    .modelContainer(for: ToyCharacter.self, inMemory: true)
}
