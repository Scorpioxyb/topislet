# 顶屿 TopIslet v0.1.0-alpha.1

这是首个面向 GitHub 的开发者预览候选版本，目标是验证围绕 MacBook 刘海的音乐活动岛是否能够在日常使用中保持实用、低打扰和安全可控。

## 主要能力

- 汽水音乐真实歌名、歌手、封面、播放状态和进度同步。
- 汽水客户端定向播放 / 暂停、上一首和下一首控制。
- 进度点击与拖动，以及媒体焦点冲突时的安全阻断。
- 折叠、紧凑、展开三种状态和悬停展开交互。
- 计时器、日历和提醒事项低打扰事件接入。
- 设置面板、布局校准和本地诊断。
- 标准 macOS DMG 拖放安装界面，包含顶屿与 Applications 双图标布局。

## 系统要求

- macOS 26.0+
- 带刘海的 Apple Silicon MacBook
- 汽水音乐

## 已知限制

- 当前只对汽水音乐完成主要适配。
- 依赖非公开 MediaRemote 能力，macOS 更新可能影响兼容性。
- ad-hoc 签名候选包未经过 Apple 公证，Gatekeeper 可能阻止直接双击打开。
- 其他 MacBook 尺寸需要从顶屿菜单选择“校准布局...”进行校准。
- 当前不适合 App Store 分发。
- 此版本起正式采用 `io.github.scorpioxyb.topislet` Bundle ID；从旧原型升级后，需要重新授予辅助功能、日历和提醒事项权限。

## 隐私

数据在本机处理；不使用 OCR、屏幕录制、抓包、MITM 或 token 提取。日历和提醒事项权限均为可选并分别申请。详情见 `PRIVACY.md`。

## 校验

Release 附件同时提供 `.sha256` 文件。下载后可运行：

```bash
shasum -a 256 -c TopIslet-v0.1.0-arm64.dmg.sha256
```

打开 `TopIslet-v0.1.0-arm64.dmg`，将“顶屿.app”拖到“Applications”快捷入口即可完成安装。
