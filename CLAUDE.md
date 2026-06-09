# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tsureteku is a SwiftUI + SwiftData iOS app, currently a fresh Xcode template (single `Item` model, single `ContentView` list view). See `AGENTS.md` for repository conventions (style, commit/PR guidelines, suggested folder layout under `Tsureteku/` as features are added).

## Common commands

Build for the default destination:
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku build
```

Build for a simulator:
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Run tests (no test target exists yet — this will fail until one is added):
```
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku test -destination 'platform=iOS Simulator,name=iPhone 16'
```

Open in Xcode: `open Tsureteku.xcodeproj`

## Architecture

The whole app fits in three files under `Tsureteku/`:

- `TsuretekuApp.swift` — `@main` entry. Builds a single `ModelContainer` over `Schema([Item.self])` with on-disk persistence and injects it via `.modelContainer(...)`. Any new `@Model` types must be added to that `Schema` array or they won't be persisted.
- `ContentView.swift` — root view. Uses `@Query` to read `Item`s and `@Environment(\.modelContext)` to insert/delete. New SwiftData-backed views follow the same pattern; don't pass the context manually.
- `Item.swift` — the only `@Model`. Add new models as siblings and register them in `TsuretekuApp`'s schema.

The `#Preview` in `ContentView` uses `.modelContainer(for: Item.self, inMemory: true)` — mirror this in previews for new model-backed views so previews don't write to the on-disk store.

## Language rules
- Always answer in Japanese.
