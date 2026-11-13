# 验收记录索引

本目录保存每个 build 的实机与自动化验收证据。记录只陈述实际观察到的结果：单元测试、打包通过与真实设备验收分开写，未完成的门禁明确标为未通过。

- 命名：`YYYY-MM-DD-buildNNN-主题.md`；一次验收一份文件，事后补证追加到原文件末尾，不改写已有结论。
- 历史门禁快照：[STAGE0_CURRENT_GATES.md](STAGE0_CURRENT_GATES.md)（截至 build71，已被第一阶段工作流取代）。
- build 151–180 的逐版本开发说明：[DEV_LOG_build151-180.md](DEV_LOG_build151-180.md)。
- 隐私：不写入个人路径、原始日志或媒体原文；记录只引用汇总结果。

> **2026-11-13 本机原始数据丢失：** 清理存储时执行的 `swift package clean` 清空了主目录整个 `.build/`，2026-11-13 之前记录中引用的 `.build/qa/…` 原始采样、`.build/rollback/…` 回滚副本和 `.build/release-artifacts/` 下未公开的候选 DMG 均已永久删除（无 Time Machine 或本地快照）。各记录中的汇总数字、哈希与结论仍是现存的唯一证据，引用这些路径的段落按历史描述阅读。已公开的 DMG 仍可从 GitHub Releases 获取。`.build/` 只能存放可重新生成的构建产物。

新增记录后运行 `python3 Scripts/generate-acceptance-index.py` 更新下表；`--check` 可在 CI 中检查索引是否过期。

## 记录

<!-- index:start -->

### 2026-11

| 日期 | 记录 |
| --- | --- |
| 11-13 | [build180 快速连续切歌复验](2026-11-13-build180-rapid-skip-recheck.md) |
| 11-13 | [build180 保持展开模式外部点击实机验证](2026-11-13-build180-pinned-outside-click.md) |

### 2026-10

