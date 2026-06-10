//
//  AddCharacterView.swift
//  Tsureteku
//
//  Sheet: takes a picked photo, runs subject cutout, lets the user name and
//  save the result as a Character.
//

import SwiftData
import SwiftUI
import UIKit

struct AddCharacterView: View {
    let sourceImage: UIImage

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var cutoutImage: UIImage?
    @State private var phase: Phase = .processing

    private enum Phase: Equatable {
        case processing
        case ready
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .background(checkerboard, in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                TextField("名前（例: くまさん）", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)

                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("キャラを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .task { await runCutout() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch phase {
        case .processing:
            VStack(spacing: 12) {
                ProgressView()
                Text("被写体を抽出中…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .ready:
            if let cutoutImage {
                Image(uiImage: cutoutImage)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // Subtle checker pattern so transparent areas read as transparent.
    private var checkerboard: some ShapeStyle {
        LinearGradient(
            colors: [.gray.opacity(0.10), .gray.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var canSave: Bool {
        guard case .ready = phase else { return false }
        guard cutoutImage != nil else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runCutout() async {
        do {
            let result = try await SubjectCutoutService.extractForeground(from: sourceImage)
            cutoutImage = result
            phase = .ready
        } catch SubjectCutoutError.noSubjectFound {
            phase = .failed("被写体を見つけられませんでした。別の写真を試してください。")
        } catch {
            phase = .failed("切り抜きに失敗しました。")
        }
    }

    private func save() {
        guard let cutoutImage, let data = cutoutImage.pngData() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let companion = Companion(name: trimmed, imageData: data)
        modelContext.insert(companion)
        dismiss()
    }
}
