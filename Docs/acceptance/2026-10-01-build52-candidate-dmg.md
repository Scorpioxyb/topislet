# build 52 内容候选 DMG

阶段 0 未完成。源码基于 bc6ced7，包含 build 51 窗口创建有限重试与 AX 内容根缓存失效修正。本轮仅把 CFBundleVersion 调整为 52，并制作本地候选镜像；未替换 /Applications 的 build 51。

## 产物与校验

- `.build/release-artifacts/build52/TopIslet-v0.1.3-build52-arm64-candidate.dmg`
- 对应 `.dmg.sha256`、`content-verification.json` 与 `packaging.log` 保留在同目录。
- DMG SHA256：e9a23ec3f9f1e46586b5a109494521e122ce91ae48557e12d85bf4cc85d0c5ee
- 内部主程序 SHA256：39dd379b52bb9e4c5f3c6b82e144e85a645fa7ccb29396dcebb77e8de856888a
- 主程序 arm64、minos 26.0；0.1.3 (52)、Bundle ID io.github.scorpioxyb.topislet。
- adhoc codesign deep strict 通过；hdiutil verify 通过。
- 只读挂载后再次验证签名与程序哈希匹配，确认 Applications 符号链接指向 /Applications，项目及第三方许可证位于 app 内。
- 挂载已卸载，生成用 dmg-source 已移动 macOS Trash；未永久删除文件。

## 未验收范围

系统 CGSession 字典明确返回 locked=1。未启动新的 CUA 会话或尝试解除锁屏；SkyComputerUseService/CUALockScreenGuardian 不存在。

本轮没有执行 build-release.sh 内的 Finder/AppleScript 操作。候选使用普通镜像布局，尚未配置或实证 Finder 安装背景与图标位置。签名为本地 adhoc，未公证；不是正式公开发布产物。

build 52 未安装、未运行，因此不能用 build 51 的实际播放控制或全屏证据直接宣称 build 52 完整通过。解锁后先安装候选并验证元数据、前后台三键及窗口恢复，再补 Desktop 2/伪全屏、AX 异常、动画/命中区、生命周期与最终封版审计。