| 日期 | 记录 |
| --- | --- |
| 10-14 | [build180 GitHub源码同步](2026-10-14-build180-github-sync.md) |
| 10-13 | [第三轮：待安装的播放等待基准修复](2026-10-13-pending-playback-baseline-candidate.md) |
| 10-13 | [build180：音乐展开方式与歌词快捷切换](2026-10-13-build180-music-interaction.md) |
| 10-13 | [第三轮：build178 播放证据拒绝原因](2026-10-13-build178-admission-diagnostics.md) |
| 10-13 | [第三轮：build177 音乐展开视图连续性](2026-10-13-build177-stable-music-surface.md) |
| 10-13 | [第三轮：build176 外部点击位置快照](2026-10-13-build176-click-location.md) |
| 10-13 | [第三轮：build175 播放证据与切歌截止衔接](2026-10-13-build175-evidence-deadline.md) |
| 10-13 | [第三轮：build174 语义控件缓存顺序核验](2026-10-13-build174-control-order-validation.md) |
| 10-13 | [第三轮：build173 AX 备用状态与实时播放证据](2026-10-13-build173-ax-playback-evidence.md) |
| 10-13 | [第三轮：build171–172 时长补齐](2026-10-13-build171-172-duration-recovery.md) |
| 10-13 | [第三轮：build170 播放状态与时间轴一致性](2026-10-13-build170-playback-state-coherence.md) |
| 10-13 | [第三轮：build169 歌词查询分段计时](2026-10-13-build169-lyric-read-timing.md) |
| 10-13 | [第三轮：build169 连续控制衔接验收](2026-10-13-build169-chained-controls.md) |
| 10-13 | [第三轮：源事件时间与位置接收时间分离](2026-10-13-build168-source-and-receipt-clocks.md) |
| 10-13 | [第三轮：空包到期仍保留原子切歌基准](2026-10-13-build167-atomic-empty-baseline.md) |
| 10-13 | [第三轮：空状态包的有界等待](2026-10-13-build166-empty-publication-wait.md) |
| 10-13 | [第三轮：build164 有界跳转锚点](2026-10-13-build164-bounded-seek-anchor.md) |
| 10-13 | [第三轮：build163 进程清单补证与桌面2全屏](2026-10-13-build163-inventory-corroboration.md) |
| 10-13 | [第三轮：build162 最终控制与短时观察补证](2026-10-13-build162-final-controls-and-smoke.md) |
| 10-13 | [第三轮：build162 控制预检与媒体会话隔离](2026-10-13-build162-control-probe-session.md) |
| 10-13 | [第三轮：build161 换句重影与预检故障](2026-10-13-build161-lyric-compositing.md) |
| 10-13 | [第三轮：build160 暂停时间轴交接](2026-10-13-build160-pause-timeline.md) |
| 10-13 | [第三轮：build159 歌词归属与全屏验收](2026-10-13-build159-corpus-and-fullscreen.md) |
| 10-13 | [第三轮：build158 有界等待与切歌回退](2026-10-13-build158-passive-grace.md) |
| 10-13 | [第三轮：build156/157 身份顺序与真实目标交付](2026-10-13-build156-157-identity-order.md) |
| 10-13 | [第三轮：build154/155 切歌交付定位](2026-10-13-build154-155-transition-delivery.md) |
| 10-13 | [Build153 控制队列隔离候选](2026-10-13-build153-control-queues.md) |
| 10-13 | [Build 152 第三轮音乐稳定性候选](2026-10-13-build152-music-stability.md) |
| 10-12 | [第一阶段活动仲裁与音乐状态验收](2026-10-12-stage1-activity-policy.md) |
| 10-12 | [Build 151 默认态改良](2026-10-12-build151-default-state.md) |
| 10-08 | [v0.1.3-alpha.1 发布验收](2026-10-08-v0.1.3-alpha.1-published.md) |
| 10-08 | [Build 150 前奏署名与实时发布](2026-10-08-build150-intro-credits-and-publication.md) |
| 10-08 | [Build 148：汽水进度跳转后继续播放](2026-10-08-build148-seek-starts-playback.md) |
| 10-08 | [build 147：无歌词区域的听歌表达](2026-10-08-build147-listening-empty-state.md) |
| 10-07 | [Build 143：歌词身份稳定与切歌实测](2026-10-07-build143-lyric-identity-regression.md) |
| 10-06 | [Build 142：切歌歌词加载与暂停跳转](2026-10-06-build142-track-switch-lyrics.md) |
| 10-06 | [Build 139：歌词后台读取优化](2026-10-06-build139-lyric-polling.md) |
| 10-06 | [build 138 歌词来源稳定性修复](2026-10-06-build138-lyrics-source-priority.md) |
| 10-06 | [汽水词级歌词候选：build 132](2026-10-06-build131-qishui-timed-lyrics.md) |
| 10-05 | [汽水逐字歌词时间轴只读探测](2026-10-05-qishui-word-timestamp-probe.md) |
| 10-03 | [build99 歌词重复渲染树修复验收](2026-10-03-build99-lyrics-renderer-transition.md) |
| 10-03 | [build98 歌词根节点与跑马灯边界修复验收](2026-10-03-build98-lyrics-root-and-mask-fix.md) |
| 10-03 | [build103 歌词层级与展开高度验收](2026-10-03-build103-lyrics-followup.md) |
| 10-02 | [build92 紧凑歌词滚动与汽水候选修复](2026-10-02-build92-lyrics-compact-marquee.md) |
| 10-02 | [build90 汽水身份门禁修复](2026-10-02-build90-qishui-identity-gate.md) |
| 10-02 | [build89 歌词索引映射修复](2026-10-02-build89-lyric-index-remap.md) |
| 10-02 | [build88 展开歌词高度同步修复](2026-10-02-build88-expanded-lyric-height.md) |
| 10-02 | [build87 Release 安装与实机回归](2026-10-02-build87-release-regression.md) |
| 10-02 | [build86 歌词发布节拍与延迟修复](2026-10-02-build86-lyric-latency-reduction.md) |
| 10-02 | [build85 紧凑态歌词黑带修复](2026-10-02-build85-compact-lyric-black-band-fix.md) |
| 10-02 | [build84 歌词延迟日报汇总](2026-10-02-build84-lyric-latency-summary.md) |
| 10-02 | [build83 歌词匿名延迟观测](2026-10-02-build83-lyric-latency-probe.md) |
| 10-02 | [build82 紧凑态歌词窄框与双行滚动修复](2026-10-02-build82-compact-lyric-frame.md) |
| 10-02 | [build81 模式树切换竞态修复](2026-10-02-build81-mode-tree-race.md) |
| 10-02 | [build80 歌词快照新鲜度收紧](2026-10-02-build80-lyrics-freshness.md) |
| 10-02 | [build79 歌词几何重排竞态修复](2026-10-02-build79-lyrics-geometry-race.md) |
| 10-02 | [build78 歌词呈现状态机收敛](2026-10-02-build78-lyrics-state-machine.md) |
| 10-02 | [build77 收起态歌词换行修复](2026-10-02-build77-lyrics-newline-fix.md) |
| 10-02 | [build76 紧凑歌词裁切修复](2026-10-02-build76-lyrics-clip-fix.md) |
| 10-02 | [build75 歌词运行态复核](2026-10-02-build75-lyrics-runtime-recheck.md) |
| 10-02 | [build74 歌词诊断与修复](2026-10-02-build74-lyrics-diagnosis.md) |
| 10-02 | [build72 歌词稳定性候选](2026-10-02-build72-lyrics-stability-candidate.md) |
| 10-01 | [v0.1.3 build 49 汽水进程重建与元数据](2026-10-01-v0.1.3-build49-instance-playback.md) |
| 10-01 | [v0.1.3 build 48 恢复任务显式验证](2026-10-01-v0.1.3-build48-explicit-recovery-probe.md) |
| 10-01 | [v0.1.3 build 47 AX 结构事件批次](2026-10-01-v0.1.3-build47-ax-event-batch.md) |
| 10-01 | [v0.1.3 build 46 控件健康检查](2026-10-01-v0.1.3-build46-control-health.md) |
| 10-01 | [v0.1.3 build 45 恢复反馈检查点](2026-10-01-v0.1.3-build45-recovery-feedback.md) |
| 10-01 | [v0.1.3 build 44 本体菜单与生命周期](2026-10-01-v0.1.3-build44-local-menu.md) |
| 10-01 | [v0.1.3 build 43 恢复判定修复检查点](2026-10-01-v0.1.3-build43-recovery-verification.md) |
| 10-01 | [v0.1.3 build 42 动画收尾回归](2026-10-01-v0.1.3-build42-animation-completion.md) |
| 10-01 | [两小时观察启动前播放检查](2026-10-01-playback-preflight-guard.md) |
| 10-01 | [最小化播放树退化现场与重建保护](2026-10-01-minimized-control-tree-regression.md) |
| 10-01 | [歌词适配：来源核实与显示修正](2026-10-01-lyrics-source-and-presentation.md) |
| 10-01 | [歌词桌面来源归属核查](2026-10-01-lyrics-desktop-identity-audit.md) |
| 10-01 | [联合观察工具准备，未开始新的两小时验收](2026-10-01-joint-observer-preparation.md) |
| 10-01 | [较长全屏测试视频准备](2026-10-01-fullscreen-long-fixture.md) |
| 10-01 | [build71 汽水 AX 歌词路径候选安装](2026-10-01-build71-qishui-ax-lyrics-install.md) |
| 10-01 | [build70 占位歌词高度修正与安装](2026-10-01-build70-placeholder-height-install.md) |
| 10-01 | [build69 歌词 UI 候选安装](2026-10-01-build69-lyrics-install.md) |
| 10-01 | [build68 解锁后几何与紧凑态证据](2026-10-01-build68-resumed-geometry-compact.md) |
| 10-01 | [build68 正式联合观察启动](2026-10-01-build68-joint-run1-start.md) |
| 10-01 | [build68 安装、后台控制、菜单生命周期与静态截图](2026-10-01-build68-installed-controls-lifecycle.md) |
| 10-01 | [build68 显示前全屏状态复核候选](2026-10-01-build68-fullscreen-presentation-guard.md) |
| 10-01 | [build67 原生流媒体全屏与AX无响应恢复](2026-10-01-build67-fullscreen-and-ax-recovery.md) |
| 10-01 | [build67 显式窗口动画时钟与安装实测](2026-10-01-build67-explicit-frame-installed.md) |
| 10-01 | [build66 全屏抑制焦点豁免修复](2026-10-01-build66-fullscreen-focus-policy.md) |
| 10-01 | [build65 隔离隐藏取消补验](2026-10-01-build65-isolated-hidden-cancellation.md) |
| 10-01 | [安装前完整性与长观察联合审核](2026-10-01-build65-integrity-and-joint-audit.md) |
| 10-01 | [build65 动画代理派发修复候选](2026-10-01-build65-animator-proxy-dispatch.md) |
| 10-01 | [build64 AppKit完成回调候选](2026-10-01-build64-appkit-completion-candidate.md) |
| 10-01 | [build63 隐藏期间动画生命周期候选与61内存观察](2026-10-01-build63-hidden-animation-lifecycle.md) |
| 10-01 | [build61 原始动画失败证据与build62候选](2026-10-01-build61-raw-animation-build62-candidate.md) |
| 10-01 | [build61 第三次内存快照及子进程细观察](2026-10-01-build61-memory-third-snapshot.md) |
| 10-01 | [build61 同进程中期内存比较](2026-10-01-build61-memory-comparison.md) |
| 10-01 | [build61 后台歌词核查与运行观察启动](2026-10-01-build61-lyrics-background-probe.md) |
| 10-01 | [build61 安装与被动几何验收](2026-10-01-build61-installed-geometry.md) |
| 10-01 | [build61 一小时观察中的隐藏后台切歌往返](2026-10-01-build61-hidden-next-previous.md) |
| 10-01 | [61长观察终局与66安装、实机几何和后台控制](2026-10-01-build61-final-build66-installed.md) |
| 10-01 | [build60 信号退出、计时活动及全屏恢复](2026-10-01-build60-signals-timer-fullscreen-restore.md) |
| 10-01 | [build60 最小化后台三键与不响应恢复](2026-10-01-build60-minimized-and-fault-controls.md) |
| 10-01 | [build60 锁屏中断与歌词证据更正](2026-10-01-build60-lock-and-lyric-evidence-correction.md) |
| 10-01 | [build60 直接点击接管悬停展开](2026-10-01-build60-interaction-ownership.md) |
| 10-01 | [build60 隐藏且最小化控制及菜单退出重开](2026-10-01-build60-hidden-controls-and-menu-lifecycle.md) |
| 10-01 | [build60 几何观察与build61时长修正](2026-10-01-build60-geometry-and-build61-timing.md) |
| 10-01 | [build59 Vimeo 原生全屏回归](2026-10-01-build59-vimeo-native-fullscreen.md) |
| 10-01 | [build59 最小化后台三键实机验收](2026-10-01-build59-minimized-controls.md) |
| 10-01 | [build59 歌词补充适配](2026-10-01-build59-lyrics-supplement.md) |
| 10-01 | [build59 歌词适配当前交付范围](2026-10-01-build59-lyrics-current-status.md) |
| 10-01 | [build59 从DMG安装，启动与交互待解锁](2026-10-01-build59-installed-awaiting-unlock.md) |
| 10-01 | [build59 首次启动、后台可见窗三键及歌词卡片](2026-10-01-build59-first-live-controls.md) |
| 10-01 | [build59 DMG 与长稳资源诊断](2026-10-01-build59-dmg-and-resource-audit.md) |
| 10-01 | [build59 主窗口主动关闭后600秒观察](2026-10-01-build59-closed-paused-observation.md) |
| 10-01 | [build59 不响应后自动恢复与三键](2026-10-01-build59-ax-unresponsive-recovery.md) |
| 10-01 | [build58 未知最小化状态保护](2026-10-01-build58-unknown-minimized-guard.md) |
| 10-01 | [build58 候选代码校验及打包路径纠正](2026-10-01-build58-corrected-candidate.md) |
| 10-01 | [build57 Finder 安装界面视觉](2026-10-01-build57-finder-visual.md) |
| 10-01 | [build57 修正候选构建](2026-10-01-build57-candidate.md) |
| 10-01 | [build56 Vimeo 原生视频全屏隐藏与主动退出恢复](2026-10-01-build56-vimeo-native-fullscreen.md) |
| 10-01 | [build56 两小时混合场景资源监测终结](2026-10-01-build56-two-hour-terminal.md) |
| 10-01 | [build56 原窗口显示后 renderer 播放树恢复](2026-10-01-build56-renderer-tree-return.md) |
| 10-01 | [build56 几何与视频交互补验](2026-10-01-build56-geometry-and-video-interaction.md) |
| 10-01 | [build56 主动恢复入口与实机验证](2026-10-01-build56-explicit-recovery.md) |
| 10-01 | [build56 DMG 候选内容验证](2026-10-01-build56-dmg-candidate.md) |
| 10-01 | [build56 诊断分段与长时间监测启动](2026-10-01-build56-diagnostic-and-long-run.md) |
| 10-01 | [build55 主窗口关闭后只剩桌面歌词的状态修正](2026-10-01-build55-lyrics-only-window.md) |
| 10-01 | [build54 Vimeo 视频全屏观察](2026-10-01-build54-vimeo-fullscreen.md) |
| 10-01 | [build54 最小化与桌面歌词并存的三键实测](2026-10-01-build54-minimized-three-controls.md) |
| 10-01 | [最小化播放器被桌面歌词窗口干扰](2026-10-01-build54-minimized-lyrics-fix.md) |
| 10-01 | [build54 退出、清理与重开](2026-10-01-build54-lifecycle.md) |
| 10-01 | [build54 最小化状态不响应恢复与三键](2026-10-01-build54-ax-recovery-controls.md) |
| 10-01 | [build54 动画观察器严格判定](2026-10-01-build54-animation-observer.md) |
| 10-01 | [build 53 自动重试提示](2026-10-01-build53-retry-feedback.md) |
| 10-01 | [build 53 退出与重新启动](2026-10-01-build53-lifecycle.md) |
| 10-01 | [build 53 内部全屏操作路径与候选包](2026-10-01-build53-internal-fullscreen-candidate.md) |
| 10-01 | [build 53 Chrome 前台播放暂停与菜单验收限制](2026-10-01-build53-chrome-control-partial.md) |
| 10-01 | [build 52 安装与两轮恢复实测](2026-10-01-build52-installed-recovery.md) |
| 10-01 | [build 52 内容候选 DMG](2026-10-01-build52-candidate-dmg.md) |
| 10-01 | [build 52 AX 无响应自动恢复验收](2026-10-01-build52-ax-unresponsive.md) |
| 10-01 | [build 51 窗口启动读取与前台三键](2026-10-01-build51-window-bootstrap.md) |
| 10-01 | [build 50 状态流退出与 DMG 内容校验](2026-10-01-build50-stream-lifecycle.md) |
| 10-01 | [build 50 后台三键与音乐全屏保留验收](2026-10-01-build50-background-fullscreen.md) |
| 10-01 | [build 49 原生播放器全屏验证](2026-10-01-build49-player-fullscreen.md) |
| 10-01 | [AX 内容根节点缓存清理检查点](2026-10-01-ax-root-invalidation.md) |

