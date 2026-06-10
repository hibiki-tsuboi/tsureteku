//
//  Companion.swift
//  Tsureteku
//
//  A user-registered character cut out from a photo. `imageData` is a PNG with
//  alpha — what the AR placement view binds as a billboard texture. The type
//  name avoids `Character`, which collides with Swift's built-in glyph type.
//

import Foundation
import SwiftData

@Model
final class Companion {
    var name: String
    var createdAt: Date
    // Stored as a separate file via SwiftData's external storage so the
    // SQLite store stays small.
    @Attribute(.externalStorage) var imageData: Data

    init(name: String, imageData: Data, createdAt: Date = .now) {
        self.name = name
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
