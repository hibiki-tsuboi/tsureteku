//
//  ToyCharacter.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/09.
//

import Foundation
import SwiftData

@Model
final class ToyCharacter {
    var id: UUID
    var name: String
    var originalImageFileName: String
    var cutoutImageFileName: String
    var modelFileName: String? = nil
    var objectCaptureDirectoryName: String? = nil
    var defaultSizeMeters: Double = 0.34
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        originalImageFileName: String,
        cutoutImageFileName: String,
        modelFileName: String? = nil,
        objectCaptureDirectoryName: String? = nil,
        defaultSizeMeters: Double = 0.34,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.originalImageFileName = originalImageFileName
        self.cutoutImageFileName = cutoutImageFileName
        self.modelFileName = modelFileName
        self.objectCaptureDirectoryName = objectCaptureDirectoryName
        self.defaultSizeMeters = defaultSizeMeters
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}
