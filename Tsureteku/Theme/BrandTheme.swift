//
//  BrandTheme.swift
//  Tsureteku
//
//  アプリ全体で共有するブランドカラーとスタイル。
//  AppIcon の紫グラデ＋ミントの差し色に合わせた「ポップで元気」なトーン。
//

import SwiftUI

enum BrandColor {
    /// メインの紫（アクセントカラーと同値） #7C5CFF
    static let purple = Color(red: 0.486, green: 0.361, blue: 1.0)
    /// 濃い紫（グラデーション下・押下） #5B3FD9
    static let purpleDeep = Color(red: 0.357, green: 0.247, blue: 0.851)
    /// 明るい紫（グラデーション上・淡い背景） #B9A3F0
    static let purpleLight = Color(red: 0.725, green: 0.639, blue: 0.941)
    /// ポップな差し色のミント #3FE0B8
    static let mint = Color(red: 0.247, green: 0.878, blue: 0.722)
    /// 温かみのあるクリーム #FFF6E3
    static let cream = Color(red: 1.0, green: 0.965, blue: 0.890)
}

extension LinearGradient {
    /// ブランドの紫グラデーション。
    static let brand = LinearGradient(
        colors: [BrandColor.purpleLight, BrandColor.purple, BrandColor.purpleDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
