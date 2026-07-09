# MVP v0.1 验收清单

## 验收目标

MVP v0.1 的目标不是扩展更多功能，而是确认 MacBook 灵动岛作为“汽水音乐顶部岛”具备可持续试用的稳定性：显示真实、控制安全、性能稳定、交互不突兀。

## 验收范围

- 顶部灵动岛三态：折叠、紧凑、展开。
- 汽水音乐真实同步：歌名、歌手、封面、播放态、进度。
- 基础控制：播放/暂停、上一首、下一首、进度条展示。
- 媒体冲突：抖音、浏览器视频、QuickTime/QuickPlayer 同时播放。
- 设置与校准：设置面板、布局校准、状态诊断。
- 性能：CPU、窗口响应、后台稳定性。

## P0 验收项

| 编号 | 验收项 | 通过标准 | 验证方式 |
| --- | --- | --- | --- |
| A1 | App 可安装运行 | `/Applications/MacBook 灵动岛.app` 可打开，顶部岛出现 | `Scripts/package-app.sh` 后 `open` |
| A2 | CPU 稳定 | 稳态 CPU 通常低于 5%，不得长期高于 10% | `ps -p $(pgrep -x MacBookIsland | head -n 1) -o %cpu` |
| A3 | 汽水真实同步 | `--adapter-status` 显示 `verifiedQishuiSource=true`，歌名/歌手与汽水一致 | CLI + 目视对比 |
| A4 | 进度可信 | `elapsedTime` 和 `progress` 连续递增；点击岛后不得回到 0 或几秒 | 连续读数 + 手动点击 |
| A5 | AX 不污染进度 | AX fallback 允许 `progress=unavailable`，不得覆盖主进度 | `--qishui-status` |
| A6 | 播放控制安全 | 单独播放汽水时，播放/暂停/切歌命中汽水 | 手动操作 |
| A7 | 视频冲突安全 | 抖音/QuickTime/浏览器视频播放时，不得误控视频 | 手动操作 |
| A8 | 聚焦兜底可接受 | 其他媒体抢焦点时，可短暂激活汽水控制，并恢复原 App | 手动操作 |
| A9 | 点击交互稳定 | 连续点击展开/收起不跳位、不归零、不明显卡顿 | 手动操作 |
| A10 | 设置可用 | 设置、校准、状态诊断入口可打开且不自动弹窗 | 手动操作 |

## 验证命令

```bash
swift build
Scripts/package-app.sh
codesign --verify --deep --strict --verbose=2 "/Applications/MacBook 灵动岛.app"
"/Applications/MacBook 灵动岛.app/Contents/MacOS/MacBookIsland" --adapter-status
"/Applications/MacBook 灵动岛.app/Contents/MacOS/MacBookIsland" --qishui-status
ps -p $(pgrep -x MacBookIsland | head -n 1) -o pid,stat,%cpu,%mem,time,command
```

## 手工测试矩阵

| 场景 | 操作 | 预期 |
| --- | --- | --- |
| 汽水单独播放 | 播放 30 秒后点击岛展开 | 进度保持当前时间，不从 0 开始 |
| 汽水切歌 | 连续点下一首 3 次 | 歌名、歌手、封面最终一致，不长期错位 |
| 汽水暂停/播放 | 点岛内播放按钮 | 按钮状态可回读，不长期 pending |
| 浏览器视频冲突 | 播放抖音视频后点岛播放/暂停 | 不误控视频，汽水通过兜底控制或显示受限 |
| QuickTime 冲突 | 播放本地视频后操作岛 | 不清空汽水状态，不误控视频 |
| 设置窗口 | 打开/关闭设置与校准 | CPU 回落，无隐藏窗口持续重排 |

## MVP 出口标准

- P0 全部通过，或只剩明确可接受的体验限制。
- 没有长期 CPU 高占用。
- 没有会误控视频播放器的控制路径。
- 没有主界面调试文案泄露。
- Git 工作区保持干净，并有对应提交记录。
