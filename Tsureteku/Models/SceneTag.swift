//
//  SceneTag.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/07/04.
//

import Foundation

/// 撮影メディアにシーン自動分類で付与するタグ。
/// Vision の分類ラベル（英語・約1,300種）をそのまま持つと表示も絞り込みも扱いづらいため、
/// アプリで意味のある少数の日本語カテゴリへ集約する。
enum SceneTag: String, Codable, CaseIterable {
    case outdoor
    case indoor
    case nature
    case water
    case food
    case night
    case city

    var displayName: String {
        switch self {
        case .outdoor:
            "屋外"
        case .indoor:
            "屋内"
        case .nature:
            "自然"
        case .water:
            "水辺"
        case .food:
            "食べ物"
        case .night:
            "夜"
        case .city:
            "街"
        }
    }

    var iconName: String {
        switch self {
        case .outdoor:
            "sun.max"
        case .indoor:
            "house"
        case .nature:
            "leaf"
        case .water:
            "water.waves"
        case .food:
            "fork.knife"
        case .night:
            "moon.stars"
        case .city:
            "building.2"
        }
    }
}
