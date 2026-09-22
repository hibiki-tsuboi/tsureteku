//
//  BackupRestoreView.swift
//  Tsureteku
//
//  Created by Claude on 2026/09/22.
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 機種変更用に、全データをJSONファイルへ書き出す・JSONファイルから復元する画面。
struct BackupRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var characters: [ToyCharacter]
    @Query private var photos: [CapturedPhoto]

    @State private var includesObjectCaptureData = true
    @State private var sizeEstimate: BackupSizeEstimate?
    @State private var runningOperation: BackupOperation?
    @State private var progress = 0.0
    @State private var operationTask: Task<Void, Never>?
    @State private var exportedBackup: ExportedBackup?
    @State private var isImporterPresented = false
    @State private var restoreResult: BackupRestoreResult?
    @State private var isRestoreResultPresented = false
    @State private var errorMessage: String?
    @State private var isErrorPresented = false

    var body: some View {
        NavigationStack {
            Form {
                if let runningOperation {
                    progressSection(for: runningOperation)
                }

                exportSection
                restoreSection
            }
            .navigationTitle("バックアップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .disabled(isRunning)
                }
            }
        }
        .interactiveDismissDisabled(isRunning)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.json]) { result in
            handleImportSelection(result)
        }
        .sheet(item: $exportedBackup) { backup in
            BackupShareSheet(url: backup.url)
        }
        .alert(
            restoreResult.map(restoreResultTitle) ?? "",
            isPresented: $isRestoreResultPresented,
            presenting: restoreResult
        ) { _ in
            Button("OK") {}
        } message: { result in
            Text(restoreResultMessage(result))
        }
        .alert("エラー", isPresented: $isErrorPresented, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .task(id: sizeEstimateID) {
            await updateSizeEstimate()
        }
    }

    // MARK: - セクション

    private var exportSection: some View {
        Section {
            LabeledContent("推し", value: "\(characters.count)体")
            LabeledContent("写真・動画", value: "\(photos.count)件")

            if hasObjectCaptureData {
                Toggle(isOn: $includesObjectCaptureData) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("3D撮影の元データを含める")

                        Text(objectCaptureDataDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isRunning)
            }

            if hasData {
                LabeledContent("ファイルサイズ（目安）") {
                    if let sizeEstimate {
                        Text("約\(formattedByteCount(sizeEstimate.backupFileBytes(includingObjectCaptureData: includesObjectCaptureData)))")
                    } else {
                        ProgressView()
                    }
                }
            }

            Button {
                startExport()
            } label: {
                Label("バックアップを書き出す", systemImage: "square.and.arrow.up")
            }
            .disabled(isRunning || !hasData)
        } header: {
            Text("書き出し")
        } footer: {
            Text("推し・3Dモデル・写真・動画・タグをすべて1つのJSONファイルにまとめます。AirDropや「ファイル」アプリで新しいiPhoneへ移してください。")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                isImporterPresented = true
            } label: {
                Label("バックアップから復元", systemImage: "square.and.arrow.down")
            }
            .disabled(isRunning)
        } header: {
            Text("復元")
        } footer: {
            Text("書き出したJSONファイルを選んでください。今あるデータは消えずに追加され、すでにある推しや写真はスキップします。")
        }
    }

    private func progressSection(for operation: BackupOperation) -> some View {
        Section {
            ProgressView(value: progress) {
                Text(operation.title)
            } currentValueLabel: {
                Text(progress, format: .percent.precision(.fractionLength(0)))
            }
            .padding(.vertical, 4)

            Button("キャンセル", role: .cancel) {
                operationTask?.cancel()
            }
        } footer: {
            Text("完了するまでアプリを開いたままにしてください。")
        }
    }

    // MARK: - 表示用

    private var isRunning: Bool {
        runningOperation != nil
    }

    private var hasData: Bool {
        !characters.isEmpty || !photos.isEmpty
    }

    private var hasObjectCaptureData: Bool {
        characters.contains { $0.objectCaptureDirectoryName != nil }
    }

    private var objectCaptureDataDescription: String {
        var text = "3Dモデルを作り直すときに使う撮影写真です。"

        if let sizeEstimate {
            text += "（約\(formattedByteCount(sizeEstimate.objectCaptureBytes))）"
        }

        return text
    }

    /// データが増減したら書き出しサイズを計算し直す。
    private var sizeEstimateID: String {
        "\(characters.count)-\(photos.count)"
    }

    private func formattedByteCount(_ byteCount: Int64) -> String {
        byteCount.formatted(.byteCount(style: .file))
    }

    private func restoreResultTitle(_ result: BackupRestoreResult) -> String {
        result.restoredCharacterCount + result.restoredPhotoCount > 0 ? "復元しました" : "追加するデータはありませんでした"
    }

    private func restoreResultMessage(_ result: BackupRestoreResult) -> String {
        var lines: [String] = []

        if result.restoredCharacterCount + result.restoredPhotoCount > 0 {
            lines.append("推し\(result.restoredCharacterCount)体、写真・動画\(result.restoredPhotoCount)件を追加しました。")
        }

        if result.skippedCount > 0 {
            lines.append("すでにある\(result.skippedCount)件はスキップしました。")
        }

        if result.missingFileCount > 0 {
            lines.append("\(result.missingFileCount)個のファイルがバックアップに入っていませんでした。")
        }

        if lines.isEmpty {
            lines.append("バックアップにデータが入っていませんでした。")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - 処理

    private func updateSizeEstimate() async {
        guard let plan = try? BackupService.makeExportPlan(from: modelContext) else {
            return
        }

        sizeEstimate = await BackupService.estimateSize(of: plan)
    }

    private func startExport() {
        let plan: BackupExportPlan
        do {
            plan = try BackupService.makeExportPlan(from: modelContext)
        } catch {
            showError(error)
            return
        }

        let includesObjectCaptureData = includesObjectCaptureData
        run(.exporting) { reportProgress in
            let url = try await BackupService.export(
                plan,
                includingObjectCaptureData: includesObjectCaptureData,
                progress: reportProgress
            )
            try Task.checkCancellation()
            exportedBackup = ExportedBackup(url: url)
        }
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        let backupURL: URL
        do {
            backupURL = try result.get()
        } catch {
            showError(error)
            return
        }

        run(.restoring) { reportProgress in
            let payload = try await BackupService.prepareRestore(from: backupURL, progress: reportProgress)

            guard !Task.isCancelled else {
                BackupService.discard(payload)
                throw CancellationError()
            }

            restoreResult = try BackupService.restore(payload, into: modelContext)
            isRestoreResultPresented = true
        }
    }

    /// 重い処理を進捗つきで実行する。キャンセルされたときは何も表示しない。
    private func run(
        _ operation: BackupOperation,
        _ work: @escaping (_ reportProgress: @escaping @Sendable (Double) -> Void) async throws -> Void
    ) {
        progress = 0
        runningOperation = operation
        // 数GBの処理中に画面が消えて中断されないよう、自動ロックを止めておく。
        UIApplication.shared.isIdleTimerDisabled = true

        operationTask = Task {
            defer {
                runningOperation = nil
                operationTask = nil
                UIApplication.shared.isIdleTimerDisabled = false
            }

            do {
                try await work { value in
                    Task { @MainActor in
                        progress = value
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        isErrorPresented = true
    }
}

private enum BackupOperation {
    case exporting
    case restoring

    var title: String {
        switch self {
        case .exporting:
            "書き出し中…"
        case .restoring:
            "復元中…"
        }
    }
}

private struct ExportedBackup: Identifiable {
    let id = UUID()
    let url: URL
}

private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    BackupRestoreView()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
