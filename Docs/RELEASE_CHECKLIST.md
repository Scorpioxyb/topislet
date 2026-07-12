# GitHub 发布检查清单

目标版本：`v0.1.0-alpha.1`
App 版本：`0.1.0`
目标平台：macOS 26.0+、带刘海的 Apple Silicon MacBook

## 当前结论

源码仓库结构和自动化发布骨架已经准备，但**尚不满足公开二进制 Release 条件**。在下列 P0 全部完成前，只能继续作为本机开发版本或私有仓库候选。

## P0：公开前必须完成

- [ ] 项目负责人确认仓库名称，建议 `macbook-island`。
- [ ] 项目负责人确认仓库可见性：公开或私有。
- [ ] 项目负责人选择主项目许可证并加入根目录 `LICENSE`。
- [ ] 确认稳定 Bundle ID；建议 `io.github.<owner>.MacBookIsland`。
- [ ] 审核并决定是否提交当前 `Scripts/package-app.sh` 的用户改动，确保 tag 对应干净工作树。
- [ ] 记录 Vendor MediaRemote Adapter 的精确源码 commit、项目补丁和可复现构建命令。
- [ ] 在最终候选 App 上关闭 `Docs/ISSUE_BOARD.md` 中全部 P0 动态验收项。
- [ ] 决定二进制分发策略：
  - [ ] Developer ID 签名、hardened runtime、Apple 公证和 staple；或
  - [ ] 明确标记为 ad-hoc 签名开发者预览版，并说明 Gatekeeper 限制。
- [ ] 使用无个人信息、封面展示权明确的真实 MacBook Hero 照片或录屏替换临时截图。
- [ ] 将 `.github/ISSUE_TEMPLATE/config.yml` 中的 `OWNER/REPOSITORY` 替换为正式仓库地址。

## 已完成的仓库准备

- [x] README 重构为面向用户的产品主页。
- [x] 明确当前状态为 `v0.1.0-alpha`。
- [x] 系统最低版本统一为 macOS 26.0，与 Vendor framework 一致。
- [x] 增加 `PRIVACY.md`、`SECURITY.md`、`CONTRIBUTING.md`。
- [x] 增加 `THIRD_PARTY_NOTICES.md` 并保留 BSD 3-Clause 正文。
- [x] 增加 GitHub Issue 和 Pull Request 模板。
- [x] 增加 GitHub Actions Debug / Release 构建与打包冒烟测试。
- [x] 增加手动 GitHub prerelease 工作流，默认不会自动发布。
- [x] 增加独立 Release 打包脚本，生成 arm64 ZIP 与 SHA-256。
- [x] Git 跟踪文件中未发现第三方 App 解包 JavaScript、`.DS_Store` 或常见 token 格式。
- [x] 本机 Debug、Release 和 x86_64 交叉构建通过。

## 最终候选构建

```bash
BUNDLE_ID="io.github.<owner>.MacBookIsland" \
VERSION="0.1.0" \
BUILD_NUMBER="2" \
bash Scripts/build-release.sh
```

正式签名时额外设置：

```bash
SIGN_IDENTITY="Developer ID Application: <Team> (<TEAM_ID>)"
```

输出必须包含：

- `MacBook-Island-v0.1.0-arm64.zip`
- `MacBook-Island-v0.1.0-arm64.zip.sha256`

## 最终验证

- [ ] 从干净 tag 构建，不使用工作区未提交文件。
- [ ] 解压 ZIP 后 `codesign --verify --deep --strict --verbose=2` 通过。
- [ ] 正式签名版 `spctl -a -vv -t exec` 通过。
- [ ] 公证版 `xcrun stapler validate` 通过。
- [ ] App 主二进制为 arm64，最低系统版本为 26.0。
- [ ] Vendor framework 最低系统版本为 26.0，包含 arm64。
- [ ] Release 页附 SHA-256、已知限制、权限说明和第三方声明。

## P0 实机回归

- [ ] 汽水单独播放：歌名、歌手、封面、播放态和进度同步。
- [ ] 连续切歌 10 次：元数据原子更新，无旧回包覆盖。
- [ ] 播放 / 暂停快速点击：状态和时间不回退。
- [ ] 进度点击和拖动：无归零、回弹或误控。
- [ ] 抖音播放并抢占媒体焦点后，汽水仍持续同步。
- [ ] 抖音前台时三种控制只命中汽水，前台 0 切换、鼠标 0 位移、抖音 0 误控。
- [ ] QuickTime / QuickPlayer 并存行为与抖音一致。
- [ ] 展开、收回、连续点击和悬停动画无跳位或明显卡顿。
- [ ] 日历和提醒事项授权、撤权、关闭开关及大日历库回归。
