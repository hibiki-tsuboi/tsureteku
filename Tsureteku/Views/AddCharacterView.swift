//
//  AddCharacterView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import PhotosUI
import RealityKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AddCharacterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingCharacters: [ToyCharacter]

    @State private var registrationMode: CharacterRegistrationMode = .photo
    @State private var characterName = ""
    @State private var sourceImage: UIImage?
    @State private var cutoutImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    /// 自動切り抜きに失敗したなど、保存自体はできる注意喚起。エラーと区別して控えめに表示する。
    @State private var warningMessage: String?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isManualTrimPresented = false
    @State private var isImportingModel = false
    @State private var isModelImportProcessing = false
    @State private var importedModelFileName: String?
    @State private var importedModelDisplayName: String?
    @State private var importedModelSourceThumbnailImage: UIImage?
    @State private var importedModelThumbnailImage: UIImage?
    @State private var defaultSizeMeters = ToyCharacter.initialSizeMeters
    @State private var activeProcessingID: UUID?
    @State private var activeModelImportID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("登録方法") {
                    Picker("登録方法", selection: $registrationMode) {
                        ForEach(CharacterRegistrationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TextField("名前", text: $characterName)
                }

                switch registrationMode {
                case .photo:
                    photoRegistrationContent
                case .objectCapture:
                    objectCaptureRegistrationContent
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
                        discardImportedModel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if registrationMode == .photo {
                        Button("保存", action: saveCharacter)
                            .disabled(!canSave || isProcessing)
                    } else if importedModelFileName != nil {
                        Button("保存", action: saveImportedModelCharacter)
                            .disabled(!canSaveImportedModel || isModelImportProcessing)
                    }
                }
            }
            .fileImporter(
                isPresented: $isImportingModel,
                allowedContentTypes: [.usdzModel]
            ) { result in
                importModel(result)
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
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else {
                    return
                }

                Task {
                    await loadPhotoItem(newItem)
                }
            }
            .onAppear {
                // 開いた時点で両タブとも既定名を入れておき、タブ切替で名前の有無がブレないようにする。
                fillDefaultNameIfNeeded()
            }
            .onChange(of: registrationMode) { _, newMode in
                if newMode == .objectCapture {
                    fillDefaultNameIfNeeded()
                    warningMessage = nil
                    errorMessage = nil
                } else {
                    discardImportedModel()
                }
            }
            .onDisappear {
                activeProcessingID = nil
                discardImportedModel()
            }
        }
    }

    @ViewBuilder
    private var photoRegistrationContent: some View {
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
                Text("背景や余白が気になる時だけ手動で範囲を調整できます。問題なければそのまま保存できます。")
            }

            arSizeSection
        }
    }

    @ViewBuilder
    private var objectCaptureRegistrationContent: some View {
        Section {
            Button {
                isImportingModel = true
            } label: {
                Label(importedModelFileName == nil ? "3Dモデルを登録（USDZ）" : "3Dモデルを差し替え（USDZ）", systemImage: "square.and.arrow.down")
            }

            if let importedModelDisplayName {
                HStack(spacing: 12) {
                    modelThumbnailPreview

                    VStack(alignment: .leading, spacing: 4) {
                        Text(importedModelDisplayName)
                            .lineLimit(1)

                        Text(isModelImportProcessing ? "サムネイルを作成中" : "3Dモデルを登録できます")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("3Dデータ")
        } footer: {
            Text("USDZファイルを選ぶと、モデルから一覧用サムネイルを作成して新しい推しとして登録できます。画像はあとから詳細画面で変更できます。")
        }

        Section {
            NavigationLink {
                NewObjectCaptureCharacterView(
                    characterName: trimmedCharacterName,
                    defaultSizeMeters: defaultSizeMeters,
                    onCharacterCreated: { dismiss() }
                )
            } label: {
                Label("3D撮影して作る", systemImage: "camera.aperture")
            }
            .disabled(!canStartObjectCaptureRegistration || !ObjectCaptureSession.isSupported)

            if ObjectCaptureSession.isSupported {
                Label("iPhoneで撮影して、3Dモデルの推しを作成します。", systemImage: "cube.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("この端末では3D撮影を利用できません。", systemImage: "iphone.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !canStartObjectCaptureRegistration {
                Text("名前を入力すると3D撮影へ進めます。")
            }
        }

        arSizeSection
    }

    @ViewBuilder
    private var modelThumbnailPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))

            if let importedModelThumbnailImage {
                Image(uiImage: importedModelThumbnailImage)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            } else if isModelImportProcessing {
                ProgressView()
            } else {
                Image(systemName: "cube.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
    }

    private var arSizeSection: some View {
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

    private var canStartObjectCaptureRegistration: Bool {
        !trimmedCharacterName.isEmpty
    }

    private var canSaveImportedModel: Bool {
        importedModelFileName != nil && !trimmedCharacterName.isEmpty
    }

    private var trimmedCharacterName: String {
        characterName.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func importModel(_ result: Result<URL, Error>) {
        let importID = UUID()
        activeModelImportID = importID
        isModelImportProcessing = true

        do {
            let sourceURL = try result.get()
            let fileName = try CharacterImageStore.saveModel(from: sourceURL)
            let modelURL = try CharacterImageStore.modelURL(for: fileName)

            discardImportedModel()
            activeModelImportID = importID
            isModelImportProcessing = true
            importedModelFileName = fileName
            importedModelDisplayName = sourceURL.lastPathComponent
            importedModelSourceThumbnailImage = nil
            importedModelThumbnailImage = nil
            errorMessage = nil
            warningMessage = nil
            fillDefaultNameIfNeeded()

            Task {
                let thumbnailImages = await ModelThumbnailService.makeThumbnailImages(for: modelURL)

                guard activeModelImportID == importID,
                      importedModelFileName == fileName else {
                    return
                }

                let fallbackImage = CharacterPlaceholderImageFactory.make3DModelImage()
                importedModelSourceThumbnailImage = thumbnailImages?.source ?? fallbackImage
                importedModelThumbnailImage = thumbnailImages?.cutout ?? fallbackImage
                isModelImportProcessing = false
                activeModelImportID = nil
            }
        } catch {
            isModelImportProcessing = false
            activeModelImportID = nil
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
                warningMessage = result.warningMessage

                fillDefaultNameIfNeeded()

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

    private func fillDefaultNameIfNeeded() {
        if trimmedCharacterName.isEmpty {
            characterName = defaultCharacterName()
        }
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

    private func saveImportedModelCharacter() {
        guard let importedModelFileName else {
            return
        }

        var savedOriginalFileName: String?
        var savedCutoutFileName: String?
        var insertedCharacter: ToyCharacter?

        do {
            let fallbackImage = CharacterPlaceholderImageFactory.make3DModelImage()
            let sourceThumbnailImage = importedModelSourceThumbnailImage ?? importedModelThumbnailImage ?? fallbackImage
            let cutoutThumbnailImage = importedModelThumbnailImage ?? sourceThumbnailImage
            let originalFileName = try CharacterImageStore.save(sourceThumbnailImage, kind: .original)
            savedOriginalFileName = originalFileName
            let cutoutFileName = try CharacterImageStore.save(cutoutThumbnailImage, kind: .cutout)
            savedCutoutFileName = cutoutFileName
            let now = Date()
            let character = ToyCharacter(
                name: trimmedCharacterName,
                originalImageFileName: originalFileName,
                cutoutImageFileName: cutoutFileName,
                modelFileName: importedModelFileName,
                defaultSizeMeters: defaultSizeMeters,
                createdAt: now,
                updatedAt: now
            )

            modelContext.insert(character)
            insertedCharacter = character
            try modelContext.save()
            self.importedModelFileName = nil
            importedModelDisplayName = nil
            dismiss()
        } catch {
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

    private func discardImportedModel() {
        CharacterImageStore.deleteModelIfExists(fileName: importedModelFileName)
        activeModelImportID = nil
        isModelImportProcessing = false
        importedModelFileName = nil
        importedModelDisplayName = nil
        importedModelSourceThumbnailImage = nil
        importedModelThumbnailImage = nil
    }
}

private enum CharacterRegistrationMode: String, CaseIterable, Identifiable {
    case photo
    case objectCapture

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .photo:
            "写真"
        case .objectCapture:
            "3Dモデル"
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

private struct CharacterImageProcessingResult {
    let sourceImage: UIImage
    let cutoutImage: UIImage
    let warningMessage: String?
}

#Preview {
    AddCharacterView()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
