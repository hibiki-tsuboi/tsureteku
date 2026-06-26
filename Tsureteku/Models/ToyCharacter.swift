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
    static let arBrightnessMultiplierRange: ClosedRange<Double> = 0.6...1.6

    var id: UUID
    var name: String
    var originalImageFileName: String
    var cutoutImageFileName: String
    var modelFileName: String? = nil
    var objectCaptureDirectoryName: String? = nil
    var defaultSizeMeters: Double = 0.34
    var arBrightnessMultiplier: Double = 1.0
    var modelYawDegrees: Double = 0
    var modelVerticalOffsetMeters: Double = 0
    var isARMotionEnabled: Bool = false
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    var normalizedARBrightnessMultiplier: Double {
        let multiplier = arBrightnessMultiplier > 0 ? arBrightnessMultiplier : 1
        return min(
            max(multiplier, Self.arBrightnessMultiplierRange.lowerBound),
            Self.arBrightnessMultiplierRange.upperBound
        )
    }

    init(
        id: UUID = UUID(),
        name: String,
        originalImageFileName: String,
        cutoutImageFileName: String,
        modelFileName: String? = nil,
        objectCaptureDirectoryName: String? = nil,
        defaultSizeMeters: Double = 0.34,
        arBrightnessMultiplier: Double = 1.0,
        modelYawDegrees: Double = 0,
        modelVerticalOffsetMeters: Double = 0,
        isARMotionEnabled: Bool = false,
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
        self.arBrightnessMultiplier = arBrightnessMultiplier
        self.modelYawDegrees = modelYawDegrees
        self.modelVerticalOffsetMeters = modelVerticalOffsetMeters
        self.isARMotionEnabled = isARMotionEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}
