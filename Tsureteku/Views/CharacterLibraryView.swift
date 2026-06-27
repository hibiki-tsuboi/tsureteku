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

    let resetTrigger: Int

    @State private var navigationPath = NavigationPath()
    @State private var isAddingCharacter = false

    init(resetTrigger: Int = 0) {
        self.resetTrigger = resetTrigger
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if characters.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            ForEach(characters) { character in
                                NavigationLink(value: character.id) {
                                    characterRow(character)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        delete(character)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        } footer: {
                            Text(Self.versionText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .listSectionSpacing(.compact)
                    .contentMargins(.top, 0, for: .scrollContent)
                }
            }
            .navigationTitle("推し")
            .toolbar {
                if !characters.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isAddingCharacter = true
                        } label: {
                            Label("推しを登録", systemImage: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddingCharacter) {
                AddCharacterView()
            }
            .navigationDestination(for: UUID.self) { characterID in
                if let character = characters.first(where: { $0.id == characterID }) {
                    CharacterDetailView(character: character)
                } else {
                    ContentUnavailableView("推しが見つかりません", systemImage: "questionmark.circle")
                }
            }
            .onChange(of: resetTrigger) { _, _ in
                navigationPath = NavigationPath()
            }
        }
    }

    private var emptyState: some View {
        ZStack(alignment: .bottom) {
            WelcomeEmptyState(
                icon: "teddybear.fill",
                title: "推しをつれていこう",
                message: "お気に入りの推しを登録すると、ARで一緒に写真が撮れるよ。",
                actionTitle: "最初の推しを登録",
                action: { isAddingCharacter = true }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(Self.versionText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }

    private func characterRow(_ character: ToyCharacter) -> some View {
        HStack(spacing: 14) {
            CharacterThumbnailView(character: character, showsName: false)
                .frame(width: 86)

            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)

                Text(Self.metadataText(for: character))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }

            Spacer()
        }
        .padding(.vertical, 6)
    }

    /// "v1.0.0 (2)" の形式でアプリのバージョンとビルド番号を表示する。
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "v\(version) (\(build))"
    }

    private static func metadataText(for character: ToyCharacter) -> String {
        var items = [
            character.modelFileName == nil ? "2D" : "3D",
            "\(Int(character.defaultSizeMeters * 100))cm"
        ]

        if character.isARMotionEnabled {
            items.append("動きON")
        }

        return items.joined(separator: " ・ ")
    }

    private func delete(_ character: ToyCharacter) {
        CharacterImageStore.deleteIfExists(fileName: character.originalImageFileName, kind: .original)
        CharacterImageStore.deleteIfExists(fileName: character.cutoutImageFileName, kind: .cutout)
        CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
        CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: character.objectCaptureDirectoryName)
        modelContext.delete(character)

        try? modelContext.save()
    }
}

#Preview {
    CharacterLibraryView()
        .modelContainer(for: ToyCharacter.self, inMemory: true)
}
