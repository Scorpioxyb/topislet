# 协调器拆分第 4 步：汽水适配器（工作计划）

2026-11-15 起草，v0.2.0 M1。背景与目标结构见 [全局规划 4.2](../product/GLOBAL_PLAN_2026-11.md)。每个子步骤行为不变，单独提交，测试全过。

## 现状（拆分前）

`MusicAdapterCoordinator`（`MediaAdapter.swift`）约 3,750 行：汽水约 1,690 行、Apple Music 约 720 行、网易云约 300 行、共用约 1,050 行。

**只搬汽水达不到“单个类型不超过约 1,500 行”。** 搬完汽水，协调器还剩约 2,150 行。要达标，还得把 Apple Music 的编排也搬成独立驱动（4b）。汽水部分自己也有约 1,670 行，所以歌词要单独成一个类型。

**汽水暂时不能完全实现 `MusicAppAdapter`。** `MusicAppSnapshot` 缺几样汽水要发布的东西：逐字歌词、桌面歌词标记、待确认播放与时间轴下限、受保护的 `canSeek`、恢复控制动作，以及汽水专属的来源可用性状态。汽水的数据也是状态流推送，协议是拉取。先用中间形态：`QishuiMusicAdapter` 持有状态和方法，协调器委托给它。快照类型补齐后再接协议。

## 子步骤

| 步骤 | 内容 | 状态 |
| --- | --- | --- |
| 4.1 | 纯逻辑：播放推断搬成 `QishuiPlaybackInference`（含进度样本、签名、状态文案） | 完成 |
| 4.2 | 歌词搬成 `QishuiLyricPipeline`，用注入的闭包取当前身份、发布、记录 | 完成：机械搬运，未新增测试 |
| 4.3 | 只搬状态：新建 `@MainActor final class QishuiMusicAdapter`，持有全部汽水存储属性和协作对象，协调器用 `qishui.x` 访问，不搬逻辑 | 完成：28 个存储属性搬入，引用按编译器报错逐处加前缀；除声明和一处可选绑定改写外，差异只有 `qishui.` 前缀 |
| 4.4 | 搬状态流与快照接收、状态文案和状态构建；通过弱引用的宿主协议回调协调器。`refreshSourceStatus` 等公开入口留在协调器里转发 | 完成：24 个函数与 `cachedStatus` 搬入，另含待确认播放的开始、确认、超时与回滚；宿主协议 `QishuiMusicAdapterHost` 9 项（前台来源、使用诊断、歌词管线、竞争播放、发布、记录，以及身份与控制可用性排程这三项留到 4.5、4.6 再收回）。逐函数比对：除 `qishui.` 前缀去掉、协调器调用改走 `host?.` 外与原文一致；`host` 为空时竞争播放按“有”处理（更保守，实际不会为空）。文本检查改指向新文件，两个函数仍相邻 |
| 4.5 | 搬身份刷新，以及启动、退出、激活三个钩子（在协调器观察者中的原位置调用） | 完成：身份刷新、切歌后身份对账、生命周期元数据补读、前台刷新与 `qishuiMediaIdentity` 搬入；启动钩子的汽水部分成为 `resetForQishuiLaunch()`，在原位置、250ms 等待前调用，等待后的第二次判断留在协调器；退出与激活钩子原本已是适配器调用。三个观察者本身是三个来源共用的，留在协调器。宿主协议去掉两项身份排程，新增是否在观察、`selectedSource()`（原位置、原次数调用）、跳转代次和控制可用性排程（后者 4.6 收回）。逐函数比对：差异只在改走宿主的那几处；`host` 为空时一律放弃本次读取 |
| 4.6 | 搬控制可用性与健康检查（`tick` 中原位置调用） | 完成：控制可用性探测、刷新、退避重试、取消排程、进程选择，以及恢复后的重置与核验搬入；`tick` 里的健康检查成为 `scheduleControlHealthCheckIfNeeded()`，在原位置调用。`resetQishuiControlVerificationForRecovery` 与 `verifyQishuiControlsAfterRecovery` 在协调器里留作转发。宿主协议去掉两项控制排程，剩 8 项。逐函数比对：差异只在发布改走宿主 |
| 4.7 | 搬控制发送与汽水跳转；`verify-qishui-control-safety.sh` 的 `SeekCoordinator.qishuiAdmission(` 检查同一提交改指向新文件 | 完成：`sendControl`、`pressSemanticControl`、`synchronizeAfterQueuedTrackControl` 整体搬入；`performControlImplementation` 与 `performSeek` 在协调器里建立显示来源绑定与授权后，汽水分支分别交给 `performQishuiControl`、`performQishuiSeek`，`refreshControlFollowUp` 的汽水部分交给 `refreshQishuiControlFollowUp`。授权复核的位置和次数不变（控制两处、跳转两处）。宿主协议新增选择器读取、`selectedMusicSelection()`（同样只在原位置调用）、所选来源状态和“来源已切换”结果，共 12 项。安全脚本的跳转准入检查改指向 `QishuiMusicAdapter.swift`。逐段比对：差异只在改走宿主的那几处 |
| 4.8 | 引入 `PublishedTrackToken`，先合并身份刷新的两处重复门禁，再到歌词、恢复核验、控制回读、跳转 | 待做 |
| 4b | Apple Music 驱动，满足 1,500 行门禁 | 待做 |

## 不能变的顺序

- `selectedMusicSource()` 有副作用（更新选择器、记录 `source_change`、作废待定跳转），只能经宿主协议在原位置、按原次数调用，不缓存、不当参数传。
- `refreshSourceStatus` 里，身份对账发生在写 `latestMediaRemoteSnapshot` 之后、更新 `cachedStatus` 之前，`qishuiSourceCandidate` 读的是旧 `cachedStatus`。
- `markQishuiNotRunning` 先用快照记使用诊断再清空；`controlGeneration` 先递增再取消排程。
- 启动钩子的顺序、250ms 等待和第二次判断保持不变；`stopRealtimeObservation` 里汽水与共用的清理交错，逐项保持原顺序。
- 现有的 `[weak self]` 捕获保持弱引用；适配器回调协调器一律走弱引用宿主。
- 代次在 `await` 前捕获；`sendControl` 之后的授权复核不增不减。
- `Tests/MacBookIslandTests/MusicNativePresentationRegressionTests.swift` 按文本检查 `refreshSourceStatus` 与 `applyQishuiDirectSnapshot` 相邻；4.4 时改指向新文件，两个函数保持相邻和原顺序。

## 门禁

每个子步骤：`swift test` 全过、脚本测试、`verify-qishui-control-safety.sh`。4.3–4.8 合并进一个开发构建后，做一轮“汽水专属控制”短实机（三键、拖动进度、暂停中拖动续播）。这些改动不与界面改动进同一个构建。
