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
                        .onDelete(perform: deleteCharacters)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("キャラ")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingCharacter = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingCharacter) {
                AddCharacterView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("キャラなし", systemImage: "teddybear")
        } actions: {
            Button {
                isAddingCharacter = true
            } label: {
                Label("追加", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
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

    private func deleteCharacters(offsets: IndexSet) {
        for index in offsets {
            let character = characters[index]
            CharacterImageStore.deleteIfExists(fileName: character.originalImageFileName, kind: .original)
            CharacterImageStore.deleteIfExists(fileName: character.cutoutImageFileName, kind: .cutout)
            CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
            CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: character.objectCaptureDirectoryName)
            modelContext.delete(character)
        }

        try? modelContext.save()
    }
}

#Preview {
    CharacterLibraryView()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
