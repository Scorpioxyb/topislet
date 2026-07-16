# 2026-07-16 汽水控件树健康门禁验收

## 目标

验证汽水窗口仍存在但 Electron 辅助功能树退化时，顶屿不会继续显示可用控制；恢复唯一语义控制组后，按钮可由后台健康检查自动恢复。

## 实机异常样本

- 汽水 PID：`33284`。
- 汽水专属状态流仍正常，包含真实播放态、进度、封面和 `com.soda.music` 来源证明。
- `AXManualAccessibility=true`，但完整诊断只扫描到 2 个节点、0 个候选。
- `AXFocusedWindow`、`AXMainWindow` 和 `AXWindows` 均错误返回 `AXApplication` 自身，不是标准窗口。

## 本次门禁

1. 只有完整语义扫描恰好找到一个底部播放控制组时返回 `available`。
2. 窗口存在但候选为 0 或多于 1 时返回 `controlTreeUnavailable`。
3. AX 读取失败返回 `unknown`；`unknown` 与 `controlTreeUnavailable` 都不允许控制。
4. 健康检查复用真实控制的 `AXManualAccessibility` 初始化、有界扫描和稀疏树重建路径，但不按压任何按钮。
5. 检查在汽水专属串行后台队列运行；异常态按 3、6、12 秒退避重试，恢复唯一候选后自动启用。
6. 完整扫描只由启动、PID / 窗口结构事件和退避任务触发，不绑定歌名、进度或封面的高频更新。
7. 已验证的唯一最小化窗口可复用缓存控件做只读健康确认，避免探针自身的临时恢复 / 最小化通知形成扫描循环。

## 动态结果

- 新增只读命令输出：

```text
controlAvailability=controlTreeUnavailable
allowsControl=false
reason=汽水辅助功能控件暂不可用；顶屿会在后台自动重试。
```

- 同一时刻 `--qishui-control-diagnostic` 确认 `scanned=2`、`candidateCount=0` 和 `AXWindows=count:1,roles:AXApplication`。
- 安装版后台运行后，控件树在退避自修复期间重新暴露唯一候选；`--qishui-control-availability` 自动变为 `controlAvailability=available`、`allowsControl=true`，未重启汽水，也未要求用户手动同步。
- 恢复后的安装版语义控件成功把 `The Incident - Matt Sassari, BLR` 从播放切为暂停，再恢复播放；两次结果均为 `semanticQishuiControlSent=true`，来源持续为 `com.soda.music`，封面 11963 bytes。
- 安装版稳态 CPU 实测约 0.8%，没有出现高频深层扫描或窗口通知循环。
- 产品不会回退到系统媒体键、全局 MediaRemote 控制、坐标点击、鼠标移动或激活汽水，因此不会误控抖音、QuickTime 或浏览器媒体。

## 自动回归

- 110 项 Swift Testing 回归通过。
- 新增窗口异常树、唯一候选、0 候选、多候选、读取失败与严格 `allowsControl` 决策覆盖。
- Debug / Release 构建、安装版动态探针和 DMG 独立挂载烟测通过；DMG SHA-256 为 `42680238b324603cbdcd51a7930daba0a07d67f41ec071073ca22b53c0204fc1`。
