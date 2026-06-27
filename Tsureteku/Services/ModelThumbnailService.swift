//
//  ModelThumbnailService.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/27.
//

import QuickLookThumbnailing
import UIKit

enum ModelThumbnailService {
    static func makeThumbnail(for modelURL: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: modelURL,
                size: CGSize(width: 512, height: 512),
                scale: UIScreen.main.scale,
                representationTypes: .thumbnail
            )

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                guard let image = representation?.uiImage else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: ImagePreparation.normalizedAndScaled(image))
            }
        }
    }
}
