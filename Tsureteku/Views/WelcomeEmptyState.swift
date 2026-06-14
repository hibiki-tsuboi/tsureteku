//
//  WelcomeEmptyState.swift
//  Tsureteku
//
//  3タブで共通利用する空状態ビュー。世界観を統一し、
//  「何をするアプリか」を温かく・ポップに伝える。
//

import SwiftUI

struct WelcomeEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(LinearGradient.brand)
                    .frame(width: 128, height: 128)
                    .shadow(color: BrandColor.purple.opacity(0.35), radius: 18, y: 8)

                Image(systemName: icon)
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 10) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 28)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }
                .buttonStyle(BrandButtonStyle())
                .padding(.top, 2)
            }
        }
        .padding(24)
    }
}

/// ブランドの紫グラデーションを使った、ポップな丸ピルボタン。
struct BrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 30)
            .background(LinearGradient.brand, in: Capsule())
            .shadow(color: BrandColor.purple.opacity(0.4), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    WelcomeEmptyState(
        icon: "teddybear.fill",
        title: "ぬいぐるみを連れていこう",
        message: "お気に入りのぬいぐるみを撮って登録すると、ARで一緒に写真が撮れるよ。",
        actionTitle: "最初のぬいぐるみを登録",
        action: {}
    )
}
