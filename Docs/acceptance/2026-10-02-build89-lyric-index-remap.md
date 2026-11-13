# build89 歌词索引映射修复

日期：2026-10-02

## 根因

`MusicLyricPresentation.state` 会先过滤汽水 AX 的元数据/诊断行并拆分嵌入换行，但原实现继续使用过滤前的 `lyricIndex`。当来源在当前句前提供作词或诊断行时，索引会偏移，造成歌曲归属正确但显示句子错位。

## 修复

- 根据原始数组索引计算清洗后索引，再做原文/译文配对。
- 当前原始行被过滤时返回 `.unavailable`，不借用下一句填充界面。
- 新增元数据行前置、双语配对和被过滤当前行的回归测试。

## 验证

- `swift test --quiet`：293 项通过。
- `git diff --check`：通过。
- `Scripts/verify-qishui-control-safety.sh`：通过。
- `/Applications/顶屿.app`：`0.1.3 (89)`，严格签名通过。
- Release DMG：`.build/release-artifacts/build89/TopIslet-v0.1.3-arm64.dmg`。
- DMG SHA-256：`6ba454cdba5dbc50a29b0679376d30798edda3ff7fe2652204a6a60a3402c68b`。
- 汽水 PID `37785` 未重启，安装后 `--adapter-status` 仍为可信汽水且 `isPlaying=true`。
- 30 秒安装版资源烟测：31 个样本、平均 CPU `0.082%`、P95 `0.112%`、最大 CPU `0.119%`、最大 physical footprint 增长 `0.421%`、窗口数始终为 1、违规 `0`。

## 尚未关闭

真实超视口长句的完整滚动首尾周期、像素端到端延迟、两小时资源、多屏、流媒体全屏和 Reduce Motion 仍需独立实机证据。最后一次 Computer Use 状态仍为锁屏，未绕过锁屏或虚报像素通过。