### 2026-09

| 日期 | 记录 |
| --- | --- |
| 09-28 | [v0.1.3 build 41 阶段 0 稳定性验收](2026-09-28-v0.1.3-build41-stability.md) |
| 09-19 | [v0.1.3 build 39 汽水控件树恢复验收](2026-09-19-v0.1.3-build39-qishui-control-tree-recovery.md) |
| 09-19 | [v0.1.3 build 38 收起黑边修复验收](2026-09-19-v0.1.3-build38-collapse-edge.md) |
| 09-18 | [v0.1.3 build 37 汽水控制自动恢复验收](2026-09-18-v0.1.3-build37-qishui-control-auto-recovery.md) |
| 09-16 | [v0.1.3 build 36 空岛快捷面板验收](2026-09-16-v0.1.3-build36-quick-panel.md) |
| 09-16 | [v0.1.3 build 35 空岛活动中心验收](2026-09-16-v0.1.3-build35-activity-center.md) |
| 09-16 | [v0.1.3 build 34 空岛点击验收](2026-09-16-v0.1.3-build34-empty-island-click.md) |
| 09-16 | [v0.1.3 build 33 macOS 27 活动入口验收](2026-09-16-v0.1.3-build33-macos27-activities.md) |
| 09-15 | [v0.1.3 build 32 顶部边缘几何验收](2026-09-15-v0.1.3-top-edge-geometry.md) |
| 09-05 | [v0.1.3 build 31 可观测性与隐私验收](2026-09-05-v0.1.3-build31-observability.md) |
| 09-04 | [v0.1.3 汽水三键运行态回归](2026-09-04-v0.1.3-qishui-three-control-runtime.md) |
| 09-04 | [v0.1.3 M5 MediaRemote client 缓存候选验收](2026-09-04-v0.1.3-mediaremote-client-cache.md) |
| 09-03 | [v0.1.3 汽水三键可用性恢复验收](2026-09-03-v0.1.3-qishui-control-recovery.md) |
| 09-03 | [v0.1.2 最终候选长稳门禁复核](2026-09-03-v0.1.2-final-candidate-health-check.md) |
| 09-01 | [v0.1.3 seek 终态可观测性验收](2026-09-01-v0.1.3-seek-terminal-observability.md) |
| 09-01 | [v0.1.3 汽水切歌阶段延迟验收](2026-09-01-v0.1.3-qishui-transition-stages.md) |
| 09-01 | [v0.1.3 汽水切歌控制延迟自动门禁](2026-09-01-v0.1.3-qishui-control-latency.md) |
| 09-01 | [v0.1.2-alpha.5 智能专辑色候选验收](2026-09-01-v0.1.2-alpha5-smart-accent-candidate.md) |
| 09-01 | [v0.1.2-alpha.4 设计候选验收](2026-09-01-v0.1.2-alpha4-design-candidate.md) |
| 09-01 | [v0.1.2-alpha.3 日常诊断覆盖验收](2026-09-01-v0.1.2-alpha3-diagnostic-coverage.md) |

