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
                    Label("AR", systemImage: "camera.viewfinder")
                }

            CharacterLibraryView()
                .tabItem {
                    Label("キャラ", systemImage: "teddybear")
                }

            CapturedPhotoHistoryView()
                .tabItem {
                    Label("履歴", systemImage: "photo.stack")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
