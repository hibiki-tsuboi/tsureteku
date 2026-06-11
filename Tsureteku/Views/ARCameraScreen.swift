//
//  ARCameraScreen.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import SwiftData
import SwiftUI

struct ARCameraScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToyCharacter.createdAt, order: .reverse) private var characters: [ToyCharacter]

    @State private var selectedCharacterID: UUID?
    @State private var captureTrigger = 0
    @State private var removeLastTrigger = 0
    @State private var resetTrigger = 0
    @State private var isAddingCharacter = false
    @State private var statusMessage: String?

    var body: some View {
        ZStack {
            ARCharacterView(
                selectedAsset: selectedAsset,
                captureTrigger: $captureTrigger,
                removeLastTrigger: $removeLastTrigger,
                resetTrigger: $resetTrigger,
                onCapture: handleCapture,
                onStatus: showStatus
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer()
                bottomControls
            }
        }
        .onAppear(perform: selectInitialCharacterIfNeeded)
        .onChange(of: characters.map(\.id)) { _, _ in
            selectInitialCharacterIfNeeded()
        }
        .sheet(isPresented: $isAddingCharacter) {
            AddCharacterView()
        }
    }

    private var header: some View {
        HStack {
            Text("つれてく")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                removeLastTrigger += 1
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("最後の配置を削除")

            Button {
                resetTrigger += 1
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("配置をリセット")

            Button {
                isAddingCharacter = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .accessibilityLabel("キャラ追加")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }

            if characters.isEmpty {
                Button {
                    isAddingCharacter = true
                } label: {
                    Label("キャラ追加", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)
            } else {
                characterPicker
                sizeControl

                Button {
                    captureTrigger += 1
                } label: {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 68))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("撮影")
            }
        }
        .padding(.bottom, 26)
    }

    private var characterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(characters) { character in
                    Button {
                        select(character)
                    } label: {
                        CharacterThumbnailView(
                            character: character,
                            isSelected: character.id == selectedCharacterID
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var sizeControl: some View {
        if let selectedCharacter {
            HStack(spacing: 10) {
                Image(systemName: selectedCharacter.modelFileName == nil ? "arrow.up.and.down" : "cube")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { selectedCharacter.defaultSizeMeters },
                        set: { newValue in
                            selectedCharacter.defaultSizeMeters = newValue
                            selectedCharacter.updatedAt = Date()
                            try? modelContext.save()
                        }
                    ),
                    in: 0.12...1.2
                )

                Text("\(Int(selectedCharacter.defaultSizeMeters * 100))cm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var selectedAsset: CharacterARAsset? {
        guard let selectedCharacter else {
            return nil
        }

        return CharacterARAsset(
            id: selectedCharacter.id,
            name: selectedCharacter.name,
            cutoutImageFileName: selectedCharacter.cutoutImageFileName,
            modelFileName: selectedCharacter.modelFileName,
            defaultSizeMeters: Float(selectedCharacter.defaultSizeMeters)
        )
    }

    private var selectedCharacter: ToyCharacter? {
        if let selectedCharacterID,
           let selected = characters.first(where: { $0.id == selectedCharacterID }) {
            return selected
        }

        return characters.first
    }

    private func selectInitialCharacterIfNeeded() {
        guard selectedCharacter == nil else {
            return
        }

        selectedCharacterID = characters.first?.id
    }

    private func select(_ character: ToyCharacter) {
        selectedCharacterID = character.id
        character.lastUsedAt = Date()
        try? modelContext.save()
    }

    private func handleCapture(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            showStatus("写真に保存しました。")
        case .failure(let error):
            showStatus(error.localizedDescription)
        }
    }

    private func showStatus(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            statusMessage = message
        }

        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.2)) {
                if statusMessage == message {
                    statusMessage = nil
                }
            }
        }
    }
}

#Preview {
    ARCameraScreen()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
