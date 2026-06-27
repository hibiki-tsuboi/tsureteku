//
//  ToyCharacter.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/09.
//

import Foundation
import SwiftData

enum CharacterARPlacementMode: String, CaseIterable, Identifiable {
    case model3D
    case image2D

    var id: Self { self }

    var title: String {
        switch self {
        case .model3D:
            return "3D"
        case .image2D:
            return "画像"
        }
    }

    var systemImage: String {
        switch self {
        case .model3D:
            return "cube.fill"
        case .image2D:
            return "photo"
        }
    }
}

@Model
final class ToyCharacter {
    static let arBrightnessMultiplierRange: ClosedRange<Double> = 0.6...1.6
    static let initialSizeMeters = 0.20

    var id: UUID
    var name: String
    var originalImageFileName: String
    var cutoutImageFileName: String
    var modelFileName: String? = nil
    var objectCaptureDirectoryName: String? = nil
    var defaultSizeMeters: Double = ToyCharacter.initialSizeMeters
    var arBrightnessMultiplier: Double = 1.0
    var modelYawDegrees: Double = 0
    var modelVerticalOffsetMeters: Double = 0
    var isARMotionEnabled: Bool = false
    var arPlacementModeRawValue: String = CharacterARPlacementMode.model3D.rawValue
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?

    var arPlacementMode: CharacterARPlacementMode {
        get {
            CharacterARPlacementMode(rawValue: arPlacementModeRawValue) ?? .model3D
        }
        set {
            arPlacementModeRawValue = newValue.rawValue
        }
    }

    var effectiveARPlacementMode: CharacterARPlacementMode {
        modelFileName == nil ? .image2D : arPlacementMode
    }

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
        defaultSizeMeters: Double = ToyCharacter.initialSizeMeters,
        arBrightnessMultiplier: Double = 1.0,
        modelYawDegrees: Double = 0,
        modelVerticalOffsetMeters: Double = 0,
        isARMotionEnabled: Bool = false,
        arPlacementMode: CharacterARPlacementMode = .model3D,
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
        self.arPlacementModeRawValue = arPlacementMode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }
}
