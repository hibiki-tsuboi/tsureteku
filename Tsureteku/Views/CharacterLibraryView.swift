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
                        Section {
                            ForEach(characters) { character in
                                NavigationLink {
                                    CharacterDetailView(character: character)
                                } label: {
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    private var emptyState: some View {
        ZStack(alignment: .bottom) {
            WelcomeEmptyState(
                icon: "teddybear.fill",
                title: "推しをつれていこう",
                message: "お気に入りの推しを撮って登録すると、ARで一緒に写真が撮れるよ。",
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

                Text(Self.relativeDateText(character.createdAt))
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

    /// 今日／昨日／6/13（今年）／2025/1/1（別の年）の形式で日付を表示する。
    private static func relativeDateText(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "今日"
        }

        if calendar.isDateInYesterday(date) {
            return "昨日"
        }

        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return ""
        }

        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return "\(month)/\(day)"
        }

        return "\(year)/\(month)/\(day)"
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
