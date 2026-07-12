# 汽水音乐适配调查记录

## 当前结论

- 汽水音乐 Bundle ID 是 `com.soda.music`。
- 早期浅层 Accessibility 树只能稳定看到主窗口和系统窗口按钮；后续通过深层汽水内容窗口 AX 扫描，已能读取当前可见歌名、封面、歌词和进度，但播放/暂停状态仍只能间接推断。
- V1 已加入汽水 client 定向控制：播放/暂停、上一首、下一首直接发送给 `com.soda.music` 的 `MRNowPlayingClient`，不切换前台 App，也不依赖系统当前媒体焦点；失败时只允许唯一语义 AX 控件降级。
- 桌面歌词界面来自 `/Applications/汽水音乐.app/Contents/Resources/desktopLyrics.asar`。
- `desktopLyrics.asar` 内部通过 `window.transportPort` 连接主进程服务，不是通过 Accessibility 读取 UI。
- 桌面歌词订阅的共享状态包括 `player`、`queue`、`desktopLyrics`。
- 关键字段包括 `player.isPlaying`、`player.progressSeconds`、`player.mediaDetail.lyrics`、`queue.currentPlayableKey`、`queue.playables`。
- 播放控制调用内部服务：`player.togglePlay()`、`queue.playPrevious(...)`、`queue.playNext(...)`。
- 2026-07-08 实测 CoreGraphics 窗口列表能看到 4 个汽水音乐顶部透明窗口，尺寸为 `1710 x 34 pt`，另有一个 `1100 x 720 pt` 主窗口。
- 2026-07-08 继续只读搜索 `LunaStorage`、`Local Storage/leveldb`、`Session Storage`：未命中当前系统播放中的 `Sweet Release / Nu Aspect`；`QueueCache` 有歌曲、歌手、封面 URL，但更像队列/推荐缓存，不能直接当作当前播放态。
- 2026-07-08 新增 `QishuiStateProbe` 直接适配探针：只读观察 `LunaStorage`、`Local Storage/leveldb`、`Session Storage`、`IndexedDB`、`LunaCacheV2`。首次 20 秒观察未捕捉到状态文件变化，说明不能假设播放/暂停会实时落盘。
- 这些顶部窗口疑似桌面歌词/顶部歌词层，但 V1.2 不再使用 OCR：截图识别成本高，还需要屏幕录制权限，不符合当前产品主线。
- V1.2 主线改为 `QishuiAdapter`：优先寻找汽水直接来源，包括本地状态目录、可发现 IPC 和汽水内容窗口 AX；系统播放信息只保留为手动诊断。
- `NowPlayingAXBridge` 已降级为实验手动诊断入口：只有用户显式点击菜单里的系统播放诊断才会打开 macOS 控制中心；后台不自动轮询、不自动弹右上角面板。
- 产品原则已调整为“汽水直接适配、真实优先”：汽水音乐运行时不再轮播内置假歌名/假歌词；直接源读不到时显示明确等待或不可读状态。
- 2026-07-08 新增应用内 `QishuiAdapter`：已能确认汽水运行、读取 `LunaStorage/Config` 桌面歌词配置、读取 `QueueCache` 队列缓存和封面候选字段；当前实测仍未发现实时 `currentPlayableKey/isPlaying` 落盘。
- 2026-07-09 路线 2 调查：汽水内部确有实时 `sharedState` 总线，桌面歌词订阅 `player`、`queue`、`desktopLyrics`，但入口是 Electron preload 创建的 `window.transportPort`，通过 `ipcRenderer.postMessage(namespace + ".port", MessagePort)` 接入主进程；该通道只存在于汽水自己的 renderer/preload 内，外部 macOS 进程没有可直接注册的 IPC 入口。
- 2026-07-09 实测 `Info.plist` 没有公开 `CFBundleURLTypes`，但源码中会注册 `luna` scheme；目前可见的 deeplink 只处理 `/playing` 和 `/comment`，用于打开/播放指定歌曲或评论，不提供“查询当前播放状态”的能力。
- 2026-07-09 源码里的 `inspector.open(9300)` 被生产构建条件关掉，`lsof -iTCP:9300 -sTCP:LISTEN` 未发现监听；`lsof -p <汽水 PID>` 未发现可作为本地状态 API 的 127.0.0.1/Unix 监听服务。
- 2026-07-09 当前安全边界内的主线调整为：AX 直接读取真实歌名/封面/歌词 + AX 事件唤醒 + 定时轮询兜底。V1.3 已加入 `QishuiAXChangeMonitor`，在汽水 AX 树变化时触发一次同步，不再只等固定轮询。
- 2026-07-09 `QishuiAXReader` 改为优先扫描汽水内容窗口/焦点窗口，跳过菜单栏和系统菜单项；当前一次读取诊断耗时约 237ms，能读到 `GOTTASADAE (가라사대) - BewhY`、封面 URL 和可见歌词。
- 2026-07-09 V1.4 新增 `MediaRemoteNowPlayingSource` 作为本机原型主同步源：动态加载 macOS 私有 `MediaRemote.framework`，监听 Now Playing 变化通知，读取歌名、歌手、专辑、播放态、进度、时长和封面数据；只有来源能校验为 `com.soda.music` 或汽水音乐进程时才更新灵动岛。
- 2026-07-09 当前实测 `./MacBookIsland.app/Contents/MacOS/MacBookIsland --mediaremote-status` 返回 `mediaRemoteAvailable=true` 但 `verifiedQishuiSource=false`、`currentTrack=nil`、来源 `unknown`。因此这一版不会冒充同步成功：MediaRemote 有汽水事件时优先使用；没有可确认来源时自动降级 AX。
- 2026-07-09 V1.5 新增 `MediaRemoteAdapterStreamSource`：通过 `/usr/bin/perl` 加载 `MediaRemoteAdapter.framework`，绕过 macOS 15.4+ 普通 App 读取 Now Playing metadata 的 entitlement 限制，以常驻 `stream` 方式接收真实播放数据；封面在曲目变化时用单次 `get` 补齐。当前 `--adapter-status` 已能读取汽水真实歌名、歌手、播放态、进度、时长和封面 bytes。
- 2026-07-09 修复 QuickPlayer/QuickTime 并存场景：当视频播放器抢占 macOS 当前媒体会话时，`MediaRemoteAdapterStreamSource` 不再用非汽水来源的空状态覆盖汽水岛，而是短时保留最近一次可信汽水快照用于显示并冻结进度；同时控制命令在未确认媒体焦点回到汽水前会被拦截，避免误控视频播放器。
- 2026-07-09 抖音/Chrome 视频页测试暴露底层性能问题：旧实现会在 UI tick 和实时事件回调中同步拉取 MediaRemote/AX，且启动自动打开的设置 `Form` 会跟随模型刷新持续重排，导致 App CPU 一度约 84%-97%，灵动岛点击像是失效。当前已改为常驻 stream 事件驱动，普通 tick 只做轻量状态读取和低频进度发布；启动不再自动打开设置窗口，设置/校准窗口关闭后释放 SwiftUI 内容；手动刷新/诊断才允许同步重探测。
- 2026-07-10 定向控制突破：普通 App 二进制仍拿不到 MediaRemote clients，但系统解释器进程可以通过 Adapter 的同步 `findNowPlayingClient` 找到 `com.soda.music`，再调用 `MRMediaRemoteSendCommandToClient`。轻量桥已实测完成暂停→播放→暂停、下一首和上一首，前台 App 保持不变；App 主线程只等待后台桥返回，真实结果仍由汽水专属流确认。
- 2026-07-12 定向控制迁移到现有 `/usr/bin/perl` + MediaRemoteAdapter：Adapter 新增 `send-client`，仅接受命令 2/4/5；Swift 外层超时调整为 2 秒，覆盖内部最长 1 秒 client 查找与 0.5 秒命令确认。运行链不再调用 `/usr/bin/python3`，AX 唯一语义控件继续作为安全降级。
- 2026-07-09 进度条修正：AX 窗口树会同时暴露当前播放、列表项、旧歌和其他区域的多个 `mm:ss / mm:ss` 文本，不能作为可信进度来源。当前主进度只认 MediaRemote Adapter 的 `elapsedTime/duration`；当媒体焦点被抢走但仍保留最近可信汽水快照时，按最近可信播放态本地推进进度。AX fallback 的 `progress=unavailable` 是刻意降级，避免显示假进度。

