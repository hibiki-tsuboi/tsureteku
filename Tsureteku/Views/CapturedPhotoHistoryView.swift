//
//  CapturedPhotoHistoryView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var emptyState: some View {
        WelcomeEmptyState(
            icon: "photo.stack.fill",
            title: "思い出はまだこれから",
            message: "ARで推しと一緒に撮影すると、ここに写真が並んでいくよ。"
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

                if let image = CapturedPhotoStore.image(named: photo.imageFileName) {
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

    @State private var isShareSheetPresented = false
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let image = CapturedPhotoStore.image(named: photo.imageFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("写真を読み込めません", systemImage: "photo.badge.exclamationmark")
                }
                .foregroundStyle(.white)
            }
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
                .disabled(CapturedPhotoStore.image(named: photo.imageFileName) == nil)
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
            if let image = CapturedPhotoStore.image(named: photo.imageFileName) {
                PhotoShareSheet(image: image)
            }
        }
        .confirmationDialog("この写真を削除しますか？", isPresented: $isDeleteConfirmationPresented, titleVisibility: .visible) {
            Button("削除", role: .destructive, action: deletePhoto)
            Button("キャンセル", role: .cancel) {
            }
        }
    }

    private func deletePhoto() {
        CapturedPhotoStore.deleteIfExists(fileName: photo.imageFileName)
        modelContext.delete(photo)
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CapturedPhotoHistoryView()
        .modelContainer(for: [CapturedPhoto.self], inMemory: true)
}
