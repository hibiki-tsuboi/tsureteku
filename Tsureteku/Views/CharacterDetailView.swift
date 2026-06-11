//
//  CharacterDetailView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct CharacterDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var character: ToyCharacter

    @State private var isImportingModel = false
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
                    Button(role: .destructive) {
                        removeModel()
                    } label: {
                        Label("3Dモデル削除", systemImage: "trash")
                    }
                }
            }

            Section("Object Capture") {
                NavigationLink {
                    ObjectCaptureWorkflowView(character: character)
                } label: {
                    Label("3D撮影セットを作る", systemImage: "camera.aperture")
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
    }

    private func importModel(_ result: Result<URL, Error>) {
        do {
            let sourceURL = try result.get()
            let fileName = try CharacterImageStore.saveModel(from: sourceURL)

            CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
            character.modelFileName = fileName
            character.updatedAt = Date()
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeModel() {
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        character.modelFileName = nil
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
