//
//  CharacterPlaceholderImageFactory.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/27.
//

import UIKit

enum CharacterPlaceholderImageFactory {
    static func make3DModelImage() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let configuration = UIImage.SymbolConfiguration(pointSize: 190, weight: .semibold)
            let symbol = UIImage(systemName: "cube.fill", withConfiguration: configuration)?
                .withTintColor(.systemPurple, renderingMode: .alwaysOriginal)
            let symbolSize = CGSize(width: 230, height: 230)
            let symbolOrigin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )

            symbol?.draw(in: CGRect(origin: symbolOrigin, size: symbolSize))
        }
    }
}
