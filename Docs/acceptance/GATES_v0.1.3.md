# v0.1.3 版本门禁表

候选：`0.1.3 build 181`（2026-11-13 安装到本机）。依据 [2026-11 全局规划](../product/GLOBAL_PLAN_2026-11.md) 5.2，接替历史快照 [STAGE0_CURRENT_GATES](STAGE0_CURRENT_GATES.md)。

规则：自动化结果和实机结果分开写；未做的写“未做”。build 180 的实机证据单独标明，不当作 build 181 已复验。

验证环境：本机 MacBook（`Mac17,4`），macOS 27.3，用 macOS 27.2 SDK 构建；汽水音乐 2.9.1。

## build 181 相对 build 180 的改动

| 改动 | 行为影响 | 提交 |
| --- | --- | --- |
| 每首汽水歌曲记录一条匿名歌词结果事件，日报统计（schema 7） | 只新增诊断日志；展示的歌词和身份门禁不变 | `diag: record one anonymous lyric outcome per Qishui track` |
| `main.swift` 按文件拆分 | 无：仅搬运，另有 10 处顶层 `private` 去掉，内容按行核对一致 | `refactor: split main.swift into files without behavior change` |
| 两个时序敏感的测试改为不依赖 CI 机器速度 | 仅测试 | `ci: run script tests and index check; fix two timing-flaky tests` |
| 安装脚本停止旧进程时固定 UTF-8 locale | 仅打包脚本 | `build: 0.1.3 build 181; ...` |

## 门禁

| 门禁 | 自动化 | 实机 | 证据 |
| --- | --- | --- | --- |
| Swift 测试 | 本机 403/403 通过（build 181 源码） | — | 本地 `swift test`；云端 CI 通过（2026-11-13，提交 `00f4e8e`） |
| Release 构建与打包 | 本机通过；Release 二进制 40 段校验一致 | 安装版签名严格校验通过 | `Scripts/package-app.sh` 输出 |
| 控制安全脚本 | 通过，含进度跳转例外的前提检查 | — | `Scripts/verify-qishui-control-safety.sh` |
| 脚本测试与验收索引 | 16/16 通过；索引 `--check` 通过 | — | CI 已加入这两步，云端通过（2026-11-13，提交 `00f4e8e`） |
| 安装后启动 | — | 通过：新进程启动，辅助功能授权保留（`--ax-check` 为 true），汽水状态同步与歌词发布正常 | 本机统一日志 |
| 两小时长跑 | — | **不再作为门禁**（负责人 2026-11-13 决定：不再例行做长时间测试，日常使用中出现问题再修复）。本次在 14 分钟、172 个样本时中止：平均 CPU 0.18%，线程、子进程、窗口数未增长；物理占用比启动后 30 秒的基线高 31%、RSS 高 11%，含启动预热，时长太短，不构成通过或失败结论 | 本机 `LocalData/qa/2026-11-13-build181-long-run/` |
| 三态截图与拆分前一致 | — | 未做 | — |
| 汽水三键控制与并存回归 | — | build 181 未做；build 180 已验收 | [ISSUE_BOARD](../ISSUE_BOARD.md) P0 表 |
| 快速连续切歌 | — | build 181 未做；build 180 单轮复验通过 | [build180 快速切歌复验](2026-11-13-build180-rapid-skip-recheck.md) |
| 保持展开模式外部点击 | — | build 181 未做；build 180 单轮实机通过 | [build180 保持展开](2026-11-13-build180-pinned-outside-click.md) |
| 物理键盘延迟 | — | build 180 已分层测量，顶屿侧无可安全缩短环节 | [build180 键盘延迟分层](2026-11-13-build180-keyboard-latency-layers.md) |
| 歌词结果分类取证 | 8 项新测试通过 | 已开始采集，数据不足 1 天 | `swift run DailyUsageAnalyzer --last 7d` |
| README 演示素材 | — | 未做：仍为 build 137 | 需要人工录制 |

## 阶段退出条件（全局规划第 6 节）

- [ ] 开放项只剩“后台歌词”，且已有歌词结果分类数据。
- [ ] README 演示与发布 build 一致。
- [ ] 按 [发布检查清单](../qa/RELEASE_CHECKLIST.md) 完成发布。