## 架构含义

V1 不应把汽水音乐当作稳定公开 API。当前更可靠的产品策略是：

- UI 和计时器、提醒作为稳定能力。
- 汽水音乐先做运行检测和适配状态提示。
- 歌名、歌手、封面、歌词优先通过汽水本地状态、缓存和可发现 IPC 获取；没有稳定来源时明确标记 unavailable。
- 不伪造真实汽水音乐数据；无法读取时显示预览数据和明确状态。

## 推荐技术路径

1. 继续做 `MusicAdapterCoordinator` / `MediaAdapter` 边界，让 UI 不直接依赖汽水音乐。
2. 正式建设 `QishuiAdapter`：优先只读汽水本地状态、缓存、可发现 IPC；系统“播放中”只保留为手动诊断兜底。
3. 只读分析 `window.transportPort` 和 `sharedState` 的主进程来源，继续观察是否存在可读的本地状态、日志、缓存或 IPC 通道。
4. 如果没有稳定只读来源，发布版只承诺运行检测、AX 可见内容同步和基础音乐态容器；不得回退到全局媒体键。
5. 不修改汽水音乐 asar，不注入 Electron；MediaRemote 私有 API 只作为本机原型和外部分发前的技术验证路径。
6. 本机原型优先启用 MediaRemote Adapter 常驻 client 流做事件驱动同步；控制侧通过系统解释器承载的轻量桥定向发送给汽水 client，并以唯一语义 AX 作为安全降级。发布版必须评估系统解释器依赖、私有 API、系统更新和 App Store 风险。
7. 能力按来源声明：`track/artwork/lyrics/playbackState/control`，没有稳定汽水来源就标记 unavailable，不用系统来源冒充汽水官方 API。
8. 同步体验采用事件唤醒优先：MediaRemote 汽水 Now Playing 通知优先；汽水 AX 通知兜底；通知不可靠或窗口不可见时，用低频轮询兜底；控制按钮点击后继续短 burst 回读。
9. 进度条只使用可信 MediaRemote Adapter 进度；AX 仅用于歌名、歌手、封面 URL 和歌词兜底，不再参与主进度计算。
10. UI 主线程不得做同步进程启动、MediaRemote 阻塞读取或 AX 深扫描；这些只允许在手动诊断或明确后台任务中执行。

