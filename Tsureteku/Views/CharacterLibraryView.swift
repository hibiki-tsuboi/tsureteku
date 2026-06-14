//
//  CharacterLibraryView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import SwiftData
import SwiftUI

struct CharacterLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToyCharacter.createdAt, order: .reverse) private var characters: [ToyCharacter]

    @State private var isAddingCharacter = false
    @State private var pendingDeletionCharacter: ToyCharacter?

    var body: some View {
        NavigationStack {
            Group {
                if characters.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(characters) { character in
                            NavigationLink {
                                CharacterDetailView(character: character)
                            } label: {
                                characterRow(character)
                            }
                        }
                        .onDelete(perform: requestDeletion)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("キャラ")
            .toolbar {
                if !characters.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingCharacter = true
                        } label: {
                            Label("追加", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingCharacter) {
                AddCharacterView()
            }
            .confirmationDialog(
                "このキャラを削除しますか？",
                isPresented: Binding(
                    get: { pendingDeletionCharacter != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeletionCharacter = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingDeletionCharacter
            ) { character in
                Button("削除", role: .destructive) {
                    deleteCharacter(character)
                }
                Button("キャンセル", role: .cancel) {}
            } message: { character in
                Text("「\(character.name)」を削除します。登録した写真と3Dモデルも削除され、元に戻せません。")
            }
        }
    }

    private var emptyState: some View {
        WelcomeEmptyState(
            icon: "teddybear.fill",
            title: "ぬいぐるみを連れていこう",
            message: "お気に入りのぬいぐるみを撮って登録すると、ARで一緒に写真が撮れるよ。",
            actionTitle: "最初のぬいぐるみを登録",
            action: { isAddingCharacter = true }
        )
    }

    private func characterRow(_ character: ToyCharacter) -> some View {
        HStack(spacing: 14) {
            CharacterThumbnailView(character: character)
                .frame(width: 86)

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)

                Text(character.createdAt, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func requestDeletion(offsets: IndexSet) {
        guard let index = offsets.first else {
            return
        }

        pendingDeletionCharacter = characters[index]
    }

    private func deleteCharacter(_ character: ToyCharacter) {
        CharacterImageStore.deleteIfExists(fileName: character.originalImageFileName, kind: .original)
        CharacterImageStore.deleteIfExists(fileName: character.cutoutImageFileName, kind: .cutout)
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: character.objectCaptureDirectoryName)
        modelContext.delete(character)
        try? modelContext.save()

        pendingDeletionCharacter = nil
    }
}

#Preview {
    CharacterLibraryView()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
