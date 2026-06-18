//
//  ObjectCaptureWorkflowView.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import AVFoundation
import Combine
import RealityKit
import SwiftData
import SwiftUI
import _RealityKit_SwiftUI

struct ObjectCaptureWorkflowView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var character: ToyCharacter
    /// 3Dモデルの作成に成功したときに呼ばれる。撮影フローを閉じて詳細画面へ戻すために使う。
    var onModelCreated: () -> Void = {}

    @StateObject private var sessionStore = ObjectCaptureSessionStore()
    @State private var didStartSession = false
    @State private var captureState: ObjectCaptureSession.CaptureState = .initializing
    @State private var feedback: Set<ObjectCaptureSession.Feedback> = []
    @State private var cameraTracking: ObjectCaptureSession.Tracking = .notAvailable
    @State private var canRequestImageCapture = false
    @State private var userCompletedScanPass = false
    @State private var numberOfShotsTaken = 0
    @State private var isReconstructing = false
    @State private var reconstructionProgress = 0.0
    @State private var reconstructionStatus = ""
    @State private var errorMessage: String?
    /// モデル生成中に「使えなかった写真」の枚数。失敗時の原因案内に使う。
    @State private var unusableSampleCount = 0
    /// 直近のモデル生成が失敗したか。リトライ導線の出し分けに使う。
    @State private var reconstructionFailed = false
    /// 作成成功を伝えるアラートの表示状態。
    @State private var showCreationSuccessAlert = false
    @State private var statusMessage: String?
    @State private var didRequestDetection = false
    @State private var didRequestCapture = false
    @State private var activeCaptureDirectoryName: String?
    @State private var previousCaptureDirectoryName: String?

    private var session: ObjectCaptureSession {
        sessionStore.session
    }

    var body: some View {
        ZStack {
            if ObjectCaptureSession.isSupported {
                if shouldShowObjectCaptureView {
                    ObjectCaptureView(session: session)
                        .hideObjectReticle(false)
                        .id(session.id)
                        .ignoresSafeArea(edges: .top)
                } else {
                    completedCaptureBackground
                }

                overlay
                    .zIndex(1)
                    .allowsHitTesting(true)
            } else {
                ContentUnavailableView {
                    Label("Object Capture非対応", systemImage: "camera.aperture")
                } description: {
                    Text("3D撮影はObject Capture対応iPhoneの実機でのみ利用できます。")
                }
            }
        }
        .navigationTitle("3D撮影")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // 生成中に戻ると、モデルは保存されるのに完成通知が出ないまま離脱してしまう。
        // 完了アラート→詳細復帰の導線を必ず通すため、再構築中は戻る操作を無効化する。
        .navigationBarBackButtonHidden(isReconstructing)
        .interactiveDismissDisabled(isReconstructing)
        .alert("3Dモデルができました", isPresented: $showCreationSuccessAlert) {
            Button("OK") {
                onModelCreated()
            }
        } message: {
            Text("\(character.name)の3Dモデルを作成しました。AR配置で使えます。")
        }
        .onDisappear {
            if !isReconstructing {
                session.cancel()
                restorePreviousCaptureDirectoryIfEmpty()
            }
        }
        .task(id: session.id) {
            await startIfNeeded()
        }
        .task(id: session.id) {
            let currentSession = session
            captureState = currentSession.state

            for await state in currentSession.stateUpdates {
                handleCaptureStateUpdate(state)
            }
        }
        .task(id: session.id) {
            let currentSession = session
            feedback = currentSession.feedback

            for await feedback in currentSession.feedbackUpdates {
                self.feedback = feedback
            }
        }
        .task(id: session.id) {
            let currentSession = session
            cameraTracking = currentSession.cameraTracking

            for await tracking in currentSession.cameraTrackingUpdates {
                cameraTracking = tracking
            }
        }
        .task(id: session.id) {
            let currentSession = session
            canRequestImageCapture = currentSession.canRequestImageCapture

            for await canRequestImageCapture in currentSession.canRequestImageCaptureUpdates {
                self.canRequestImageCapture = canRequestImageCapture
            }
        }
        .task(id: session.id) {
            let currentSession = session
            userCompletedScanPass = currentSession.userCompletedScanPass

            for await userCompletedScanPass in currentSession.userCompletedScanPassUpdates {
                self.userCompletedScanPass = userCompletedScanPass
            }
        }
        .task(id: session.id) {
            let currentSession = session
            numberOfShotsTaken = currentSession.numberOfShotsTaken

            for await numberOfShotsTaken in currentSession.numberOfShotsTakenUpdates {
                self.numberOfShotsTaken = numberOfShotsTaken
            }
        }
    }

    private var shouldShowObjectCaptureView: Bool {
        guard !isReconstructing else {
            return false
        }

        if case .completed = captureState {
            return false
        }

        return true
    }

    private var completedCaptureBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if isReconstructing {
                ContentUnavailableView {
                    Label("3Dモデルを作成中", systemImage: "cube")
                } description: {
                    Text("完了までこのままお待ちください。")
                }
                .padding(.horizontal, 24)
            } else if canGenerateModel {
                ContentUnavailableView {
                    Label("撮影データを保存しました", systemImage: "checkmark.circle")
                } description: {
                    Text("このまま3Dモデルを作成できます。")
                }
                .padding(.horizontal, 24)
            } else {
                ContentUnavailableView {
                    Label("撮影データが不足しています", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("3Dモデル作成には20枚以上を目安に撮影してください。撮り直すには「撮り直す」をタップしてください。")
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private var overlay: some View {
        VStack(spacing: 0) {
            guidancePanel
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Spacer()

            actionPanel
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
        }
    }

    private var guidancePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(workflowStep.title, systemImage: workflowStep.iconName)
                    .font(.headline)

                Spacer()

                Text("\(workflowStep.index)/\(CaptureWorkflowStep.allCases.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            stepProgress

            Text(stepInstruction)
                .font(.subheadline)

            HStack(spacing: 12) {
                Label("\(numberOfShotsTaken)枚", systemImage: "photo.stack")
                Label(trackingLabelText, systemImage: "location.viewfinder")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isReconstructing {
                ProgressView(value: reconstructionProgress)
                Text(reconstructionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !feedback.isEmpty {
                Text(feedbackText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var stepProgress: some View {
        HStack(spacing: 6) {
            ForEach(CaptureWorkflowStep.allCases) { step in
                Capsule()
                    .fill(step.rawValue <= workflowStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
        }
        .accessibilityHidden(true)
    }

    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if userCompletedScanPass {
                Button {
                    beginBackSideCapture()
                } label: {
                    Label("裏側を撮る", systemImage: "arrow.triangle.2.circlepath.camera")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 12) {
                primaryButton

                if shouldShowFinishButton {
                    Button {
                        session.finish()
                    } label: {
                        Label("完了", systemImage: "checkmark")
                            .frame(minWidth: 86, minHeight: 46)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canFinish)
                    .accessibilityLabel("撮影完了")
                }
            }

            if case .completed = captureState {
                Button {
                    reconstructModel()
                } label: {
                    Label(
                        reconstructionFailed ? "もう一度作成する" : "3Dモデルを作成",
                        systemImage: reconstructionFailed ? "arrow.clockwise" : "cube"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isReconstructing || !canGenerateModel)
            }

            if let actionHint {
                Text(actionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch captureState {
        case .initializing:
            Button {
                session.resetDetection()
            } label: {
                Label("準備中", systemImage: "hourglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)

        case .ready:
            Button {
                startDetection()
            } label: {
                Label("推しを認識", systemImage: "viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .detecting:
            Button {
                startCapturing()
            } label: {
                Label("周りを撮影", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .capturing:
            Button {
                requestManualCapture()
            } label: {
                Label("1枚撮る", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canRequestImageCapture)

        case .finishing:
            Button {
            } label: {
                Label("保存中", systemImage: "hourglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(true)

        case .completed:
            let retakeLabel = Label("撮り直す", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
            // 生成に失敗したときは、撮り直しが有力な選択肢なので目立たせる。
            if reconstructionFailed {
                Button(action: restartCaptureSet) { retakeLabel }
                    .buttonStyle(.borderedProminent)
                    .disabled(isReconstructing)
            } else {
                Button(action: restartCaptureSet) { retakeLabel }
                    .buttonStyle(.bordered)
                    .disabled(isReconstructing)
            }

        case .failed:
            Button {
                restartCaptureSet()
            } label: {
                Label("再開", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        @unknown default:
            Button {
                restartCaptureSet()
            } label: {
                Label("再開", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var workflowStep: CaptureWorkflowStep {
        if isReconstructing {
            return .generate
        }

        if case .completed = captureState {
            return .generate
        }

        if userCompletedScanPass {
            return .backSide
        }

        switch captureState {
        case .initializing, .ready, .failed:
            return .setup
        case .detecting:
            return .recognize
        case .capturing, .finishing:
            return .capture
        case .completed:
            return .generate
        @unknown default:
            return .setup
        }
    }

    private var stepInstruction: String {
        if userCompletedScanPass {
            return "表側の撮影が一区切りつきました。必要なら推しを裏返して、裏側も撮影します。"
        }

        switch captureState {
        case .initializing:
            return "カメラを準備しています。推しを明るい場所に置いて、全体が見える位置にします。"
        case .ready:
            return "推し全体を画面に入れて、下のボタンで認識を始めます。"
        case .detecting:
            return "画面のガイドに合わせて、推しが見切れない位置で待ちます。"
        case .capturing:
            return "推しは動かさず、iPhoneをゆっくり回して周りを撮影します。"
        case .finishing:
            return "撮影データを保存しています。このまま待ちます。"
        case .completed:
            return "撮影データができました。枚数が十分なら3Dモデルを作成できます。"
        case .failed:
            return "撮影準備に失敗しました。再開するか、明るさとカメラ許可を確認してください。"
        @unknown default:
            return "状態を確認しています。"
        }
    }

    private var actionHint: String? {
        if isReconstructing {
            return "作成が終わると、この推しの3Dモデルとして登録されます。"
        }

        if case .completed = captureState {
            if canGenerateModel {
                return "作成した3DモデルはAR配置で自動的に使われます。"
            }

            return "3Dモデル作成には20枚以上が目安です。今は\(numberOfShotsTaken)枚なので、「撮り直す」から推しの周りをゆっくり多めに撮影してください。"
        }

        switch captureState {
        case .ready:
            return "推しだけが大きく映るようにすると認識しやすくなります。"
        case .detecting:
            return "認識できたら「周りを撮影」に進みます。"
        case .capturing:
            return "\(minimumShotsForModel)枚以上撮ると、3Dモデル作成に進みやすくなります。"
        default:
            return nil
        }
    }

    private var trackingLabelText: String {
        switch cameraTracking {
        case .notAvailable:
            return "追跡未取得"
        case .normal:
            return "追跡良好"
        case .limited:
            return "追跡制限中"
        @unknown default:
            return "追跡確認中"
        }
    }

    private var canGenerateModel: Bool {
        numberOfShotsTaken >= minimumShotsForModel
    }

    private var shotsNeededForModel: Int {
        max(0, minimumShotsForModel - numberOfShotsTaken)
    }

    private var minimumShotsForModel: Int {
        20
    }

    private var canFinish: Bool {
        switch captureState {
        case .capturing, .detecting:
            // 3Dモデル作成に必要な枚数（20枚）に満たないうちは完了させない。
            canGenerateModel
        default:
            false
        }
    }

    private var shouldShowFinishButton: Bool {
        switch captureState {
        case .detecting, .capturing:
            true
        default:
            false
        }
    }

    private var feedbackText: String {
        feedback
            .map(feedbackDescription)
            .sorted()
            .joined(separator: " / ")
    }

    private func startIfNeeded() async {
        guard ObjectCaptureSession.isSupported, !didStartSession else {
            return
        }

        didStartSession = true
        guard await requestCameraAccess() else {
            errorMessage = "カメラの利用が許可されていません。設定アプリでカメラを許可してください。"
            didStartSession = false
            captureState = .failed(CaptureStartupError.cameraAccessDenied)
            return
        }

        await Task.yield()
        startCaptureSetOnCurrentSession()
    }

    private func restartCaptureSet() {
        if !isReconstructing {
            session.cancel()
        }

        resetCaptureState()
        didStartSession = false
        sessionStore.replaceSession()
    }

    private func resetCaptureState() {
        captureState = .initializing
        feedback = []
        cameraTracking = .notAvailable
        canRequestImageCapture = false
        userCompletedScanPass = false
        numberOfShotsTaken = 0
        reconstructionProgress = 0
        reconstructionStatus = ""
        errorMessage = nil
        unusableSampleCount = 0
        reconstructionFailed = false
        statusMessage = nil
        didRequestDetection = false
        didRequestCapture = false
        activeCaptureDirectoryName = nil
        previousCaptureDirectoryName = nil
    }

    private func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func handleCaptureStateUpdate(_ state: ObjectCaptureSession.CaptureState) {
        captureState = state

        switch state {
        case .ready:
            guard !didRequestDetection, !didRequestCapture else {
                return
            }

            errorMessage = nil
            statusMessage = "推し全体が入る位置で検出を開始してください。"

        case .detecting:
            didRequestDetection = false
            errorMessage = nil
            statusMessage = "推しを枠内に収めて、準備できたら撮影開始を押してください。"

        case .capturing:
            didRequestDetection = false
            didRequestCapture = false
            errorMessage = nil
            statusMessage = "端末をゆっくり動かして、推しを一周撮影してください。"

        case .completed:
            didRequestDetection = false
            didRequestCapture = false
            if let previousCaptureDirectoryName {
                CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: previousCaptureDirectoryName)
                self.previousCaptureDirectoryName = nil
            }
            statusMessage = "撮影データを保存しました。3Dモデルを作成できます。"

        case .failed:
            didRequestDetection = false
            didRequestCapture = false
            restorePreviousCaptureDirectoryIfEmpty()

        default:
            break
        }
    }

    private func startDetection() {
        errorMessage = nil
        statusMessage = "検出を開始しています..."
        didRequestDetection = true

        if session.startDetecting() {
            captureState = .detecting
            statusMessage = "推しを枠内に収めて、準備できたら撮影開始を押してください。"
        } else {
            didRequestDetection = false
            statusMessage = "まだ検出を開始できません。カメラを推しに向けて、少し待ってからもう一度押してください。"
        }
    }

    private func startCapturing() {
        errorMessage = nil
        statusMessage = "撮影を開始しています..."
        didRequestDetection = false
        didRequestCapture = true
        session.startCapturing()
        captureState = .capturing
        statusMessage = "端末をゆっくり動かして、推しを一周撮影してください。"
    }

    private func requestManualCapture() {
        session.requestImageCapture()
        statusMessage = "1枚撮影しました。角度を少し変えて続けてください。"
    }

    private func beginBackSideCapture() {
        userCompletedScanPass = false
        statusMessage = "裏側の撮影を始めます。推しを裏返してゆっくり撮影してください。"
        session.beginNewScanPassAfterFlip()
    }

    private func restorePreviousCaptureDirectoryIfEmpty() {
        guard numberOfShotsTaken == 0,
              let activeCaptureDirectoryName,
              character.objectCaptureDirectoryName == activeCaptureDirectoryName else {
            return
        }

        CharacterImageStore.deleteObjectCaptureDirectoryIfExists(directoryName: activeCaptureDirectoryName)
        character.objectCaptureDirectoryName = previousCaptureDirectoryName
        character.updatedAt = Date()
        try? modelContext.save()

        self.activeCaptureDirectoryName = previousCaptureDirectoryName
        previousCaptureDirectoryName = nil
    }

    private func startCaptureSetOnCurrentSession() {
        do {
            let captureDirectory = try CharacterImageStore.newObjectCaptureDirectory()
            previousCaptureDirectoryName = character.objectCaptureDirectoryName
            activeCaptureDirectoryName = captureDirectory.directoryName

            var configuration = ObjectCaptureSession.Configuration()
            configuration.isOverCaptureEnabled = true
            session.shouldPlayHaptics = true
            session.isAutoCaptureEnabled = true
            session.start(imagesDirectory: captureDirectory.url, configuration: configuration)

            character.objectCaptureDirectoryName = captureDirectory.directoryName
            character.updatedAt = Date()
            try? modelContext.save()
            errorMessage = nil
            statusMessage = "撮影準備ができました。"
        } catch {
            didStartSession = false
            errorMessage = error.localizedDescription
            captureState = .failed(error)
        }
    }

    private enum CaptureStartupError: LocalizedError {
        case cameraAccessDenied

        var errorDescription: String? {
            switch self {
            case .cameraAccessDenied:
                "カメラの利用が許可されていません。"
            }
        }
    }

    private func reconstructModel() {
        guard let directoryName = character.objectCaptureDirectoryName else {
            errorMessage = "撮影データがありません。"
            return
        }

        Task {
            do {
                let inputURL = try CharacterImageStore.objectCaptureDirectoryURL(for: directoryName)
                let output = try CharacterImageStore.newModelURL()
                isReconstructing = true
                reconstructionProgress = 0
                reconstructionStatus = "準備中"
                errorMessage = nil
                unusableSampleCount = 0
                reconstructionFailed = false

                var configuration = PhotogrammetrySession.Configuration()
                configuration.isObjectMaskingEnabled = true
                configuration.featureSensitivity = .high
                configuration.ignoreBoundingBox = false

                let photogrammetrySession = try PhotogrammetrySession(input: inputURL, configuration: configuration)
                let request = PhotogrammetrySession.Request.modelFile(url: output.url, detail: .reduced)
                try photogrammetrySession.process(requests: [request])

                var didCompleteModel = false

                for try await outputEvent in photogrammetrySession.outputs {
                    switch outputEvent {
                    case .requestProgress(_, let fractionComplete):
                        reconstructionProgress = fractionComplete
                        reconstructionStatus = "作成中"

                    case .requestProgressInfo(_, let progressInfo):
                        reconstructionStatus = progressInfo.processingStage.map(stageText) ?? "作成中"

                    case .requestComplete(_, .modelFile):
                        didCompleteModel = true
                        reconstructionProgress = 1
                        reconstructionStatus = "モデル作成完了"

                    case .requestError(_, let error):
                        throw error

                    case .processingComplete:
                        if didCompleteModel {
                            CharacterImageStore.deleteModelIfExists(fileName: character.modelFileName)
                            character.modelFileName = output.fileName
                            character.updatedAt = Date()
                            try? modelContext.save()
                        }
                        isReconstructing = false
                        if didCompleteModel {
                            showCreationSuccessAlert = true
                        }

                    case .processingCancelled:
                        isReconstructing = false
                        reconstructionStatus = "キャンセルしました"

                    case .invalidSample(_, let reason):
                        unusableSampleCount += 1
                        reconstructionStatus = reason

                    case .skippedSample:
                        unusableSampleCount += 1
                        reconstructionStatus = "一部の写真をスキップしました"

                    case .automaticDownsampling:
                        reconstructionStatus = "写真を自動縮小しています"

                    case .inputComplete:
                        reconstructionStatus = "写真を読み込みました"

                    case .stitchingIncomplete:
                        reconstructionStatus = "一部の合成が不完全です"

                    default:
                        break
                    }
                }
            } catch {
                isReconstructing = false
                reconstructionFailed = true
                errorMessage = reconstructionFailureMessage()
            }
        }
    }

    /// 生成失敗時に、原因の見当と次の一手をユーザーへ案内するメッセージを組み立てる。
    private func reconstructionFailureMessage() -> String {
        if unusableSampleCount > 0 {
            return "3Dモデルの生成に失敗しました。\(unusableSampleCount)枚の写真が使えませんでした。明るい場所で、推しをゆっくり一周しながら撮り直すと成功しやすくなります。"
        }
        return "3Dモデルの生成に失敗しました。撮影中は推しと背景を動かさず、つるつる・透明・無地の推しは柄のある台に置くと認識されやすくなります。"
    }

    private func stageText(_ stage: PhotogrammetrySession.Output.ProcessingStage) -> String {
        switch stage {
        case .preProcessing:
            "前処理中"
        case .imageAlignment:
            "写真を整列中"
        case .pointCloudGeneration:
            "点群を生成中"
        case .meshGeneration:
            "メッシュを生成中"
        case .textureMapping:
            "テクスチャを生成中"
        case .optimization:
            "最適化中"
        @unknown default:
            "生成中"
        }
    }

    private func feedbackDescription(_ feedback: ObjectCaptureSession.Feedback) -> String {
        switch feedback {
        case .objectTooClose:
            "近すぎます"
        case .objectTooFar:
            "遠すぎます"
        case .movingTooFast:
            "動きが速すぎます"
        case .environmentLowLight:
            "少し暗いです"
        case .environmentTooDark:
            "暗すぎます"
        case .outOfFieldOfView:
            "画面外です"
        case .objectNotFlippable:
            "反転撮影に不向きです"
        case .overCapturing:
            "撮りすぎています"
        case .objectNotDetected:
            "対象が見つかりません"
        @unknown default:
            "確認してください"
        }
    }

}

private enum CaptureWorkflowStep: Int, CaseIterable, Identifiable {
    case setup
    case recognize
    case capture
    case backSide
    case generate

    var id: Self {
        self
    }

    var index: Int {
        rawValue + 1
    }

    var title: String {
        switch self {
        case .setup:
            "準備"
        case .recognize:
            "認識"
        case .capture:
            "周囲を撮影"
        case .backSide:
            "裏側を撮影"
        case .generate:
            "3Dモデル作成"
        }
    }

    var iconName: String {
        switch self {
        case .setup:
            "light.max"
        case .recognize:
            "viewfinder"
        case .capture:
            "camera"
        case .backSide:
            "arrow.triangle.2.circlepath.camera"
        case .generate:
            "cube"
        }
    }
}

@MainActor
private final class ObjectCaptureSessionStore: ObservableObject {
    @Published private(set) var session = ObjectCaptureSession()

    private var retiredSessions: [ObjectCaptureSession] = []

    func replaceSession() {
        let retiredSession = session
        retiredSessions.append(retiredSession)
        session = ObjectCaptureSession()

        Task { [weak self, retiredSession] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            self?.retiredSessions.removeAll { $0.id == retiredSession.id }
        }
    }
}