### 2026-08

| 日期 | 记录 |
| --- | --- |
| 08-31 | [v0.1.2 日常使用日志验收](2026-08-31-v0.1.2-daily-usage-logging.md) |
| 08-31 | [v0.1.2 候选版本打包验收](2026-08-31-v0.1.2-candidate-packaging.md) |
| 08-31 | [v0.1.2-alpha.2 端到端媒体诊断验收](2026-08-31-v0.1.2-alpha2-end-to-end-diagnostics.md) |
| 08-30 | [v0.1.2 辅助功能授权恢复与汽水三键验收](2026-08-30-v0.1.2-accessibility-recovery.md) |

### 2026-07

| 日期 | 记录 |
| --- | --- |
| 07-26 | [v0.1.2 汽水切歌原子加载延迟优化](2026-07-26-v0.1.2-qishui-transition-latency.md) |
| 07-26 | [v0.1.2 内存门禁修复与压力复测](2026-07-26-v0.1.2-memory-gate-remediation.md) |
| 07-26 | [v0.1.2 长稳资源观察](2026-07-26-v0.1.2-long-run-observation.md) |
| 07-26 | [v0.1.2 最终候选两小时长稳验收](2026-07-26-v0.1.2-final-candidate-2h-long-run.md) |
| 07-25 | [v0.1.2 设置与恢复入口验收](2026-07-25-v0.1.2-settings-recovery.md) |
| 07-25 | [v0.1.2 减少动态效果验收](2026-07-25-v0.1.2-reduced-motion.md) |
| 07-25 | [v0.1.2 登录时自动启动验收](2026-07-25-v0.1.2-login-item.md) |
| 07-25 | [v0.1.2 显示器热变化验收](2026-07-25-v0.1.2-display-hot-update.md) |
| 07-22 | [2026-07-22 v0.1.2 多显示器与动画锚定验收](2026-07-22-v0.1.2-multi-display-animation.md) |
| 07-22 | [2026-07-22 v0.1.2 Apple Music 封面与控制验收](2026-07-22-v0.1.2-apple-music-artwork.md) |
| 07-20 | [v0.1.2 M0 自动化基线](2026-07-20-v0.1.2-baseline.md) |
| 07-20 | [汽水最小化控制不弹窗验收](2026-07-20-qishui-minimized-control.md) |
| 07-20 | [P0 三音乐来源状态一致性验收](2026-07-20-p0-media-source-consistency.md) |
| 07-20 | [P0 主线程与反向动画验收](2026-07-20-p0-main-thread-and-reversal.md) |
| 07-19 | [P0 悬停性能与窗口锚定验收](2026-07-19-p0-hover-performance.md) |
| 07-19 | [网易云音乐后台同步与进程重绑验收](2026-07-19-netease-music-hardening.md) |
| 07-19 | [网易云音乐 Beta 候选稳定性验收](2026-07-19-netease-music-beta-candidate.md) |
| 07-19 | [MacBook 机型几何自适应验收](2026-07-19-display-geometry-adaptation.md) |
| 07-19 | [2026-07-19 Apple Music 封面恢复路由验收](2026-07-19-apple-music-artwork-recovery.md) |
| 07-17 | [网易云音乐 Alpha 验收记录](2026-07-17-netease-music-alpha.md) |
| 07-17 | [2026-07-17 Apple Music 电台瞬时读取重试验收](2026-07-17-apple-music-transient-refresh-retry.md) |
| 07-17 | [2026-07-17 Apple Music 统一快照准入验收](2026-07-17-apple-music-snapshot-admission.md) |
| 07-17 | [2026-07-17 Apple Music Alpha 扩展回归](2026-07-17-apple-music-alpha-extended.md) |
| 07-16 | [v0.1.1-alpha.4 发布后验收](2026-07-16-v0.1.1-alpha.4-post-release.md) |
| 07-16 | [汽水无窗口控制调查](2026-07-16-qishui-windowless-control-investigation.md) |
| 07-16 | [2026-07-16 汽水控件树健康门禁验收](2026-07-16-qishui-control-tree-health.md) |
| 07-16 | [2026-07-16 汽水控制能力动态验收](2026-07-16-qishui-control-capability.md) |
| 07-16 | [2026-07-16 单窗口动画回归](2026-07-16-island-animation-regression.md) |
| 07-16 | [2026-07-16 浏览器媒体并存回归](2026-07-16-browser-media-regression.md) |
| 07-16 | [2026-07-16 Apple Music 原生时间线量化](2026-07-16-apple-music-native-timeline.md) |
| 07-16 | [2026-07-16 Apple Music build 18 动态回归](2026-07-16-apple-music-build18-regression.md) |
| 07-15 | [汽水运行时与媒体焦点综合回归](2026-07-15-qishui-runtime-regression.md) |
| 07-13 | [汽水切歌元数据原子性回归](2026-07-13-qishui-metadata-atomicity.md) |
| 07-13 | [汽水退出清理与 Apple Music 权限验收](2026-07-13-qishui-exit-and-apple-music-permission.md) |
| 07-13 | [汽水专属流并存回归](2026-07-13-qishui-concurrent-media.md) |
| 07-12 | [顶屿 v0.1.1 发布预检记录](2026-07-12-release-preflight.md) |
| 07-10 | [MVP v0.1 验收记录](2026-07-10-0056-mvp-v0.1-check.md) |

共 206 份带日期记录。
<!-- index:end -->
