# Project Tsureteku

## Project Overview
Tsureteku（つれてく）は、SwiftUI と SwiftData を使用した AR iOS アプリです。お気に入りの「推し」（ぬいぐるみ・フィギュア等）を写真の自動切り抜きや3Dスキャン（Object Capture / USDZ）で登録し、ARで床・机・壁や自撮りで一緒に配置して写真・動画を撮影できます。データは端末内にのみ保存されます。

- **Main Technologies**: Swift, SwiftUI, SwiftData, RealityKit, ARKit, Vision, Xcode
- **Deployment Target**: iOS 18.0
- **Source Code**: `Tsureteku/` ディレクトリに主要なソースコードが格納されています。

## Building and Running
プロジェクトのビルドと実行には以下のコマンドを使用します。

### Xcode で開く
```bash
open Tsureteku.xcodeproj
```

### ビルド
```bash
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku build
```

### シミュレータでのビルド
```bash
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### テストの実行
（現在はテストターゲットが存在しませんが、追加された場合は以下のコマンドで実行可能です）
```bash
xcodebuild -project Tsureteku.xcodeproj -scheme Tsureteku test -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Development Conventions
開発時には以下のガイドラインに従ってください。

- **Coding Style**:
  - インデントは 4 スペース。
  - 型名は `UpperCamelCase`、関数・プロパティ名は `lowerCamelCase`。
  - 関数は小さく、単一の責任を持つように保つ。
  - 継承が必要ない場合は `final class` または `struct` を優先する。
  - SwiftUI モディファイアの順序: レイアウト → 振る舞い → アクセシビリティ。
- **Testing**:
  - 新しいビジネスロジックや UI 状態の変化に対して、少なくとも 1 つのテストを追加することを推奨します。
  - テストファイル名は `SomethingTests.swift`、メソッド名は `testSomethingWhenCondition()` とします。
- **Commit Messages**:
  - 簡潔で命令形のメッセージ（例: `feat: add onboarding flow`）を使用する。
  - 1 つのコミットには 1 つの論理的な変更を含める。
- **Language**:
  - 回答は常に日本語で行ってください。

## Project Structure
- `Tsureteku/`: ソースコードとアセット
  - `TsuretekuApp.swift`: アプリのエントリポイント、`ModelContainer` 設定（`ToyCharacter`, `CapturedPhoto`）
  - `ContentView.swift`: ルートの `TabView`（AR / 推し / 履歴）
  - `Models/`: SwiftData モデル（`ToyCharacter`, `CapturedPhoto`）
  - `Views/`: 各画面（推し登録/一覧/詳細、Object Capture、写真履歴 など）
  - `AR/`: RealityKit/ARKit の AR ビュー（`ARCharacterView`）
  - `Services/`: ファイル保存・画像処理（`CharacterImageStore`, `SubjectCutoutService` など）
  - `Theme/`: ブランドカラー・スタイル
  - `Assets.xcassets/`: アプリアイコンやカラーセット
- `Tsureteku.xcodeproj/`: Xcode プロジェクトファイル（`Tsureteku/` 配下のファイルは自動でターゲットに追加されます）
- `AGENTS.md`: リポジトリの詳細なガイドライン
- `README.md`: プロジェクトの基本情報

## Language rules
- Always answer in Japanese.
