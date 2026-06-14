//
//  ContentView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/09.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            ARCameraScreen()
                .tabItem {
                    Image(systemName: "camera.viewfinder")
                        .accessibilityLabel("AR")
                }

            CharacterLibraryView()
                .tabItem {
                    Image(systemName: "teddybear")
                        .accessibilityLabel("キャラ")
                }

            CapturedPhotoHistoryView()
                .tabItem {
                    Image(systemName: "photo.stack")
                        .accessibilityLabel("履歴")
                }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
