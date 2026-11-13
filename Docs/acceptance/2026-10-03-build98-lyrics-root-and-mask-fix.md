# build98 歌词根节点与跑马灯边界修复验收

## 已验证

- `swift test --quiet`：294 项通过。
- `/Applications/顶屿.app`：`0.1.3 (98)`。
- `codesign --verify --deep --strict`：通过。
- Release 构建的 40 段代码/数据校验：通过。
- 汽水 PID `37785`、Bundle ID `com.soda.music` 的 AX 读取：可从 `AXFocusedWindow` 找到实时播放器树。
- 连续 adapter 采样中，`Hotel Lobby / 马思唯, 艾志恒Asen` 稳定返回 active lyric：
  `After show 这是after party 妹儿看我给你耍一点杂技`。

## 本轮修复

- 后台/非标准 AXWindows 状态下优先使用汽水的 `AXFocusedWindow` 作为播放器树根。
- 歌手归属比较统一为完整歌手集合，兼容 `/`、逗号、顿号和 `&` 分隔，不放宽标题、PID 或歌曲归属门禁。
- 跑马灯遮罩取消左侧 6% 透明区，只保留右侧渐隐，避免短句和滚动起点吞掉首字。

## 未完成门禁

- 本轮 Computer Use 初始化时 macOS 处于锁屏，无法完成安装版的真实点击、长句滚动前后截图和收起/展开残留区域复核。
- 锁屏状态下汽水 AX 只暴露菜单栏，不能据此判断后台可见窗口的最终视觉结果。

