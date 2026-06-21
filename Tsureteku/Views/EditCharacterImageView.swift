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
    @State private var currentCutoutImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var warningMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isManualTrimPresented = false
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
                        Label {
                            Text(warningMessage == nil ? "自動切り抜き済み" : "写真を読み込み済み")
                        } icon: {
                            Image(systemName: warningMessage == nil ? "checkmark.circle.fill" : "photo")
                                .foregroundStyle(warningMessage == nil ? .green : .secondary)
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
                        Text("背景や余白が気になる時だけ手動で範囲を調整できます。保存しても3Dモデルは変更されません。")
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

        DispatchQueue.global(qos: .userInitiated).async {
            let result = ReplacementCharacterImageProcessor.process(image)

            DispatchQueue.main.async {
                guard activeProcessingID == processingID else {
                    return
                }

                sourceImage = result.sourceImage
                cutoutImage = result.cutoutImage
                warningMessage = result.warningMessage
                isProcessing = false
                activeProcessingID = nil
            }
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
