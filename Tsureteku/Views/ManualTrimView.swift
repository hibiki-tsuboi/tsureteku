//
//  ManualTrimView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import SwiftUI
import UIKit

struct ManualTrimView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    var onSave: (UIImage) -> Void

    @State private var leadingTrim = 0.0
    @State private var trailingTrim = 0.0
    @State private var topTrim = 0.0
    @State private var bottomTrim = 0.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                preview
                    .padding()

                Form {
                    trimSlider("左", value: $leadingTrim)
                    trimSlider("右", value: $trailingTrim)
                    trimSlider("上", value: $topTrim)
                    trimSlider("下", value: $bottomTrim)

                    Button {
                        leadingTrim = 0
                        trailingTrim = 0
                        topTrim = 0
                        bottomTrim = 0
                    } label: {
                        Label("リセット", systemImage: "arrow.counterclockwise")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("トリミング")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        applyCrop()
                    }
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.thinMaterial)

            Image(uiImage: previewImage)
                .resizable()
                .scaledToFit()
                .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private var previewImage: UIImage {
        ImageCropService.crop(image, normalizedRect: cropRect) ?? image
    }

    private var cropRect: CGRect {
        let maxHorizontalTrim = min(0.9, leadingTrim + trailingTrim)
        let maxVerticalTrim = min(0.9, topTrim + bottomTrim)

        let adjustedTrailing = maxHorizontalTrim >= 0.9 ? 0.9 - leadingTrim : trailingTrim
        let adjustedBottom = maxVerticalTrim >= 0.9 ? 0.9 - topTrim : bottomTrim

        return CGRect(
            x: leadingTrim,
            y: topTrim,
            width: max(0.1, 1 - leadingTrim - adjustedTrailing),
            height: max(0.1, 1 - topTrim - adjustedBottom)
        )
    }

    private func trimSlider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .frame(width: 28, alignment: .leading)

            Slider(value: value, in: 0...0.45)

            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func applyCrop() {
        guard let croppedImage = ImageCropService.crop(image, normalizedRect: cropRect) else {
            return
        }

        onSave(croppedImage)
        dismiss()
    }
}
