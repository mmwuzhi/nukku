# Nukku：播放状态判断 & Dia/Bilibili 读取问题排查总结

## 背景

在 Nukku 里按以下思路做了媒体信息读取：

1. 优先使用 MediaRemote 读取 macOS 系统 Now Playing 信息
2. 如果 MediaRemote 读不到，再尝试浏览器 JS / MediaSession fallback
3. 最后 fallback 到浏览器标题、窗口标题、App icon 等

但目前遇到两个问题：

1. 视频明明已经暂停好几秒，Nukku 顶部仍然显示“正在播放”
2. Dia 浏览器里的 Bilibili 可以被 macOS 控制中心读取到，但 Nukku 读取不到

这两个问题很可能不是同一个 bug，而是两个不同层面的缺口。

---

## 问题 1：暂停后 Nukku 仍显示正在播放

### 现象

页面视频已经暂停，但 Nukku 顶部仍然显示正在播放状态，例如：

- 顶部 notch 仍显示播放动态条
- UI 仍认为媒体处于 playing 状态
- 但实际视频已经 paused

### 可能原因

很多 Now Playing / MediaRemote 数据并不是实时完全可靠的。

可能出现：

    title / artwork 还在
    playbackState 没及时变
    playbackRate 没及时变
    elapsedTime 不再变化但 state 仍然是 playing
    上一条媒体信息残留
    浏览器桥接到系统 Now Playing 的状态有延迟

所以不能只根据单个字段判断是否正在播放。

尤其不要这样写：

    isPlaying = playbackState == .playing

这太容易被脏数据骗。

---

## 正确做法：不要只信 playbackState，要检测 elapsedTime 是否真的在动

推荐维护连续两次采样。

数据结构可以类似：

    struct MediaSample {
        let title: String
        let appBundleID: String?
        let playbackState: PlaybackState
        let playbackRate: Double?
        let elapsedTime: TimeInterval?
        let duration: TimeInterval?
        let sampledAt: Date
    }

核心思路：

    如果 playbackState 明确是 paused/stopped，则认为暂停
    如果 playbackState 是 playing，但 elapsedTime 长时间不动，也认为已经暂停/卡住
    如果 playbackRate <= 0，也不能简单认为正在播放
    如果 elapsedTime 持续推进，才更可信地认为正在播放

示例逻辑：

    final class MediaActivityDetector {
        private var lastSample: MediaSample?

        func isActuallyPlaying(_ current: MediaSample) -> Bool {
            defer { lastSample = current }

            // 如果系统明确说不是 playing，优先相信不是播放中
            guard current.playbackState == .playing else {
                return false
            }

            // 如果有 playbackRate，并且 <= 0，通常不应认为正在播放
            if let rate = current.playbackRate, rate <= 0.01 {
                return false
            }

            guard
                let last = lastSample,
                last.title == current.title,
                last.appBundleID == current.appBundleID,
                let lastElapsed = last.elapsedTime,
                let currentElapsed = current.elapsedTime
            else {
                // 第一次看到 playing，可以先暂时相信一次
                return true
            }

            let wallDelta = current.sampledAt.timeIntervalSince(last.sampledAt)
            let mediaDelta = currentElapsed - lastElapsed

            // 时间间隔太短时不判断，避免误杀
            guard wallDelta > 1.0 else {
                return true
            }

            // 正常播放时，media elapsed 应该跟着现实时间增加
            // 给一点容错，比如至少达到现实时间的 0.3 倍
            return mediaDelta > wallDelta * 0.3
        }
    }

---

## 推荐的播放状态判断顺序

不要只依赖一个字段。

推荐顺序：

    1. playbackState 明确是 paused / stopped
       → 认为暂停

    2. playbackRate 存在，并且 <= 0.01
       → 认为暂停

    3. playbackState 是 playing，但 elapsedTime 连续 1.5～2 秒不动
       → 认为暂停 / stalled

    4. playbackState 是 playing，playbackRate > 0，elapsedTime 也在推进
       → 认为正在播放

    5. title / artwork 存在，但状态不可靠
       → 可以继续显示内容，但按钮状态显示为 paused

也就是说，内容显示和播放状态可以分开判断：

    内容是否显示：
    看 title / artwork / app / source 是否有意义

    是否正在播放：
    看 playbackRate + elapsedTime 是否真的在推进

---

## UI debounce 建议

暂停/播放状态最好不要一收到一次变化就立刻切换。

推荐：

    检测到 playing：
      可以立即显示播放中

    检测到 paused / stalled：
      连续 2 次检测到，或持续 1.5 秒后，再切成暂停

原因：

    浏览器和 MediaRemote 的状态变化可能有延迟
    暂停瞬间可能出现一两次脏数据
    debounce 可以避免 UI 抖动

