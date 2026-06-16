//
//  CharacterThumbnailView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import SwiftUI

struct CharacterThumbnailView: View {
    let character: ToyCharacter
    var isSelected = false
    /// 撮影画面のピッカー用。サムネを小さくし、名前ラベルを省いて高さを詰める。
    var compact = false

    private var side: CGFloat { compact ? 54 : 76 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                    .frame(width: side, height: side)

                if let image = CharacterImageStore.image(named: character.cutoutImageFileName, kind: .cutout) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(compact ? 5 : 7)
                        .frame(width: side, height: side)
                } else {
                    Image(systemName: "teddybear")
                        .font(compact ? .body : .title2)
                        .foregroundStyle(.secondary)
                }

                if character.modelFileName != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "cube.fill")
                                .font(compact ? .caption2 : .caption)
                                .foregroundStyle(.white)
                                .padding(compact ? 3 : 5)
                                .background(Color.accentColor, in: Circle())
                                .padding(compact ? 3 : 4)
                        }
                    }
                    .frame(width: side, height: side)
                }
            }

            if !compact {
                Text(character.name)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 82)
            }
        }
    }
}
