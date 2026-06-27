//
//  ContentView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/09.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedTab: AppTab = .ar
    @State private var arSessionResetTrigger = 0
    @State private var characterLibraryResetTrigger = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ARCameraScreen(sessionResetTrigger: arSessionResetTrigger)
                .tabItem {
                    Label("AR", systemImage: "camera.viewfinder")
                }
                .tag(AppTab.ar)

            CharacterLibraryView(resetTrigger: characterLibraryResetTrigger)
                .tabItem {
                    Label("推し", systemImage: "teddybear")
                }
                .tag(AppTab.characters)

            CapturedPhotoHistoryView()
                .tabItem {
                    Label("履歴", systemImage: "photo.stack")
                }
                .tag(AppTab.history)
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab == .ar, newTab != .ar {
                arSessionResetTrigger += 1
            }

            if oldTab != .characters, newTab == .characters {
                characterLibraryResetTrigger += 1
            }
        }
        .preferredColorScheme(.light)
    }
}

private enum AppTab: Hashable {
    case ar
    case characters
    case history
}

#Preview {
    ContentView()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
