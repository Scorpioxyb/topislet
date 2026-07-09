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
- 进度条只使用 MediaRemote Adapter 的可信 `elapsedTime / duration`；AX 兜底若显示 `progress=unavailable` 是预期行为，不能用 AX 的列表时间覆盖主进度。
- 播放中连续读取 `--adapter-status` 时，`elapsedTime` 和 `progress` 应稳定递增，不应倒退或跳到旧歌进度。
- 拖动后不显示调试文案；媒体焦点被视频占用时，进度拖动不得误控视频播放器。

## QuickPlayer/QuickTime 并存回归

- 先播放汽水音乐，再打开 QuickPlayer/QuickTime 播放视频。
- 灵动岛不能变成空状态或假数据，应该保留最近一次可信汽水音乐状态。
- 视频播放器占用系统媒体焦点时，点击播放/暂停、上一首、下一首不会控制视频播放器。
- 设置面板中能看到媒体焦点冲突的解释，主胶囊不显示调试备注。
- 关闭或暂停视频，让汽水音乐重新成为系统播放源后，控制恢复。

## 抖音/浏览器视频并存回归

- 打开 Chrome 或 Safari 中的抖音视频页面，同时保持汽水音乐运行。
- 灵动岛点击展开、收起、设置入口仍然响应。
- `ps -p $(pgrep -x MacBookIsland | head -n 1) -o %cpu` 稳态不应长期高于 10%。
- 启动后不应自动弹出设置窗口；再次打开 App 或菜单点击“设置...”才出现设置窗口。
- 关闭设置/校准窗口后，CPU 应回落，不应留下隐藏窗口持续重排。
- 主界面不应因为视频页面频繁媒体事件而持续重排卡顿。
- 汽水仍是可确认来源时，歌曲信息继续更新；若媒体焦点被视频占用，岛保留汽水显示但冻结自动进度。
- 点击播放/暂停、上一首、下一首时，若 macOS 当前媒体焦点确认在汽水音乐，应直接作用于汽水；若焦点被抖音/浏览器视频抢占，应短暂激活汽水发送控制并恢复原 App，不能误控视频播放器。
- 媒体焦点被视频占用时，拖动进度条不得控制视频播放器；当前版本可明确阻断，后续再验证定向 seek。

## 汽水专属控制

- 汽水音乐单独播放时，播放/暂停、上一首、下一首、进度拖动都命中汽水。
- 抖音/QuickTime/浏览器视频播放时，播放/暂停、上一首、下一首应通过汽水聚焦兜底作用于汽水；视频不能被暂停或切换。
- 汽水音乐未运行时，控制按钮不得误控当前系统媒体。
- 汽水窗口最小化或隐藏时，播放/暂停、上一首、下一首应优先通过汽水聚焦兜底执行；若无法激活汽水，应给出受限状态且不得误控当前视频播放器。

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
