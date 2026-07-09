# QA 检查清单

## 构建与安装

- `swift build` 能通过。
- `Scripts/package-app.sh` 能生成并安装 `/Applications/MacBook 灵动岛.app`。
- `codesign --verify --deep --strict --verbose=2 "/Applications/MacBook 灵动岛.app"` 通过。
- 双击 App 或 `open "/Applications/MacBook 灵动岛.app"` 后顶部灵动岛出现，设置面板可打开。

## 汽水音乐同步

- 汽水音乐播放时，`--qishui-status` 显示 `verifiedQishuiSource=true`。
- 灵动岛显示真实歌名、歌手、封面。
- 切歌后歌名、歌手、封面在同一轮同步中更新，不能长期错位。
- 播放/暂停后按钮状态能回读，不长期停留在 pending。
- 进度条显示真实进度，拖动后不显示调试文案。

## QuickPlayer/QuickTime 并存回归

- 先播放汽水音乐，再打开 QuickPlayer/QuickTime 播放视频。
- 灵动岛不能变成空状态或假数据，应该保留最近一次可信汽水音乐状态。
- 视频播放器占用系统媒体焦点时，点击播放/暂停、上一首、下一首不会控制视频播放器。
- 设置面板中能看到媒体焦点冲突的解释，主胶囊不显示调试备注。
- 关闭或暂停视频，让汽水音乐重新成为系统播放源后，控制恢复。

## 交互与视觉

- 胶囊与摄像头模组垂直位置匹配，底部不露出摄像头遮挡区域。
- 连续点击展开/收起没有明显位置跳动。
- 展开态点击外部能自动恢复折叠/紧凑形态。
- 主界面不出现“已同步”“来源”“Adapter”等调试文案。
- 背景保持透明，胶囊外没有发灰或不干净的边。

## 诊断命令

```bash
.build/debug/MacBookIsland --qishui-status
.build/debug/MacBookIsland --adapter-status
.build/debug/MacBookIsland --mediaremote-status
```

