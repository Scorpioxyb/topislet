# build84 歌词延迟日报汇总

状态：本地 Release 候选，Goal 仍进行中；未封版、未发布。

## 变更

- `MusicUsageDailySummary` schema 升为 6。
- `DailyUsageAnalyzer` 新增 `lyricUIPublicationLatency`，从匿名 `lyric_ui_published` 事件计算 count、P50、P95 和最大年龄。
- `lyric_age_ms < 0` 的未知年龄不会进入统计。
- 不记录或输出原始歌词文本。

## 验证

- `swift test`：290 项通过。
- build84 Release 构建、40 段校验和严格签名通过。
- `/Applications/顶屿.app` 已安装为 `0.1.3 (84)`。
- `swift run DailyUsageAnalyzer --last 24h` 成功生成：`.build/qa/topislet-daily-usage-2026-10-02.json`。
- 当前 24 小时日志中的歌词年龄样本：`count=6`、`P50=501ms`、`P95=504ms`、`max=504ms`。

## 证据边界

这些样本证明快照到 `MusicState`/UI 模型发布的延迟分布已经可汇总，且样本低于 0.9 秒新鲜度门禁。日志中的匿名歌词指纹仍主要对应同一 active 行，当前汽水处于暂停状态，因此尚未证明音频播放期间的 active 行切换、音频时间轴同步或像素端到端延迟。

## 尚未关闭门禁

- 播放中多个不同 active lyric 指纹的连续采样。
- 长句完整滚动往返周期。
- 模式切换逐帧黑边/残影、多屏、全屏、Reduce Motion。
- 两小时性能和最终发布/公证。
