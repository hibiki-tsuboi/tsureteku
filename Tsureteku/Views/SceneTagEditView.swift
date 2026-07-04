//
//  SceneTagEditView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/07/04.
//

import SwiftData
import SwiftUI

/// 写真・動画のシーンタグを手動で付け外しするシート。
struct SceneTagEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let photo: CapturedPhoto

    /// 「自動で判定し直す」の実行中かどうか。
    @State private var isReclassifying = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SceneTag.allCases, id: \.self) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack {
                                Label(tag.displayName, systemImage: tag.iconName)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if photo.sceneTags.contains(tag) {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(BrandColor.purple)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("手動で変更したタグは、自動判定で上書きされなくなります。")
                }

                if photo.isSceneTagsEditedManually {
                    Section {
                        Button(action: reclassify) {
                            HStack {
                                Text("タグを自動で判定し直す")

                                if isReclassifying {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isReclassifying)
                    } footer: {
                        Text("手動での変更を破棄して、いますぐ自動判定をやり直します。")
                    }
                }
            }
            .navigationTitle("タグを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func toggle(_ tag: SceneTag) {
        var tags = Set(photo.sceneTags)
        if tags.contains(tag) {
            tags.remove(tag)
        } else {
            tags.insert(tag)
        }

        // 表示順が安定するよう allCases の並びで保存する。
        photo.sceneTags = SceneTag.allCases.filter(tags.contains)
        photo.isSceneTagsEditedManually = true
        try? modelContext.save()
    }

    /// その場で自動判定をやり直し、結果を即座にチェックマークへ反映する。
    /// 遅延実行（次回履歴表示時の再分類）だと押した直後に何も変わらず分かりづらいため。
    private func reclassify() {
        isReclassifying = true
        Task {
            // 分類には縮小画像で十分。履歴画面のバックフィルと同じ条件で判定する。
            let tags: [SceneTag]
            if let image = CapturedPhotoStore.thumbnail(named: photo.imageFileName, maxPixelSize: 512) {
                tags = await SceneClassificationService.tags(in: image)
            } else {
                tags = []
            }

            photo.sceneTags = tags
            photo.isSceneTagsEditedManually = false
            photo.sceneClassifierVersion = SceneClassificationService.classifierVersion
            try? modelContext.save()
            isReclassifying = false
        }
    }
}

#Preview {
    SceneTagEditView(photo: CapturedPhoto(imageFileName: "sample.jpg"))
        .modelContainer(for: [CapturedPhoto.self], inMemory: true)
}
