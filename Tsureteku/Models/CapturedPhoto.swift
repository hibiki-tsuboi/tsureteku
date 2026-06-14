//
//  CapturedPhoto.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/11.
//

import Foundation
import SwiftData

@Model
final class CapturedPhoto {
    var id: UUID
    var imageFileName: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        imageFileName: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.createdAt = createdAt
    }
}
