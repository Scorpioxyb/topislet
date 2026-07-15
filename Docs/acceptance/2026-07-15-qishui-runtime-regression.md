# 汽水运行时与媒体焦点综合回归

日期：2026-07-15

## 环境

- 安装包：`/Applications/顶屿.app`
- 提交：`9a7e18c`
- 汽水音乐：`com.soda.music`
- 并存媒体：QuickTime Player 播放本地 QuickTime MOV
- Apple Music 保持打开并暂停在 `Fast Times`

## 汽水专属同步

- 冷启动后 AX 扫描 381 个节点并唯一命中底部播放控制组。
- 播放 `City of Stars` 时，连续两次专属读取进度从 `103.5909s` 增长到 `104.6391s`，封面为 `9190 bytes`。
- 暂停后两次读取均冻结在 `12.034892s`；恢复后按汽水回包时间戳继续推进，没有从旧位置回退。
- 切换 `SUNRISE -> Moment -> SUNRISE` 时，常驻 stream 只发布完整歌名、歌手、专辑、时长和封面，没有发布一次性诊断中出现的过渡混合字段。
- 三个并发下一首控制均命中汽水，最终只发布完整的 `BIRDS OF A FEATHER / Billie Eilish / HIT ME HARD AND SOFT / 5824 bytes`。

## QuickTime 焦点冲突

- QuickTime 播放有效 MOV 时，系统全局 MediaRemote 已不再确认汽水来源；汽水专属读取仍返回完整歌曲、播放态、进度和封面。
- 汽水暂停后冻结在 `16.583414s`，QuickTime 保持播放并从 `5s` 继续推进，前台应用仍为 QuickTime Player。
- 汽水恢复和下一首只影响汽水；QuickTime 保持播放且前台不变。
- 视频焦点下汽水最终完整更新为 `In The Event Of Her Departure / Matthew Ifield / My Favourite Place To Be / 14257 bytes`。

## 退出与重启

- 汽水播放中退出后，旧 PID `90674` 完整结束；专属 adapter 与 AX 均返回 `currentTrack=nil`，旧歌曲没有恢复。
- 重启后 PID 变为 `372`，第一次语义播放控制成功。
- 新进程恢复为 `赤と青 (情绪氛围版) / Lost / 落 / 7207 bytes`，未继承旧 PID 的曲目、进度或封面。

## 资源与清理

- 顶屿稳态 CPU 抽样约 `0.7%`。
- 音乐态窗口保持居中 `377x34`、`Y=0`；清理后默认胶囊为居中 `245x34`。
- 验收结束后汽水和 QuickTime 均已关闭；独立执行 `pgrep` 检查，未发现 Computer Use、浏览器控制、调试 watch、QishuiProbe 或额外 `osascript` 进程残留。该结论来自进程检查，不是从 `Transport closed` 推断。
- Apple Music 仍保持 `Fast Times`，封面 `107973 bytes`。

## 未完成

- Computer Use 和浏览器控制通道均返回 `Transport closed`，没有执行点击；本轮未能启动并验证真实抖音视频播放。
- 因此“抖音实际播放并抢占媒体焦点”仍是 P0 的唯一未验收场景；不能用本轮 QuickTime 结果替代。

## 结论

- 汽水单应用同步、暂停冻结、恢复推进、原子切歌、并发切歌、退出清理、新 PID 冷启动均通过。
- QuickTime 实际播放时的数据隔离和控制隔离通过。
- 本轮不改产品代码；抖音浏览器实测恢复后再决定是否把对应 P0 标记为已验收。
