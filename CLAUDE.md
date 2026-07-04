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
- The Xcode project uses a file-system-synchronized group, so files added under `Tsureteku/` are picked up automatically (no manual `.pbxproj` edits needed). The local package under `Packages/` is referenced explicitly in the `.pbxproj`.

## Architecture

App entry and data:
- `TsuretekuApp.swift` — `@main`. Builds one on-disk `ModelContainer` over `Schema([ToyCharacter.self, CapturedPhoto.self])` and injects it via `.modelContainer(...)`. **Any new `@Model` type must be added to that `Schema` array** or it won't be persisted.
- `ContentView.swift` — root `TabView`: AR (`ARCameraScreen`), 推し (`CharacterLibraryView`), 履歴 (`CapturedPhotoHistoryView`). The app is locked to light mode (`.preferredColorScheme(.light)`).

Models (`Tsureteku/Models/`):
- `ToyCharacter` — a registered 推し: name, original/cutout image filenames, optional 3D model (USDZ) filename and Object Capture directory, plus AR settings: size, yaw, vertical offset, brightness multiplier, motion on/off, and placement mode (`CharacterARPlacementMode`: 3D model vs. 2D cutout, selectable per character when a model exists).
- `CapturedPhoto` — a saved AR capture, photo **or video** (`CapturedMediaType`). For videos, `imageFileName` holds the poster image and `videoFileName` the movie file; both appear in one history timeline. Also carries scene tags (`SceneTag`: 屋外/食べ物/… — 10 curated Japanese categories) plus `sceneClassifierVersion` and a manual-edit flag that control re-classification.

SwiftData-backed views use `@Query` + `@Environment(\.modelContext)` (don't pass the context manually). Mirror the existing previews' `.modelContainer(for: …, inMemory: true)` for new model-backed views so previews don't write to the on-disk store.

Views (`Tsureteku/Views/`): character add / library / detail, 2D image replacement (`EditCharacterImageView`), the Object Capture preparation + workflow, 3D model adjustment, photo/video history + previews (`CapturedPhotoPreviewView`, `CapturedVideoPreviewView`), and shared pieces (thumbnail, empty state, manual trim, camera capture). The history tab filters by scene tag (chips above the grid; auto-backfills unclassified media on appear) and `SceneTagEditView` edits a capture's tags manually.

AR (`Tsureteku/AR/ARCharacterView.swift`): a RealityKit/ARKit `UIViewRepresentable` that runs world- or face-tracking sessions, places 2D photo cutouts and 3D models, handles selection / scale / rotate, occlusion (person segmentation on supported devices; scene-mesh occlusion via Scene Reconstruction on LiDAR devices), per-character brightness, idle/motion animation, a placement sparkle effect, and snapshot capture. UI state flows in via `@Binding` trigger counters from `ARCameraScreen`. Video recording lives in `ARCameraScreen` and uses ReplayKit (`RPScreenRecorder`) — it records the whole screen, so all visible UI is hidden while recording.

Reality Composer Pro content (`Packages/TsuretekuContent/`): a local Swift package holding RCP-authored scenes (`Sources/TsuretekuContent/TsuretekuContent.rkassets`), loaded at runtime with `Entity(named:in: tsuretekuContentBundle)`. Currently contains `Sparkle.usda`, the particle burst played when a 推し is placed. Edit scenes visually by opening `Package.realitycomposerpro` in Reality Composer Pro, or edit the `.usda` as text — note the emitter config struct must be named `currentState` (not `currentConfiguration`); wrong field names are silently ignored and fall back to defaults.

Services (`Tsureteku/Services/`): file-backed stores and image processing.
- `CharacterImageStore` / `CapturedPhotoStore` — persist images, videos, USDZ models, and Object Capture directories under Application Support (`Tsureteku/…`), referenced by filename stored on the model. `CapturedPhotoStore` also generates video poster images.
- `SubjectCutoutService` (Vision foreground mask), `ImageCropService`, `ImagePreparation`, `ImageThumbnailCache` (downsampled + cached thumbnails for lists), `PhotoLibrarySaver`.
- `SceneClassificationService` — on-device scene tagging via Vision's `VNClassifyImageRequest`, mapped to `SceneTag` through a curated keyword table (two-stage: precision 0.9 multi-tag, then a relaxed 0.7 single-tag fallback). **After changing thresholds or keywords, bump `classifierVersion`** so the history view re-classifies existing media (manually edited captures are skipped).
- Thumbnails for 3D characters: `ModelThumbnailService` (renders a USDZ to source + cutout images), `ObjectCaptureThumbnailService` (picks a representative capture photo), `CharacterPlaceholderImageFactory` (fallback placeholder).
- `UTType+Tsureteku` — `UTType.usdzModel` for file importers.

`Tsureteku/Theme/BrandTheme.swift` — brand colors, gradient, and button style.

## Language rules
- Always answer in Japanese.