## 控制边界

- 全局媒体键与聚焦兜底已从运行时移除；同时有多个播放器时也不得把控制交给系统当前媒体会话。
- 播放/暂停、上一首、下一首优先定向发送给 `com.soda.music` client；桥不可用时只能尝试汽水 PID 内的唯一语义 AX 控件，否则安全失败。
- 进度跳转目前仍依赖当前媒体源；当媒体焦点不是汽水时必须阻断，直到找到可验证的定向 seek 方案。

## 已验证命令

```bash
swift run QishuiProbe --summary-only --depth 8
swift run QishuiProbe --summary-only --depth 12
swift run QishuiStateProbe
swift run QishuiStateProbe --watch 20
.build/debug/MacBookIsland --qishui-status
.build/debug/MacBookIsland --adapter-status
.build/debug/MacBookIsland --mediaremote-status
.build/debug/MacBookIsland --mediaremote-watch 20
.build/debug/MacBookIsland --qishui-targeted-control playPause
npx -y @electron/asar extract "/Applications/汽水音乐.app/Contents/Resources/desktopLyrics.asar" /tmp/qishui-asar/desktopLyrics
npx -y prettier --parser babel /tmp/qishui-asar/desktopLyrics/assets/desktopLyrics-BEcsjpdL.js
```
