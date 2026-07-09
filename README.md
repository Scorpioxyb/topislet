# MacBook 灵动岛

一个 macOS 顶部灵动岛 V1 原型，用 SwiftUI + AppKit 实现。

当前目标是把 MacBook 摄像头模组周围的遮挡区域变成真实可用的顶部轻操作区。V1 重点支持汽水音乐、计时器和通知提醒，其中汽水音乐坚持真实同步，不用假歌名或 OCR 冒充。

## 运行

```bash
swift run MacBookIsland
```

启动后会在屏幕顶部中央显示灵动岛原型。菜单栏会出现“岛”入口，可用于显示、隐藏、触发提醒和退出。

## 打包安装

```bash
Scripts/package-app.sh
open "/Applications/MacBook 灵动岛.app"
```

打包脚本会生成本地 `.app`，复制 MediaRemote Adapter 资源并进行本机 ad-hoc 签名。

## 布局校准

菜单栏点击“岛” -> “校准布局...”，可以实时调整：

- 灵动岛整体垂直位置
- 展开态高度
- 展开态左侧三个功能按钮的位置
- 展开态右侧收起 / 最小化按钮的位置
- 展开内容与顶部按钮的间距

校准值会保存到本机 `UserDefaults`，重启 App 后继续生效。由于 macOS 截图不会显示物理刘海，最终位置以 MacBook 屏幕实物遮挡为准。

## V1 范围

- 顶部黑色胶囊灵动岛浮层
- 音乐播放样式：歌名、歌手、封面占位、状态提示、播放控制
- 汽水音乐直接适配状态：检测进程、读取本地状态目录、读取队列缓存和桌面歌词设置
- macOS 系统“播放中”读取实验：只保留为菜单里的手动诊断入口，不做自动同步
- QuickPlayer/QuickTime 抢占系统媒体会话时，保留最近一次可信汽水状态，并阻止误控视频播放器
- 计时器：开始、暂停、重置、加 1 分钟
- 通知提醒：示例提醒、稍后提醒、关闭
- 展开、常驻、收起三种状态
- 布局校准面板：适配真实 MacBook 刘海位置，支持重启后保留

## 下一步

- 继续验证汽水音乐内部状态路径，重点寻找实时 `currentPlayableKey`、`isPlaying`、歌词和封面来源
- 将 `QishuiAdapter` 的只读探测结果升级为稳定 `MediaSnapshot`
- 验证封面、播放进度和歌词的轻量读取能力
- 按 `Docs/ROADMAP.md` 推进 V1.6 动效和状态机稳定性

## 汽水音乐探测

```bash
swift run QishuiProbe --depth 12 > Reports/qishui-ax-dump.txt
```

当前探测结论：

- 汽水音乐 Bundle ID：`com.soda.music`
- 主窗口 Accessibility 只暴露窗口、容器和系统窗口按钮，不稳定暴露歌名、封面、歌词或播放按钮。
- 汽水音乐自带 `desktopLyrics.asar`，内部状态包含 `player.isPlaying`、`player.progressSeconds`、`player.mediaDetail.lyrics`、`queue.currentPlayableKey` 和 `queue.playables`。
- 下一步适配优先级：优先使用 `QishuiAdapter` 只读本地状态、缓存和可发现 IPC；不使用截图 OCR；普通 AX 树只能作为窗口检测和基础状态判断。

## 当前适配层

- `Sources/MacBookIsland/MediaAdapter.swift` 负责音乐数据边界。
- `Sources/MacBookIsland/QishuiAdapter.swift` 负责汽水音乐直接适配，只读 `LunaStorage` 等本地状态目录。
- 当前会检测汽水音乐是否运行，读取 `Config`、`QueueCache`，并在发现实时播放态后映射歌名、歌手、封面、歌词、播放态和进度。
- 用户显式点击“实验：打开系统播放诊断”时，才会通过控制中心“播放中”面板做手动诊断；后台不会自动打开控制中心。
- 汽水音乐运行且已授权辅助功能时，播放 / 暂停、上一首、下一首会尝试发送 macOS 系统媒体键事件。
- 在真实歌名/封面/歌词来源稳定前，UI 不伪造汽水音乐歌曲数据；直接源读不到时显示不可用/等待状态。
- V1.2 不再使用 OCR，也不请求系统屏幕录制权限。
- 可用 `.build/debug/MacBookIsland --qishui-status` 查看当前直接适配探测结果。
- 详细调查记录见 `Docs/qishui-adapter-notes.md`。

## 项目管理文档

- `Docs/PRODUCT_REQUIREMENTS.md`：产品定位、范围和非目标。
- `Docs/ROADMAP.md`：版本路线图。
- `Docs/QA_CHECKLIST.md`：手工验收清单。
- `Docs/CHANGELOG.md`：变更记录。