示例策略：

    playing → 立即生效
    paused/stalled → 延迟 1.5 秒确认
    no title/no artwork → 延迟清空，避免闪烁

---

## 问题 2：Dia 的 Bilibili 控制中心能读到，但 Nukku 读不到

### 现象

Dia 浏览器里播放 Bilibili：

    macOS 控制中心可以显示 Bilibili 播放信息

但 Nukku：

    读取不到
    或显示 fallback 内容
    或没有正确识别为当前播放内容

### 这说明什么？

如果 macOS 控制中心能显示，说明：

    Dia / Bilibili 至少已经成功把媒体信息注册进了系统 Now Playing 管线

也就是说，问题不在 Bilibili 页面完全没有 metadata。

更可能是：

    Nukku 的 MediaRemote 读取方式没有拿到正确 client
    或 Nukku 过滤掉了 Dia
    或 Nukku 只读取了默认 now playing info
    或 Nukku 只在 isPlaying 为 true 时才读取 metadata
    或 Nukku 没有监听 now playing client / info 变化
    或 artwork/title 字段处理不完整

---

## 重点排查方向

### 1. 不要只调用一次 MRMediaRemoteGetNowPlayingInfo

有时候：

    MRMediaRemoteGetNowPlayingInfo

拿到的不是控制中心当前展示的那个媒体源。

尤其在这些情况下容易出问题：

    多个播放器同时存在
    Apple Music / Spotify / 浏览器并存
    浏览器网页播放器切换
    新浏览器如 Dia / Arc / Zen
    媒体 session client 变化

推荐同时使用 / 监听：

    MRMediaRemoteGetNowPlayingApplicationIsPlaying
    MRMediaRemoteGetNowPlayingClient
    MRMediaRemoteGetNowPlayingInfo
    NowPlayingInfoDidChange notification
    NowPlayingApplicationDidChange notification
    NowPlayingClientDidChange notification

核心目标是确认：

    当前 MediaRemote client 到底是谁？
    client bundle id 是不是 Dia？
    info 里有没有 title/artwork？
    是没拿到，还是拿到了但被过滤掉？

---

## 2. Debug 阶段不要 whitelist 太早

Dia 是新浏览器，bundle id 可能不在已有列表里。

不要只允许这些：

    com.apple.Safari
    com.google.Chrome
    com.microsoft.edgemac
    company.thebrowser.Browser
    org.mozilla.firefox

Dia 的 bundle id 可能不一样。

Debug 阶段应该：

    不按 bundle id 过滤 MediaRemote client
    允许所有 client
    把 client 信息全部打印出来

否则很可能出现：

    系统控制中心拿到了 Dia
    Nukku 也拿到了
    但 Nukku 因为不认识 Dia，把它过滤掉了

---

## 3. Dia 可能通过 helper process 注册媒体 session

有些 Chromium 系浏览器的媒体 session 不一定直接表现为主 App bundle。

可能出现：

    控制中心显示 Dia
    但 MediaRemote client 的 bundle id / process name 不是你预期的 Dia 主程序
    或者是某个 helper process
    或者 name 和 bundle id 字段有差异

所以不要写死：

    if bundleID == "xxx" { ... }

更好的做法：

    先 dump 出所有 client/info 字段
    再决定如何识别

---

## 4. 不要先判断 isPlaying 再读取 nowPlayingInfo

错误写法：

    if isPlaying {
        getNowPlayingInfo()
    }

这个逻辑会错过很多浏览器媒体。

因为浏览器媒体经常出现：

    metadata 有
    title 有
    artwork 有
    但 isPlaying / playbackState / playbackRate 不稳定

正确顺序应该是：

    先读取 nowPlayingInfo
    再根据 title / artwork / elapsedTime / playbackRate 判断状态

也就是说：

    是否有内容
    和
    是否正在播放

要分开判断。

推荐逻辑：

    let info = getNowPlayingInfo()

    if info has title/artwork {
        show content
    }

    isPlaying = detectByRateAndElapsedTime(info)

---

## 5. 可能是 artwork 字段没有处理完整

有时候 MediaRemote 里的 artwork 不一定只靠一个字段。

需要检查这些信息：

    kMRMediaRemoteNowPlayingInfoArtworkData
    kMRMediaRemoteNowPlayingInfoArtworkMIMEType
    kMRMediaRemoteNowPlayingInfoArtworkIdentifier
    artwork data 是否为空
    artwork MIME type 是否是 webp / jpg / png
    NSImage 是否成功 decode

可能出现：

    title 其实有
    artwork data 也有
    但 decode 失败
    所以 UI fallback 了

也可能是：

    title 有
    artwork 没有
    但 Nukku 的 isUseful 要求 artwork 必须存在
    所以被过滤掉了

