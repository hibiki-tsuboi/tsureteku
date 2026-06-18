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
    @State private var removeLastTrigger = 0
    @State private var resetTrigger = 0
    @State private var scaleDownTrigger = 0
    @State private var scaleUpTrigger = 0
    @State private var rotateLeftTrigger = 0
    @State private var rotateRightTrigger = 0
    @State private var faceCameraTrigger = 0
    @State private var removeSelectedTrigger = 0
    @State private var clearPlacementSelectionTrigger = 0
    @State private var isAddingCharacter = false
    @State private var isARActive = false
    @State private var isCameraAccessDenied = false
    @State private var isARUnsupported = false
    @State private var isResetConfirmationPresented = false
    @State private var isSelfieMode = false
    @State private var isRecording = false
    /// 録画開始時刻。HUDの経過時間表示に使う。
    @State private var recordingStartDate: Date?
    @State private var recordingPreview: RecordingPreviewItem?
    @State private var captureFlashOpacity = 0.0
    @State private var statusMessage: String?
    @State private var selectedPlacementName: String?
    @State private var capturedPhoto: CapturedARPhoto?
    @State private var isControlPanelExpanded = false

    /// iPadの大画面で操作パネルや案内が間延びしないようにする最大幅。
    private static let contentMaxWidth: CGFloat = 540

    var body: some View {
        ZStack {
            if isARActive {
                arExperience
            } else {
                landingView
            }
        }
        .onAppear(perform: selectInitialCharacterIfNeeded)
        .onChange(of: characters.map(\.id)) { _, _ in
            selectInitialCharacterIfNeeded()
        }
        .sheet(isPresented: $isAddingCharacter) {
            AddCharacterView()
        }
        .fullScreenCover(item: $capturedPhoto) { photo in
            CapturedPhotoPreviewView(image: photo.image, onSave: saveCapturedPhoto) { result in
                handlePreviewSave(result)
            }
        }
        .fullScreenCover(item: $recordingPreview) { item in
            RecordingPreview(previewController: item.controller) {
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
        .confirmationDialog(
            "配置をリセットしますか？",
            isPresented: $isResetConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("リセット", role: .destructive) {
                resetTrigger += 1
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("配置した推しがすべて消えます。撮影した写真は残ります。")
        }
        .toolbar(isARActive ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - AR起動中

    private var arExperience: some View {
        ZStack {
            ARCharacterView(
                selectedAsset: selectedAsset,
                isSelfieMode: isSelfieMode,
                captureTrigger: $captureTrigger,
                removeLastTrigger: $removeLastTrigger,
                resetTrigger: $resetTrigger,
                scaleDownTrigger: $scaleDownTrigger,
                scaleUpTrigger: $scaleUpTrigger,
                rotateLeftTrigger: $rotateLeftTrigger,
                rotateRightTrigger: $rotateRightTrigger,
                faceCameraTrigger: $faceCameraTrigger,
                removeSelectedTrigger: $removeSelectedTrigger,
                clearPlacementSelectionTrigger: $clearPlacementSelectionTrigger,
                selectedPlacementName: $selectedPlacementName,
                onCapture: handleCapture,
                onStatus: showStatus
            )
            .ignoresSafeArea()

            Color.white
                .opacity(captureFlashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // ReplayKitは画面全体をそのまま録画するため、録画中はAR被写体に重なる
            // 操作系を出さず、写り込みを最小化した上部HUDだけにする。
            VStack(spacing: 0) {
                if isRecording {
                    recordingHUD
                    Spacer()
                } else {
                    arHeader
                    Spacer()
                    if characters.isEmpty {
                        welcomeCard
                        Spacer()
                    } else {
                        bottomControls
                    }
                }
            }
        }
    }

    private var arHeader: some View {
        HStack {
            Button {
                isSelfieMode = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    isARActive = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
            .clipShape(Circle())
            .accessibilityLabel("ARを閉じる")

            Spacer()

            if !characters.isEmpty {
                if ARFaceTrackingConfiguration.isSupported {
                    Button {
                        toggleSelfieMode()
                    } label: {
                        Image(systemName: isSelfieMode ? "camera.rotate.fill" : "camera.rotate")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelfieMode ? BrandColor.purple : Color.accentColor)
                    .clipShape(Circle())
                    .accessibilityLabel(isSelfieMode ? "背面カメラに切り替え" : "自撮りに切り替え")
                }

                if !isSelfieMode {
                    Button {
                        removeLastTrigger += 1
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("最後の配置を削除")

                    Button {
                        isResetConfirmationPresented = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Circle())
                    .accessibilityLabel("配置をリセット")
                }

                Button {
                    isAddingCharacter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityLabel("推し追加")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
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
                        message: "お気に入りの推しを登録して、ARで一緒に写真を撮ろう！",
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
            startRecording()
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

    /// 録画中に表示する最小限のHUD。経過時間インジケータと停止ボタンだけを
    /// 画面上部の細いバーにまとめ、録画動画への写り込みを抑える。
    private var recordingHUD: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)

                if let recordingStartDate {
                    Text(timerInterval: recordingStartDate...Date.distantFuture, countsDown: false)
                        .font(.callout.weight(.semibold).monospacedDigit())
                } else {
                    Text("録画中")
                        .font(.callout.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                stopRecording()
            } label: {
                Label("停止", systemImage: "stop.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .clipShape(Capsule())
            .accessibilityLabel("録画を停止")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: Self.contentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    /// 推し情報・選択・サイズを1枚にまとめたパネル。
    /// 既定では推し名のバーだけを表示し、タップで推しピッカーとサイズ調整を展開する。
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
                sizeControl
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
    private var sizeControl: some View {
        if let selectedCharacter {
            HStack(spacing: 10) {
                Image(systemName: selectedCharacter.modelFileName == nil ? "arrow.up.and.down" : "cube")
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { selectedCharacter.defaultSizeMeters },
                        set: { newValue in
                            selectedCharacter.defaultSizeMeters = newValue
                            selectedCharacter.updatedAt = Date()
                            try? modelContext.save()
                        }
                    ),
                    in: 0.12...1.2
                )

                Text("\(Int(selectedCharacter.defaultSizeMeters * 100))cm")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var placementTools: some View {
        if selectedPlacementName != nil {
            HStack(spacing: 10) {
                placementToolButton(systemImage: "minus.circle", accessibilityLabel: "選択中の推しを小さく") {
                    scaleDownTrigger += 1
                }

                placementToolButton(systemImage: "plus.circle", accessibilityLabel: "選択中の推しを大きく") {
                    scaleUpTrigger += 1
                }

                placementToolButton(systemImage: "rotate.left", accessibilityLabel: "選択中の推しを左に回転") {
                    rotateLeftTrigger += 1
                }

                placementToolButton(systemImage: "rotate.right", accessibilityLabel: "選択中の推しを右に回転") {
                    rotateRightTrigger += 1
                }

                if !isSelfieMode {
                    placementToolButton(systemImage: "camera.viewfinder", accessibilityLabel: "選択中の推しをカメラに向ける") {
                        faceCameraTrigger += 1
                    }

                    placementToolButton(systemImage: "trash", accessibilityLabel: "選択中の推しを削除", role: .destructive) {
                        removeSelectedTrigger += 1
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
            .padding(.horizontal, 14)
        }
    }

    private func placementToolButton(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(accessibilityLabel)
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
            modelYawDegrees: Float(selectedCharacter.modelYawDegrees),
            modelVerticalOffsetMeters: Float(selectedCharacter.modelVerticalOffsetMeters)
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
        // AR画面を開くたびに、推しピッカー・サイズ調整をすぐ使えるよう展開しておく。
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

    private func startRecording() {
        let recorder = RPScreenRecorder.shared()

        guard recorder.isAvailable else {
            showStatus("この端末では画面収録を利用できません。")
            return
        }

        recorder.isMicrophoneEnabled = true
        recorder.startRecording { error in
            DispatchQueue.main.async {
                if let error {
                    showStatus(error.localizedDescription)
                    return
                }

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                recordingStartDate = Date()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording = true
                }
            }
        }
    }

    private func stopRecording() {
        RPScreenRecorder.shared().stopRecording { previewController, error in
            DispatchQueue.main.async {
                recordingStartDate = nil
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording = false
                }

                if let error {
                    showStatus(error.localizedDescription)
                    return
                }

                if let previewController {
                    recordingPreview = RecordingPreviewItem(controller: previewController)
                } else {
                    showStatus("動画を保存できませんでした。")
                }
            }
        }
    }

    /// 撮影時に触覚・シャッター音・一瞬の白フラッシュで「撮れた」手応えを返す。
    private func triggerCaptureFeedback() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        AudioServicesPlaySystemSound(1108)

        captureFlashOpacity = 0.9
        withAnimation(.easeOut(duration: 0.35)) {
            captureFlashOpacity = 0
        }
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

    private func handlePreviewSave(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            showStatus("写真に保存しました。")
        case .failure(let error):
            showStatus(error.localizedDescription)
        }
    }

    private func saveCapturedPhoto(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PhotoLibrarySaver.save(image) { result in
            switch result {
            case .success:
                do {
                    let fileName = try CapturedPhotoStore.save(image)
                    let photo = CapturedPhoto(imageFileName: fileName)
                    modelContext.insert(photo)
                    try modelContext.save()
                    completion(.success(()))
                } catch {
                    completion(.failure(error))
                }

            case .failure(let error):
                completion(.failure(error))
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
    let controller: RPPreviewViewController
}

/// ReplayKitの録画プレビュー（保存・共有）を表示するラッパー。
private struct RecordingPreview: UIViewControllerRepresentable {
    let previewController: RPPreviewViewController
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> RPPreviewViewController {
        previewController.previewControllerDelegate = context.coordinator
        return previewController
    }

    func updateUIViewController(_ uiViewController: RPPreviewViewController, context: Context) {}

    final class Coordinator: NSObject, RPPreviewViewControllerDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
            onFinish()
        }
    }
}

#Preview {
    ARCameraScreen()
        .modelContainer(for: [ToyCharacter.self, CapturedPhoto.self], inMemory: true)
}
