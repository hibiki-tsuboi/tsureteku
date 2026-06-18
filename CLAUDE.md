# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tsureteku（つれてく）is a SwiftUI + SwiftData iOS app for taking a favorite character ("推し" — a plush toy, figure, etc.) along in augmented reality. You register a 推し from a photo (Vision auto-cutout) or a 3D scan (Object Capture / imported USDZ), place it in AR — on floors, tables, or walls, or beside your face in selfie mode — and take photos and videos with it. All data is stored on-device.

See `AGENTS.md` for repository conventions (style, commit/PR guidelines).

## Common commands

Build for the default destination:
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku build
```

Build for a simulator (use an installed destination — `generic/platform=iOS Simulator`, or a specific device name):
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku -destination 'generic/platform=iOS Simulator' build
```

Run tests (no test target exists yet — this will fail until one is added):
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku test -destination 'platform=iOS Simulator,name=iPhone 17'
```

Open in Xcode: `open Tsureteku.xcodeproj`

Notes:
- Deployment target is **iOS 18.0**.
- AR, the camera, and Object Capture (3D scanning) require a **physical device** — the simulator can only build/run the non-AR UI.
- The Xcode project uses a file-system-synchronized group, so files added under `Tsureteku/` are picked up automatically (no manual `.pbxproj` edits needed).

## Architecture

App entry and data:
- `TsuretekuApp.swift` — `@main`. Builds one on-disk `ModelContainer` over `Schema([ToyCharacter.self, CapturedPhoto.self])` and injects it via `.modelContainer(...)`. **Any new `@Model` type must be added to that `Schema` array** or it won't be persisted.
- `ContentView.swift` — root `TabView`: AR (`ARCameraScreen`), 推し (`CharacterLibraryView`), 履歴 (`CapturedPhotoHistoryView`). The app is locked to light mode (`.preferredColorScheme(.light)`).

Models (`Tsureteku/Models/`):
- `ToyCharacter` — a registered 推し: name, original/cutout image filenames, optional 3D model (USDZ) filename and Object Capture directory, plus AR size / yaw / vertical offset.
- `CapturedPhoto` — a saved AR photo (image filename + date).

SwiftData-backed views use `@Query` + `@Environment(\.modelContext)` (don't pass the context manually). Mirror the existing previews' `.modelContainer(for: …, inMemory: true)` for new model-backed views so previews don't write to the on-disk store.

Views (`Tsureteku/Views/`): character add / library / detail, the Object Capture preparation + workflow, 3D model adjustment, photo history / preview, and shared pieces (thumbnail, empty state, manual trim, camera capture).

AR (`Tsureteku/AR/ARCharacterView.swift`): a RealityKit/ARKit `UIViewRepresentable` that runs world- or face-tracking sessions, places 2D photo cutouts and 3D models, handles selection / scale / rotate, person occlusion, idle animation, and snapshot capture. UI state flows in via `@Binding` trigger counters from `ARCameraScreen`.

Services (`Tsureteku/Services/`): file-backed stores and image processing.
- `CharacterImageStore` / `CapturedPhotoStore` — persist images, USDZ models, and Object Capture directories under Application Support (`Tsureteku/…`), referenced by filename stored on the model.
- `SubjectCutoutService` (Vision foreground mask), `ImageCropService`, `ImagePreparation`, `ImageThumbnailCache` (downsampled + cached thumbnails for lists), `PhotoLibrarySaver`.

`Tsureteku/Theme/BrandTheme.swift` — brand colors, gradient, and button style.

## Language rules
- Always answer in Japanese.
