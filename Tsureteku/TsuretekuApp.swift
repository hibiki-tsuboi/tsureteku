//
//  TsuretekuApp.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/09.
//

import SwiftUI
import SwiftData

@main
struct TsuretekuApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ToyCharacter.self,
            CapturedPhoto.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
