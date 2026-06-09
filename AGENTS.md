# Repository Guidelines

## Project Structure & Module Organization
This repository is a small SwiftUI + SwiftData iOS app.
- Source: `Tsureteku/` (App entry, views, models)
  - `TsuretekuApp.swift` — app bootstrap and data model container setup
  - `ContentView.swift` — primary UI flow
  - `Item.swift` — SwiftData model
- Assets: `Tsureteku/Assets.xcassets/`
- Xcode project: `Tsureteku.xcodeproj/`

Keep feature code grouped by concern in new folders under `Tsureteku/` (for example, `Views/`, `Models/`, `Services/`) as they are added.

## Build, Test, and Development Commands
- `open Tsureteku.xcodeproj`  
  Open the project in Xcode for standard editing/debugging.
- `xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku build`  
  Compile the app in the default configuration.
- `xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku -destination 'platform=iOS Simulator,name=iPhone 16' build`  
  Build against a simulator target.
- `xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku test -destination 'platform=iOS Simulator,name=iPhone 16'`  
  Run tests when a test target exists or is added later.

## Coding Style & Naming Conventions
- Use Swift conventions:
  - 4-space indentation
  - `UpperCamelCase` for types (`ContentView`)
  - `lowerCamelCase` for functions and properties (`addItem`, `deleteItems`)
  - Keep functions focused and small.
- Prefer `final class`/`struct` defaults unless inheritance is required.
- Use SwiftUI modifiers in a readable order (layout → behavior → accessibility).
- No project-wide formatter/linter is configured yet; follow standard Swift API Design Guide conventions.

## Testing Guidelines
- The current project has **no dedicated test files or test target** yet.
- When adding tests, place them in a `TsuretekuTests/`-style target and use the standard `XCTest` naming:
  - Test files: `SomethingTests.swift`
  - Test methods: `testSomethingWhenCondition()`
- Run tests with the CLI command above, or via Xcode’s Test action on the scheme.
- Add at least one test per new business logic branch and UI state change.

## Commit & Pull Request Guidelines
- Commit messages should follow [gitmoji.dev](https://gitmoji.dev/) format (use an emoji prefix, then a short Japanese/English summary).
- Recommended examples:
  - `📝 Update contributor documentation`
  - `🧹 Clean up Xcode/IDE artifacts from version control`
- Keep one logical change per commit and include verification steps in the PR description.
- PRs should include:
  - summary of behavior change
  - verification command used (e.g., `xcodebuild ... build`)
  - screenshots for UI-visible changes
  - any migration/configuration notes (bundle ID, simulator/OS version assumptions)

## Language rules
- Always answer in Japanese.