因此 isUseful 不要过于严格。

---

## 建议加一个 Debug Overlay / Debug Log

强烈建议在 Nukku 里临时加一个 debug panel。

直接显示这些信息：

    frontmostApp:
      name:
      bundleID:
      processID:

    MediaRemote client:
      appName:
      bundleID:
      processID:
      raw client object:

    MediaRemote info:
      all keys:
      title:
      artist:
      album:
      playbackState:
      playbackRate:
      elapsedTime:
      duration:
      timestamp:
      artworkData exists:
      artworkData size:
      artworkMIMEType:
      artworkIdentifier:

    Browser fallback:
      browserName:
      browserBundleID:
      document.title:
      location.href:
      mediaSession.playbackState:
      mediaSession.title:
      mediaSession.artist:
      mediaSession.album:
      artwork count:
      first artwork src:

这样可以一眼判断到底是哪一层断了。

---

## MediaRemote 原始字段建议全部 dump

Debug 时不要只打印解析后的 model。

应该直接打印原始 dictionary：

    print(nowPlayingInfo.keys)
    print(nowPlayingInfo)

重点看类似字段：

    kMRMediaRemoteNowPlayingInfoTitle
    kMRMediaRemoteNowPlayingInfoArtist
    kMRMediaRemoteNowPlayingInfoAlbum
    kMRMediaRemoteNowPlayingInfoArtworkData
    kMRMediaRemoteNowPlayingInfoArtworkMIMEType
    kMRMediaRemoteNowPlayingInfoPlaybackRate
    kMRMediaRemoteNowPlayingInfoElapsedTime
    kMRMediaRemoteNowPlayingInfoDuration
    kMRMediaRemoteNowPlayingInfoTimestamp

如果 macOS 控制中心能显示，但 Nukku dump 里完全没有 title/artwork：

    说明 MediaRemote client/info 获取链路有问题

如果 dump 里有 title 但 UI 没显示：

    说明是解析 / isUseful / 过滤逻辑问题

如果 dump 里有 artworkData 但 UI 没图：

    说明是 artwork decode / MIME type / NSImage 转换问题

如果 dump 里有 Dia client 但被跳过：

    说明是 whitelist / bundle id 判断问题

---

## 修正后的整体读取逻辑

推荐改成：

    1. 永远先读取 MediaRemote info
       不要先判断 isPlaying

    2. 如果 MediaRemote 有 title / artwork：
       内容显示用 MediaRemote

    3. 播放状态不要只用 playbackState
       用 playbackRate + elapsedTime 变化共同判断

    4. 如果 MediaRemote 没有可用 title：
       如果前台是 Safari / Chrome / Edge / Arc / Dia：
         尝试 Browser JS MediaSession

    5. 如果 Browser JS MediaSession 有 title / artwork：
       显示它

    6. 如果还没有：
       读取网页 title / favicon / og:image

    7. 最后 fallback：
       前台 app window title + app icon

---

## 推荐 Coordinator 伪代码

    func currentContent() async -> NotchContent? {
        // 1. 永远先读 MediaRemote，不要先判断 isPlaying
        if let media = await mediaRemoteProvider.snapshot(),
           media.hasUsefulContent {
            var content = media.asNotchContent()

            // 播放状态单独判断
            content.isPlaying = mediaActivityDetector.isActuallyPlaying(media.sample)

            return content
        }

        // 2. MediaRemote 没内容，再尝试 Browser MediaSession
        if let browserMedia = await browserMediaSessionProvider.snapshot(),
           browserMedia.hasUsefulContent {
            return browserMedia.asNotchContent()
        }

        // 3. 再尝试普通网页信息
        if let browserTab = await browserTabProvider.snapshot(),
           browserTab.hasUsefulContent {
            return browserTab.asNotchContent()
        }

        // 4. 最后 fallback 到前台 App
        return await frontmostAppProvider.snapshot()
    }

---

## 内容可用性判断

内容是否显示，不应该依赖是否正在播放。

推荐：

    extension MediaSnapshot {
        var hasUsefulContent: Bool {
            if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }

            if artwork != nil {
                return true
            }

            return false
        }
    }

也就是说：

    有 title 就可以显示
    有 artwork 也可以显示
    不要因为 paused 就隐藏
    不要因为 playbackState 不可靠就丢掉内容

---

## 播放状态判断

播放状态应该单独判断：

    extension MediaSnapshot {
        var sample: MediaSample {
            MediaSample(
                title: title ?? "",
                appBundleID: bundleID,
                playbackState: playbackState,
                playbackRate: playbackRate,
                elapsedTime: elapsedTime,
                duration: duration,
                sampledAt: Date()
            )
        }
    }

判断：

    isPlaying =
        playbackRate > 0.01
        && elapsedTimeIsMoving

