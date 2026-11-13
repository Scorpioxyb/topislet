# build85 紧凑态歌词黑带修复

日期：2026-10-02

## 问题证据

用户截图显示：紧凑态顶部歌词被裁切，歌词岛下方出现一整条空黑带。该现象与展开面板在收起后仍保留 SwiftUI 子树、同时参与 AppKit 窗口缩放事务相符；它不是歌词文本归属本身的问题。

## 修复

- `IslandRootView` 仅在 `expanded` 模式挂载 `ExpandedIslandBodyPanel`，紧凑态和收起态不再保留不可见的展开面板/歌词子树。
- `MarqueeText` 增加短边缘渐隐，长歌词滚动时不再以生硬的硬裁切结束。
- `Packaging/Info.plist` build 升至 `85`。

## 验证

| 检查 | 结果 |
| --- | --- |
| `swift test --quiet` | 290 项通过 |
| `git diff --check` | 通过 |
| `Scripts/verify-qishui-control-safety.sh` | 通过 |
| Release 打包 / 安装 | `/Applications/顶屿.app`，`0.1.3 (85)` |
| 当前顶屿截图 | 紧凑态无黑色残留带，歌词和封面处于同一顶部胶囊内 |

系统日志中出现的 `AppIntents/linkd` 注册错误来自 macOS 服务重连，不是顶屿布局错误；未观察到顶屿自身崩溃或歌词渲染异常。

## 未关闭门禁

本记录只覆盖截图对应的黑带/残留面板问题。播放中多首歌曲的歌词时间轴同步、长句完整滚动周期、多屏/全屏/Reduce Motion 和长期运行门禁仍按 `STAGE0_CURRENT_GATES.md` 执行。
