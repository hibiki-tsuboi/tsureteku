//
//  ContentView.swift
//  Tsureteku
//
//  Library of registered companions plus an entry point into the AR placement
//  view. Add flow: PhotosPicker → AddCharacterView (cutout + name) → save.
//

import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Companion.createdAt, order: .reverse) private var companions: [Companion]

    @State private var pickerItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var isAddSheetPresented = false
    @State private var isARPresented = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if companions.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("つれてく")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    isARPresented = true
                } label: {
                    Label("ARで連れていく", systemImage: "arkit")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .disabled(companions.isEmpty)
            }
            .fullScreenCover(isPresented: $isARPresented) {
                ARPlacementView(companions: companions)
            }
            .sheet(isPresented: $isAddSheetPresented) {
                if let sourceImage {
                    AddCharacterView(sourceImage: sourceImage)
                }
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        sourceImage = image
                        isAddSheetPresented = true
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("ぬいぐるみを登録", systemImage: "teddybear")
        } description: {
            Text("右上の + から写真を選ぶと、被写体を切り抜いて登録します")
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(companions) { companion in
                    cell(for: companion)
                }
            }
            .padding()
        }
    }

    private func cell(for companion: Companion) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                if let ui = UIImage(data: companion.imageData) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            .frame(height: 120)

            Text(companion.name)
                .font(.caption)
                .lineLimit(1)
        }
        .contextMenu {
            Button("削除", role: .destructive) {
                modelContext.delete(companion)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Companion.self, inMemory: true)
}
