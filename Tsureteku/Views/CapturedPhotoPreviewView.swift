//
//  CapturedPhotoPreviewView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import SwiftUI
import UIKit

struct CapturedPhotoPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    var onSave: (UIImage, @escaping (Result<Void, Error>) -> Void) -> Void
    var onSaveCompleted: (Result<Void, Error>) -> Void

    @State private var isSaving = false
    @State private var didSave = false
    @State private var statusMessage: String?
    @State private var isShareSheetPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 132)

                VStack(spacing: 0) {
                    Spacer()

                    footer
                }
            }
            .navigationTitle("撮影プレビュー")
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
                PhotoShareSheet(image: image)
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
                    dismiss()
                } label: {
                    Label("撮り直す", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button {
                    savePhoto()
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

    private func savePhoto() {
        guard !isSaving, !didSave else {
            return
        }

        isSaving = true
        statusMessage = "保存しています..."

        onSave(image) { result in
            isSaving = false

            switch result {
            case .success:
                didSave = true
                statusMessage = "写真に保存しました。"
            case .failure(let error):
                statusMessage = error.localizedDescription
            }

            onSaveCompleted(result)
        }
    }
}

struct PhotoShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

#Preview {
    CapturedPhotoPreviewView(
        image: UIImage(systemName: "photo") ?? UIImage(),
        onSave: { _, completion in completion(.success(())) }
    ) { _ in }
}
