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

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if photos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(photos) { photo in
                                NavigationLink {
                                    CapturedPhotoDetailView(photo: photo)
                                } label: {
                                    CapturedPhotoGridCell(photo: photo)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("履歴")
        }
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

            Text(photo.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
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
