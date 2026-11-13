# 文档地图

顶屿的文档按“对外说明 / 产品 / 工程 / 质量 / 证据 / 归档”分层。改动功能时先更新对应层，再在 `acceptance/` 留证据。

## 对外说明（会出现在 GitHub 首页与 Release）

| 文档 | 用途 |
| --- | --- |
| [README](../README.md) | 项目介绍、安装、权限与隐私概要 |
| [CHANGELOG](CHANGELOG.md) | 按发布版本整理的变更，面向用户 |
| [ROADMAP](ROADMAP.md) | 当前版本状态与后续方向；顶部一节永远描述最新 build |
| [updates/](updates/) | 每次公开同步或预发布的开发更新，Release 页面直接链接这里，**不要移动或改名** |
| [ISSUE_BOARD](ISSUE_BOARD.md) | 开放问题与已解决问题 |

## 产品 `product/`

| 文档 | 用途 |
| --- | --- |
| [V0.2_PRODUCT_REPLAN](product/V0.2_PRODUCT_REPLAN.md) | **当前产品基准**：定位、活动引擎、AI 边界、P0/P1/P2 |
| [PRODUCT_REQUIREMENTS](product/PRODUCT_REQUIREMENTS.md) | 产品需求总表 |
| [LYRICS_PRODUCT_PLAN](product/LYRICS_PRODUCT_PLAN.md) | 歌词能力的产品规划 |
| [V0.2_PLAN](product/V0.2_PLAN.md) | V0.2 稳定性与活动扩展计划（定位以重规划为准） |
| [V0.1.3_PLAN](product/V0.1.3_PLAN.md) | v0.1.3 里程碑计划 |
| [OPTIMIZATION_BACKLOG](product/OPTIMIZATION_BACKLOG.md) | 体验与性能优化待办 |

## 工程 `engineering/`

| 文档 | 用途 |
| --- | --- |
| [MUSIC_ADAPTER_INTAKE](engineering/MUSIC_ADAPTER_INTAKE.md) | 新音乐应用适配的准入标准 |
| [qishui-adapter-notes](engineering/qishui-adapter-notes.md) | 汽水音乐适配的技术笔记 |
| [MEDIAREMOTE_ADAPTER_REPRODUCIBILITY](engineering/MEDIAREMOTE_ADAPTER_REPRODUCIBILITY.md) | MediaRemote Adapter 供应链与可复现构建 |
| [APPLE_SIGNING_AND_NOTARIZATION](engineering/APPLE_SIGNING_AND_NOTARIZATION.md) | Developer ID 签名与公证 |

## 质量 `qa/`

| 文档 | 用途 |
| --- | --- |
| [STAGE1_DEVELOPMENT_WORKFLOW](qa/STAGE1_DEVELOPMENT_WORKFLOW.md) | **当前开发与分层验收流程** |
| [QA_CHECKLIST](qa/QA_CHECKLIST.md) | 实机回归清单与硬性安全规则 |
| [MVP_ACCEPTANCE](qa/MVP_ACCEPTANCE.md) | MVP 验收标准 |
| [RELEASE_CHECKLIST](qa/RELEASE_CHECKLIST.md) | 发布检查清单 |

## 证据 `acceptance/`

[验收记录索引](acceptance/README.md)：每个 build 的实机与自动化证据，含历史门禁快照和 build 151–180 开发日志。

## 设计与素材

- [design/](design/)：布局与视觉设计记录。
- [assets/](assets/)：README 与更新页引用的截图、展示素材。

## 归档 `archive/`

已被取代的计划和旧版本发布说明：v0.1.2 计划与检查清单、v0.1.0 / v0.1.1 发布说明。只读保留，不再更新。

## 维护规则

1. **一个事实一个位置。** 当前状态写在 ROADMAP 顶部；问题写在 ISSUE_BOARD；证据写在 `acceptance/`。其他文档链接过去，不复制。
2. **对外与内部分开。** `updates/`、CHANGELOG、ROADMAP、README 面向公开读者；`acceptance/` 是工程证据。
3. **只在本机保留的素材**：原始录屏（`assets/recordings/` 里的 `.mov`、社媒成片和 `production-v2/`）与 Logo 概念图（`design/logo-concepts/`）通过 `.git/info/exclude` 留在本机，不进入仓库。
4. **不写入个人信息。** 不出现个人路径、用户名、原始日志或媒体原文。
5. **计划被取代时移到 `archive/`**，并在新计划中说明取代关系。
6. **新增验收记录后**运行 `python3 Scripts/generate-acceptance-index.py`。
7. **`.build/` 只放可重新生成的构建产物。** `swift package clean` 会清空整个目录；原始采样、回滚副本和候选 DMG 若需保留，必须放在 `.build/` 之外。2026-11-13 的数据丢失见[验收记录索引](acceptance/README.md)。
