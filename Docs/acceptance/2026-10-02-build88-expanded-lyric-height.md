# build88 展开歌词高度同步修复

日期：2026-10-02

## 根因

build87 在展开态先展示无歌词曲目、随后歌词快照异步到达时，SwiftUI 已经挂载 `LyricsShelf`，但 AppKit 面板高度仍停留在无歌词的 148pt 档。真实截图表现为歌词卡片底部被窗口裁掉，只露出上沿。`model.$music` 的歌词状态订阅只在 `.compact` 调用 `repositionPanel`，因此没有提交展开态的新高度。

## 修复

- 新增 `MusicExpandedLayout.bodyHeight`，把有歌词、无歌词和最小高度策略集中到同一纯函数。
- `IslandModel.expandedBodyHeight` 使用该策略，避免模型和视图各自维护高度常量。
- 歌词状态提交后的 AppKit 重定位同时覆盖 `.compact` 与 `.expanded`，并使用已提交的 `model.mode`，使歌词栏挂载与窗口尺寸在同一状态事务后完成。
- 新增展开高度策略回归测试。

## 验证

- `swift test --quiet`：292 项通过。
- `git diff --check`：通过。
- `Scripts/verify-qishui-control-safety.sh`：通过。
- Release DMG：`.build/release-artifacts/build88/TopIslet-v0.1.3-arm64.dmg`。
- DMG SHA-256：`ac7a772505ebf5da642a6d820100cb395642c75c038ffd2a73b7f80f9427b289`。
- `/Applications/顶屿.app`：`0.1.3 (88)`，深度严格签名通过，汽水 PID `37785` 保持播放。
- 实机路径：build88 展开无歌词曲目 `Drop That Beat`，切换到有歌词曲目 `Vultures` 后，展开歌词卡片完整落在窗口内；收起后最终紧凑帧完整显示当前句与译文。
- 30 秒安装版资源烟测：31 个样本、平均 CPU `0.128%`、P95 `0.149%`、最大 CPU `0.159%`、最大 physical footprint 增长 `0.378%`、窗口数始终为 1、违规 `0`。

## 尚未关闭

本记录只关闭“展开态歌词异步到达后的高度裁切”这一缺陷。超视口长句的完整滚动首尾周期、像素端到端延迟、两小时资源、多屏、流媒体原生/伪全屏和 Reduce Motion 仍需独立证据，不能由本轮测试或静态截图替代。

最后一次实机补验时 Computer Use 权威状态仍为锁屏，自动解锁失败；未绕过锁屏，也没有把代码审计或短烟测写成像素级通过。
