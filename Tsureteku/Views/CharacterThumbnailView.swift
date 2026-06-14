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

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    }
                    .frame(width: 76, height: 76)

                if let image = CharacterImageStore.image(named: character.cutoutImageFileName, kind: .cutout) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                        .frame(width: 76, height: 76)
                } else {
                    Image(systemName: "teddybear")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                if character.modelFileName != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "cube.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Color.accentColor, in: Circle())
                                .padding(4)
                        }
                    }
                    .frame(width: 76, height: 76)
                }
            }

            Text(character.name)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 82)
        }
    }
}
