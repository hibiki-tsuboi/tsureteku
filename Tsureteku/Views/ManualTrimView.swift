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

    /// 画像に対する正規化座標 [0,1] の切り抜き範囲。
    @State private var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// ドラッグ開始時の範囲。translation を始点に足して算出するため保持する。
    @State private var dragStartRect: CGRect?

    /// 切り抜き範囲の最小サイズ（画像比）。
    private let minSize: CGFloat = 0.1

    private enum Corner {
        case topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { geometry in
                    let displayRect = aspectFitRect(imageSize: image.size, in: geometry.size)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()

                        cropOverlay(displayRect: displayRect)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .padding()

                VStack(spacing: 12) {
                    Text("枠の角をドラッグして、切り抜く範囲を決めます。枠の中をドラッグすると移動できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                        }
                    } label: {
                        Label("リセット", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
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

    // MARK: - Overlay

    @ViewBuilder
    private func cropOverlay(displayRect: CGRect) -> some View {
        let frame = cropFrameRect(in: displayRect)

        // 範囲外を暗くし、切り抜き範囲だけ明るく見せる。
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.45))
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)

            Rectangle()
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)

        // 枠の中をドラッグして移動。
        Color.clear
            .frame(width: frame.width, height: frame.height)
            .contentShape(Rectangle())
            .position(x: frame.midX, y: frame.midY)
            .gesture(moveGesture(displayRect: displayRect))

        // 枠線。
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)

        // 四隅のハンドル。
        handle(.topLeading, displayRect: displayRect)
        handle(.topTrailing, displayRect: displayRect)
        handle(.bottomLeading, displayRect: displayRect)
        handle(.bottomTrailing, displayRect: displayRect)
    }

    private func handle(_ corner: Corner, displayRect: CGRect) -> some View {
        let frame = cropFrameRect(in: displayRect)
        let point: CGPoint
        switch corner {
        case .topLeading:
            point = CGPoint(x: frame.minX, y: frame.minY)
        case .topTrailing:
            point = CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeading:
            point = CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing:
            point = CGPoint(x: frame.maxX, y: frame.maxY)
        }

        return ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(Color.accentColor, lineWidth: 2)
        }
        .frame(width: 22, height: 22)
        .shadow(color: .black.opacity(0.3), radius: 2)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .position(point)
        .gesture(cornerGesture(corner, displayRect: displayRect))
    }

    // MARK: - Gestures

    private func moveGesture(displayRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect else { return }
                moveCrop(translation: value.translation, start: start, displayRect: displayRect)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func cornerGesture(_ corner: Corner, displayRect: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartRect == nil {
                    dragStartRect = cropRect
                }
                guard let start = dragStartRect else { return }
                resizeCorner(corner, translation: value.translation, start: start, displayRect: displayRect)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    private func moveCrop(translation: CGSize, start: CGRect, displayRect: CGRect) {
        let dx = displayRect.width > 0 ? translation.width / displayRect.width : 0
        let dy = displayRect.height > 0 ? translation.height / displayRect.height : 0

        let newMinX = min(max(0, start.minX + dx), 1 - start.width)
        let newMinY = min(max(0, start.minY + dy), 1 - start.height)
        cropRect = CGRect(x: newMinX, y: newMinY, width: start.width, height: start.height)
    }

    private func resizeCorner(_ corner: Corner, translation: CGSize, start: CGRect, displayRect: CGRect) {
        let dx = displayRect.width > 0 ? translation.width / displayRect.width : 0
        let dy = displayRect.height > 0 ? translation.height / displayRect.height : 0

        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch corner {
        case .topLeading:
            minX = max(0, min(start.minX + dx, start.maxX - minSize))
            minY = max(0, min(start.minY + dy, start.maxY - minSize))
        case .topTrailing:
            maxX = min(1, max(start.maxX + dx, start.minX + minSize))
            minY = max(0, min(start.minY + dy, start.maxY - minSize))
        case .bottomLeading:
            minX = max(0, min(start.minX + dx, start.maxX - minSize))
            maxY = min(1, max(start.maxY + dy, start.minY + minSize))
        case .bottomTrailing:
            maxX = min(1, max(start.maxX + dx, start.minX + minSize))
            maxY = min(1, max(start.maxY + dy, start.minY + minSize))
        }

        cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Geometry

    /// 画像をコンテナ内にアスペクト維持で収めたときの表示矩形（scaledToFit と一致）。
    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// 正規化された cropRect を、表示矩形内のビュー座標へ変換する。
    private func cropFrameRect(in displayRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + cropRect.minX * displayRect.width,
            y: displayRect.minY + cropRect.minY * displayRect.height,
            width: cropRect.width * displayRect.width,
            height: cropRect.height * displayRect.height
        )
    }

    private func applyCrop() {
        guard let croppedImage = ImageCropService.crop(image, normalizedRect: cropRect) else {
            return
        }

        onSave(croppedImage)
        dismiss()
    }
}
