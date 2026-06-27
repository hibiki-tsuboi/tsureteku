//
//  UTType+Tsureteku.swift
//  Tsureteku
//
//  Created by Codex on 2026/06/27.
//

import UniformTypeIdentifiers

extension UTType {
    static var usdzModel: UTType {
        UTType(filenameExtension: "usdz") ?? .data
    }
}
