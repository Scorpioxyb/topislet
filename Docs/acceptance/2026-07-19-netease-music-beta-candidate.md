# 网易云音乐 Beta 候选稳定性验收

日期：2026-07-19

## 环境

- 设备：MacBook Air (`Mac17,4`)，Apple M5，24 GB
- 系统：macOS 26.5.2 (`25F84`)
- 网易云音乐：3.1.8 (`3368`)，Bundle ID `com.netease.163music`
- 顶屿：0.1.1 (`18`)
- 基线合并：PR #19，`75a6a10`

## 连续同步样本

- 顶屿主进程连续运行约 39 分钟时，网易云专属 `stream-client` 仍为主进程的唯一直接子进程；抽样 RSS 约 `87 MB`，CPU 约 `1.6%`。
- 连续 45 次、约 90 秒只读采样全部返回 `availability=ready` 和 `playbackState=playing`。
- 覆盖 `Adieu (RMX by Richard Z. Kruspe)`、`Zwitter`、`ZEIG DICH`、`Rosenrot` 四首歌曲及三次自然切换。
- 每首歌内进度单调递增；自然切歌后从接近 0 秒重新开始，没有沿用上一首进度。
- 四首封面分别为 `10765 / 7884 / 5428 / 9131 bytes`，均随新曲完整快照一起变化。
- 单次 PID 定向读取约 `62-112ms`，未出现 degraded、空曲目或旧 PID 回写。

## 播放控制与时间线

- 暂停后四次读取固定在 `62.967s`；固定 5 秒复验从 `1.063s` 到 `1.110s`，属于来源采样精度范围，没有继续播放式增长。
- 恢复后从 `1.439s` 连续推进到 `3.545s`，底层 `elapsedTime`、`elapsedTimeNow`、`timestamp` 与 `playbackRate` 固定间隔复验一致。
- 播放 / 暂停仍只触发网易云 PID `45994` 内原生“控制”菜单。

## 本轮发现与修复

- 原始状态流确认网易云切歌会先发送新曲 `paused + 30s 临时时长`，约 1 秒后才发送 `playing + 真实时长`。
- 实例样本 `Giftig -> Klavier` 先返回 `Klavier/paused/30.041s`，再返回 `Klavier/playing/30.041s`。
- 实例样本 `Klavier -> Zeit` 先返回 `Zeit/paused/30.041s`，再返回 `Zeit/playing/321.749s`。
- 顶屿现根据上一首的可信播放态建立自然或按钮切歌事务；上一首播放中时，在 2.2 秒有界窗口内拒绝该暂停占位快照，元数据任务最多等待 2.8 秒。窗口结束后仍允许真实暂停收敛，不会无限保留旧歌。
- 重装并重启顶屿后，主进程 PID `68366` 实测 `Eifersucht -> Engel -> DEUTSCHLAND`，日志只发布最终 `state=playing` 快照，没有中间暂停闪烁。

## 自动化与打包

- 新增自然切歌暂停占位、前台权威元数据刷新和有界等待策略回归。
- `swift test` 共 137 项通过。
- `Scripts/package-app.sh` 通过，`/Applications/顶屿.app` 严格签名验证通过。
- 旧主进程退出后两个状态流均结束；新主进程仅重建一个汽水流和一个网易云流，没有孤儿进程。

## 真实私人漫游

- 通过网易云“私人漫游”入口启动 `Page One - Ella Bright`，PID 定向读取返回封面 `10059 bytes`、时长 `191.658s` 和连续播放进度。
- 首轮进入电台时发现前台激活触发的 `.metadata` 刷新仍可能直接发布 `Page One/paused`；修复后所有权威元数据刷新统一进入切歌事务。
- 重新打包并重启顶屿后，前台界面切歌 `SMELLS LIKE LUV -> Ally And Austin`，主进程只记录最终 `Ally And Austin/playing`，封面 `6610 bytes`、时长 `157.896s`。
- 窗口最小化后通过岛内同路径切到 `Dauntless (无畏Funk) - XiRXG`，约 `0.895s` 得到封面 `12193 bytes`、时长 `119.142s` 和 `playing`，没有中间暂停发布。
- 后台暂停四次读取均固定在 `23.401s`；恢复后进度继续递增。
- 私人漫游自然续播到 `Take Me (To The Moon) - Ian Asher/D A N N Y` 时，主进程只记录最终 `playing`；随后 25 次、约 50 秒采样全部 `ready/playing`，进度从 `11.856s` 单调增加到 `62.464s`，封面保持 `8502 bytes`。

## Beta 门槛结论

- 当前设备与网易云 3.1.8 已达到 Beta 候选标准，但产品支持等级继续保持 Alpha。
- 真实“私人漫游”场景已经完成；升级 Beta 前仍需至少一个不同网易云版本或第二台设备样本。
- 网易云定向 seek 仍无来源证明，进度条保持只读。
