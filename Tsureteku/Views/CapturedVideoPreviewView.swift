//
//  CapturedVideoPreviewView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/20.
//

import AVKit
import SwiftUI
import UIKit

struct CapturedVideoPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let videoURL: URL
    var onSave: (URL, @escaping (Result<Void, Error>) -> Void) -> Void
    var onSaveCompleted: (Result<Void, Error>) -> Void

    @State private var player: AVPlayer
    @State private var isSaving = false
    @State private var didSave = false
    @State private var statusMessage: String?
    @State private var isShareSheetPresented = false

    init(
        videoURL: URL,
        onSave: @escaping (URL, @escaping (Result<Void, Error>) -> Void) -> Void,
        onSaveCompleted: @escaping (Result<Void, Error>) -> Void
    ) {
        self.videoURL = videoURL
        self.onSave = onSave
        self.onSaveCompleted = onSaveCompleted
        _player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 132)

                VStack(spacing: 0) {
                    Spacer()

                    footer
                }
            }
            .navigationTitle("動画プレビュー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("閉じる")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $isShareSheetPresented) {
                VideoShareSheet(url: videoURL)
            }
            .onAppear {
                player.play()
            }
            .onDisappear {
                player.pause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
                guard notification.object as? AVPlayerItem == player.currentItem else {
                    return
                }

                player.seek(to: .zero)
                player.play()
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let statusMessage {
                HStack(spacing: 6) {
                    if didSave {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BrandColor.mint)
                    }

                    Text(statusMessage)
                }
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Button {
                    saveVideo()
                } label: {
                    Label(didSave ? "保存済み" : "保存", systemImage: didSave ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(didSave ? BrandColor.mint : BrandColor.purple)
                .disabled(isSaving || didSave)

                Button {
                    isShareSheetPresented = true
                } label: {
                    Label("共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .fontDesign(.rounded)
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func saveVideo() {
        guard !isSaving, !didSave else {
            return
        }

        isSaving = true
        statusMessage = "保存しています..."

        onSave(videoURL) { result in
            isSaving = false

            switch result {
            case .success:
                didSave = true
                statusMessage = "写真ライブラリに保存しました。"
            case .failure(let error):
                statusMessage = error.localizedDescription
            }

            onSaveCompleted(result)
        }
    }
}

struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

#Preview {
    CapturedVideoPreviewView(
        videoURL: URL(fileURLWithPath: "/tmp/preview.mp4"),
        onSave: { _, completion in completion(.success(())) }
    ) { _ in }
}
