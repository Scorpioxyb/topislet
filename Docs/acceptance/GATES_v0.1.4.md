# v0.1.4 版本门禁表

候选：`0.1.4 build 189`（2026-11-15）。目标发布：**v0.1.4-alpha.1**，ad-hoc 签名开发者预览版。依据 [版本计划](../product/VERSION_PLAN_2026-11.md)（2026-11-15 确认），接替 [GATES_v0.1.3](GATES_v0.1.3.md)；v0.1.3 未单独发布，其开放项“后台歌词”转入 [GATES_v0.2.0](GATES_v0.2.0.md)。

规则：自动化结果和实机结果分开写；未做的写“未做”。不继承 build 180–188 的实机证据。

验证环境：本机 MacBook（`Mac17,4`），macOS 27.3；汽水音乐 2.9.1。

## 相对公开版 build 180 的改动

| 改动 | 行为影响 |
| --- | --- |
| 展开音乐“沉浸”面板（build 187–188） | 界面：纯黑贴顶表面、124pt 封面、单栏歌词、封面模糊铺底、控制行悬停出现、面板固定 660×190 |
| 悬停展开模式下点按后移开会收起（build 185） | 交互修复 |
| 主题层 `IslandTheme` 与新的不透明度令牌（build 182） | 全局细节，计时、通知等其他界面字号未变 |
| `main.swift` 按文件拆分；协调器拆分第 1–3 步 | 无：行为不变，测试与重放夹具覆盖 |
| 状态流重放夹具进入 CI | 仅测试 |
| 每首汽水歌曲一条匿名歌词结果分类 | 只新增本地诊断日志，不含歌名与歌词 |
| 移除已停用的汽水歌词 OCR 实验代码 | 无（原本就不运行） |

## 门禁

| 门禁 | 自动化 | 实机 | 证据 |
| --- | --- | --- | --- |
| Swift 测试 | 本机 433/433 通过（不少于 v0.1.3 的 403） | — | 本地 `swift test`；云端 CI 通过（提交 `55439d5`，含测试修复 `2083b5d`） |
| 脚本测试 | 22/22 通过 | — | `python3 -m unittest discover -s Scripts/tests -p 'test_*.py'` |
| 验收索引 | `--check` 通过 | — | `Scripts/generate-acceptance-index.py` |
| 控制安全脚本 | 通过 | — | `Scripts/verify-qishui-control-safety.sh` |
| 日常日志（近 7 天） | 控制 25/25、进度跳转 25/25（确认 16、超时 0、取消 9）、汽水切歌 12/12 完整发布（原子 P95 710ms）；另记 `rapid_source_switch` 1 次、`artwork_unresolved` 1 次；`playback_confirmation` 缺样本 | — | `LocalData/qa/topislet-daily-usage-2026-11-15.json`（主检出目录） |
| 安装后启动 | — | 通过（2026-11-15）：安装后新进程启动，版本 0.1.4 / 189，辅助功能授权保留（`--ax-check` 为 true），两个状态流辅助进程在运行 | 本机 `Scripts/package-app.sh` 输出 |
| 汽水专属控制（含拆分第 1–3 步） | — | **通过**（2026-11-15 02:46–02:48，用户在岛上操作，汽水窗口最小化）：播放 / 暂停 12 次、上一首 1 次、下一首 3 次，全部 `outcome=accepted`、`dispatch_path=cached_verified`，按压 3–12ms；播放状态均由 MediaRemote 确认（210–237ms）；切歌原子发布 606–666ms。进度跳转 5 次全部确认，落点与目标相差不超过 2‰，确认用时 650–844ms。暂停中跳转 2 次（请求 10、13），0.5–0.7 秒后恢复播放，其间没有手动播放操作 | 本机统一日志 `MusicUsage` 类别 |
| 新面板 | — | 用户完成悬停、拖动、有 / 无歌词与“降低透明度”的目视检查，未报告问题（2026-11-15）；控制行命中由上一行的控制与跳转事件佐证 | 用户口头确认 |
| `QA_CHECKLIST.md` 短项与安全硬门禁 | — | **部分做，其余豁免**（负责人 2026-11-15 确认）：汽水控制与安全相关项已由上方“汽水专属控制”一行覆盖（只用语义控件、未发送全局媒体键、未自动打开或取消最小化汽水）；Apple Music、网易云、日历与提醒事项、多来源共存、布局像素项豁免，理由是这些代码路径自 build 180 起未改动，且本版本是 ad-hoc 开发预览 | 上方汽水控制证据；豁免见本行 |
| README 演示素材 | — | **豁免**（负责人 2026-11-15 确认）：仍为 build 137 的素材，重录推迟到 v0.2.0；Release 页注明演示不是当前面板 | — |
| 发布包 | 通过（2026-11-15）：本机由提交 `b259d75` 构建 `TopIslet-v0.1.4-arm64.dmg`（3.6 MB），40 段代码与数据核验一致；`verify-release-dmg.sh` 通过（DMG 校验和、挂载后签名、版本与 build 号）；SHA-256 `cdecc72deda638cffcd1ad45702742e3b90a67fbaa2e2b78b61f6b65bc598353`。ad-hoc 签名，未公证 | `LocalData/release-artifacts/`（主检出目录） |

