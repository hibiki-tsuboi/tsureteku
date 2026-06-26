//
//  ARCameraScreen.swift
//  Tsureteku
//
//  Created by Hibiki Tsuboi on 2026/06/10.
//

import ARKit
import AudioToolbox
import AVFoundation
import ReplayKit
import SwiftData
import SwiftUI
import UIKit

struct ARCameraScreen: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ToyCharacter.createdAt, order: .reverse) private var characters: [ToyCharacter]

    @State private var selectedCharacterID: UUID?
    @State private var captureTrigger = 0
    @State private var resetTrigger = 0
    @State private var scaleDownTrigger = 0
    @State private var scaleUpTrigger = 0
    @State private var rotateLeftTrigger = 0
    @State private var rotateRightTrigger = 0
    @State private var faceCameraTrigger = 0
    @State private var removeSelectedTrigger = 0
    @State private var clearPlacementSelectionTrigger = 0
    @State private var toggleSelectedPlacementMotionTrigger = 0
    @State private var isAddingCharacter = false
    @State private var isARActive = false
    @State private var isCameraAccessDenied = false
    @State private var isARUnsupported = false
    @State private var isResetConfirmationPresented = false
    @State private var isRecordingConfirmationPresented = false
    @State private var isSelfieMode = false
    @State private var isRecording = false
    @State private var isRecordingReadyToStop = false
    @State private var isStoppingRecording = false
    /// 録画確認後〜実際の録画開始までの準備中フラグ。この間も操作UIを隠し、誤操作を防ぐ。
    @State private var isPreparingRecording = false
    @State private var recordingPreview: RecordingPreviewItem?
    @State private var captureFlashOpacity = 0.0
    @State private var statusMessage: String?
    @State private var selectedPlacementName: String?
    @State private var selectedPlacementMotionEnabled = false
    /// シーンに推しがまだ1体も置かれていないか。配置ヒントの表示判定に使う。
    @State private var isSceneEmpty = true
    /// Apple標準の平面検出コーチングが表示中か。表示中は配置ヒントを出さない。
    @State private var isCoachingActive = false
    @State private var capturedPhoto: CapturedARPhoto?
    @State private var isControlPanelExpanded = false

    /// iPadの大画面で操作パネルや案内が間延びしないようにする最大幅。
    private static let contentMaxWidth: CGFloat = 540
    /// iOS標準のカメラ撮影・録画フィードバック音。
    private static let photoCaptureSoundID: SystemSoundID = 1108
    private static let recordingStartSoundID: SystemSoundID = 1117
    private static let recordingStopSoundID: SystemSoundID = 1118

    var body: some View {
        ZStack {
            if isARActive {
                arExperience
            } else {
                landingView
            }
        }
        .onAppear {
            selectInitialCharacterIfNeeded()
        }
        .onChange(of: characters.map(\.id)) { _, _ in
            selectInitialCharacterIfNeeded()
        }
        .sheet(isPresented: $isAddingCharacter) {
            AddCharacterView()
        }
        .fullScreenCover(item: $capturedPhoto, onDismiss: {
            capturedPhoto = nil
        }) { photo in
            CapturedPhotoPreviewView(image: photo.image, onSave: saveCapturedPhoto) { result in
                handlePreviewSave(result)
            }
        }
        .fullScreenCover(item: $recordingPreview) { item in
            CapturedVideoPreviewView(videoURL: item.url, onSave: saveRecordedVideo) { result in
                handleVideoPreviewSave(result)
            }
            .onDisappear {
                deleteTemporaryRecording(at: item.url)
                recordingPreview = nil
            }
        }
        .alert("カメラを使えません", isPresented: $isCameraAccessDenied) {
            Button("設定を開く") {
                openAppSettings()
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("ARで推しと撮影するにはカメラの利用を許可してください。設定アプリの「つれてく」から変更できます。")
        }
        .alert("ARを利用できません", isPresented: $isARUnsupported) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("この端末はARに対応していないため、AR撮影は利用できません。")
        }
        .alert(
            "配置をリセットしますか？",
            isPresented: $isResetConfirmationPresented
        ) {
            Button("キャンセル", role: .cancel) {}
            Button("リセット", role: .destructive) {
                resetTrigger += 1
            }
        } message: {
            Text("配置した推しがすべて消えます。撮影した写真は残ります。")
        }
        .alert("録画を開始しますか？", isPresented: $isRecordingConfirmationPresented) {
            Button("キャンセル", role: .cancel) {}
            Button("録画開始") {
                startRecordingAfterConfirmation()
            }
        } message: {
            Text("録画中は操作ボタンを隠します。画面のどこかをタップすると録画を終了します。推しの配置やサイズ調整は開始前に済ませてください。")
        }
        .toolbar(isARActive ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - AR起動中

    private var arExperience: some View {
        ZStack {
            ARCharacterView(
                selectedAsset: selectedAsset,
                isSelfieMode: isSelfieMode,
                isRecording: isRecording,
                captureTrigger: $captureTrigger,
                resetTrigger: $resetTrigger,
                scaleDownTrigger: $scaleDownTrigger,
                scaleUpTrigger: $scaleUpTrigger,
                rotateLeftTrigger: $rotateLeftTrigger,
                rotateRightTrigger: $rotateRightTrigger,
                faceCameraTrigger: $faceCameraTrigger,
                removeSelectedTrigger: $removeSelectedTrigger,
                clearPlacementSelectionTrigger: $clearPlacementSelectionTrigger,
                toggleSelectedPlacementMotionTrigger: $toggleSelectedPlacementMotionTrigger,
                selectedPlacementName: $selectedPlacementName,
                selectedPlacementMotionEnabled: $selectedPlacementMotionEnabled,
                isSceneEmpty: $isSceneEmpty,
                isCoachingActive: $isCoachingActive,
                onCapture: handleCapture,
                onStatus: showStatus
            )
            .ignoresSafeArea()

            Color.white
                .opacity(captureFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                if isRecording || isPreparingRecording {
                    recordingStopControl
                } else {
                    arHeader
                    Spacer()
                    if characters.isEmpty {
                        welcomeCard
                        Spacer()
                    } else {
                        if shouldShowPlacementHint {
                            placementHint
                        }
                        bottomControls
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isSceneEmpty)
            .animation(.easeInOut(duration: 0.3), value: isCoachingActive)
        }
    }

    /// 配置がまだ無く、平面検出コーチングも出ていない通常モードのときだけ、
    /// 「タップで置ける」ことを伝えるヒントを表示する。最初の配置で自動的に消える。
    private var shouldShowPlacementHint: Bool {
        isSceneEmpty && !isCoachingActive && !isSelfieMode
    }

    /// タップ配置が隠れジェスチャーにならないよう、置き方を促すヒント。
    private var placementHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap.fill")
                .font(.headline)
                .symbolEffect(.bounce, options: .repeating)

            Text("床や机をタップして推しを置こう")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(LinearGradient.brand, in: Capsule())
        .shadow(color: BrandColor.purple.opacity(0.35), radius: 12, y: 4)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var arHeader: some View {
        HStack(spacing: 12) {
            arHeaderButton(
                systemImage: "xmark",
                accessibilityLabel: "ARを閉じる"
            ) {
                isSelfieMode = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    isARActive = false
                }
            }

            Spacer()

            if !characters.isEmpty {
                if ARFaceTrackingConfiguration.isSupported {
                    arHeaderButton(
                        systemImage: isSelfieMode ? "camera.rotate.fill" : "camera.rotate",
                        accessibilityLabel: isSelfieMode ? "背面カメラに切り替え" : "自撮りに切り替え",
                        isActive: isSelfieMode
                    ) {
                        toggleSelfieMode()
                    }
                }

                if !isSelfieMode {
                    arHeaderButton(
                        systemImage: "trash",
                        accessibilityLabel: "配置をリセット",
                        role: .destructive
                    ) {
                        isResetConfirmationPresented = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background(alignment: .top) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.5),
                    Color.black.opacity(0.22),
                    Color.black.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 118)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private func arHeaderButton(
        systemImage: String,
        accessibilityLabel: String,
        isActive: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Circle().fill((isActive ? BrandColor.purple : Color.black).opacity(isActive ? 0.58 : 0.22))
                    }
                }
                .overlay {
                    Circle().stroke(.white.opacity(isActive ? 0.72 : 0.42), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.34), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - ランディング（カメラ起動前）

    private var landingView: some View {
        ZStack {
            LinearGradient(
                colors: [BrandColor.purpleLight.opacity(0.35), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if characters.isEmpty {
                    Spacer()
                    WelcomeEmptyState(
                        icon: "teddybear.fill",
                        title: "推しをつれていこう",
                        message: "お気に入りの推しを登録すると、ARで一緒に写真が撮れるよ。",
                        actionTitle: "推しを登録",
                        action: { isAddingCharacter = true }
                    )
                    Spacer()
                } else {
                    launchContent
                }
            }
        }
    }

    private var launchContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(LinearGradient.brand)
                        .frame(width: 128, height: 128)
                        .shadow(color: BrandColor.purple.opacity(0.35), radius: 18, y: 8)

                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 10) {
                    Text("つれてく準備OK！")
                        .font(.system(.title2, design: .rounded).weight(.bold))

                    Text("カメラを起動して、推しと一緒にARで撮影しよう。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
                .padding(.horizontal, 28)

                registeredPreview
            }

            Spacer()

            Button {
                startARSession()
            } label: {
                Label("ARでつれてく", systemImage: "camera.viewfinder")
                    .font(.system(.headline, design: .rounded).weight(.bold))
            }
            .buttonStyle(BrandButtonStyle())
            .padding(.bottom, 34)
        }
        .frame(maxWidth: Self.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var registeredPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(characters) { character in
                    CharacterThumbnailView(character: character)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }

            placementTools
            controlPanel
            captureControls
        }
        .frame(maxWidth: Self.contentMaxWidth)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    /// シャッター（写真）と録画（動画）を横並びにしたボタン群。
    private var captureControls: some View {
        ZStack {
            captureButton

            HStack {
                Spacer()
                recordButton
                    .padding(.trailing, 36)
            }
        }
    }

    /// 録画開始ボタン（赤い丸＋ビデオアイコン）。
    private var recordButton: some View {
        Button {
            isRecordingConfirmationPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 54, height: 54)

                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("動画を撮影")
    }

    /// ReplayKitは画面全体を録画するため、録画中は可視UIを出さず透明な停止領域だけを置く。
    private var recordingStopControl: some View {
        Button {
            stopRecordingIfReady()
        } label: {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("録画を停止")
        .disabled(!isRecordingReadyToStop || isStoppingRecording)
    }

    /// 推し情報・選択を1枚にまとめたパネル。
    /// 既定では推し名のバーだけを表示し、タップで推しピッカーを展開する。
    /// 撮影時に画面下半分が隠れないよう、普段は畳んでおける。
    private var controlPanel: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isControlPanelExpanded.toggle()
                }
            } label: {
                selectedCharacterSummary
            }
            .buttonStyle(.plain)

            if isControlPanelExpanded {
                characterPicker
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 14)
    }

    /// シャッター風の撮影ボタン。
    private var captureButton: some View {
        Button {
            captureTrigger += 1
            triggerCaptureFeedback()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 4)
                    .frame(width: 78, height: 78)

                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("撮影")
        .padding(.top, 2)
    }

    private var welcomeCard: some View {
        WelcomeEmptyState(
            icon: "teddybear.fill",
            title: "推しをつれていこう",
            message: "お気に入りの推しを登録して、ARで一緒に写真を撮ろう！",
            actionTitle: "推しを登録",
            action: { isAddingCharacter = true }
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .frame(maxWidth: Self.contentMaxWidth)
        .padding(.horizontal, 24)
    }

    private var characterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(characters) { character in
                    Button {
                        select(character)
                    } label: {
                        CharacterThumbnailView(
                            character: character,
                            isSelected: character.id == selectedCharacterID,
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var selectedCharacterSummary: some View {
        if let selectedCharacter {
            HStack(spacing: 10) {
                Label(
                    selectedCharacter.name,
                    systemImage: selectedCharacter.modelFileName == nil ? "photo" : "cube.fill"
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

                Spacer()

                Label("\(Int(selectedCharacter.defaultSizeMeters * 100))cm", systemImage: "ruler")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())

                Text(selectedCharacter.modelFileName == nil ? "2D" : "3D")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())

                if let selectedPlacementName {
                    Label(selectedPlacementName, systemImage: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isControlPanelExpanded ? 180 : 0))
            }
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var placementTools: some View {
        if selectedPlacementName != nil {
            HStack(spacing: 0) {
                placementToolButton(systemImage: "minus.circle", accessibilityLabel: "選択中の推しを小さく") {
                    scaleDownTrigger += 1
                }

                placementToolButton(systemImage: "plus.circle", accessibilityLabel: "選択中の推しを大きく") {
                    scaleUpTrigger += 1
                }

                placementToolButton(systemImage: "digitalcrown.horizontal.arrow.counterclockwise", accessibilityLabel: "選択中の推しを左に回転") {
                    rotateLeftTrigger += 1
                }

                placementToolButton(systemImage: "digitalcrown.horizontal.arrow.clockwise", accessibilityLabel: "選択中の推しを右に回転") {
                    rotateRightTrigger += 1
                }

                placementToolButton(
                    systemImage: "sparkles",
                    accessibilityLabel: selectedPlacementMotionEnabled ? "選択中の推しの動きをオフ" : "選択中の推しの動きをオン",
                    isActive: selectedPlacementMotionEnabled
                ) {
                    toggleIdleMotion()
                }

                if !isSelfieMode {
                    placementToolButton(systemImage: "scope", accessibilityLabel: "選択中の推しをカメラに向ける") {
                        faceCameraTrigger += 1
                    }

                    placementToolButton(systemImage: "trash", accessibilityLabel: "選択中の推しを削除", role: .destructive) {
                        removeSelectedTrigger += 1
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 14)
        }
    }

    private func placementToolButton(
        systemImage: String,
        accessibilityLabel: String,
        isActive: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(role == .destructive ? .red : (isActive ? .white : BrandColor.purple))
                .background {
                    ZStack {
                        Circle().fill(.thinMaterial)
                        if isActive {
                            Circle().fill(BrandColor.purple.opacity(0.9))
                        }
                    }
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(isActive ? 0.5 : 0.24), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .frame(maxWidth: .infinity)
    }

    private var selectedAsset: CharacterARAsset? {
        guard let selectedCharacter else {
            return nil
        }

        return CharacterARAsset(
            id: selectedCharacter.id,
            name: selectedCharacter.name,
            cutoutImageFileName: selectedCharacter.cutoutImageFileName,
            modelFileName: selectedCharacter.modelFileName,
            defaultSizeMeters: Float(selectedCharacter.defaultSizeMeters),
            arBrightnessMultiplier: Float(selectedCharacter.normalizedARBrightnessMultiplier),
            modelYawDegrees: Float(selectedCharacter.modelYawDegrees),
            modelVerticalOffsetMeters: Float(selectedCharacter.modelVerticalOffsetMeters),
            isMotionEnabled: selectedCharacter.isARMotionEnabled
        )
    }

    private var selectedCharacter: ToyCharacter? {
        if let selectedCharacterID,
           let selected = characters.first(where: { $0.id == selectedCharacterID }) {
            return selected
        }

        return characters.first
    }

    private func selectInitialCharacterIfNeeded() {
        // selectedCharacter は characters.first にフォールバックするため判定に使えない。
        // selectedCharacterID が実在の推しを指しているかで判定し、未選択なら先頭を選ぶ。
        if let selectedCharacterID, characters.contains(where: { $0.id == selectedCharacterID }) {
            return
        }

        selectedCharacterID = characters.first?.id
    }

    private func select(_ character: ToyCharacter) {
        selectedCharacterID = character.id
        selectedPlacementName = nil
        clearPlacementSelectionTrigger += 1
        character.lastUsedAt = Date()
        try? modelContext.save()
    }

    private func startARSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            isARUnsupported = true
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            activateAR()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { isGranted in
                DispatchQueue.main.async {
                    if isGranted {
                        activateAR()
                    } else {
                        isCameraAccessDenied = true
                    }
                }
            }
        case .denied, .restricted:
            isCameraAccessDenied = true
        @unknown default:
            isCameraAccessDenied = true
        }
    }

    private func activateAR() {
        // 撮影プレビューを閉じた後に古い写真状態が残っていても、次回起動時に再表示しない。
        capturedPhoto = nil
        // AR画面を開くたびに、推しピッカーをすぐ使えるよう展開しておく。
        isControlPanelExpanded = true

        withAnimation(.easeInOut(duration: 0.25)) {
            isARActive = true
        }
    }

    private func toggleSelfieMode() {
        selectedPlacementName = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelfieMode.toggle()
        }
    }

    private func toggleIdleMotion() {
        toggleSelectedPlacementMotionTrigger += 1
    }

    private func startRecordingAfterConfirmation() {
        // 確認直後に準備中フラグを立てて操作UIを隠す。ここで隠さないと、録画開始までの
        // 待機中にシャッター等を押せてしまい、録画とプレビューが競合する。
        isPreparingRecording = true
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording, !isStoppingRecording else {
            isPreparingRecording = false
            return
        }

        let recorder = RPScreenRecorder.shared()

        guard recorder.isAvailable else {
            isPreparingRecording = false
            showStatus("この端末では画面収録を利用できません。")
            return
        }

        isRecordingReadyToStop = false
        withAnimation(.easeInOut(duration: 0.2)) {
            isRecording = true
        }
        isPreparingRecording = false

        recorder.isMicrophoneEnabled = true
        recorder.startRecording { error in
            DispatchQueue.main.async {
                if let error {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRecording = false
                    }
                    isRecordingReadyToStop = false
                    showStatus(error.localizedDescription)
                    return
                }

                triggerRecordingStartFeedback()
                isRecordingReadyToStop = true
            }
        }
    }

    private func stopRecordingIfReady() {
        guard isRecordingReadyToStop, !isStoppingRecording else {
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopRecording()
    }

    private func stopRecording() {
        isStoppingRecording = true
        isRecordingReadyToStop = false

        let outputURL = temporaryRecordingURL()
        try? FileManager.default.removeItem(at: outputURL)

        RPScreenRecorder.shared().stopRecording(withOutput: outputURL) { error in
            DispatchQueue.main.async {
                isStoppingRecording = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording = false
                }

                if let error {
                    deleteTemporaryRecording(at: outputURL)
                    showStatus(error.localizedDescription)
                    return
                }

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    showStatus("動画を保存できませんでした。")
                    return
                }

                playRecordingStopSound()
                recordingPreview = RecordingPreviewItem(url: outputURL)
            }
        }
    }

    private func temporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tsureteku-recording-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func deleteTemporaryRecording(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// 撮影時に触覚・シャッター音・一瞬の白フラッシュで「撮れた」手応えを返す。
    private func triggerCaptureFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(Self.photoCaptureSoundID)

        captureFlashOpacity = 0.9
        withAnimation(.easeOut(duration: 0.35)) {
            captureFlashOpacity = 0
        }
    }

    /// ReplayKitの録画開始が成功したタイミングで、録画開始が分かる音と触覚を返す。
    private func triggerRecordingStartFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(Self.recordingStartSoundID)
    }

    /// 録画停止と動画ファイル作成が終わったタイミングで、終了音を鳴らす。
    private func playRecordingStopSound() {
        AudioServicesPlaySystemSound(Self.recordingStopSoundID)
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }

    private func handleCapture(_ result: Result<UIImage, Error>) {
        switch result {
        case .success(let image):
            capturedPhoto = CapturedARPhoto(image: image)
        case .failure(let error):
            showStatus(error.localizedDescription)
        }
    }

    private func handlePreviewSave(_ result: Result<CapturedPhotoSaveOutcome, Error>) {
        switch result {
        case .success(.savedToLibrary):
            showStatus("写真ライブラリに保存しました。")
        case .success(.savedToHistoryOnly):
            showStatus("履歴に保存しました。")
        case .failure(let error):
            showStatus(error.localizedDescription)
        }
    }

    private func handleVideoPreviewSave(_ result: Result<CapturedPhotoSaveOutcome, Error>) {
        switch result {
        case .success(.savedToLibrary):
            showStatus("写真ライブラリに保存しました。")
        case .success(.savedToHistoryOnly):
            showStatus("履歴に保存しました。")
        case .failure(let error):
            showStatus(error.localizedDescription)
        }
    }

    private func saveCapturedPhoto(_ image: UIImage, completion: @escaping (Result<CapturedPhotoSaveOutcome, Error>) -> Void) {
        // アプリ内の履歴が主たる保存先。まずここへ確実に残し、写真ライブラリ保存は付加的に行う。
        // こうすることで写真ライブラリの権限が拒否されても、履歴から写真が失われない。
        do {
            let fileName = try CapturedPhotoStore.save(image)
            let photo = CapturedPhoto(imageFileName: fileName)
            modelContext.insert(photo)
            try modelContext.save()
        } catch {
            completion(.failure(error))
            return
        }

        PhotoLibrarySaver.save(image) { result in
            switch result {
            case .success:
                completion(.success(.savedToLibrary))
            case .failure(let libraryError):
                completion(.success(.savedToHistoryOnly(libraryError: libraryError)))
            }
        }
    }

    private func saveRecordedVideo(_ url: URL, completion: @escaping (Result<CapturedPhotoSaveOutcome, Error>) -> Void) {
        // アプリ内の履歴を主たる保存先とし、動画を恒久ディレクトリへ保存してから写真ライブラリへ
        // 付加的に保存する。重いファイルIO・ポスター生成はメインスレッド外で行い、SwiftData更新だけ
        // メインアクターで実行する。
        Task {
            var savedVideoFileName: String?
            var savedPosterFileName: String?

            do {
                let videoFileName = try CapturedPhotoStore.saveVideo(from: url)
                savedVideoFileName = videoFileName

                let storedURL = CapturedPhotoStore.videoURL(named: videoFileName) ?? url
                let poster = await CapturedPhotoStore.makePosterImage(from: storedURL)
                    ?? CapturedPhotoStore.placeholderPosterImage()
                let posterFileName = try CapturedPhotoStore.save(poster)
                savedPosterFileName = posterFileName

                try await MainActor.run {
                    let media = CapturedPhoto(
                        imageFileName: posterFileName,
                        videoFileName: videoFileName,
                        mediaType: .video
                    )
                    modelContext.insert(media)
                    try modelContext.save()
                }

                // ライブラリ保存は付加的。失敗しても履歴には残っているので致命ではない。
                // 一時ファイルではなく恒久コピーを渡し、プレビュー終了時の一時ファイル削除と競合させない。
                PhotoLibrarySaver.saveVideo(at: storedURL) { result in
                    switch result {
                    case .success:
                        completion(.success(.savedToLibrary))
                    case .failure(let libraryError):
                        completion(.success(.savedToHistoryOnly(libraryError: libraryError)))
                    }
                }
            } catch {
                // 履歴への保存に失敗したら、作りかけのファイルを後始末する。
                CapturedPhotoStore.deleteIfExists(fileName: savedVideoFileName)
                CapturedPhotoStore.deleteIfExists(fileName: savedPosterFileName)
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func showStatus(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            statusMessage = message
        }

        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(.easeInOut(duration: 0.2)) {
                if statusMessage == message {
                    statusMessage = nil
                }
            }
        }
    }
}

private struct CapturedARPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct RecordingPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    ARCameraScreen()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
