# 顶屿 TopIslet

> A lightweight activity island built around the MacBook notch.
> 把 MacBook 刘海周围变成低打扰、可交互的活动区域。

<img src="Packaging/IslandAppIcon.png" alt="顶屿 App 图标" width="160">

## 发布状态

当前版本为 **v0.1.1-alpha 开发者预览版**，优先验证汽水音乐同步、安全媒体控制和顶部交互。它不是 Apple 或汽水音乐的官方产品，也暂不适合 App Store 分发。

项目代码采用 `GPL-3.0-only`，正式 Bundle ID 为 `io.github.scorpioxyb.topislet`。首个 GitHub Release 按 **ad-hoc 签名、未公证的 Alpha 开发者预览版**发布；Developer ID 与 Apple 公证暂缓，不把本版本描述为稳定版或免警告安装包。进度见 [发布检查清单](Docs/RELEASE_CHECKLIST.md)。

Developer ID 与 Apple 公证接入见 [签名与公证说明](Docs/APPLE_SIGNING_AND_NOTARIZATION.md)；MediaRemote Adapter 的固定上游 commit、项目补丁和逐字节重建记录见 [供应链与可复现构建](Docs/MEDIAREMOTE_ADAPTER_REPRODUCIBILITY.md)。

## 当前能力

- 围绕 MacBook 摄像头区域显示折叠、紧凑和展开三种状态。
- 读取汽水音乐的真实歌名、歌手、封面、播放状态与进度。
- 播放 / 暂停、上一首、下一首只触发汽水窗口内经过结构校验的唯一语义控件，不发送全局媒体键。
- 进度条显示汽水专属可信进度；当前保持只读，不发送系统全局跳转命令。
- 计时器按需接管灵动岛，结束后恢复音乐活动。
- 日历和提醒事项经过用户单独授权后，可提供低打扰临近提醒。
- 支持悬停展开、移开收回、点击固定展开和刘海位置校准。

## 系统要求

| 项目 | 当前要求 |
| --- | --- |
| macOS | **macOS 26.0 或更高版本** |
| 设备 | 优先支持带刘海的 Apple Silicon MacBook |
| 音乐来源 | 汽水音乐，Bundle ID `com.soda.music` |
| 源码构建 | Xcode Command Line Tools、Swift 6 |

> MediaRemote Adapter 当前二进制的最低系统版本为 macOS 26.0，因此项目不再宣称兼容 macOS 14。其他系统版本需要重新构建并单独验证该依赖。

## 安装

### GitHub Release

正式 Release 准备完成后，可从 Releases 下载 `.dmg`：

1. 打开 `TopIslet-….dmg`。
2. 将“顶屿.app”拖到右侧“Applications”快捷入口。
3. 推出磁盘映像，再从“应用程序”文件夹打开顶屿。

顶屿是菜单栏 App，正常运行时不会出现在程序坞。在 Developer ID 签名和 Apple 公证完成前，下载包只会标记为开发者预览版；macOS 若阻止首次打开，可在 Finder 中右键顶屿并选择“打开”，不应关闭 Gatekeeper。

### 从源码运行

```bash
git clone https://github.com/Scorpioxyb/topislet.git
cd topislet
swift run MacBookIsland
```

本地打包安装：

```bash
bash Scripts/package-app.sh
open "/Applications/顶屿.app"
```

生成可分发候选包使用独立脚本：

```bash
VERSION="0.1.1" bash Scripts/build-release.sh
```

脚本会生成包含“顶屿.app”和“Applications”快捷入口的 arm64 DMG，以及对应的 SHA-256 校验和，不会自动发布到 GitHub。

## 第一次使用

1. 打开 App，确认菜单栏出现顶屿图标。
2. 打开汽水音乐并播放歌曲，灵动岛会自动显示播放状态。
3. 点击或悬停顶部岛展开；移开后自动收回，点击展开则保持固定。
4. 如果胶囊与实体刘海不贴合，从顶屿菜单选择“校准布局...”。
5. 日历和提醒事项仅在“设置 → 日程”中按需单独授权。

> 从旧版“MacBook 灵动岛”升级：先退出旧版并将旧 `.app` 移到废纸篓，避免两个进程同时显示顶部岛。由于 App 显示名和 Bundle ID 已更改，macOS 会把顶屿识别为新的 App；首次启动后需要重新授予辅助功能权限，如启用日程功能，也需要重新授予日历和提醒事项权限。旧版布局和设置可能不会自动迁移。

## 权限与隐私

| 权限 | 是否必需 | 用途 |
| --- | --- | --- |
| 辅助功能 | 音乐控制必需 | 识别并触发汽水进程内经过结构校验的唯一语义控件 |
| 日历 | 可选 | 读取临近开始的定时日程 |
| 提醒事项 | 可选 | 读取刚到期且具有具体时间的提醒 |
| 屏幕录制 | 不需要 | 项目不使用 OCR 或屏幕录制同步音乐 |

播放、日历和提醒数据在本机处理；当前版本没有账号系统、云同步、广告 SDK 或遥测上传。完整说明见 [PRIVACY.md](PRIVACY.md)。

## 已知限制

- 当前只对汽水音乐进行了产品级适配，其他媒体应用不会自动获得完整控制能力。
- 项目依赖 macOS 非公开 MediaRemote 能力，系统更新可能导致兼容性变化。
- 当前没有汽水专属定向 seek 接口，因此进度条保持只读。
- Developer ID 签名与 Apple 公证尚未完成，当前本机包只是 ad-hoc 签名开发包。
- 目前主要在一台带刘海的 Apple Silicon MacBook 上验证，其他尺寸仍需实机校准。

## 诊断

```bash
.build/debug/MacBookIsland --adapter-status
.build/debug/MacBookIsland --qishui-status
.build/debug/MacBookIsland --mediaremote-status
.build/debug/MacBookIsland --eventkit-status
```

诊断命令不会主动申请权限。开发调查记录见 [汽水适配说明](Docs/qishui-adapter-notes.md)。

## 开发

```bash
swift build
swift build -c release
bash -n Scripts/package-app.sh Scripts/build-release.sh
plutil -lint Packaging/Info.plist
```

项目使用 SwiftUI + AppKit；主要模块说明见 [产品需求](Docs/PRODUCT_REQUIREMENTS.md)、[路线图](Docs/ROADMAP.md) 和 [QA 检查清单](Docs/QA_CHECKLIST.md)。

## 贡献与安全

- 贡献前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 安全问题请按 [SECURITY.md](SECURITY.md) 的方式私下报告。
- 发布步骤和未完成门禁见 [Docs/RELEASE_CHECKLIST.md](Docs/RELEASE_CHECKLIST.md)。

## 许可证与第三方组件

源代码按 [GNU General Public License v3.0 only](LICENSE)（`GPL-3.0-only`）授权。分发修改版时必须遵守 GPL v3 的源码提供、许可证保留及同许可证分发要求。

`TopIslet`、`顶屿`名称和项目 Logo 不随 GPL 代码许可证一并授权，不得以暗示官方版本、官方认可或合作关系的方式使用。详见 [TRADEMARKS.md](TRADEMARKS.md)。

MediaRemote Adapter 使用 BSD 3-Clause License。完整归属与当前供应链缺口见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 免责声明

MacBook、macOS、Dynamic Island 和 Apple 是 Apple Inc. 的商标或产品名称；汽水音乐属于其权利人。本项目与 Apple、汽水音乐及其关联公司不存在隶属、赞助或官方合作关系。
