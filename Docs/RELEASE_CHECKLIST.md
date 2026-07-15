# GitHub 发布检查清单

目标版本：`v0.1.1-alpha.3`
App 版本：`0.1.1 (17)`
目标平台：macOS 26.0+、带刘海的 Apple Silicon MacBook

## 当前结论

本版本按**公开 GitHub Alpha 开发者预览版**发布。项目负责人已接受 ad-hoc 签名和未公证带来的 Gatekeeper 提示；未完成的动态回归继续作为 Alpha 已知风险跟踪，不能把本版本宣传为稳定版。

## P0：公开前必须完成

- [x] 项目负责人确认仓库名称：`topislet`。
- [x] 项目负责人确认仓库可见性：公开。
- [x] 项目负责人选择 `GPL-3.0-only`，并加入根目录 `LICENSE`。
- [x] 确认稳定 Bundle ID：`io.github.scorpioxyb.topislet`。
- [x] 保留并纳入 `Scripts/package-app.sh` 的 `.build/package` 输出改动，不再生成旧名重复 App。
- [x] 记录 Vendor MediaRemote Adapter 的精确源码 commit、项目补丁和可复现构建命令，并完成逐字节重建验证。
- [ ] 在最终候选 App 上关闭 `Docs/ISSUE_BOARD.md` 中全部 P0 动态验收项。
- [ ] 决定二进制分发策略：
  - [ ] Developer ID 签名、hardened runtime、Apple 公证和 staple；或
  - [x] 明确标记为 ad-hoc 签名开发者预览版，并说明 Gatekeeper 限制。
- [x] README 首发使用项目自有 App 图标，不公开展示权不明确的真实专辑封面截图。
- [x] 将 `.github/ISSUE_TEMPLATE/config.yml` 中的安全报告链接替换为正式仓库地址。

## 已完成的仓库准备

- [x] README 重构为面向用户的产品主页。
- [x] 明确当前状态为 `v0.1.1-alpha`。
- [x] 系统最低版本统一为 macOS 26.0，与 Vendor framework 一致。
- [x] 增加 `PRIVACY.md`、`SECURITY.md`、`CONTRIBUTING.md`。
- [x] 增加 `THIRD_PARTY_NOTICES.md` 并保留 BSD 3-Clause 正文。
- [x] 增加 GitHub Issue 和 Pull Request 模板。
- [x] 增加 GitHub Actions Debug / Release 构建与打包冒烟测试。
- [x] CI 执行全部 Swift 自动化测试，Release workflow 在候选构建前验证精确 tag、干净工作区和测试结果。
- [x] 增加 GitHub ad-hoc 候选包构建工作流；该工作流只上传临时 Artifact，不允许直接发布未公证 DMG。
- [x] 增加独立 Release 打包脚本，生成可拖放安装的 arm64 DMG 与 SHA-256。
- [x] 增加独立 DMG 自动验收脚本，检查镜像结构、Finder 布局资源、身份、架构、最低系统版本、许可证和校验和。
- [x] 增加 Developer ID 就绪检查、公证与 staple 脚本；账号和证书就绪后可直接执行。
- [x] DMG 自动验收校验文件名、`CFBundleShortVersionString` 和 `CFBundleVersion` 一致性。
- [x] Git 跟踪文件中未发现第三方 App 解包 JavaScript、`.DS_Store` 或常见 token 格式。
- [x] 本机 Debug、Release 和 x86_64 交叉构建通过。

## 最终候选构建

```bash
VERSION="0.1.1" \
BUILD_NUMBER="17" \
bash Scripts/build-release.sh
bash Scripts/verify-release-dmg.sh .build/release-artifacts/TopIslet-v0.1.1-arm64.dmg
```

正式签名时额外设置：

```bash
SIGN_IDENTITY="Developer ID Application: <Team> (<TEAM_ID>)"
```

输出必须包含：

- `TopIslet-v0.1.1-arm64.dmg`
- `TopIslet-v0.1.1-arm64.dmg.sha256`

## 最终验证

- [ ] 从干净 tag 构建，不使用工作区未提交文件。
- [x] 挂载 DMG 后，“顶屿.app”签名验证通过，且“Applications”快捷入口正确指向 `/Applications`。
- [ ] 正式签名版 `spctl -a -vv -t exec` 通过。
- [ ] 公证版 `xcrun stapler validate` 通过。
- [x] App 主二进制为 arm64，最低系统版本为 26.0。
- [x] Vendor framework 最低系统版本为 26.0，包含 arm64。
- [ ] Release 页附 SHA-256、已知限制、权限说明和第三方声明。
- [ ] 从旧原型升级后，重新授予辅助功能、日历和提醒事项权限，并确认新 Bundle ID 下功能正常。

## P0 实机回归

- [x] 汽水单独播放：歌名、歌手、封面、播放态和进度同步。
- [x] 汽水重启后 `AXManualAccessibility` 从 `0` 自动初始化为 `1`，第一次控制无需激活汽水即可成功。
- [ ] 连续切歌 10 次：元数据原子更新，无旧回包覆盖。
  - [x] 自动化压力序列通过：连续 10 首、每轮稀疏新曲、完整提交和上一轮迟到回包均无混合快照。
- [ ] 播放 / 暂停快速点击：状态和时间不回退。
  - [x] 策略级乱序回归通过：旧操作 ID 不能收尾最新操作，Apple Music 使用显式 `pause/play/pause`；完整状态机仍保留实机验收。
- [x] 进度条保持只读，不发送系统全局 seek，不会误控视频。
- [x] 抖音播放并抢占媒体焦点后，汽水仍持续同步。
- [x] 抖音前台时三种控制只命中汽水，前台 0 切换、鼠标 0 位移、抖音 0 误控；汽水最小化状态也通过。
- [x] QuickTime 前台时播放/暂停、下一首、上一首只命中汽水；QuickTime 播放开关与时间线零变化。
- [ ] 展开、收回、连续点击和悬停动画无跳位或明显卡顿。
  - [x] 自动化和本机结构验收通过：单 `NSPanel`、中心/顶边固定、旧动画 completion 失效、6 次快速反向悬停后尺寸正确。
  - [ ] 产品负责人视觉验收中间帧流畅度和透明肩部点击行为。
- [ ] 日历和提醒事项授权、撤权、关闭开关及大日历库回归。
