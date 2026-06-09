# Project Tsureteku

## Project Overview
Tsureteku は、SwiftUI と SwiftData を使用したシンプルな iOS アプリケーションです。アイテム（`Item`）のリストを表示し、追加および削除する機能を備えています。

- **Main Technologies**: Swift, SwiftUI, SwiftData, Xcode
- **Architecture**: 標準的な SwiftUI + SwiftData アプリ構成
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
  - `TsuretekuApp.swift`: アプリのエントリポイント、SwiftData の `ModelContainer` 設定
  - `ContentView.swift`: メイン UI（リスト表示、追加/削除機能）
  - `Item.swift`: SwiftData モデルクラス
  - `Assets.xcassets/`: アプリアイコンやカラーセット
- `Tsureteku.xcodeproj/`: Xcode プロジェクトファイル
- `AGENTS.md`: リポジトリの詳細なガイドライン
- `README.md`: プロジェクトの基本情報

## Language rules
- Always answer in Japanese.
