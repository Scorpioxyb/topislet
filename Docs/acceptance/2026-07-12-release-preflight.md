# 顶屿 v0.1.0 发布预检记录

- 日期：2026-07-12
- Bundle ID：`io.github.scorpioxyb.topislet`
- 目标：`TopIslet-v0.1.0-arm64.dmg`

## 已通过的自动检查

- Debug、Release、x86_64 交叉构建。
- DMG 完整性与 SHA-256。
- Finder 布局：`660×400pt`、图标视图、128pt 图标、App `(170,190)`、Applications `(490,190)`。
- DMG 顶层仅包含“顶屿.app”、Applications 快捷入口及隐藏布局资源。
- App Bundle ID、显示名、arm64、macOS 26.0 最低版本。
- GPL-3.0-only、BSD 3-Clause 与第三方声明随 App 分发。
- MediaRemote Adapter 从固定上游 commit 和项目补丁逐字节重建成功。
- 汽水实时诊断确认 `verifiedQishuiSource=true`，当前曲目、播放态、进度与封面可读。

## 等待 Developer ID 后执行

- Developer ID + hardened runtime 下的 Adapter、Perl 和 Python 桥回归。
- DMG 公证、staple、Gatekeeper 与浏览器下载 quarantine 测试。
- 新签名身份下辅助功能、日历、提醒事项授权和撤权。

## 最终实机动态回归

- 汽水单独播放、连续切歌 10 次、播放/暂停、seek。
- 抖音抢占媒体焦点后同步与定向控制。
- QuickTime / QuickPlayer 并存。
- 展开、收回、连续点击、悬停与 DMG 拖放安装视觉。
