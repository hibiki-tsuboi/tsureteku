//
//  CharacterDetailView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import RealityKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CharacterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var character: ToyCharacter

    @State private var isImportingModel = false
    @State private var isModelDeleteConfirmationPresented = false
    @State private var shareableModel: ShareableModel?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    CharacterThumbnailView(character: character)
                        .frame(width: 92)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("名前", text: $character.name)
                            .font(.headline)
                            .onSubmit(save)

                        Text(character.createdAt, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("AR") {
                HStack {
                    Text("初期サイズ")
                    Slider(value: $character.defaultSizeMeters, in: 0.12...1.2)
                        .onChange(of: character.defaultSizeMeters) { _, _ in
                            save()
                        }

                    Text("\(Int(character.defaultSizeMeters * 100))cm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section("3Dモデル") {
                if character.modelFileName == nil {
                    Label("未登録", systemImage: "cube.transparent")
                        .foregroundStyle(.secondary)
                } else {
                    Label("USDZ登録済み", systemImage: "cube.fill")
                }

                Button {
                    isImportingModel = true
                } label: {
                    Label(character.modelFileName == nil ? "USDZを登録" : "USDZを差し替え", systemImage: "square.and.arrow.down")
                }

                if character.modelFileName != nil {
                    NavigationLink {
                        ModelAdjustmentView(character: character)
                    } label: {
                        Label("3Dモデルを確認・調整", systemImage: "cube")
                    }

                    Button {
                        shareModel()
                    } label: {
                        Label("3Dモデルを共有", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        isModelDeleteConfirmationPresented = true
                    } label: {
                        Label("3Dモデル削除", systemImage: "trash")
                    }
                }
            }

            Section("Object Capture") {
                if ObjectCaptureSession.isSupported {
                    NavigationLink {
                        ObjectCapturePreparationView(character: character)
                    } label: {
                        Label("3D撮影セットを作る", systemImage: "camera.aperture")
                    }
                } else {
                    Label("3D撮影セットを作る", systemImage: "camera.aperture")
                        .foregroundStyle(.secondary)

                    Label("この端末では使えません（USDZ登録は可能）", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if character.objectCaptureDirectoryName != nil {
                    Label("撮影データあり", systemImage: "folder")
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
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImportingModel,
            allowedContentTypes: [.usdzModel]
        ) { result in
            importModel(result)
        }
        .confirmationDialog(
            "3Dモデルを削除しますか？",
            isPresented: $isModelDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive, action: removeModel)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("削除すると元に戻せません。もう一度3D撮影またはUSDZ登録が必要です。")
        }
        .sheet(item: $shareableModel) { model in
            ModelShareSheet(url: model.url)
        }
    }

    private func shareModel() {
        guard let modelFileName = character.modelFileName,
              let sourceURL = try? CharacterImageStore.modelURL(for: modelFileName) else {
            errorMessage = "共有できる3Dモデルがありません。"
            return
        }

        let trimmedName = character.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "推し" : trimmedName
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let safeName = baseName.components(separatedBy: invalidCharacters).joined()
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).usdz")

        try? FileManager.default.removeItem(at: exportURL)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: exportURL)
            shareableModel = ShareableModel(url: exportURL)
        } catch {
            // 名前付きコピーに失敗した場合は元ファイルをそのまま共有する。
            shareableModel = ShareableModel(url: sourceURL)
        }
    }

    private func importModel(_ result: Result<URL, Error>) {
        do {
            let sourceURL = try result.get()
            let fileName = try CharacterImageStore.saveModel(from: sourceURL)

            CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
            character.modelFileName = fileName
            character.modelYawDegrees = 0
            character.modelVerticalOffsetMeters = 0
            character.updatedAt = Date()
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeModel() {
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        character.modelFileName = nil
        character.modelYawDegrees = 0
        character.modelVerticalOffsetMeters = 0
        character.updatedAt = Date()
        save()
    }

    private func save() {
        character.updatedAt = Date()
        try? modelContext.save()
    }
}

private extension UTType {
    static var usdzModel: UTType {
        UTType(filenameExtension: "usdz") ?? .data
    }
}

private struct ShareableModel: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ModelShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
