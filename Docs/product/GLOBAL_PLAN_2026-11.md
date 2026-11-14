# 顶屿全局规划（2026-11）

**状态：已确认，当前产品基准（负责人 2026-11-13 接受第 7 节全部八项建议）**
**基线：源码与安装版 `0.1.3 build 180`，公开下载 `v0.1.3-alpha.2 / build 180`**
**范围：产品设计、前端（岛界面、窗口、交互、动画、设置）、后端（来源适配、播放与身份状态机、歌词、诊断、构建发布）**

本文只读审查代码、文档与 git 记录后写成，没有运行应用、没有发送任何控制命令、没有重新跑测试。文中“已核对”指我在本次审查中直接读到的文件内容；标注 **〔推断〕** 的内容是根据代码结构或常识做出的判断，未经实机或测试验证。文中的测试数与实机结论均引用既有记录，不是本次新证据。

本文已取代 `V0.2_PRODUCT_REPLAN` 成为 [文档地图](../README.md) 中登记的产品基准，取代关系见 [2.5](#25-与旧计划的取代关系)。

---

## 0. 结论先行

1. **产品已经是一个“音乐优先的刘海岛”，文档却仍把它描述成“通用活动层 + AI 命令入口”。** 9 月 23 日重规划之后的 140 个 build 几乎全部投入在汽水音乐的状态一致性、控制和歌词上；活动中心至今只有计时预设和一个恢复入口。建议把定位改回事实：音乐是主线，活动是辅线，AI 命令入口移出路线图。
2. **顶屿这一侧的延迟已经没有可安全压缩的空间。** 切歌约 665ms 中约 600ms 属于汽水自己；能改善的是“等待期间的观感”，而不是门禁和去抖。
3. **最大的工程风险是两个巨型类型，不是功能缺口。** `IslandModel`（约 2,000 行、31 个 `@Published`）和 `MusicAdapterCoordinator`（约 4,600 行、约 145 个方法、约 100 个存储属性）让每次修复都要靠新增代次门禁来防回归，build 151–180 的 30 个 build 就是这个成本的体现。
4. **最大的发布风险是 ad-hoc 签名。** 没有 Developer ID 就没有公证、没有可靠的自动更新，升级还可能丢失辅助功能授权〔推断〕。这是一个只有负责人能做的付费决定。
5. **验证方式需要从“每个 build 一篇记录”转成“每个版本一张门禁表 + 日常日志被动取证”。** 现状是 约 210 篇验收记录、一张停在 build 71 的门禁表，以及一份仍以 v0.1.1-alpha.4 为目标的发布清单。

---

## 1. 现状评估

### 1.1 产品今天是什么

- 一个 macOS 26+、Apple Silicon 的菜单栏应用，在刘海周围显示折叠、紧凑、展开三态的岛（`README.md`“当前能力”；`Sources/MacBookIsland/IslandActivityPolicy.swift` 的 `IslandMode`）。
- 四种活动：活动中心、音乐、计时器、通知（`IslandActivityPolicy.swift` 的 `IslandFeature`）。音乐来自三个来源：汽水（主适配）、网易云与 Apple Music（Alpha），见 `Docs/engineering/MUSIC_ADAPTER_INTAKE.md`。
- 汽水歌词：词级时间轴来自网络查询并经歌名、完整歌手名单、时长核验；窗口和桌面歌词作为补充（`README.md`“歌词与网络”；`Sources/MacBookIsland/QishuiTimedLyrics.swift`、`QishuiLyricReader.swift`）。
- 计时器（5/15/25/45 分钟）、日历临近事件、到期提醒可短暂接管后恢复（`EventKitActivitySource.swift`；`IslandActivityArbitrationPolicy`）。
- 发布形态：GitHub 预发布 DMG，ad-hoc 签名，未公证（`README.md`“发布状态”；`Docs/qa/RELEASE_CHECKLIST.md`）。

### 1.2 真实的强项

| 强项 | 依据 |
| --- | --- |
| 控制安全做成了硬约束而不是约定 | `Scripts/verify-qishui-control-safety.sh` 在 CI 中执行（`.github/workflows/ci.yml`）；`Docs/qa/QA_CHECKLIST.md`“安全硬门禁”；汽水、Chrome、Safari、抖音、QuickTime 并存回归均已验收（`Docs/ISSUE_BOARD.md` P0 表） |
| 原子切歌发布确实有效 | 2026-11-13 专项中 8 次切歌的早期候选身份哈希全部与最终曲目不同，顶屿全部暂缓，完整候选到达后 5–9ms 一次发布到位（`Docs/acceptance/2026-11-13-build180-keyboard-latency-layers.md`） |
| 诊断能力强且注意隐私 | 曲目只记 12 位截断哈希；`DailyUsageAnalyzer`、15 分钟健康心跳、`keyboard-latency-audit.py` 都是只读（`README.md`“诊断”；`Sources/MusicUsageDiagnostics/`） |
| 验证纪律 | 单元测试与实机验收分开陈述，失败和反证保留（`Docs/acceptance/README.md`；`Docs/acceptance/STAGE0_CURRENT_GATES.md`） |
| 几何与单窗口动画 | 运行时读取安全区域、单 `NSPanel`、可中断形变（`IslandDisplayGeometry.swift`；`Docs/ISSUE_BOARD.md` P1“单窗口连续轮廓”“可中断形变动画”） |
| 自动化基数 | 44 个测试文件、395 个用例（本次按 `@Test`/`func test` 计数为 395，与 `Docs/updates/2026-10-14-build180-music-interaction.md` 一致）；CI 跑 Debug、测试、Release、打包与 DMG 校验 |
| 供应链 | MediaRemote Adapter 固定上游 commit 并可逐字节重建（`Docs/engineering/MEDIAREMOTE_ADAPTER_REPRODUCIBILITY.md`） |

### 1.3 真实的弱项

**产品**

- **定位与实际投入不一致。** `Docs/product/V0.2_PRODUCT_REPLAN.md` 第 1 节把音乐降级为“一个活动源”，第 6–7 节规划 AI Command Bar、文件 Shelf、快捷动作；而 `ExpandedActivityCenter`（`main.swift` 约 5724 行起）实际只有四个计时预设和“重启并连接”恢复行。重规划第 7 节 P0 的“打开常用 App、截图并复制、快速笔记”均未实现。
- **路线图自相矛盾。** `Docs/ROADMAP.md` 下半部分仍写“v0.3.0 补齐歌词”，而歌词已在 0.1.3 交付；“当前版本：v0.1.3-dev”一节停留在 build 31 语境。
- **进度跳转的口径三处不同。** `README.md` 说校验通过时支持点击/拖动跳转；`MUSIC_ADAPTER_INTAKE.md` 表格写汽水进度“可信只读”；`ISSUE_BOARD.md` P2 写“当前进度只读；系统全局 seek 已移除”。代码事实是 `QishuiSeekSafety.supportsTargetedSeek = false`、`supportsGuardedMediaFocusSeek = true`，注释明确“seek 命令仍然跟随系统媒体焦点”（`MediaAdapter.swift` 约 130 行）。这是全项目唯一一条不按来源定向的控制路径，需要负责人明确表态（见第 7 节决策 5）。
- **“媒体键没反应”有一半不是顶屿的问题，但用户无从得知。** 日常样本 16 次按键中 7 次被系统路由给网易云（同上测量记录），岛上没有任何提示。

**前端**

- **无首次使用引导。** 代码中没有 onboarding 流程（本次检索无结果）；辅助功能、自动化、日历、提醒四类授权靠 `README.md`“第一次使用”九步文字说明。
- **辅助功能覆盖薄。** `main.swift` 7,256 行里 `accessibility*` 视图修饰符约 24 处（其中标签 11 处），进度条没有可调节动作，未见“增强对比度 / 降低透明度”适配（本次检索无结果）。`OPTIMIZATION_BACKLOG.md` P2“减少动态效果与辅助功能”仍标“待开始”，而减少动态效果其实已实现并在 v0.1.2 实机验收（`Docs/acceptance/2026-07-25-v0.1.2-reduced-motion.md`），之后新增的歌词滚动与逐字高亮没有对应复验记录。
- **动画时长的文档口径不一。** 代码是 240ms / 180ms（`IslandMotion.duration`）；`OPTIMIZATION_BACKLOG.md` 仍写 `280ms / 200ms`；`STAGE0_CURRENT_GATES.md` 记录 build 61 实测时长未通过，后续没有关闭记录。
- **视觉常量散落。** 字号、透明度、圆角直接写在各个 View 里，没有统一主题层〔推断：基于抽查 `ExpandedActivityCenter`，未逐个统计〕。
- **只有当前 15 英寸 Air 做过像素级验收**（`README.md`“已知限制”）。

**架构**

- `main.swift` 7,256 行，包含约 750 行命令行诊断入口、`IslandModel`（1272–3254 行）、`AppDelegate`（3287–4381 行）、全部设置页与全部岛视图。`OPTIMIZATION_BACKLOG.md` P2“拆分 `main.swift`”一直“待开始”，`V0.1.3_PLAN.md` 明确写“不做大规模拆分”。
- `MusicAdapterCoordinator`（`MediaAdapter.swift` 451–5043 行）是单一类型。文件内 `qishui` 出现约 550 次、`appleMusic` 约 307 次、`netease` 约 129 次：三个来源的特判都在协调器里。
- **适配器协议没有覆盖主适配。** `MusicAppAdapter`（`MusicAppAdapter.swift`）只有 `AppleMusicAppAdapter` 和 `NeteaseMusicAppAdapter` 实现；汽水由协调器直接驱动 `MediaRemoteAdapterStreamSource`、`QishuiAXReader`、`QishuiSemanticAXController`、`QishuiLyricReader`。`MUSIC_ADAPTER_INTAKE.md` 的七条准入门槛因此没有对应的统一类型约束。
- **身份门禁靠分散的代次检查实现。** build 151–180 的记录标题几乎都是某一处时序或归属的补丁（`Docs/acceptance/DEV_LOG_build151-180.md`；10-13 的 27 篇记录）。门禁本身正确，但没有一个“已发布曲目令牌”类型让编译器帮忙。
- 状态流通过 `/usr/bin/perl` 子进程运行（`MediaRemoteAdapterStreamSource.swift` 234、2158、2216 行），依赖系统自带 perl 与非公开 MediaRemote；`README.md` 已声明系统更新风险。
- 仓库里保留 `Experiments/QishuiLyricsOCRBridge.swift.disabled`。它不参与构建，但与“不使用 OCR”的公开承诺并列出现在公开仓库里，容易引起误读。（2026-11-13 已按负责人决定删除，git 历史里仍可找回。）

**测试与 QA**

- **实机证据是手工且不可重放的。** 状态机的回归主要靠单元测试 + 人工操作 + 读日志；没有“录制的状态流样本 → 重放 → 断言发布序列”的夹具〔推断：`Tests/Fixtures/` 只有一个挂起适配器脚本〕。
- **build 180 没有自己的两小时长跑记录。** 最近一次完整通过是 v0.1.2 最终候选（`Docs/acceptance/2026-07-26-v0.1.2-final-candidate-2h-long-run.md`）；build 56、61、68 的长跑分别失败或中断（`STAGE0_CURRENT_GATES.md`）。
- **记录数量已经超过可读范围。** `Docs/acceptance/` 有 约 210 篇；唯一的总门禁表 `STAGE0_CURRENT_GATES.md` 停在 build 71 且自称历史快照。
- **2026-11-13 丢失了全部原始取证数据**（`Docs/acceptance/README.md` 顶部说明）。规则已补（`Docs/README.md` 维护规则 7），但 `README.md`“安装”一节仍指导把 DMG 工具装进 `.build/dmg-tools`——这属于可再生内容，不违规，只是容易让人以为 `.build/` 可以放东西。
- CI 没有跑 `Scripts/tests/` 下的 Python 测试，也没有跑 `generate-acceptance-index.py --check`（`.github/workflows/ci.yml`）。

**发布**

- ad-hoc 签名、未公证；`APPLE_SIGNING_AND_NOTARIZATION.md` 的脚本已就绪，卡在开发者账号。
- 没有应用内更新机制（代码中无 Sparkle 或更新检查，本次检索无结果）。
- `Docs/qa/RELEASE_CHECKLIST.md` 的目标版本仍是 `v0.1.1-alpha.4 / 0.1.1 (18)`。
- README 演示素材是 build 137（`Docs/ISSUE_BOARD.md` 开放项）。

---

## 2. 产品设计方案

### 2.1 定位

> **顶屿是 MacBook 刘海上的音乐岛：把你正在听的歌——歌名、封面、进度、歌词和三枚只会命中该播放器的按钮——放在视线最上方；计时和日程提醒只在需要时短暂借用这块位置。**

理由：

- 差异化在这里。重规划第 3 节列出的同类产品都做系统 Now Playing；顶屿独有的是**对汽水、网易云这类国内播放器的定向读取与定向控制**，以及“宁可不显示也不显示错句”的歌词。
- 9 月以来的实际投入和日常使用日志都在音乐上（`DEV_LOG_build151-180.md`；`2026-11-13-build180-rapid-skip-recheck.md` 中两天 7,345 条事件、34 次切歌）。
- 重规划要解决的两个断点——“汽水不在时岛仍有价值”“外部 App 的恢复必须由用户发起”——已经分别由活动中心降级和恢复契约解决（重规划“本轮已落地”）。它们是**底线**，不需要靠扩张成通用活动层来兑现。

### 2.2 目标用户与核心场景

目标用户沿用 `PRODUCT_REQUIREMENTS.md`：长时间听歌同时写代码、学习、开会的个人 MacBook 用户；愿意授予辅助功能，但不接受 OCR 或屏幕录制。补充一条：**主力播放器是汽水音乐**，其次是网易云或 Apple Music。

| 场景 | 岛应当做到 | 当前状态 |
| --- | --- | --- |
| 边工作边听歌，瞥一眼知道在放什么、唱到哪句 | 折叠/紧凑态显示当前句；无可信歌词时显示歌名歌手 | 已交付；后台歌词可用性未完成（`ISSUE_BOARD.md`） |
| 不离开当前应用切歌、暂停 | 三键只命中当前显示的来源；失败时明确禁用 | 已验收（`ISSUE_BOARD.md` P0） |
| 用物理媒体键 | 岛跟随真实状态；不参与路由 | 已测量；路由归属无提示 |
| 同时开着视频、抖音、浏览器 | 不被抢占、不误控 | 已验收 |
| 汽水没开或窗口关了 | 岛仍可用（计时、日程）；不拉起汽水 | 已落地；活动中心内容偏少 |
| 专注 25 分钟 / 会议前 10 分钟提醒 | 短暂接管，结束后恢复音乐 | 计时已用；日历与提醒“待验收”（`ISSUE_BOARD.md` P2） |

### 2.3 岛应当做与不应当做

**应当做**

- 只展示可核验来源的真实状态；不确定时显示更少，而不是猜。
- 所有等待都有反馈：按钮按下、切歌进行中、控制不可用及其原因。
- 一切外部副作用（打开、重启、激活其他 App）只发生在用户点击之后。
- 权限按功能懒申请，可逐项查看、关闭、恢复。

**不应当做**（本规划期内）

- AI Command Bar、本地或远程模型。
- 系统 HUD（音量、亮度、电池）、通知镜像、相机镜像、屏幕录制类功能。
- 开发者模式（Codex / Claude Code 状态）。
- 浏览器或 PWA 播放器适配（`MUSIC_ADAPTER_INTAKE.md` 已判定暂不准入）。
- 任何需要放宽项目硬规则才能实现的能力：全局媒体键、私有 MediaRemote client 控制、自动拉起或取消最小化汽水、放宽歌词身份门禁、OCR。

### 2.4 优先级

**v0.1.3 收尾（不加功能）**

- 关闭 build 180 的三个开放项中能关的两个：一次两小时长跑、重录 README 演示。后台歌词按 4.4 先取证再定。

**v0.2.0“稳定日用版”——主题是可信赖，不是新功能**

- P0：架构拆分（4.1、4.2），行为不变。
- P0：切歌等待期的过渡反馈（3.2）与控制不可用的四种原因区分（3.3）。
- P0：首次使用引导与权限页（3.5）。
- P0：发布门禁重建（5.2、5.3），Developer ID 取决于决策 3。
- P1：后台歌词按取证结果处理（4.4）；网易云、Apple Music 由 Alpha 升 Beta 的样本补齐。
- P1：辅助功能通读（3.6）；日历与提醒事项实机验收。

**v0.3 及以后——二选一，不并行**

- 方向 A：第四个播放器（QQ 音乐优先，按 `MUSIC_ADAPTER_INTAKE.md` 的探针顺序）。前提是汽水已经成为 `MusicAppAdapter` 的一个实现（4.2）。
- 方向 B：一个非音乐能力（文件 Shelf），按 `STAGE1_DEVELOPMENT_WORKFLOW.md`“先确定一项具体用户工作流及权限范围，再做可操作原型”。

活动源协议（重规划第 4 节的 `IslandActivitySource`）仍按 `STAGE1_DEVELOPMENT_WORKFLOW.md` 的判断：等出现第五种活动的真实迁移需求再引入。现有四种活动用 `IslandActivityArbitrationPolicy` 的纯函数已经够用。

### 2.5 与旧计划的取代关系

已于 2026-11-13 执行：

| 文档 | 处理 |
| --- | --- |
| `product/V0.2_PRODUCT_REPLAN.md` | 第 1 节定位、第 6 节 AI Command Bar、第 7 节功能路线 **被本文取代**。第 2 节恢复契约表、第 4 节仲裁规则、第 5 节音乐边界、第 8 节权限分级 **继续有效**，作为原则引用 |
| `archive/V0.2_PLAN.md` | 里程碑 1–4 已完成或并入本文第 6 节，**整体被取代**，已移入 `archive/` |
| `product/V0.1.3_PLAN.md` | v0.1.3 收尾完成后移入 `archive/`；其“明确不做 · 大规模拆分 `main.swift`”一条被本文 4.1 取代 |
| `archive/OPTIMIZATION_BACKLOG.md` | P0、P1 均已验收；P2 四项并入本文（3.6、4.1、4.5、5.3）。已移入 `archive/` |
| `product/LYRICS_PRODUCT_PLAN.md` | 继续有效；P1 未勾选的实机截图验收与 P2 并入本文 4.4 |
| `product/PRODUCT_REQUIREMENTS.md` | 继续有效；“产品定位”一句按 2.1 改写，P0“可信只读进度”按决策 5 的结果统一 |
| `ROADMAP.md` | 顶部一节保留；“当前版本 / 当前开发 / 后续版本 / v0.3.0 / v1.0.0”各节按本文第 6 节重写 |
| `acceptance/STAGE0_CURRENT_GATES.md` | 已是历史快照；由 5.2 的版本门禁表接替 |
| `qa/RELEASE_CHECKLIST.md` | 已改成不带版本号的模板（5.3）；v0.1.1-alpha.4 的旧清单移入 `archive/RELEASE_CHECKLIST_0.1.1-alpha.4.md` |

`V0.1.3_PLAN.md` 待 v0.1.3 收尾后归档；`STAGE0_CURRENT_GATES.md` 待 `GATES_v0.1.3.md` 建立后由它接替。三处口径不一致（1.3）已在同一提交中更正。

---

## 3. 前端（界面与交互）方案

### 3.1 交互模型：把现有规则收成一张表

现在的规则分散在 `CollapsedIslandTapPolicy`、`IslandExpansionPolicy`、`MusicPresentationPolicy.swift`、`AppDelegate` 的悬停与外部点击监视里。行为本身不需要改，需要的是一张“状态 × 输入”的权威表，放进 `Docs/design/`，并让策略测试逐行对应：

| 输入 | 折叠 | 紧凑 | 展开 |
| --- | --- | --- | --- |
| 悬停进入 | 悬停模式：展开；其他模式：无 | 同左 | 保持 |
| 悬停离开 | — | 悬停模式：收起 | 悬停模式：收起；操作过控件后保留 |
| 单击岛体 | 按 `CollapsedIslandTapPolicy` | 展开 | 命中控件则执行，否则无 |
| 单击外部 | — | 收起 | 保持展开模式：不收；其他：收起 |
| 右键 | 菜单 | 菜单 | 菜单 |
| 全屏覆盖 | 隐藏 | 隐藏 | 隐藏，退出后恢复 |

保持展开模式下“全屏抑制后恢复”和“重启后持久化”尚无实机记录（`ISSUE_BOARD.md`），补一轮即可。

### 3.2 切歌等待期的过渡反馈（本节最高杠杆）

事实：切歌后约 45–95ms 顶屿就收到第一个候选，但它是新旧混杂包，必须暂缓；约 600ms 后才有可发布的完整候选（测量记录）。这 600ms 里岛上是旧歌的完整画面。

提案：**收到被暂缓的切歌候选时，进入“切换中”呈现，但不发布任何新字段。**

- 旧歌名、歌手、封面保持原样并整体降低不透明度；进度条停止推进；歌词区清空（旧歌词本来就应在身份变化时失效）。
- 完整候选到达后一次性换入，沿用现有原子发布。
- 超过现有发布期限仍未收敛时，按现有逻辑回到已提交状态，取消“切换中”。

这不违反原子发布：屏幕上不会出现“新歌名配旧歌手或旧封面”，只是告诉用户“收到了”。岛内按钮触发的切歌已经有 `pendingTrackControl` 反馈（`IslandModel`）；这个提案把同样的观感延伸到物理按键和播放器内切歌。

需要先验证的点〔推断〕：早期候选是否可靠地只在真实切歌时出现。测量记录里 8/8 成立，但样本小；应先在 `DailyUsageAnalyzer` 中统计“早期候选之后未发生切歌”的比例，为 0 或接近 0 再做界面。

### 3.3 控制不可用：四种原因四种呈现

重规划第 2 节已经指出“未运行、窗口关闭、控件树不可用、权限缺失”在体验上容易被当成同一种故障。`MusicControlCapability.swift` 与 `MusicAdapterRuntimePresenter` 已有区分数据，界面上统一成：

| 原因 | 按钮 | 一句说明 | 动作 |
| --- | --- | --- | --- |
| 权限缺失 | 可点 | 需要辅助功能权限 | 打开系统设置（已实现，`2026-08-30` 记录） |
| 控件树暂不可用 | 禁用 | 正在重新连接 | 无，后台退避重试 |
| 主窗口已关闭 | 禁用 | 汽水窗口已关闭，重新显示后恢复 | 无；不提供“帮你打开” |
| 需要用户恢复 | 禁用 + 恢复行 | 需要重启汽水以连接控制 | “重启并连接”，仅用户点击（已实现） |

### 3.4 媒体键路由提示

只在**设置 → 音乐**的诊断区显示“系统媒体键当前归属：某应用”，并在岛显示来源与系统归属不一致时给出一句解释。不在岛体上提示，不尝试改写路由。

可行性〔推断〕：现有 MediaRemote 状态流已经能读到系统 Now Playing 的归属应用（竞争播放检查在用），应当不需要新增读取路径；需在实现前确认不引入新轮询。

### 3.5 首次使用与设置

- **首次启动引导（新增）**：一个三步窗口——选择你用的播放器 → 只为选中的播放器申请对应权限 → 看到岛上出现当前歌曲即完成。跳过任何一步都不阻塞使用。这是把 `README.md` 的九步文字变成产品内流程，也兑现重规划第 8 节“不做启动即索取全部权限”。
- **设置页结构**保持现有四页（常规、音乐、活动、关于；`main.swift` 4413–5274 行），调整两处：
  - 歌词从“音乐”页里的一个开关升级为独立小节，开启时原地显示“会向汽水相关的搜索服务发送歌名与歌手”，与 `README.md`“歌词与网络”和 `PRIVACY.md` 的表述一致。
  - 诊断信息折叠到“音乐 → 诊断”，默认收起，保留复制按钮（`ISSUE_BOARD.md`“状态诊断可视化”已完成的能力）。
- 清理 `AppSettings.swift` 中已迁移的 `autoExpandMusicLyrics` 键：保留一次性迁移读取，移除对外开关。

### 3.6 视觉、动画与辅助功能

- **动画口径统一为代码值 240ms / 180ms**，更正文档，并为 build 61 留下的“实测时长未通过”补一次实机采样后关闭或重开。不改曲线。
- **主题层**：拆分视图时（4.1）顺手把字号、间距、透明度、圆角收进一个 `IslandTheme` 命名空间。只做搬运，不改数值，用现有截图对照。
- **辅助功能通读**（一次完成，之后进门禁表）：
  - 所有按钮有标签与状态；进度条实现可调节动作，朗读“已播放 / 总时长”。
  - 歌词作为普通文本暴露，不逐句触发朗读。
  - 适配“增强对比度”“降低透明度”：提高次级文字不透明度，去掉玻璃背景。
  - 复验减少动态效果下的歌词滚动与逐字高亮。
- **其他机型**：继续按 `README.md`“已知限制”收集 Air 13、Pro 14/16 的真机截图；外接屏与无刘海屏各补一轮三态截图（`LYRICS_PRODUCT_PLAN.md` 第 7 节）。
- 界面语言本期保持简体中文；文案集中成常量以便将来本地化，不在本期做英文界面。

---

## 4. 后端（来源适配、状态与歌词）方案

### 4.1 拆分 `main.swift`：先搬文件，不改行为

第一步只在同一个 target 内按文件拆分，不改访问级别以外的任何东西：

| 新文件 | 来自 `main.swift` | 说明 |
| --- | --- | --- |
| `main.swift` | 入口 | 只保留“解析参数 → 诊断命令或启动 App” |
| `DiagnosticsCLI.swift` | 约 10–757 行 | 全部 `--xxx-status` 命令 |
| `IslandModel.swift` 及 `IslandModel+Music/Timer/Notifications/Geometry.swift` | 1272–3254 行 | 先按关注点拆 extension |
| `IslandPanel.swift`、`AppDelegate.swift`、`AppDelegate+Hover/OutsideClick/Display.swift` | 3254–4412 行 | 窗口与事件监视 |
| `Settings/*.swift` | 4413–5273 行 | 四个设置页 |
| `IslandViews/*.swift` | 5274–7256 行 | 外壳、折叠/紧凑/展开、音乐、歌词、计时、通知、通用控件 |

门禁：395 项测试全过、Release 构建通过、`verify-qishui-control-safety.sh` 通过、三态截图与拆分前一致。这一步不需要实机长跑，因为没有逻辑变化；记录里必须写明“仅搬运”。

第二步（v0.2 内）：把 `IslandModel` 的 31 个 `@Published` 按活动拆成子模型（音乐呈现、计时、通知队列、各来源的设置页状态），`IslandModel` 只保留模式、当前活动与仲裁。设置页专用的十余个来源状态属性（`neteaseMusic*`、`appleMusic*`）移出后，岛视图不再因设置状态变化而重算〔推断：未做性能测量〕。

`STAGE1_DEVELOPMENT_WORKFLOW.md` 的进入条件“核实活动切换在实机中符合契约后，再拆分 IslandModel 的事件生命周期”仍然适用于第二步。

### 4.2 拆分 `MusicAdapterCoordinator`：让汽水成为适配器

目标结构：

```text
MusicAdapterCoordinator（来源选择、控制授权、向 UI 发布）
  ├─ PlaybackOperationTracker（乐观状态、待确认操作、时间轴下限）
  ├─ SeekCoordinator（受保护跳转及其终态）
  ├─ UsageDiagnosticsEmitter（匿名事件）
  └─ [MusicAppAdapter]
       ├─ QishuiMusicAdapter      ← 新：包住状态流、AX 读取、语义控制、歌词
       ├─ NeteaseMusicAppAdapter  （已有）
       └─ AppleMusicAppAdapter    （已有）
```

顺序，每一步独立可回滚：

1. 抽出 `UsageDiagnosticsEmitter`——只写不读，风险最低。
2. 抽出 `PlaybackOperationTracker`（`PendingPlaybackOperation`、`PlaybackTimelineFloor`、`CachedPlaybackOverride` 及相关方法）。`PlaybackControlTimeline.swift` 已经是这个方向的先例。
3. 抽出 `SeekCoordinator`。
4. 把汽水相关成员收进 `QishuiMusicAdapter` 并实现 `MusicAppAdapter`。协调器里的 `qishui` 特判应从约 550 处降到来源选择优先级这一类真正属于协调器的地方。

**引入“已发布曲目令牌”。** 定义一个不可变的 `PublishedTrackToken`（来源、PID、曲目身份、会话代次）。歌词、封面、时间轴、控制回读的结果都必须携带签发时的令牌，由一个统一入口比较后才允许写入。这不是放宽或改变任何门禁，而是把现在分散在各回调里的“绑定当前曲目、PID 与会话”（`2026-10-14` 更新说明）收成一个类型，新增异步路径时漏掉检查会变成编译错误而不是下一篇验收记录。

每一步的门禁：测试全过 + 4.6 的重放夹具序列一致 + 一轮 `QA_CHECKLIST.md`“汽水专属控制”短实机。

### 4.3 可靠性

- **不动的东西**：40ms 去抖、原子门禁、发布期限。测量记录的结论是压低去抖最多省 25–40ms，却要动刚复验通过的快速切歌路径。
- **状态流子进程**：保留 perl 适配器。增加一条启动自检——`/usr/bin/perl` 不存在或适配器框架加载失败时，设置页显示明确原因，岛进入“仅活动”模式而不是静默无数据〔推断：未确认当前失败路径的呈现〕。把“macOS 小版本更新后状态流是否仍工作”列入每个版本门禁表。
- **来源选择**：规则不变（前台适配应用立即切换；后台按汽水、网易云、Apple Music 的真实播放优先级）。`ISSUE_BOARD.md` 中“三应用交叉实测”仍是待办，升 Beta 前补齐。
- **网易云 / Apple Music 升 Beta**：按 `ISSUE_BOARD.md` 与 `MUSIC_ADAPTER_INTAKE.md` 已列的缺口补样本（不同版本或第二台设备、电台、退出回退、并发视频）。不为升级降低门槛。

### 4.4 歌词

现状：三层来源——网络词级时间轴（经歌名、完整歌手、时长核验，内存缓存 24 首，`QishuiTimedLyrics.swift`）、同 PID 的窗口 AX 歌词、桌面歌词快照（`LYRICS_PRODUCT_PLAN.md` 第 4 节）。开放问题是汽水主窗口隐藏或最小化时歌词可用性（`ISSUE_BOARD.md`）。

方案：

1. **先取证，再决定。** 在匿名诊断中为每首歌记录一个歌词结果分类：`timed_verified`、`ax_window`、`desktop_snapshot`、`none_no_candidate`、`none_identity_rejected`、`none_network_failed`、`none_window_unavailable`，以及当时汽水窗口是否可见。只记分类，不记歌名歌词，符合现有隐私口径。跑一到两周日常使用。
2. **按数据选路。** 如果后台缺歌词主要是 `none_network_failed` 或查询慢（build 169 记录的成功查询约 1.7–2.2 秒，`STAGE0_CURRENT_GATES.md`），优化网络层：预取下一首不可行（没有可靠的队列指针，`V0.1.3_PLAN.md` M5），可做的是失败重试与超时分级。如果主要是 `none_identity_rejected`，保持拒绝，把分类如实显示在设置诊断里。**任何情况下都不放宽身份门禁。**
3. **把歌词来源抽象成协议。** `LyricProvider` 返回“带令牌的结果或明确的空原因”，三层来源各自实现，优先级与核验规则集中在一处。这是 4.2 令牌机制的直接应用。
4. **明确上游风险。** 词级歌词依赖的两个接口（`QishuiTimedLyrics.swift` 183、217 行）不是公开承诺的 API，随时可能变化（`README.md` 已声明）。要求：失败时静默回退到窗口歌词或空；功能默认关闭保持不变；设置中有一键关闭且立即清缓存（已有）。是否继续保留这条网络路径见决策 6。
5. 网易云、Apple Music 的歌词不在 v0.2 范围（`README.md`“已知限制”）。

### 4.5 诊断

- 保持“主岛无调试文案、诊断在设置或命令行”的原则（`archive/V0.2_PLAN.md` 版本原则）。
- `DiagnosticsCLI` 独立成文件后，补一个 `--self-check`：一次输出权限、三个来源连接状态、状态流存活、歌词开关与最近一次歌词结果分类，供用户提 Issue 时粘贴。输出不含歌名、路径、用户名。
- 把 15 分钟健康心跳扩成**被动长跑证据**：心跳里已有的状态之外，加上主进程 RSS、物理占用、线程数、子进程数〔推断：需确认当前心跳字段〕。这样日常使用本身就在积累“长时间运行”数据，见 5.2。

### 4.6 性能

- 以 `QA_CHECKLIST.md`“长稳资源门禁”为唯一口径（空闲 CPU、RSS 与物理占用增长 ≤15%、线程与子进程不增长、窗口数 ≤1）。
- build 61 的物理占用增长 45% 失败之后做过修复，但当前 build 没有自己的两小时结果；v0.1.3 收尾必须补一次。
- 定时器与延时调用分布在多处（`main.swift` 约 18 处、`MediaAdapter.swift` 约 14 处、`NeteaseMusicAppAdapter.swift` 约 8 处）。拆分时逐个登记“谁创建、谁取消、何时停”，目标是折叠态且无播放时没有周期性唤醒〔推断：未测量当前唤醒次数〕。
- 坚持“稳态不高频遍历辅助功能树”“不新增媒体轮询”（`MUSIC_ADAPTER_INTAKE.md` 第 6 条；`STAGE1_DEVELOPMENT_WORKFLOW.md`）。

---

## 5. 工程与质量

### 5.1 测试

- **新增状态流重放夹具（最高杠杆）。** 把真实状态流的事件序列脱敏后（曲目字段替换为合成值，保留时序与字段缺失形态）存入 `Tests/Fixtures/streams/`，测试重放并断言 UI 发布序列。首批样本：正常切歌的“混杂包 → 完整包”、四连快速切歌、暂停后跳转、汽水重启换 PID、空包到期。这让 build 151–180 靠人工复现的那类问题变成可回归的用例，也是 4.2 重构的安全网。夹具不得包含真实歌名、歌词或封面。
- 策略类测试继续保持纯函数形态（`IslandActivityPolicy`、`MusicPresentationPolicy` 是好例子）。
- 异步测试禁止固定睡眠，沿用同步门闩（`2026-10-14` 更新说明“CI 后续修复”）。
- CI 增加：`python3 -m unittest discover Scripts/tests`、`python3 Scripts/generate-acceptance-index.py --check`。

### 5.2 实机验收流程

问题不是验得少，而是结论散落在 约 210 篇记录里。调整为：

1. **每个对外版本一张门禁表**：`Docs/acceptance/GATES_vX.Y.Z.md`，接替 `STAGE0_CURRENT_GATES.md`。每行一条门禁，三列分开写：自动化结果、实机结果、证据链接。未做的写“未做”，不继承旧 build 的证据。
2. **实机分三档**，避免每个 build 都做全量：
   - 每个 build：自动化 + 与改动相关的一项短实机。
   - 每个对外版本：`QA_CHECKLIST.md` 全量短项（不做例行长跑，见决策 7 更新）。
   - 持续：日常使用的匿名日志与心跳，用 `DailyUsageAnalyzer` 每周出一份汇总，作为“无反证”的被动证据。它不能替代主动验收，只用于发现回归。
3. **单轮通过如实标注**。`ISSUE_BOARD.md` 现在的“单轮复验通过”“单轮实机通过”写法是对的，保持。
4. **产出位置**：原始采样、日报、长跑结果写 `LocalData/qa/`，候选 DMG 写 `LocalData/release-artifacts/`，回滚副本写 `LocalData/rollback/`。不运行 `swift package clean`。建议给 `LocalData/` 配一个本机备份（Time Machine 或定期拷贝），因为它是唯一不可再生的目录。
5. 验收记录继续“一次一份、只追加不改写”，但 **同一天同一主题的多个 build 合并成一份**，减少记录数量。

### 5.3 CI 与发布

- CI 现状足够（`.github/workflows/ci.yml`），只补 5.1 的两条。
- `RELEASE_CHECKLIST.md` 改写成无版本号模板，步骤为：门禁表全绿或逐项豁免并写明 → 干净 tag → `release.yml` 构建 → `verify-release-dmg.sh` → 从 Release 页重新下载安装做发布后验收 → 更新 ROADMAP 顶部、CHANGELOG、`updates/`。
- **签名与公证**：脚本已就绪（`check-signing-readiness.sh`、`notarize-release.sh`）。加入 Developer Program 后，v0.2.0 起只发布已公证包。ad-hoc 包每次构建代码签名身份都变，系统可能把新版本当成新应用而要求重新授予辅助功能〔推断：这是 macOS 权限数据库对 ad-hoc 签名的常见行为，本项目未专门记录；`README.md` 只记录了改 Bundle ID 时需要重新授权〕。如果属实，这是当前升级体验里最大的摩擦。
- **自动更新**：只在有 Developer ID 之后引入。在此之前，在“关于”页放一个打开 Release 页的链接即可，不做后台检查。
- **演示素材**：用 build 180 或 v0.1.3 收尾版重录；继续模糊第三方专辑封面，或改用自制占位封面。

### 5.4 文档维护

- 执行 2.5 的取代与归档；`Docs/README.md` 的“当前产品基准”指向本文。
- 修正 1.3 列出的三处口径不一致：进度跳转、动画时长、`OPTIMIZATION_BACKLOG.md` 的减少动态效果状态。
- ~~决定 `Experiments/QishuiLyricsOCRBridge.swift.disabled` 的去留~~：2026-11-13 已删除，git 历史里仍可找回。
- `ISSUE_BOARD.md` 的 P0–P2 历史表中，“相关提交”一列多处仍写“待本次提交”，归档时一并清理。

---

## 6. 路线图

### 近期：v0.1.3 收尾（约 1–2 周，不加功能）

| 工作 | 退出标准 |
| --- | --- |
| ~~build 180 或其后继做一次完整两小时长跑~~ | 已取消（决策 7 更新）：build 181 的长跑在 14 分钟时按负责人决定中止 |
| 歌词结果分类埋点（4.4 第 1 步） | 分类事件进入 `DailyUsageAnalyzer` 报告；不含歌名与歌词 |
| 重录 README 演示 | README 与素材 build 号一致；无权属不明的封面 |
| 文档收口（2.5、5.4） | `Docs/README.md` 基准更新；旧计划归档；三处口径统一 |
| CI 补两条检查（5.1） | 云端 CI 通过 |
| `main.swift` 文件级拆分（4.1 第一步） | 测试数不减且全过；Release 构建通过；三态截图一致；记录标明“仅搬运” |

**阶段退出**：`GATES_v0.1.3.md` 建立，开放项只剩“后台歌词”且已有取证数据。

### 中期：v0.2.0 稳定日用版（约 6–10 周）

| 工作 | 退出标准 |
| --- | --- |
| 状态流重放夹具（5.1） | 至少 5 类序列入库并在 CI 运行 |
| 协调器拆分与令牌（4.2） | 四步各自通过测试、夹具与短实机；`MediaAdapter.swift` 中不再有单个超过约 1,500 行的类型 |
| 汽水实现 `MusicAppAdapter` | 三个来源走同一协议；控制安全脚本与并存回归通过 |
| 切歌过渡反馈（3.2） | 先有“早期候选误报率”数据；实机 20 次切歌无混合画面；物理键与岛内按钮观感一致 |
| 控制不可用四态（3.3）、路由提示（3.4） | 四种原因各有一次实机截图 |
| 首次使用引导（3.5） | 全新用户账户下，不读 README 能完成授权并看到歌曲 |
| 辅助功能通读（3.6） | 旁白可完成播放、暂停、切歌、收起；增强对比度与减少动态效果各一轮截图 |
| 后台歌词（4.4 第 2 步） | 依据数据给出“已改善”或“上游受限，保持不显示”的明确结论 |
| 网易云、Apple Music 升 Beta | `MUSIC_ADAPTER_INTAKE.md` 缺口样本补齐；三应用交叉实测通过 |
| 日历与提醒事项验收 | 授权、撤权、关闭开关、大日历库各一轮（`ISSUE_BOARD.md` P2） |
| 签名公证（取决于决策 3） | `spctl` 与 `stapler validate` 通过 |

**阶段退出**：`GATES_v0.2.0.md` 全绿或逐项书面豁免；从 Release 页下载的安装包完成发布后验收。

### 远期：v0.3 及以后

- 方向 A 或 B 二选一（2.4）。
- 有 Developer ID 后的自动更新。
- 英文界面与更多机型像素验收。
- 汽水定向 seek、无窗口控制：继续标为上游受阻（`ISSUE_BOARD.md`），只在汽水提供公开接口时重启。

### 主要风险

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 汽水更新改变控件树或状态流行为 | 控制或同步失效 | 现有健康探针安全禁用；每次汽水大版本做一轮控制回归；门禁表记录已验证的汽水版本 |
| macOS 更新影响非公开 MediaRemote 或移除系统 perl | 三个来源里两个失去状态流 | 启动自检与明确降级（4.3）；系统测试版出现时提前跑自检 |
| 词级歌词接口变更或不可用 | 歌词退回窗口来源或为空 | 默认关闭、失败静默回退、分类埋点能第一时间看到（4.4） |
| 重构引入时序回归 | 重演 build 151–180 的补丁循环 | 先建重放夹具再动协调器；每步独立可回滚；不与功能改动混在同一 build |
| 单人维护、记录成本高 | 进度被验收文书拖住 | 三档验收与每版本一张门禁表（5.2） |
| 本机取证数据再次丢失 | 证据不可追溯 | `LocalData/` 规则已定；补本机备份 |
| ad-hoc 签名导致安装与升级摩擦 | 新用户流失，老用户升级后需重新授权〔推断〕 | 决策 3 |
| 受保护跳转在罕见竞态下作用于其他播放器 | 误控 | 现有五项前置校验；决策 5 明确保留或改为可选 |

---

## 7. 需要负责人决策的问题

**结果（2026-11-13）：负责人接受下表“建议”列的全部八项。** 决策 4 的结论是“v0.2.0 退出前不定，倾向 QQ 音乐”；决策 5 已按建议写入 `QA_CHECKLIST.md`“安全硬门禁”与 `verify-qishui-control-safety.sh`。

**决策 7 更新（2026-11-13）：** 负责人进一步决定改为接近选项 C——不再例行做两小时长跑，以日常使用为准，出现问题再修复；只在排查具体的资源或稳定性问题时做针对性测量。下文第 5.2、第 6 节中关于长跑的门禁以此为准。

| # | 问题 | 选项 | 建议 |
| --- | --- | --- | --- |
| 1 | 产品定位 | A 音乐优先的刘海岛，活动为辅；B 维持 9 月重规划的通用活动层 | **A**。与实际投入、差异化和日常使用一致；B 需要的 Shelf、快捷动作、AI 都还没有开始 |
| 2 | AI Command Bar | A 移出路线图；B 保留在 v0.2 P1 | **A**。与音乐主线无关，且引入网络与隐私面；1.0 之后再议 |
| 3 | 是否加入 Apple Developer Program（年费）以做 Developer ID 签名与公证 | A v0.2.0 前加入；B 继续 ad-hoc | **A**。脚本已就绪；这是公开分发、自动更新和稳定授权的前提 |
| 4 | v0.3 的方向 | A 第四个播放器（QQ 音乐）；B 文件 Shelf；C 都不做，继续打磨 | **v0.2.0 退出前不定**；届时倾向 **A**，因为它复用已建成的适配器框架并直接扩大可用人群 |
| 5 | 受保护的进度跳转（跟随系统媒体焦点，非来源定向） | A 保留并写成明文例外，纳入安全检查脚本；B 改为设置中默认关闭的可选项；C 移除，进度恢复只读 | **A，且同时把校验条件写进 `QA_CHECKLIST.md`“安全硬门禁”**。它已经过多轮验证且日常在用；但它是唯一的非定向控制路径，必须由负责人明确认可，而不是散落在三份口径不同的文档里。如果负责人认为它触碰“不做非定向控制”的底线，则选 C |
| 6 | 词级歌词的网络来源（非公开承诺的接口） | A 保留，默认关闭，首次开启明确告知；B 移除，只用窗口与桌面歌词 | **A**。它是后台歌词唯一可行的来源；但请负责人确认可接受接口随时失效以及公开仓库中包含这些调用 |
| 7 | 长时间运行门禁的频率 | A 每个对外版本一次两小时 + 日常心跳被动取证；B 每个候选都跑；C 不再跑 | **A**。符合负责人 10 月“减少重复长时间观察”的选择，同时不让长跑证据继续空缺 |
| 8 | 是否在 v0.2 维持“冻结新播放器适配” | A 维持到 v0.2.0 发布；B 现在解冻 | **A**。在汽水成为标准适配器之前新增来源，会把特判再复制一遍 |

---

## 附：本次审查读过的主要材料

- 文档：`Docs/README.md`、`ROADMAP.md`、`ISSUE_BOARD.md`、`CHANGELOG.md`（顶部）、`product/` 全部六份、`engineering/MUSIC_ADAPTER_INTAKE.md`、`engineering/APPLE_SIGNING_AND_NOTARIZATION.md`、`qa/STAGE1_DEVELOPMENT_WORKFLOW.md`、`qa/RELEASE_CHECKLIST.md`、`qa/QA_CHECKLIST.md`（长稳与安全门禁两节）、`acceptance/README.md`、`acceptance/STAGE0_CURRENT_GATES.md`、`acceptance/2026-11-13-build180-keyboard-latency-layers.md`、`acceptance/2026-11-13-build180-rapid-skip-recheck.md`（开头）、`updates/2026-10-14-build180-music-interaction.md`、根目录 `README.md`。
- 代码（结构级浏览，非逐行）：`main.swift` 的类型大纲与 `IslandMotion`、`ExpandedActivityCenter`；`MediaAdapter.swift` 的类型大纲与 `QishuiSeekSafety`；`MediaRemoteAdapterStreamSource.swift` 的类型大纲；`MusicAppAdapter.swift`；`IslandActivityPolicy.swift`；`MusicSourceSelector.swift`（开头）；`AppSettings.swift` 键表；`.github/workflows/ci.yml`；`Scripts/verify-qishui-control-safety.sh`（开头）。
- 未读或只看了标题的部分：`acceptance/` 中 2026-10-13 的逐 build 记录、另外两份 11-13 记录的正文、`qishui-adapter-notes.md`、`MEDIAREMOTE_ADAPTER_REPRODUCIBILITY.md`、`PRIVACY.md`、各适配器的实现细节、全部测试正文。涉及这些材料的判断均来自其他文档对它们的引用。
