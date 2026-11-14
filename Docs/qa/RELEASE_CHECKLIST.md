# 发布检查清单（模板）

每次对外发布（GitHub 预发布或正式版）复制本清单到该版本的门禁表或发布记录中逐项勾选，本文件本身不勾选、不写版本号。流程依据 [2026-11 全局规划](../product/GLOBAL_PLAN_2026-11.md) 5.2–5.3。历史版本的已勾选清单见 `archive/`。

## 1. 发布前门禁

- [ ] 版本门禁表 `Docs/acceptance/GATES_v<版本>.md` 已建立，每行分开写自动化结果、实机结果、证据链接；全部通过，或逐项写明豁免理由与负责人确认。不继承旧 build 的证据。
- [ ] `swift test` 全部通过，测试数不少于上一版本。
- [ ] `python3 -m unittest discover -s Scripts/tests -p 'test_*.py'` 通过。
- [ ] `python3 Scripts/generate-acceptance-index.py --check` 通过。
- [ ] `bash Scripts/verify-qishui-control-safety.sh` 通过。
- [ ] `Docs/qa/QA_CHECKLIST.md` 全量短项实机通过，“安全硬门禁”逐条确认。
- [ ] 一次完整两小时长跑：`swift Scripts/monitor-long-run.swift --pid <顶屿PID> --duration 7200 --interval 5 --output LocalData/qa/topislet-long-run-<日期>.json`，摘要 `violations` 为空。失败则如实记录并开问题，不发布。
- [ ] 门禁表记录本次验证所用的 macOS 版本与汽水音乐版本。

## 2. 构建

- [ ] 工作区干净，版本号与 build 号已提交；在该提交上打精确 tag。
- [ ] 通过 GitHub Actions `release.yml`（手动触发，填版本与 tag）构建候选包；或在本机从干净 tag 构建：

```bash
VERSION="<版本>" BUILD_NUMBER="<build>" bash Scripts/build-release.sh
```

- [ ] 本机产物写入 `LocalData/release-artifacts/`，不放 `.build/`。
- [ ] `bash Scripts/verify-release-dmg.sh LocalData/release-artifacts/TopIslet-v<版本>-arm64.dmg` 通过（结构、身份、架构、最低系统版本、许可证、校验和、版本号一致）。

## 3. 签名与公证

有 Developer ID 后（全局规划决策 3：v0.2.0 前加入 Apple Developer Program），v0.2.0 起只发布已公证包：

- [ ] `bash Scripts/check-signing-readiness.sh` 通过。
- [ ] 以 `SIGN_IDENTITY="Developer ID Application: <Team> (<TEAM_ID>)"` 构建，`bash Scripts/notarize-release.sh <DMG>` 完成公证与 staple。
- [ ] `spctl -a -vv -t exec` 与 `xcrun stapler validate` 通过。

在此之前的 ad-hoc 预发布：

- [ ] Release 页明确写“ad-hoc 签名开发者预览版，未公证”，并说明 Gatekeeper 提示与可能需要重新授予辅助功能。

## 4. 发布材料

- [ ] Release 页包含 SHA-256、已知限制、权限说明、第三方声明链接。
- [ ] README、截图和演示素材与发布 build 一致；不出现权属不明的第三方专辑封面。
- [ ] 更新 `Docs/CHANGELOG.md`、`Docs/ROADMAP.md` 顶部一节，新增 `Docs/updates/` 更新页（Release 页链接到这里，发布后不移动、不改名）。
- [ ] 原始采样、日报与长跑结果在 `LocalData/qa/`，未写入仓库。

## 5. 发布后验收

- [ ] 从公开 Release 页重新下载 DMG，校验 SHA-256，安装到 `/Applications`。
- [ ] 首次启动、权限授予、汽水三键控制、歌词开关和设置页各做一次短实机确认。
- [ ] 结果写成 `Docs/acceptance/<日期>-v<版本>-post-release.md`，运行 `python3 Scripts/generate-acceptance-index.py`。
- [ ] 若发布后发现阻断问题，在 `Docs/ISSUE_BOARD.md` 登记，并在 Release 页标注。
