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
                        Button("自動判定に戻す", action: revertToAutomatic)
                    } footer: {
                        Text("次に履歴を開いたときに、自動でタグを判定し直します。")
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

    private func revertToAutomatic() {
        photo.isSceneTagsEditedManually = false
        photo.sceneClassifierVersion = 0
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    SceneTagEditView(photo: CapturedPhoto(imageFileName: "sample.jpg"))
        .modelContainer(for: [CapturedPhoto.self], inMemory: true)
}