或者更宽松一点：

    isPlaying =
        playbackRate > 0.01
        || playbackState == .playing && elapsedTimeIsMoving

但不要只写：

    isPlaying = playbackState == .playing

---

## 针对“暂停后仍显示播放中”的具体修法

增加 elapsedTime stall detection。

逻辑：

    如果 playbackState == playing
    但 elapsedTime 在 1.5～2 秒内没有明显增加
    则认为实际已经 paused/stalled

UI 上：

    可以继续显示当前媒体卡片
    但播放状态改为 paused

也就是：

    title / artwork 继续显示
    播放动画停止
    播放按钮变成 play

这比直接清空内容更自然。

---

## 针对 Dia + Bilibili 读取不到的具体排查清单

逐项检查：

    1. 有没有把 Dia 加到浏览器支持列表？
       或者 debug 阶段是否完全取消了 whitelist？

    2. MediaRemote client 是否能拿到 Dia？
       client appName / bundleID / processID 是什么？

    3. 是否只在 isPlaying == true 时才读取 nowPlayingInfo？
       如果是，改成永远先读 info。

    4. nowPlayingInfo 原始 dictionary 里有没有 title？

    5. nowPlayingInfo 原始 dictionary 里有没有 artworkData？

    6. artworkData 是否成功转成 NSImage？

    7. isUseful 是否因为 artist 为空 / artwork 为空 / state 不是 playing 而把内容过滤掉？

    8. 有没有监听 now playing client / info 变化通知？

    9. Dia 是否通过 helper process 注册？
       bundle id / process name 是否和预期不同？

    10. Browser JS fallback 是否支持 Dia？
        Dia 如果是 Chromium 系，可能可以用类似 Chrome / Arc 的 AppleScript。
        如果不能，则需要额外适配。

---

## Dia 的 Browser JS fallback

如果 Dia 支持 AppleScript 执行 JS，可以尝试类似：

    tell application "Dia"
        execute active tab of front window javascript "JSON.stringify({
          playbackState: navigator.mediaSession.playbackState,
          title: navigator.mediaSession.metadata?.title,
          artist: navigator.mediaSession.metadata?.artist,
          album: navigator.mediaSession.metadata?.album,
          artwork: navigator.mediaSession.metadata?.artwork,
          documentTitle: document.title,
          url: location.href
        })"
    end tell

如果 Dia 不支持这个语法，需要单独查它的 AppleScript dictionary。

如果没有 AppleScript JS 能力：

    短期只能靠 MediaRemote
    长期可以做 Nukku Browser Companion Extension

---

## 最终推荐架构

### Provider 顺序

    MediaRemoteProvider
    ↓
    BrowserMediaSessionProvider
    ↓
    BrowserTabProvider
    ↓
    FrontmostAppProvider

### MediaRemoteProvider 负责

    title
    artist
    album
    artwork
    source app
    bundle id
    playbackRate
    elapsedTime
    duration
    timestamp

### MediaActivityDetector 负责

    判断是否真的正在播放
    不直接相信 playbackState
    使用 playbackRate + elapsedTime movement

### BrowserMediaSessionProvider 负责

    navigator.mediaSession.metadata
    navigator.mediaSession.playbackState
    document.title
    location.href

### BrowserTabProvider 负责

    title
    url
    favicon
    og:image
    site name

### FrontmostAppProvider 负责

    app name
    app icon
    window title

---

## 核心结论

    1. “有没有内容可以显示”和“是不是正在播放”要分开判断。

    2. MediaRemote 的 title/artwork 可以继续显示，
       但播放状态必须用 playbackRate + elapsedTime movement 二次确认。

    3. 暂停后仍显示播放中，大概率是太信任 playbackState，
       需要加 elapsedTime stall detection。

    4. Dia + Bilibili 控制中心能显示，说明系统 Now Playing 管线里有信息。

    5. Nukku 读不到 Dia + Bilibili，
       优先怀疑是 client 获取、bundle id 过滤、读取顺序、通知监听或 artwork/title 解析问题。

    6. Debug 阶段不要 whitelist MediaRemote client，
       应该 dump 所有原始字段。

    7. 不要先判断 isPlaying 再读取 nowPlayingInfo。
       应该先读取 info，再判断状态。

    8. 长期最稳方案是：
       MediaRemote + Browser JS + Browser Extension 多层 fallback。

---

## 推荐下一步

先做三个 debug 改动：

    1. MediaRemote 原始 dictionary 全量 dump

    2. 显示当前 MediaRemote client 的 appName / bundleID / processID

    3. 增加 elapsedTime stall detection

这三个做完，基本就能判断：

    是 Dia client 没拿到
    还是 info 拿到了但被过滤
    还是 artwork 解码失败
    还是播放状态判断错误