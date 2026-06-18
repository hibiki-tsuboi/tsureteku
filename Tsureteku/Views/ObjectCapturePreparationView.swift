//
//  ObjectCapturePreparationView.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import RealityKit
import SwiftData
import SwiftUI

struct ObjectCapturePreparationView: View {
    @Bindable var character: ToyCharacter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if ObjectCaptureSession.isSupported {
                tutorialContent
            } else {
                unsupportedContent
            }
        }
        .navigationTitle("3D撮影の準備")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ObjectCaptureSession.isSupported {
                startFooter
            }
        }
    }

    private var tutorialContent: some View {
        List {
            Section {
                header
            }

            Section("始める前に") {
                PreparationChecklistRow(
                    iconName: "light.max",
                    title: "明るい場所に置く",
                    description: "影が強すぎない場所で、推し全体が見えるようにします。"
                )

                PreparationChecklistRow(
                    iconName: "hand.raised",
                    title: "推しは動かさない",
                    description: "撮影中は本体を固定し、iPhoneだけをゆっくり動かします。"
                )

                PreparationChecklistRow(
                    iconName: "photo.stack",
                    title: "20枚以上撮る",
                    description: "少ない枚数では3Dモデル作成に進めません。角度を変えて一周撮ります。"
                )
            }

            Section("撮影の流れ") {
                CaptureTutorialStepRow(
                    number: 1,
                    title: "推しを認識",
                    description: "画面内に全体を入れて、対象を検出します。"
                )

                CaptureTutorialStepRow(
                    number: 2,
                    title: "周りを撮影",
                    description: "推しの周囲をゆっくり回りながら、正面と側面を撮ります。"
                )

                CaptureTutorialStepRow(
                    number: 3,
                    title: "裏側を撮影",
                    description: "表側が終わったら、必要に応じて裏返して背面も撮ります。"
                )

                CaptureTutorialStepRow(
                    number: 4,
                    title: "3Dモデルを作成",
                    description: "撮影データからUSDZモデルを作り、AR配置で使えるようにします。"
                )
            }

            Section("うまく作るコツ") {
                PreparationChecklistRow(
                    iconName: "arrow.triangle.2.circlepath.camera",
                    title: "急に動かさない",
                    description: "iPhoneを速く振ると追跡が不安定になります。少しずつ角度を変えます。"
                )

                PreparationChecklistRow(
                    iconName: "square.grid.3x3",
                    title: "背景と少し離す",
                    description: "壁や床と近すぎると形を拾いにくくなります。周りに少し余白を作ります。"
                )

                PreparationChecklistRow(
                    iconName: "sparkles",
                    title: "透明・光沢は苦手",
                    description: "反射する素材や透明パーツは、3D化すると崩れることがあります。"
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            CharacterThumbnailView(character: character)
                .frame(width: 104)

            VStack(alignment: .leading, spacing: 8) {
                Text(character.name)
                    .font(.title3.weight(.semibold))

                Text("撮影画面に進むとカメラが起動します。まず置き方と撮り方を確認してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var startFooter: some View {
        VStack(spacing: 8) {
            NavigationLink {
                // 作成成功時はこの準備画面ごと閉じ、その上の撮影画面も一緒に閉じて詳細画面へ戻す。
                ObjectCaptureWorkflowView(character: character, onModelCreated: { dismiss() })
            } label: {
                Label("撮影を始める", systemImage: "camera.aperture")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("撮影中は推しを固定し、iPhoneを動かします。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    private var unsupportedContent: some View {
        ContentUnavailableView {
            Label("3D撮影はこの端末では使えません", systemImage: "iphone.slash")
        } description: {
            Text("Object Capture対応iPhoneの実機で開いてください。USDZの登録はこのまま利用できます。")
        }
    }
}

private struct PreparationChecklistRow: View {
    let iconName: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CaptureTutorialStepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        ObjectCapturePreparationView(
            character: ToyCharacter(
                name: "推し",
                originalImageFileName: "preview-original.png",
                cutoutImageFileName: "preview-cutout.png"
            )
        )
    }
    .modelContainer(for: ToyCharacter.self, inMemory: true)
}
