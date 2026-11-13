# build90 汽水身份门禁修复

## 已完成

- 修复 `QishuiAdapter` 的 AX 读取调用：存在已验证的 MediaRemote 标题/歌手时，AX 只接受同一身份，避免把推荐卡片当成当前播放歌曲。
- 修复歌词身份选择：AX 与 MediaRemote 不一致时，歌词身份回退到 MediaRemote，不再把推荐卡片歌词归因给当前歌曲。
- `swift test --quiet`：294 项通过。
- `swift build -c release --quiet`：通过。
- `/Applications/顶屿.app` 已安装为 `0.1.3 (90)`，`codesign --verify --deep --strict` 通过。
- 汽水真实播放仍由 PID `37785` 提供；安装与验证没有重启汽水。

## 实机门禁

安装完成时 Mac 处于锁屏，已启动新的顶屿 PID `75119`，但尚未完成解锁后的画面回归。解锁后需确认顶屿标题、歌手和歌词跟随当前汽水曲目，而不是推荐卡片；该门禁未通过前不宣称最终实机完成。
