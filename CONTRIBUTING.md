# Contributing

感谢你对 MacBook Island 的关注。当前项目仍处于 alpha 阶段，优先接受可复现的问题修复、兼容性验证和小范围体验改进。

## 开发环境

- macOS 26.0+
- Xcode Command Line Tools
- Swift 6
- 带刘海的 Apple Silicon MacBook（视觉验收推荐）

## 开始

```bash
swift build
swift run MacBookIsland
```

## 提交前检查

```bash
swift build
swift build -c release
bash -n Scripts/package-app.sh Scripts/build-release.sh
plutil -lint Packaging/Info.plist
git diff --check
```

涉及 UI 的修改请附同一设备、同一状态下的调整前后截图；涉及媒体控制的修改请验证前台 App 不切换、鼠标不移动、其他播放器不被误控。

## Pull Request 要求

- 一个 PR 只解决一个明确问题。
- 说明复现方式、修改范围和验证结果。
- 不提交汽水音乐 App 解包产物、账号数据、token、日志中的个人路径或真实日历内容。
- 不加入 OCR、抓包、MITM、固定坐标控制或全局媒体键兜底。
- 不修改第三方二进制而不记录来源、许可证和可复现构建步骤。

## 代码风格

保持修改小而明确，沿用现有 SwiftUI / AppKit 风格。避免为了单一需求引入新的抽象层或依赖。
