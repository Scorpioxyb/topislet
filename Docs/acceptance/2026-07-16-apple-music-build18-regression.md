# 2026-07-16 Apple Music build 18 动态回归

## 环境

- 顶屿：GitHub Pre-release `v0.1.1-alpha.4` 的公开 DMG，App `0.1.1 (18)`，安装于 `/Applications/顶屿.app`。
- Apple Music：`com.apple.Music`，播放本机资料库曲目。
- 汽水音乐：`com.soda.music`，与 Apple Music 同时运行，用于验证路由切换和控制隔离。
- 测试使用 Apple Music 自动化、顶屿岛内控制和 Computer Use 观察真实界面；测试结束后 Computer Use 会话已完全重置。

## 定向读取与前台路由

- Apple Music 适配器返回 `availability=ready`，并绑定唯一运行实例 PID。
- 首次读取曲目 `Janice STFU`，原生封面为 `142345 bytes`；元数据和封面快照合计约 `264ms`。
- Apple Music 成为当前前台音乐应用后，顶屿正确显示歌曲、歌手、真实封面、进度和 Apple Music Logo。
- 展开态布局、来源标识和控制区显示正常，没有混入后台汽水元数据。

## 播放控制

### 播放与暂停

- 点击岛内暂停后，顶屿按钮立即切换为播放，Apple Music 原生按钮同步切换为播放。
- 暂停期间进度稳定在 `3:02 / 3:57`，没有继续推进或回退。
- 点击恢复后，按钮状态和进度均正常继续推进。

### 下一首与上一首

- 下一首从 `Janice STFU` 切换到 `B's On The Table`，歌名、歌手和进度均正确更新。
- 当前资料库队列中，播放超过数秒后第一次点击上一首会将当前歌曲重置到 0 秒，第二次点击仍未返回上一曲。
- 对照点击 Apple Music 原生上一首按钮得到相同行为，因此该现象属于当前 Apple Music 队列语义，不是顶屿控制故障。

### 绝对进度

- 在顶屿进度条约 50% 位置点击后，岛显示 `1:09 / 2:18`。
- Apple Music 原生进度 slider 同步为约 `0.50007`。
- 后台汽水保持暂停且 `elapsedTime=91.435975`，没有被误 seek。

## 元数据与应用切换

- 从 Drake 专辑切换到 `玻璃 - Gareth.T` 后，新歌名、新歌手和不同的真实封面最终均正确显示。
- Apple Music 完整退出后约 2 秒内，顶屿自动回落到汽水音乐；汽水歌曲、封面、进度和来源 Logo 均正确恢复。
- 回落后的第一次汽水播放尝试因汽水进程没有任何 AX 窗口而被安全拒绝；重新显示汽水窗口后，唯一语义控件恢复，岛内播放立即成功。

## 观察项

### Apple Music 跨专辑可见延迟

- Computer Use 采样中，点击下一首后约 0.8 至 1 秒的首次界面采样仍显示旧曲，约 2.5 秒内完成新歌名、歌手和封面切换。
- Computer Use 单次状态采集本身约占 0.8 至 1 秒，因此不能把 2.5 秒直接认定为顶屿内部延迟。
- 下一阶段应增加原生时间线测量，分别记录控制命令发出、`com.apple.Music.playerInfo` 到达、Apple Event 新曲快照返回和顶屿最终发布的时间，定位真实耗时后再调整刷新策略。

### 汽水无 AX 窗口时的安全拒绝

- 问题状态下诊断为 `accessibilityTrusted=true`、`manualAccessibilityEnabled=true`、`AXWindows=count:0`、`candidateCount=0`。
- 重新显示汽水窗口后诊断恢复为 `AXWindows=count:2`、`candidateCount=1`，控制立即成功。
- 当前拒绝行为符合“不使用系统媒体键、不做坐标点击、不误控其他媒体”的安全约束。是否在进程存在但无 AX 窗口时主动恢复汽水主窗口，留作产品决策。

## 结论

公开 build 18 的 Apple Music Alpha 动态回归通过：定向读取、前台路由、真实封面、播放控制、绝对进度、跨专辑更新、汽水隔离和退出回落均符合当前验收标准。跨专辑可见延迟进入原生打点量化，汽水无 AX 窗口时的恢复策略进入产品决策；两项均不阻塞本次公开 Alpha。
