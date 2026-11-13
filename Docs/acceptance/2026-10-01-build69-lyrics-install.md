# build69 歌词 UI 候选安装

- 提交：`35fea54 Redesign expanded music lyrics shelf`
- 版本：`0.1.3 (69)`
- 候选 DMG：`.build/release-artifacts/build69/TopIslet-v0.1.3-arm64.dmg`
- DMG SHA256：`3841bea422c8a6182cb9a2f81a2992a17ce3f78fa4974ad0dee12e0073f676c6`
- 安装二进制 SHA256：`531d8c37a1555b5f2382ae6d111e99874fb485b84ee40a5e0711d0cbac926c84`
- 候选签名、DMG 校验、40 段二进制一致性和 Info.plist 校验均通过。
- 旧 `/Applications/顶屿.app` 已按回收站策略移入废纸篓；build68 回滚副本仍保留。
- 新版本已安装并启动，当前主进程 PID 23543。
- 紧凑态截图已捕获：窗口 `377x35+666+-1`，未见安装启动异常。
- 展开态歌词栏的真实截图和命中区域尚未完成，不能宣称歌词 UI 实机验收通过。

状态：候选已安装，阶段 0 仍未封版。下一项实机检查应在汽水有可信歌词时展开顶屿，确认独立歌词栏可读、按钮仍可点击、窗口高度/黑边没有回归；如失败，优先回滚到 build68。
