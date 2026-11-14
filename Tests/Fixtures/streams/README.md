# 状态流重放夹具

`StreamReplayFixtureTests` 把这里的每个 `<名称>.jsonl` 按固定时钟重放进 `MediaRemoteAdapterStreamSource`，检查两件事：

1. 发布出去的曲目不混用两首歌的字段（以首行 `tracks` 表为准）；
2. 发布序列与 `<名称>.expected.json` 一致。

这是全局规划 5.1 的重构安全网：拆分协调器（4.2）时，行为不变的改动必须让这些序列保持一致。

## 格式

- 第一行是头：`fixture`、`description`、`running_pids`、`tracks`（每首合成曲目的标题、歌手、专辑、时长、封面标签）。
- 之后每行一步：
  - `{"t": 秒, "envelope": {...}}`：一条状态流包，形状与 `stream-client --no-diff` 输出相同；`timestampLatency` 是源事件时间到收到时的秒数，重放时换回 `timestamp`。
  - `{"t": 秒, "op": "invalidate_session" | "running_pids" | "seed_seek", ...}`：会话失效、汽水 PID 集合变化、顶屿发出受保护跳转。
- 2.4 秒发布期限在重放中按时间点精确触发，记为 `deadline` 步。
- 不模拟期间的元数据补读进程；那条路径由 `MediaRemoteAdapterStreamSourceTests` 覆盖。

## 来源与隐私

首批五个序列是按验收记录中实测的包形状合成的（v0.1.2 切歌延迟、build166/167 空包、build180 快速切歌）。真实录制可以替换或补充它们：

```bash
python3 Scripts/capture-qishui-stream.py --duration 300 --output LocalData/qa/<日期>-stream-capture/raw.jsonl
python3 Scripts/sanitize-qishui-stream.py LocalData/qa/<日期>-stream-capture/raw.jsonl Tests/Fixtures/streams/<名称>.jsonl --name <名称> --description "<说明>" --start <秒> --end <秒>
```

录制只读，不发控制、不启动或重启汽水。原始录制含真实歌名、歌手和封面，只能留在 `LocalData/`。脱敏后歌名换成 `Title N`，歌手、专辑、封面按最常同时出现的歌名编号（所以混杂包仍是“Title 2 配 Artist 1”），媒体 ID、PID 重新编号，未知字段丢弃。夹具不得包含真实歌名、歌词或封面。

## 更新期望序列

只在有意改变行为时更新，并逐行审阅差异：

```bash
TOPISLET_RECORD_STREAM_FIXTURES=1 swift test --filter StreamReplay
```