## 观察（不阻断）

- 汽水暂停且窗口最小化时，`playback_admission_evidence` 的 `direct_playback` 字段约每秒在 0 和 1 之间翻转（10 分钟 556 条，去重只滤掉相同值）；界面没有可见变化。前一天播放中的同长度时段只有 30 条。属于诊断噪声还是直接读数确实在抖，留到 v0.2.0 M1 查。
- `sync_state` 在 `qishuiMediaRemoteSynced` 与 `qishuiDetectedAXLimited` 之间约 16 秒切换一次，前一天同样存在（30 分钟 459 次），不是本版本引入。

## 发布检查清单

复制自 [RELEASE_CHECKLIST](../qa/RELEASE_CHECKLIST.md)。

### 1. 发布前门禁

- [x] 本表全部通过，或逐项写明豁免理由与负责人确认（`QA_CHECKLIST` 未改动部分与 README 演示豁免，2026-11-15）。
- [x] `swift test` 全部通过，测试数不少于上一版本（433 ≥ 403）。
- [x] 脚本测试通过。
- [x] 验收索引 `--check` 通过。
- [x] 控制安全脚本通过。
- [x] `QA_CHECKLIST.md` 全量短项实机通过，“安全硬门禁”逐条确认。——汽水控制与安全项通过，其余未改动部分豁免（见门禁表）。
- [x] 近期日常使用没有未解决的问题：日报无新增异常，`ISSUE_BOARD` 无阻断项（2026-11-15 日报见上表）。
- [x] 记录 macOS 与汽水音乐版本（见上）。

### 2. 构建

- [ ] 工作区干净，版本号与 build 号已提交；在该提交上打 tag `v0.1.4-alpha.1`。
- [x] 通过 GitHub Actions `release.yml` 或本机 `VERSION="0.1.4" BUILD_NUMBER="189" bash Scripts/build-release.sh` 构建。——本机，提交 `b259d75`。
- [x] 产物写入 `LocalData/release-artifacts/`。
- [x] `verify-release-dmg.sh` 通过。

### 3. 签名

- [ ] Release 页写明“ad-hoc 签名开发者预览版，未公证”，并说明 Gatekeeper 提示与可能需要重新授予辅助功能。

### 4. 发布材料

- [ ] Release 页包含 SHA-256、已知限制、权限说明、第三方声明链接。
- [ ] README、截图和演示素材与 build 189 一致；不出现权属不明的第三方专辑封面。——演示素材豁免至 v0.2.0；README 文字仍需更新到 build 189。
- [ ] `Docs/CHANGELOG.md`、`Docs/ROADMAP.md` 顶部、[更新页](../updates/2026-11-15-build189-immersive-panel.md) 已更新。
- [ ] 原始采样与日报留在 `LocalData/qa/`。

### 5. 发布后验收

- [ ] 从 Release 页重新下载 DMG，校验 SHA-256，安装。
- [ ] 首次启动、权限授予、汽水三键控制、歌词开关和设置页各一次短实机。
- [ ] 写 `Docs/acceptance/<日期>-v0.1.4-alpha.1-post-release.md`，重建验收索引。
