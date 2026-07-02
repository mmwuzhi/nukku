# Nukku

English | [日本語](#日本語) | [简体中文](#简体中文)

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)
![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange)
![SPM](https://img.shields.io/badge/build-SPM-blue)
![Version 0.1.0](https://img.shields.io/badge/version-0.1.0-blue)

Nukku is a macOS notch utility that turns the MacBook notch into a small interactive panel for media, files, calendar, camera preview, and system HUDs.

## Features

- Notch panel: hover or click the notch to expand a widget panel.
- HUD overlays: volume, brightness, battery, notifications, and lock state appear inside the notch, then auto-dismiss.
- Widgets:
  - Now Playing: trusted MediaRemote or browser MediaSession metadata with playback controls.
  - File Drop: drag files in, then open them or reveal them in Finder.
  - Calendar: browse a month, filter calendars, and create, edit, or delete EventKit events.
  - Camera: live preview with Center Stage on supported cameras.
- Menu bar presence: Nukku runs as an accessory app and stays out of the Dock and app switcher.
- Launch at login: managed through `SMAppService`.
- Multi-screen aware: moves back to the notched display when screens change.
- Full-screen compatible: remains visible in full-screen spaces.

## Requirements

- macOS 26 Tahoe or later.
- A MacBook with a notch. Non-notch Macs can still use the menu-bar fallback.
- Xcode 26 and Swift 6.2 for local builds.

## Install

Download `Nukku.app.zip` from the latest GitHub Release, unzip it, and move `Nukku.app` to `Applications` or `~/Applications`.

The release artifact is currently ad-hoc signed by GitHub Actions. macOS may ask you to approve the app manually on first launch. Developer ID signing and notarization can be added later by installing a Developer ID certificate in the release workflow.

## Build Locally

```bash
git clone https://github.com/mmwuzhi/nukku
cd nukku
swift build
swift test
./Scripts/package.sh --run
```

The app must run from the packaged `.app`. The bare executable does not provide the bundle identity required by macOS system services. `Scripts/package.sh` creates and signs `.build/Nukku.app`; add `--install-user` to copy it to `~/Applications/Nukku.app`, or combine it with `--run` to launch the installed copy.

## Release

The current version is `0.1.0`, stored in `VERSION`. To publish it:

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions will build on `macos-26`, run tests, package `Nukku.app`, create `Nukku.app.zip`, generate a SHA-256 checksum, and attach both files to the GitHub Release.

## Preferences

| Setting | Options | Default |
|---|---|---|
| Expand trigger | Hover / Click | Hover |
| Expand delay | 0 to 0.5 s | 0.1 s |
| Collapse delay | 0.1 to 1.0 s | 0.3 s |
| Launch at login | On / Off | On |

Open preferences from the status-bar menu or by clicking the gear icon in the expanded panel.

## Architecture Notes

Nukku uses a fixed-canvas window, 700 x 340 pt, that never resizes. All expansion and collapse animation happens inside SwiftUI through one spring animation, which avoids tearing caused by AppKit window resizing during animation.

See [CLAUDE.md](CLAUDE.md) for architecture details, directory layout, and contribution notes.

## Privacy

- Calendar access: requested on first Calendar widget use and used only to browse and edit events.
- Camera access: requested when the Camera widget is first activated. Frames stay on-device.
- Files: File Drop reads and writes only files explicitly dropped into the app.
- Browser automation: optional Apple Events access supports browser MediaSession metadata.
- Network: no analytics or telemetry. Remote MediaSession artwork may be downloaded and cached locally.

## License

MIT

## 日本語

[English](#nukku) | 日本語 | [简体中文](#简体中文)

Nukkuは、MacBookのノッチをメディア、ファイル、カレンダー、カメラプレビュー、システムHUDのための小さな操作パネルに変えるmacOSアプリです。

### 主な機能

- ノッチパネル：ノッチにホバーまたはクリックすると、ウィジェットパネルを展開できます。
- HUD表示：音量、明るさ、バッテリー、通知、ロック状態をノッチ内に表示し、自動で閉じます。
- ウィジェット：
  - 再生中：MediaRemoteまたはブラウザMediaSessionの信頼できるメタデータと再生操作。
  - ファイルドロップ：ファイルをドラッグして、開く、またはFinderに表示。
  - カレンダー：月表示、カレンダーの絞り込み、EventKit予定の作成、編集、削除。
  - カメラ：対応カメラではCenter Stage付きのライブプレビュー。
- メニューバー常駐：アクセサリアプリとして動作し、Dockとアプリスイッチャーには表示されません。
- ログイン時に起動：`SMAppService`で管理します。
- 複数画面対応：画面構成が変わると、ノッチのある画面へ戻ります。
- フルスクリーン対応：フルスクリーンスペースでも表示されます。

### 要件

- macOS 26 Tahoe以降。
- ノッチ付きMacBook。ノッチのないMacではメニューバーのフォールバックで動作します。
- ローカルビルドにはXcode 26とSwift 6.2が必要です。

### インストール

最新のGitHub Releaseから `Nukku.app.zip` をダウンロードし、展開した `Nukku.app` を `Applications` または `~/Applications` に移動してください。

現在のリリース成果物はGitHub Actionsによるad-hoc署名です。初回起動時にmacOS側で手動承認が必要になる場合があります。Developer ID署名とnotarizationは、後でリリースワークフローにDeveloper ID証明書を追加して対応できます。

### ローカルビルド

```bash
git clone https://github.com/mmwuzhi/nukku
cd nukku
swift build
swift test
./Scripts/package.sh --run
```

Nukkuはパッケージ化された `.app` から実行する必要があります。生の実行ファイルには、macOSのシステムサービスが必要とするbundle identityがありません。`Scripts/package.sh` は `.build/Nukku.app` を作成して署名します。`--install-user` を付けると `~/Applications/Nukku.app` にコピーできます。

### リリース

現在のバージョンは `VERSION` に保存された `0.1.0` です。公開するには次を実行します。

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actionsは `macos-26` 上でビルドとテストを行い、`Nukku.app` をパッケージ化し、`Nukku.app.zip` とSHA-256チェックサムをGitHub Releaseに添付します。

### プライバシー

- カレンダー：カレンダーウィジェットの初回使用時に要求し、予定の表示と編集にだけ使います。
- カメラ：カメラウィジェットの初回有効化時に要求します。映像は端末内に留まります。
- ファイル：File Dropは、ユーザーが明示的にドロップしたファイルだけを読み書きします。
- ブラウザ自動操作：ブラウザMediaSessionメタデータのために、任意でApple Eventsアクセスを使います。
- ネットワーク：分析やテレメトリはありません。リモートのMediaSessionアートワークをローカルキャッシュする場合があります。

### ライセンス

MIT

## 简体中文

[English](#nukku) | [日本語](#日本語) | 简体中文

Nukku 是一个 macOS 刘海工具，会把 MacBook 刘海变成一个小型交互面板，用来控制媒体、暂存文件、查看日历、预览摄像头和显示系统 HUD。

### 功能

- 刘海面板：鼠标悬停或点击刘海即可展开 widget 面板。
- HUD 覆盖层：音量、亮度、电池、通知和锁屏状态会显示在刘海内，并自动收起。
- Widgets：
  - 正在播放：使用可信的 MediaRemote 或浏览器 MediaSession 元数据，并提供播放控制。
  - 文件暂存：把文件拖进来后，可以打开或在 Finder 中显示。
  - 日历：浏览月份、筛选日历，并创建、编辑或删除 EventKit 日程。
  - 摄像头：实时预览，支持的摄像头可使用 Center Stage。
- 菜单栏常驻：以 accessory app 运行，不出现在 Dock 或应用切换器中。
- 登录时启动：通过 `SMAppService` 管理。
- 多屏幕感知：屏幕变化后会回到带刘海的显示器。
- 全屏兼容：在全屏空间中也保持可见。

### 要求

- macOS 26 Tahoe 或更高版本。
- 带刘海的 MacBook。无刘海 Mac 可以使用菜单栏兜底模式。
- 本地构建需要 Xcode 26 和 Swift 6.2。

### 安装

从最新的 GitHub Release 下载 `Nukku.app.zip`，解压后把 `Nukku.app` 移到 `Applications` 或 `~/Applications`。

当前发布产物由 GitHub Actions 做 ad-hoc 签名。首次启动时，macOS 可能需要你手动批准。之后可以在发布工作流里加入 Developer ID 证书，补上 Developer ID 签名和 notarization。

### 本地构建

```bash
git clone https://github.com/mmwuzhi/nukku
cd nukku
swift build
swift test
./Scripts/package.sh --run
```

这个 app 必须从打包后的 `.app` 运行。裸可执行文件没有 macOS 系统服务需要的 bundle identity。`Scripts/package.sh` 会创建并签名 `.build/Nukku.app`；加上 `--install-user` 可以复制到 `~/Applications/Nukku.app`。

### 发布

当前版本是 `VERSION` 文件里的 `0.1.0`。发布时执行：

```bash
git tag v0.1.0
git push origin v0.1.0
```

GitHub Actions 会在 `macos-26` 上构建和测试，打包 `Nukku.app`，生成 `Nukku.app.zip` 和 SHA-256 校验文件，并把它们附到 GitHub Release。

### 隐私

- 日历权限：首次使用日历 widget 时请求，只用于浏览和编辑日程。
- 摄像头权限：首次启用摄像头 widget 时请求，画面留在本机。
- 文件：File Drop 只读写用户明确拖入 app 的文件。
- 浏览器自动化：可选的 Apple Events 权限用于读取浏览器 MediaSession 元数据。
- 网络：没有分析和遥测。远程 MediaSession 封面可能会下载并缓存在本地。

### 许可证

MIT
