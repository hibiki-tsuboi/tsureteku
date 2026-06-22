//
//  CapturedPhotoHistoryView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import AVFoundation
import AVKit
import SwiftData
import SwiftUI
import UIKit

struct CapturedPhotoHistoryView: View {
    @Query(sort: \CapturedPhoto.createdAt, order: .reverse) private var photos: [CapturedPhoto]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext

    /// 一括削除のための選択モード中かどうか。
    @State private var isSelecting = false
    /// 選択中のメディアID。
    @State private var selectedIDs: Set<UUID> = []
    @State private var isBulkDeleteConfirmationPresented = false

    private var columns: [GridItem] {
        // iPad（regular幅）では1セルが小さくなりすぎないよう最小幅を広げる。
        let minimum: CGFloat = horizontalSizeClass == .regular ? 200 : 150
        return [GridItem(.adaptive(minimum: minimum), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(photos) { photo in
                                gridItem(for: photo)
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .automatic)
            // 選択モード中はタブバーを隠し、写真アプリと同じく下部に削除バーを出す。
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .toolbar { selectionToolbar }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionActionBar
                }
            }
            .alert("\(selectedIDs.count)件を削除しますか？", isPresented: $isBulkDeleteConfirmationPresented) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive, action: deleteSelected)
            } message: {
                Text("削除した写真と動画は元に戻せません。")
            }
        }
    }

    @ViewBuilder
    private func gridItem(for photo: CapturedPhoto) -> some View {
        if isSelecting {
            Button {
                toggleSelection(photo)
            } label: {
                CapturedPhotoGridCell(
                    photo: photo,
                    selectionState: selectedIDs.contains(photo.id) ? .selected : .unselected
                )
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                CapturedPhotoDetailView(photo: photo)
            } label: {
                CapturedPhotoGridCell(photo: photo)
            }
            .buttonStyle(.plain)
        }
    }

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル", action: exitSelection)
            }
        } else if !photos.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("選択") {
                    isSelecting = true
                }
            }
        }
    }

    /// 選択モード中に最下部へ出す削除バー。
    /// システムの下部ツールバーは淡いテキストで見づらいため、背景をはっきりさせ削除を赤い塗りボタンにする。
    private var selectionActionBar: some View {
        HStack {
            Button(action: toggleSelectAll) {
                Text(allSelected ? "選択を解除" : "すべて選択")
                    .font(.body.weight(.semibold))
            }
            .tint(BrandColor.purple)

            Spacer()

            Button(role: .destructive) {
                isBulkDeleteConfirmationPresented = true
            } label: {
                Text(selectedIDs.isEmpty ? "削除" : "削除 (\(selectedIDs.count))")
                    .font(.body.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var navigationTitleText: String {
        guard isSelecting else {
            return "履歴"
        }

        return selectedIDs.isEmpty ? "項目を選択" : "\(selectedIDs.count)件を選択"
    }

    private var allSelected: Bool {
        !photos.isEmpty && selectedIDs.count == photos.count
    }

    private func toggleSelection(_ photo: CapturedPhoto) {
        if selectedIDs.contains(photo.id) {
            selectedIDs.remove(photo.id)
        } else {
            selectedIDs.insert(photo.id)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(photos.map(\.id))
        }
    }

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func deleteSelected() {
        let targets = photos.filter { selectedIDs.contains($0.id) }
        for photo in targets {
            CapturedPhotoStore.deleteIfExists(fileName: photo.imageFileName)
            CapturedPhotoStore.deleteIfExists(fileName: photo.videoFileName)
            modelContext.delete(photo)
        }
        try? modelContext.save()
        exitSelection()
    }

    private var emptyState: some View {
        WelcomeEmptyState(
            icon: "photo.stack.fill",
            title: "思い出はまだこれから",
            message: "ARで推しと一緒に撮影すると、ここに写真や動画が並んでいくよ。"
        )
    }
}

private struct CapturedPhotoGridCell: View {
    let photo: CapturedPhoto
    /// 選択モード中の選択状態。nil のときは通常表示（選択UIを出さない）。
    var selectionState: SelectionState?

    enum SelectionState {
        case selected
        case unselected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.thinMaterial)

                if let image = CapturedPhotoStore.thumbnail(named: photo.imageFileName, maxPixelSize: 600) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if photo.mediaType == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
            }
            .overlay {
                if selectionState == .selected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let selectionState {
                    selectionBadge(isSelected: selectionState == .selected)
                        .padding(8)
                }
            }

            Text(photo.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func selectionBadge(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                isSelected ? Color.white : Color.white,
                isSelected ? Color.accentColor : Color.black.opacity(0.3)
            )
            .background(Color.black.opacity(isSelected ? 0 : 0.15), in: Circle())
            .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

private struct CapturedPhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let photo: CapturedPhoto

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var videoShareURL: URL?
    @State private var loadFailed = false
    @State private var isShareSheetPresented = false
    @State private var isDeleteConfirmationPresented = false

    private var isVideo: Bool { photo.mediaType == .video }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea(edges: .bottom)
                } else if loadFailed {
                    failureView(label: "動画を読み込めません")
                }
            } else {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if loadFailed {
                    // 読み込み中はエラーを出さない（黒背景のまま）。読み込みを試みて失敗した時だけ表示。
                    failureView(label: "写真を読み込めません")
                }
            }
        }
        .task(id: photo.id) {
            await loadMedia()
        }
        .onDisappear {
            player?.pause()
        }
        .navigationTitle(photo.createdAt.formatted(.dateTime.year().month().day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isShareSheetPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(!canShare)
                .accessibilityLabel("共有")

                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("削除")
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if isVideo {
                if let videoShareURL {
                    VideoShareSheet(url: videoShareURL)
                }
            } else if let image {
                PhotoShareSheet(image: image)
            }
        }
        .alert(
            isVideo ? "この動画を削除しますか？" : "この写真を削除しますか？",
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button("キャンセル", role: .cancel) {
            }
            Button("削除", role: .destructive, action: deleteMedia)
        }
    }

    private var canShare: Bool {
        isVideo ? (videoShareURL != nil) : (image != nil)
    }

    @ViewBuilder
    private func failureView(label: String) -> some View {
        ContentUnavailableView {
            Label(label, systemImage: "photo.badge.exclamationmark")
        }
        .foregroundStyle(.white)
    }

    private func loadMedia() async {
        if isVideo {
            if let fileName = photo.videoFileName,
               let url = CapturedPhotoStore.videoURL(named: fileName) {
                videoShareURL = url
                let newPlayer = AVPlayer(url: url)
                player = newPlayer
                loadFailed = false
                newPlayer.play()
            } else {
                loadFailed = true
            }
        } else {
            let loaded = CapturedPhotoStore.image(named: photo.imageFileName)
            image = loaded
            loadFailed = (loaded == nil)
        }
    }

    private func deleteMedia() {
        CapturedPhotoStore.deleteIfExists(fileName: photo.imageFileName)
        CapturedPhotoStore.deleteIfExists(fileName: photo.videoFileName)
        modelContext.delete(photo)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CapturedPhotoHistoryView()
        .modelContainer(for: [CapturedPhoto.self], inMemory: true)
}
