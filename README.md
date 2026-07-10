# MacBook 灵动岛

一个 macOS 顶部灵动岛 V1 原型，用 SwiftUI + AppKit 实现。

当前目标是把 MacBook 摄像头模组周围的遮挡区域变成真实可用的顶部轻操作区。V1 以汽水音乐为默认主活动，计时器和提醒只在事件发生时临时出现；不在岛内放置固定功能标签。

## 运行

```bash
swift run MacBookIsland
```

启动后会在屏幕顶部中央显示灵动岛原型。菜单栏会出现“岛”入口，可用于显示汽水音乐、启动计时、打开设置和退出。

运行中的 App 可以接收本机事件，用于快捷指令或后续应用适配器验证：

```bash
"/Applications/MacBook 灵动岛.app/Contents/MacOS/MacBookIsland" \
  --post-event "新的提醒" "这条内容会临时覆盖汽水音乐" "测试来源"
```

普通事件约 3 秒后恢复此前模式和汽水最新状态。这个入口只传递展示事件，不执行应用控制。

## 打包安装

```bash
bash Scripts/package-app.sh
open "/Applications/MacBook 灵动岛.app"
```

打包脚本会生成本地 `.app`，复制 MediaRemote Adapter 资源并进行本机 ad-hoc 签名。

## 布局校准

菜单栏点击“岛” -> “校准布局...”，可以实时调整：

- 灵动岛整体垂直位置
- 展开态高度

校准值会保存到本机 `UserDefaults`，重启 App 后继续生效。由于 macOS 截图不会显示物理刘海，最终位置以 MacBook 屏幕实物遮挡为准。

## V1 范围

- 顶部黑色胶囊灵动岛浮层
- 音乐播放样式：真实歌名、歌手、封面、歌词、播放状态、进度和播放控制
- 汽水专属实时流：MediaRemote Adapter 通过 `stream-client com.soda.music` 和 `get-client com.soda.music` 只读取汽水客户端
- 切歌元数据原子提交：歌名、歌手和封面准备一致后再统一发布，避免新旧歌曲混搭
- 播放 / 暂停、上一首、下一首直接发送给 `com.soda.music` 的 MediaRemote client；定向通道不可用时才尝试汽水进程内的唯一语义 AX 控件
- 如果不能唯一识别安全控件，控制会失败并保留当前界面，不使用固定坐标兜底
- 进度跳转仅在底层确认当前可跳转媒体源为汽水时发送；其他媒体占用系统焦点时安全阻断
- 计时器：从菜单启动后才接管灵动岛，支持暂停、重置、加 1 分钟
- 通知提醒：普通提醒短暂覆盖后恢复汽水；展开或拖动期间不抢占当前交互
- 展开、常驻、收起三种状态
- 布局校准面板：适配真实 MacBook 刘海位置，支持重启后保留

## 下一步

- 完成签名安装包的抖音 / QuickTime 并存实机回归，确认汽水歌名、歌手、封面、播放态和进度持续更新
- 验证连续切歌、快速播放 / 暂停和进度拖动的确认时序
- 继续寻找汽水专属的定向 seek 通道；在安全通道完成前，媒体焦点冲突时保持阻断
- 按 `Docs/ROADMAP.md` 继续收敛单窗口连续轮廓、可中断形变动画和计时器 / 提醒产品化

## 汽水音乐探测

```bash
swift run QishuiProbe --depth 12 > Reports/qishui-ax-dump.txt
```

当前探测结论：

- 汽水音乐 Bundle ID：`com.soda.music`
- MediaRemote Adapter 能按 Bundle ID 订阅汽水客户端；后台同步不再跟随系统当前 Now Playing App。
- 系统解释器承载的轻量桥能取得 `com.soda.music` 的 `MRNowPlayingClient` 并定向发送播放控制；实测不切换前台 App、不移动鼠标，也不依赖系统当前媒体焦点。
- 汽水窗口初始化 Accessibility 树后，可按角色、结构和相邻控件特征识别上一首、播放 / 暂停、下一首，作为安全降级；识别结果不唯一时不会执行控制。
- 不使用截图 OCR，不修改汽水 ASAR，不提取 token，不进行 MITM，也不通过固定屏幕坐标或合成鼠标事件控制。
- client 定向通道和 Accessibility 树都不可用时，控制会安全失败；不改回全局媒体键。

## 当前适配层

- `Sources/MacBookIsland/MediaAdapter.swift` 负责音乐数据边界。
- `Sources/MacBookIsland/MediaRemoteAdapterStreamSource.swift` 负责启动汽水专属实时流、按曲目补取封面、维护可信时间线和切歌原子提交。
- `Sources/MacBookIsland/QishuiAdapter.swift` 负责汽水运行状态和本地只读信息补充。
- `Sources/MacBookIsland/QishuiTargetedMediaController.swift` 通过轻量桥把命令直接发送给汽水 MediaRemote client。
- `Sources/MacBookIsland/QishuiSemanticAXController.swift` 只绑定汽水 PID，并在定向通道不可用时按语义查找唯一播放控件。
- 用户显式点击“实验：打开系统播放诊断”时，才会通过控制中心“播放中”面板做手动诊断；后台不会自动打开控制中心。
- 播放 / 暂停、上一首、下一首不使用系统全局媒体键，也不会为了控制汽水而短暂激活它；可用 `--qishui-targeted-control` 单独验证定向路径。
- 在真实歌名 / 封面 / 歌词来源不可用时，UI 不伪造歌曲数据；保留最近一次完整可信画面或显示不可用状态。
- V1.2 不再使用 OCR，也不请求系统屏幕录制权限。
- 可用 `.build/debug/MacBookIsland --qishui-status`、`--adapter-status` 和 `--mediaremote-status` 查看诊断结果。
- 详细调查记录见 `Docs/qishui-adapter-notes.md`。

## 项目管理文档

- `Docs/PRODUCT_REQUIREMENTS.md`：产品定位、范围和非目标。
- `Docs/ROADMAP.md`：版本路线图。
- `Docs/QA_CHECKLIST.md`：手工验收清单。
- `Docs/CHANGELOG.md`：变更记录。
